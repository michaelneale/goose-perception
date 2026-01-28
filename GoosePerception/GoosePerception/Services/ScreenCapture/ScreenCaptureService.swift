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
    
    private func startCaptureLoop() async {
        while isCapturing {
            do {
                try await captureScreen()
            } catch {
                NSLog("❌ Capture failed: \(error)")
            }
            
            try? await Task.sleep(for: .seconds(captureInterval))
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
        
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        
        if let window = focusedWindow {
            // Capture just the focused window
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = min(Int(window.frame.width), 1920)
            config.height = min(Int(window.frame.height), 1080)
        } else {
            // Fallback to full screen if no focused window found
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            config.width = 1024
            config.height = Int(Double(display.height) * (1024.0 / Double(display.width)))
        }
        
        // Capture screenshot
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        // Perform OCR on the captured image (now just focused window)
        let ocrText = try await ocrProcessor.performOCR(on: cgImage)
        
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
