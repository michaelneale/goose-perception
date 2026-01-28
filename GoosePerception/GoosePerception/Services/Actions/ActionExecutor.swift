//
// ActionExecutor.swift
//
// Executes ActionCommands on macOS.
//

import Foundation
import AppKit
import UserNotifications

/// Result of executing a single command
struct CommandResult {
    let command: ActionCommand
    let success: Bool
    let message: String?
    let error: String?
    let duration: TimeInterval
    
    static func success(_ command: ActionCommand, message: String? = nil, duration: TimeInterval = 0) -> CommandResult {
        CommandResult(command: command, success: true, message: message, error: nil, duration: duration)
    }
    
    static func failure(_ command: ActionCommand, error: String, duration: TimeInterval = 0) -> CommandResult {
        CommandResult(command: command, success: false, message: nil, error: error, duration: duration)
    }
}

/// Execution options
struct ExecutionOptions {
    /// Dry run - don't actually execute, just validate
    var dryRun: Bool = false
    
    /// Stop on first error
    var stopOnError: Bool = false
    
    /// Allowed directories for file operations (nil = allow all)
    var allowedPaths: [String]? = nil
    
    /// Whether to allow destructive operations
    var allowDestructive: Bool = false
    
    /// Whether to allow shell commands
    var allowShell: Bool = false
    
    static let `default` = ExecutionOptions()
    
    static let safe = ExecutionOptions(
        dryRun: false,
        stopOnError: true,
        allowedPaths: [
            NSHomeDirectory() + "/Documents",
            NSHomeDirectory() + "/Downloads",
            NSHomeDirectory() + "/Desktop"
        ],
        allowDestructive: false,
        allowShell: false
    )
}

