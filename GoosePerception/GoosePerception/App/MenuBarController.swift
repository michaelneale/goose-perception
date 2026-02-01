import AppKit

/// Minimal menu bar controller - just status, dashboard access, and quit
@MainActor
class MenuBarController {
    let menu: NSMenu
    private let statusItem: NSStatusItem
    
    private var statusMenuItem: NSMenuItem!
    
    private let onOpenDashboard: () -> Void
    private let onAnalyzeNow: () -> Void
    private let onQuit: () -> Void
    
    // Track active services for status display
    private var screenActive = false
    private var voiceActive = false
    private var faceActive = false
    private var isAnalyzing = false
    
    init(
        statusItem: NSStatusItem,
        onToggleCapture: @escaping () -> Void = {},  // Kept for compatibility but unused
        onOpenDashboard: @escaping () -> Void,
        onAnalyzeNow: @escaping () -> Void,
        onTestPopup: @escaping () -> Void = {},
        onToggleVoice: @escaping () -> Void = {},
        onToggleFace: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        self.statusItem = statusItem
        self.onOpenDashboard = onOpenDashboard
        self.onAnalyzeNow = onAnalyzeNow
        self.onQuit = onQuit
        
        self.menu = NSMenu()
        setupMenu()
    }
    
    private func setupMenu() {
        // Status indicator (shows what's active)
        statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Dashboard - primary action
        let dashboardItem = NSMenuItem(
            title: "Open Dashboard",
            action: #selector(openDashboard),
            keyEquivalent: "d"
        )
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        
        // Analyze now
        let analyzeItem = NSMenuItem(
            title: "Analyze Now",
            action: #selector(analyzeNow),
            keyEquivalent: "a"
        )
        analyzeItem.target = self
        menu.addItem(analyzeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - State Updates
    
    func updateCaptureState(isCapturing: Bool) {
        screenActive = isCapturing
        updateStatusDisplay()
    }
    
    func updateVoiceState(isCapturing: Bool) {
        voiceActive = isCapturing
        updateStatusDisplay()
    }
    
    func updateFaceState(isCapturing: Bool) {
        faceActive = isCapturing
        updateStatusDisplay()
    }
    
    func updateAnalysisState(isAnalyzing: Bool) {
        self.isAnalyzing = isAnalyzing
        updateStatusDisplay()
    }
    
    private func updateStatusDisplay() {
        var activeServices: [String] = []
        
        if screenActive { activeServices.append("📷") }
        if voiceActive { activeServices.append("🎤") }
        if faceActive { activeServices.append("👤") }
        
        if isAnalyzing {
            statusMenuItem.title = "Status: Analyzing 🧠"
            statusItem.button?.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Analyzing")
        } else if activeServices.isEmpty {
            statusMenuItem.title = "Status: Idle"
            statusItem.button?.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Idle")
        } else {
            statusMenuItem.title = "Active: \(activeServices.joined(separator: " "))"
            statusItem.button?.image = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "Active")
        }
    }
    
    func updateStats(captures: Int, insights: Int) {
        // Stats are now shown in Dashboard only
    }
    
    // MARK: - Actions
    
    @objc private func openDashboard() {
        onOpenDashboard()
    }
    
    @objc private func analyzeNow() {
        onAnalyzeNow()
    }
    
    @objc private func quit() {
        onQuit()
    }
}
