//
// DirectoryActivityService.swift
//
// Polls Spotlight for recently modified files and tracks directory activity
//

import Foundation

/// Service that polls Spotlight for recently modified files in user directories
/// Tracks which directories (1-2 levels below ~/) the user is actively working in
actor DirectoryActivityService {
    private let database: Database
    private(set) var isCapturing = false
    private let pollInterval: TimeInterval = 600  // 10 minutes
    private let queryWindowMinutes = 11           // Slight overlap to avoid missing files
    
    // Only track these root directories (1 level below ~/)
    private let allowedRoots: Set<String> = [
        "Documents", "Desktop", "Downloads", "Developer",
        "Movies", "Music", "Pictures", "Projects", "code"
    ]
    
    // Only track files with these extensions (common document types)
    private let trackedExtensions: Set<String> = [
        "docx", "xlsx", "xls", "pptx", "ppt",
        "pdf", "md", "txt", "rtf",
        "pages", "numbers", "key",
        "csv", "json"
    ]
    
    init(database: Database) {
        self.database = database
    }
    
    func startCapturing() async {
        guard !isCapturing else { return }
        isCapturing = true
        NSLog("📁 Directory activity tracking started (interval: \(Int(pollInterval/60))min)")
        
        // Run initial poll immediately
        Task {
            try? await pollAndStore()
        }
        
        // Start poll loop
        Task { await self.startPollLoop() }
    }
    
    func stopCapturing() {
        isCapturing = false
        NSLog("📁 Directory activity tracking stopped")
    }
    
    /// Manually trigger a poll (for testing)
    func pollNow() async throws {
        try await pollAndStore()
    }
    
    // MARK: - Private
    
    private func startPollLoop() async {
        while isCapturing {
            // Wait first, since we already did an initial poll
            try? await Task.sleep(for: .seconds(pollInterval))
            
            guard isCapturing else { break }
            
            do {
                try await pollAndStore()
            } catch {
                NSLog("❌ Directory poll failed: \(error)")
            }
        }
    }
    
    private func pollAndStore() async throws {
        let files = try await queryRecentFiles()
        
        // Extract unique directories from file paths
        var directories: [String: String] = [:]  // path -> displayName
        
        for filePath in files {
            if let dirInfo = extractAllowedDirectory(from: filePath) {
                directories[dirInfo.path] = dirInfo.displayName
            }
        }
        
        // Upsert each directory
        for (path, displayName) in directories {
            try await database.upsertDirectoryActivity(path: path, displayName: displayName)
        }
        
        if !directories.isEmpty {
            NSLog("📁 Tracked \(directories.count) active directories from \(files.count) files")
            Task { @MainActor in
                ActivityLogStore.shared.log(.system, "📁 Directory activity",
                    detail: "Detected activity in \(directories.count) directories")
            }
        }
    }
    
    /// Query Spotlight for recently modified files with tracked extensions
    private func queryRecentFiles() async throws -> [String] {
        let home = NSHomeDirectory()
        let seconds = queryWindowMinutes * 60
        
        // Build extension filter for mdfind
        // Format: (kMDItemFSName == "*.docx" || kMDItemFSName == "*.xlsx" || ...)
        let extFilters = trackedExtensions.map { "kMDItemFSName == '*.\($0)'c" }
        let extQuery = "(\(extFilters.joined(separator: " || ")))"
        
        // Time filter - files modified in the last N minutes
        let timeQuery = "kMDItemContentModificationDate >= $time.now(-\(seconds))"
        
        // Combined query
        let query = "\(timeQuery) && \(extQuery)"
        
        return try await runMdfind(query: query, scope: home)
    }
    
    /// Run mdfind and return file paths
    private func runMdfind(query: String, scope: String) async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query, "-onlyin", scope]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let paths = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                continuation.resume(returning: paths)
            }
        }
    }
    
    /// Extract allowed directory path from a file path
    /// Returns nil if not in allowed roots or too deep
    private func extractAllowedDirectory(from filePath: String) -> (path: String, displayName: String)? {
        let home = NSHomeDirectory()
        guard filePath.hasPrefix(home) else { return nil }
        
        // Get relative path (remove ~/)
        let startIndex = filePath.index(filePath.startIndex, offsetBy: home.count + 1)
        let relative = String(filePath[startIndex...])
        
        let components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        
        // First component must be in allowed list
        guard allowedRoots.contains(components[0]) else { return nil }
        
        // Exclude hidden directories
        guard !components.contains(where: { $0.hasPrefix(".") }) else { return nil }
        
        // Determine directory level (1 or 2 levels deep)
        // If file is at ~/Documents/foo.txt -> directory is ~/Documents
        // If file is at ~/Documents/reports/foo.txt -> directory is ~/Documents/reports
        // If file is at ~/Documents/reports/2024/foo.txt -> directory is ~/Documents/reports (cap at 2)
        
        let dirComponents: [String]
        if components.count <= 2 {
            // File is 1 level deep (~/Documents/foo.txt) -> use root
            dirComponents = [components[0]]
        } else {
            // File is 2+ levels deep -> use up to 2 levels
            dirComponents = Array(components.prefix(2))
        }
        
        let path = home + "/" + dirComponents.joined(separator: "/")
        let displayName = dirComponents.last ?? components[0]
        
        return (path, displayName)
    }
}