/// Executes action commands on macOS
actor ActionExecutor {
    
    /// Execute a list of commands
    func execute(_ commands: [ActionCommand], options: ExecutionOptions = .default) async -> [CommandResult] {
        var results: [CommandResult] = []
        
        for command in commands {
            // Skip comments
            if case .comment = command {
                continue
            }
            
            // Check safety
            if let error = checkSafety(command, options: options) {
                results.append(.failure(command, error: error))
                if options.stopOnError { break }
                continue
            }
            
            // Execute
            let start = Date()
            let result: CommandResult
            
            if options.dryRun {
                result = .success(command, message: "[DRY RUN] Would execute: \(command.description)")
            } else {
                result = await executeOne(command)
            }
            
            results.append(CommandResult(
                command: result.command,
                success: result.success,
                message: result.message,
                error: result.error,
                duration: Date().timeIntervalSince(start)
            ))
            
            if !result.success && options.stopOnError {
                break
            }
        }
        
        return results
    }
    
    // MARK: - Safety Checks
    
    private func checkSafety(_ command: ActionCommand, options: ExecutionOptions) -> String? {
        // Check destructive
        if command.isDestructive && !options.allowDestructive {
            return "Destructive commands not allowed"
        }
        
        // Check shell
        if case .runShell = command, !options.allowShell {
            return "Shell commands not allowed"
        }
        
        // Check path restrictions
        if let allowedPaths = options.allowedPaths {
            if let path = extractPath(from: command) {
                let expanded = expandPath(path)
                let isAllowed = allowedPaths.contains { allowed in
                    expanded.hasPrefix(allowed)
                }
                if !isAllowed {
                    return "Path not in allowed directories: \(path)"
                }
            }
        }
        
        return nil
    }
    
    private func extractPath(from command: ActionCommand) -> String? {
        switch command {
        case .moveFile(let from, _): return from
        case .copyFile(let from, _): return from
        case .deleteFile(let path): return path
        case .createFolder(let path): return path
        case .openFile(let path, _): return path
        case .revealInFinder(let path): return path
        case .writeFile(let path, _): return path
        case .appendFile(let path, _): return path
        default: return nil
        }
    }
    
    // MARK: - Execution
    
    private func executeOne(_ command: ActionCommand) async -> CommandResult {
        do {
            switch command {
            // File operations
            case .moveFile(let from, let to):
                let fromPath = expandPath(from)
                let toPath = expandPath(to)
                try FileManager.default.moveItem(atPath: fromPath, toPath: toPath)
                return .success(command, message: "Moved file")
                
            case .copyFile(let from, let to):
                let fromPath = expandPath(from)
                let toPath = expandPath(to)
                try FileManager.default.copyItem(atPath: fromPath, toPath: toPath)
                return .success(command, message: "Copied file")
                
            case .deleteFile(let path):
                try FileManager.default.removeItem(atPath: expandPath(path))
                return .success(command, message: "Deleted file")
                
            case .createFolder(let path):
                try FileManager.default.createDirectory(atPath: expandPath(path), withIntermediateDirectories: true)
                return .success(command, message: "Created folder")
                
            case .openFile(let path, let app):
                let url = URL(fileURLWithPath: expandPath(path))
                if let appName = app {
                    let appURL = URL(fileURLWithPath: "/Applications/\(appName).app")
                    let config = NSWorkspace.OpenConfiguration()
                    try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
                } else {
                    NSWorkspace.shared.open(url)
                }
                return .success(command, message: "Opened file")
                
            case .revealInFinder(let path):
                NSWorkspace.shared.selectFile(expandPath(path), inFileViewerRootedAtPath: "")
                return .success(command, message: "Revealed in Finder")
                
            // Document creation
            case .writeFile(let path, let content):
                try content.write(toFile: expandPath(path), atomically: true, encoding: .utf8)
                return .success(command, message: "Wrote \(content.count) chars")
                
            case .appendFile(let path, let content):
                let expandedPath = expandPath(path)
                if FileManager.default.fileExists(atPath: expandedPath) {
                    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: expandedPath))
                    handle.seekToEndOfFile()
                    if let data = content.data(using: .utf8) {
                        handle.write(data)
                    }
                    try handle.close()
                } else {
                    try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                }
                return .success(command, message: "Appended \(content.count) chars")
                
            // Communication
            case .sendEmail(let to, let subject, let body):
                let result = await openEmailCompose(to: to, subject: subject, body: body)
                return result ? .success(command, message: "Opened email compose") : .failure(command, error: "Failed to open email")
                
            case .openURL(let urlString):
                guard let url = URL(string: urlString) else {
                    return .failure(command, error: "Invalid URL")
                }
                NSWorkspace.shared.open(url)
                return .success(command, message: "Opened URL")
                
            case .copyToClipboard(let text):
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                return .success(command, message: "Copied to clipboard")
                
            // App control
            case .openApp(let name):
                let launched = NSWorkspace.shared.launchApplication(name)
                return launched ? .success(command, message: "Opened \(name)") : .failure(command, error: "Failed to open \(name)")
                
            case .quitApp(let name):
                let apps = NSWorkspace.shared.runningApplications.filter { 
                    $0.localizedName?.lowercased() == name.lowercased() 
                }
                for app in apps {
                    app.terminate()
                }
                return .success(command, message: "Quit \(apps.count) instance(s)")
                
            case .activateApp(let name):
                let apps = NSWorkspace.shared.runningApplications.filter { 
                    $0.localizedName?.lowercased() == name.lowercased() 
                }
                if let app = apps.first {
                    app.activate(options: .activateIgnoringOtherApps)
                    return .success(command, message: "Activated \(name)")
                }
                return .failure(command, error: "\(name) not running")
                
            // Notifications
            case .notify(let title, let message, let sound):
                await showNotification(title: title, message: message, sound: sound)
                return .success(command, message: "Showed notification")
                
            case .speak(let text):
                await speakText(text)
                return .success(command, message: "Speaking")
                
            // System
            case .runShortcut(let name, let input):
                try await runShortcut(name: name, input: input)
                return .success(command, message: "Ran shortcut")
                
            case .runShell(let shellCommand):
                let output = try await runShellCommand(shellCommand)
                return .success(command, message: output.isEmpty ? "Completed" : String(output.prefix(100)))
                
            // Skip these
            case .comment, .unknown:
                return .success(command)
            }
        } catch {
            return .failure(command, error: error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    
    private func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
    
    private func openEmailCompose(to: String, subject: String, body: String) async -> Bool {
        await MainActor.run {
            guard let service = NSSharingService(named: .composeEmail) else { return false }
            service.recipients = [to]
            service.subject = subject
            service.perform(withItems: [body])
            return true
        }
    }
    
    private func showNotification(title: String, message: String, sound: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if let soundName = sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    private func speakText(_ text: String) async {
        await MainActor.run {
            let synth = NSSpeechSynthesizer()
            synth.startSpeaking(text)
        }
    }
    
    private func runShortcut(name: String, input: String?) async throws {
        var args = ["shortcuts", "run", name]
        if let input = input {
            args += ["-i", input]
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ActionExecutor", code: Int(process.terminationStatus), 
                         userInfo: [NSLocalizedDescriptionKey: "Shortcut failed with status \(process.terminationStatus)"])
        }
    }
    
    private func runShellCommand(_ command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ActionExecutor", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: output])
        }
        
        return output
    }
}
