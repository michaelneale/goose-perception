import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

/// Service for capturing screenshots and window metadata
/// Simplified approach based on working Aquarius implementation
actor ScreenCaptureService {
    private let database: Database
    private var ocrProcessor: OCRProcessor
    
    private(set) var isCapturing = false
    private var captureInterval: TimeInterval = 20.0 // seconds
    
    init(database: Database) {
        self.database = database
        self.ocrProcessor = OCRProcessor()
    }
    
    func startCapturing() async throws {
        guard !isCapturing else { return }
        
        // Just try to capture - ScreenCaptureKit handles permission prompts
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard content.displays.first != nil else {
                throw ScreenCaptureError.noDisplayFound
            }
            NSLog("📸 Screen capture permission OK")
        } catch {
            NSLog("📸 Screen capture error: \(error)")
            throw ScreenCaptureError.permissionDenied
        }
        
        isCapturing = true
        NSLog("📸 Screen capture started (interval: \(captureInterval)s)")
        
        // Start capture loop in background (don't await)
        Task { await self.startCaptureLoop() }
    }
    
    func stopCapturing() {
        isCapturing = false
        NSLog("📸 Screen capture stopped")
    }
    
    func setCaptureInterval(_ interval: TimeInterval) {
        captureInterval = max(5, min(120, interval))
    }
    
    // MARK: - Capture Loop
    
    /// Interval for full window scan (all windows OCR'd)
    private var fullScanInterval: TimeInterval = 600 // 10 minutes
    private var lastFullScanTime: Date?
    
    private func startCaptureLoop() async {
        // Do a full scan on startup
        await performFullWindowScan()
        
        while isCapturing {
            do {
                try await captureScreen()
                
                // Check if it's time for a full scan
                if shouldPerformFullScan() {
                    await performFullWindowScan()
                }
            } catch {
                NSLog("❌ Capture failed: \(error)")
            }
            
            try? await Task.sleep(for: .seconds(captureInterval))
        }
    }
    
    private func shouldPerformFullScan() -> Bool {
        guard let lastScan = lastFullScanTime else { return true }
        return Date().timeIntervalSince(lastScan) >= fullScanInterval
    }
    
    /// OCR all visible windows - provides comprehensive context
    private func performFullWindowScan() async {
        NSLog("📸 Starting full window scan...")
        lastFullScanTime = Date()
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // Filter to reasonable windows
            let excludeApps = ["Dock", "Window Server", "Spotlight", "Notification Center", "Control Center"]
            let windows = content.windows.filter { window in
                guard let title = window.title, !title.isEmpty else { return false }
                guard window.frame.width > 200 && window.frame.height > 200 else { return false }
                let appName = window.owningApplication?.applicationName ?? ""
                return !excludeApps.contains(appName)
            }
            
            NSLog("📸 Full scan: found \(windows.count) windows to OCR")
            
            var ocrResults: [String] = []
            
            for window in windows.prefix(15) { // Limit to 15 windows max
                let config = SCStreamConfiguration()
                let filter = SCContentFilter(desktopIndependentWindow: window)
                config.width = min(Int(window.frame.width), 1920)
                config.height = min(Int(window.frame.height), 1080)
                
                do {
                    let cgImage = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    )
                    let windowOCR = try await ocrProcessor.performOCR(on: cgImage)
                    if !windowOCR.isEmpty {
                        let appName = window.owningApplication?.applicationName ?? "Unknown"
                        let windowTitle = window.title ?? ""
                        ocrResults.append("[\(appName) - \(windowTitle)]\n\(windowOCR)")
                    }
                } catch {
                    // Skip windows that fail to capture
                }
            }
            
            // Store as a single "full scan" capture
            if !ocrResults.isEmpty {
                let combinedOCR = ocrResults.joined(separator: "\n\n---\n\n")
                let capture = ScreenCapture(
                    timestamp: Date(),
                    focusedApp: "Full Scan",
                    focusedWindow: "\(ocrResults.count) windows",
                    ocrText: combinedOCR
                )
                let captureId = try await database.insertScreenCapture(capture)
                NSLog("📸 Full scan complete: \(ocrResults.count) windows, \(combinedOCR.count) chars (capture #\(captureId))")
                
                Task { @MainActor in
                    ActivityLogStore.shared.log(.screen, "📸 Full scan: \(ocrResults.count) windows", detail: "OCR'd all visible windows")
                }
            }
        } catch {
            NSLog("❌ Full window scan failed: \(error)")
        }
    }
    
    // MARK: - Screenshot Capture (Aquarius-style)
    
    private func captureScreen() async throws {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }
        
        // Get focused window info BEFORE capture
        let focusedAppInfo = getFocusedAppInfo()
        let allWindowsInfo = getOpenWindowsInfo(from: content)
        
        // Find the focused window in SCShareableContent
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedWindow = content.windows.first { window in
            guard window.owningApplication?.processID == focusedPID else { return false }
            guard let title = window.title, !title.isEmpty else { return false }
            guard window.frame.width > 100 && window.frame.height > 100 else { return false }
            return true
        }
        
        // Get top 3 windows to OCR (focused + 2 more visible windows)
        let topWindows = getTopWindowsForOCR(from: content, focusedPID: focusedPID, limit: 3)
        
        // OCR each window and combine results
        var allOCRText: [String] = []
        
        for window in topWindows {
            let config = SCStreamConfiguration()
            let filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = min(Int(window.frame.width), 1920)
            config.height = min(Int(window.frame.height), 1080)
            
            do {
                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                let windowOCR = try await ocrProcessor.performOCR(on: cgImage)
                if !windowOCR.isEmpty {
                    let appName = window.owningApplication?.applicationName ?? "Unknown"
                    let windowTitle = window.title ?? ""
                    allOCRText.append("[\(appName) - \(windowTitle)]\n\(windowOCR)")
                }
            } catch {
                NSLog("📸 Failed to OCR window: \(window.title ?? "unknown") - \(error)")
            }
        }
        
        let ocrText = allOCRText.joined(separator: "\n\n")
        
        // Create capture record
        var capture = ScreenCapture(
            timestamp: Date(),
            focusedApp: focusedAppInfo.appName,
            focusedWindow: focusedAppInfo.windowTitle,
            ocrText: ocrText
        )
        capture.setAllWindows(allWindowsInfo)
        
        // Store in database
        let captureId = try await database.insertScreenCapture(capture)
        
        // Log
        let appName = focusedAppInfo.appName ?? "Unknown"
        let windowTitle = focusedAppInfo.windowTitle ?? ""
        let windowMode = focusedWindow != nil ? "window" : "screen"
        NSLog("📸 Captured #\(captureId): \(appName) [\(windowMode)] - \(ocrText.count) chars")
        
        // Log to ActivityLogStore for Dashboard
        let ocrPreview = String(ocrText.prefix(150)).replacingOccurrences(of: "\n", with: " ")
        Task { @MainActor in
            ActivityLogStore.shared.log(.screen, "📸 \(appName): \(windowTitle)", detail: ocrPreview.isEmpty ? nil : ocrPreview)
        }
    }
    
    // MARK: - Window Info Helpers
    
    private func getFocusedAppInfo() -> (appName: String?, windowTitle: String?) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        
        let appName = frontApp.localizedName
        var windowTitle: String? = nil
        
        // Get focused window title using Accessibility API
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindow: AnyObject?
        
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            var title: AnyObject?
            if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success {
                windowTitle = title as? String
            }
        }
        
        return (appName, windowTitle)
    }
    
    private func getTopWindowsForOCR(from content: SCShareableContent, focusedPID: pid_t?, limit: Int) -> [SCWindow] {
        var result: [SCWindow] = []
        
        // First add focused window if found
        if let focusedPID = focusedPID {
            if let focusedWindow = content.windows.first(where: { window in
                guard window.owningApplication?.processID == focusedPID else { return false }
                guard let title = window.title, !title.isEmpty else { return false }
                guard window.frame.width > 100 && window.frame.height > 100 else { return false }
                return true
            }) {
                result.append(focusedWindow)
            }
        }
        
        // Add other visible windows (not from focused app, reasonable size)
        let excludeApps = ["Dock", "Window Server", "Finder", "Spotlight", "Notification Center"]
        for window in content.windows {
            guard result.count < limit else { break }
            guard let title = window.title, !title.isEmpty else { continue }
            guard window.frame.width > 200 && window.frame.height > 200 else { continue }
            
            let appName = window.owningApplication?.applicationName ?? ""
            guard !excludeApps.contains(appName) else { continue }
            
            // Don't add duplicates or windows from same app as focused
            if let focusedPID = focusedPID, window.owningApplication?.processID == focusedPID {
                continue
            }
            if result.contains(where: { $0.windowID == window.windowID }) {
                continue
            }
            
            result.append(window)
        }
        
        return result
    }
    
    private func getOpenWindowsInfo(from content: SCShareableContent) -> [ScreenCapture.WindowInfo] {
        var windowInfos: [ScreenCapture.WindowInfo] = []
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        
        for window in content.windows {
            guard let title = window.title, !title.isEmpty else { continue }
            guard window.frame.height > 50 else { continue }  // Skip tiny windows
            
            let appName = window.owningApplication?.applicationName ?? "Unknown"
            let isActive = window.owningApplication?.processID == focusedPID
            
            windowInfos.append(ScreenCapture.WindowInfo(
                appName: appName,
                windowTitle: title,
                isActive: isActive
            ))
        }
        
        return windowInfos
    }
}

// MARK: - Errors

enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplayFound
    case captureFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen capture permission denied. Enable in System Settings > Privacy & Security > Screen Recording."
        case .noDisplayFound:
            return "No display found."
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        }
    }
}
