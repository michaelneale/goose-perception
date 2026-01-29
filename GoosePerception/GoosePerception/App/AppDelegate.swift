import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.goose.perception", category: "AppDelegate")

// MARK: - Preferences (Simple UserDefaults wrapper)

@MainActor
final class Preferences {
    static let shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    private let kScreen = "pref_screen_capture"
    private let kVoice = "pref_voice_capture"
    private let kFace = "pref_face_capture"
    
    var screenCaptureEnabled: Bool {
        get { defaults.bool(forKey: kScreen) }
        set { 
            defaults.set(newValue, forKey: kScreen)
            NSLog("💾 Pref: screen = %@", newValue ? "ON" : "OFF")
        }
    }
    
    var voiceCaptureEnabled: Bool {
        get { defaults.bool(forKey: kVoice) }
        set { 
            defaults.set(newValue, forKey: kVoice)
            NSLog("💾 Pref: voice = %@", newValue ? "ON" : "OFF")
        }
    }
    
    var faceCaptureEnabled: Bool {
        get { defaults.bool(forKey: kFace) }
        set { 
            defaults.set(newValue, forKey: kFace)
            NSLog("💾 Pref: face = %@", newValue ? "ON" : "OFF")
        }
    }
    
    private init() {
        NSLog("📋 Prefs loaded: screen=%@, voice=%@, face=%@",
              screenCaptureEnabled ? "ON" : "OFF",
              voiceCaptureEnabled ? "ON" : "OFF",
              faceCaptureEnabled ? "ON" : "OFF")
    }
}

// MARK: - Service State (UI binding only, no persistence)

@MainActor
final class ServiceStateManager: ObservableObject {
    static let shared = ServiceStateManager()
    
    @Published var isScreenCaptureRunning = false
    @Published var isVoiceCaptureRunning = false
    @Published var isFaceCaptureRunning = false
    @Published var isVLMEnabled = false
    @Published var isAnalysisRunning = false
    
    @Published var screenCaptureInterval: Double = 20
    @Published var voiceSensitivity: Double = 0.5
    @Published var faceDetectionInterval: Double = 2.0
    
    @Published var lastError: String?
    @Published var servicesReady = false
    
    @Published var audioLevel: Float = 0.0
    @Published var lastTranscription: String = ""
    
    @Published var isFacePresent: Bool = false
    @Published var currentEmotion: String = ""
    @Published var emotionConfidence: Double = 0.0
    
    private init() {}
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarController!
    
    private var screenCaptureService: ScreenCaptureService!
    private var ocrProcessor: OCRProcessor!
    private var database: Database!
    private var llmService: LLMService!
    private var analysisScheduler: AnalysisScheduler!
    private var tinyAgentService: TinyAgentService!
    
    private var vlmService: VLMService!
    private var whisperService: WhisperService!
    private var audioCaptureService: AudioCaptureService!
    private var cameraCaptureService: CameraCaptureService!
    private var directoryActivityService: DirectoryActivityService!
    
    private var insightPopupManager: InsightPopupManager!
    private let stateManager = ServiceStateManager.shared
    private let prefs = Preferences.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            NSLog("🧪 Running self-test mode...")
            Task { await SelfTest.run() }
            return
        }
        
        logger.info("🚀 Goose Perception starting...")
        NSApp.setActivationPolicy(.accessory)
        
        setupMenuBar()
        insightPopupManager = InsightPopupManager()
        setupDashboardNotifications()
        
        Task { await initializeServices() }
    }
    
    private func setupDashboardNotifications() {
        NotificationCenter.default.addObserver(forName: .toggleScreenCapture, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggleScreenCapture() }
        }
        NotificationCenter.default.addObserver(forName: .toggleVoiceCapture, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggleVoiceCapture() }
        }
        NotificationCenter.default.addObserver(forName: .toggleFaceCapture, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggleFaceCapture() }
        }
        NotificationCenter.default.addObserver(forName: .runAnalysisNow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.runAnalysis() }
        }
        NotificationCenter.default.addObserver(forName: .startFaceCalibration, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Reduce detection interval during calibration for faster samples
                await self?.cameraCaptureService?.setDetectionInterval(0.5)
            }
        }
        // Update calibration when it completes
        NotificationCenter.default.addObserver(forName: .updateFaceCalibration, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.cameraCaptureService?.updateCalibration(FaceCalibrationManager.shared.calibrationData)
                await self?.cameraCaptureService?.setDetectionInterval(2.0)
            }
        }
    }
    
    private func initializeServices() async {
        ActivityLogStore.shared.log(.system, "🚀 Starting up...")
        
        database = Database.shared
        screenCaptureService = ScreenCaptureService(database: database)
        ocrProcessor = OCRProcessor()
        llmService = LLMService()
        analysisScheduler = AnalysisScheduler(database: database, llmService: llmService)
        
        vlmService = VLMService()
        whisperService = WhisperService()
        audioCaptureService = AudioCaptureService(whisperService: whisperService, database: database)
        cameraCaptureService = CameraCaptureService(database: database)
        directoryActivityService = DirectoryActivityService(database: database)
        
        // Initialize TinyAgent and ActionService for automation
        tinyAgentService = TinyAgentService()
        ActionService.initialize(tinyAgentService: tinyAgentService)
        
        NSLog("✅ All services initialized")
        
        // Callbacks - insights just go to the list, actions get popups
        analysisScheduler.setInsightCallback { content in
            Task { @MainActor in
                ActivityLogStore.shared.log(.llm, "💡 Insight", detail: content)
            }
        }
        
        analysisScheduler.setActionCallback { [weak self] action in
            Task { @MainActor in
                guard let actionId = action.id else { return }
                // Show proper action popup
                self?.insightPopupManager.showAction(
                    id: actionId,
                    title: action.title,
                    message: action.message,
                    source: action.source
                )
            }
        }
        
        // Wire up action completion/dismissal to update database
        insightPopupManager.onActionDismissed = { [weak self] actionId in
            Task {
                try? await self?.database.markActionDismissed(id: actionId)
            }
        }
        insightPopupManager.onActionCompleted = { [weak self] actionId in
            Task {
                try? await self?.database.markActionCompleted(id: actionId)
            }
        }
        
        audioCaptureService.setTranscriptionCallback { transcript in
            Task { @MainActor in
                ActivityLogStore.shared.log(.voice, "🎤 Transcribed", detail: transcript)
                ServiceStateManager.shared.lastTranscription = String(transcript.suffix(100))
            }
        }
        
        cameraCaptureService.setPresenceCallback { present in
            Task { @MainActor in
                ServiceStateManager.shared.isFacePresent = present
                if !present {
                    ServiceStateManager.shared.currentEmotion = ""
                    ServiceStateManager.shared.emotionConfidence = 0
                }
                ActivityLogStore.shared.log(.face, present ? "Face detected" : "No face detected")
            }
        }
        
        cameraCaptureService.setEmotionCallback { emotion, confidence in
            Task { @MainActor in
                ServiceStateManager.shared.currentEmotion = emotion
                ServiceStateManager.shared.emotionConfidence = confidence
                ActivityLogStore.shared.log(.face, "Emotion: \(emotion) (\(Int(confidence * 100))%)")
            }
        }
        
        stateManager.servicesReady = true
        ActivityLogStore.shared.log(.system, "✅ All services ready")
        
        preloadLLMModel()
        analysisScheduler.start()
        
        // Start directory activity tracking (always on, low overhead)
        await directoryActivityService.startCapturing()
        
        // Restore saved states
        await restoreServices()
    }
    
    private func restoreServices() async {
        NSLog("🔧 RESTORE: screen=%@, voice=%@, face=%@",
              prefs.screenCaptureEnabled ? "ON" : "OFF",
              prefs.voiceCaptureEnabled ? "ON" : "OFF",
              prefs.faceCaptureEnabled ? "ON" : "OFF")

        // Load device preferences
        let deviceManager = DeviceManager.shared
        NSLog("🔧 RESTORE: audio device=%@, video device=%@",
              deviceManager.selectedAudioDeviceID ?? "default",
              deviceManager.selectedVideoDeviceID ?? "default")

        // Screen
        if prefs.screenCaptureEnabled {
            do {
                try await screenCaptureService.startCapturing()
                stateManager.isScreenCaptureRunning = true
                menuBarController.updateCaptureState(isCapturing: true)
                NSLog("✅ Screen restored")
            } catch {
                NSLog("❌ Screen restore failed: %@", error.localizedDescription)
                prefs.screenCaptureEnabled = false
            }
        }

        // Voice - apply saved device preference
        if prefs.voiceCaptureEnabled {
            do {
                audioCaptureService.setAudioDevice(deviceManager.selectedAudioDeviceID)
                try await audioCaptureService.startCapturing()
                stateManager.isVoiceCaptureRunning = true
                menuBarController.updateVoiceState(isCapturing: true)
                NSLog("✅ Voice restored")
            } catch {
                NSLog("❌ Voice restore failed: %@", error.localizedDescription)
                prefs.voiceCaptureEnabled = false
            }
        }

        // Face - apply saved device preference and calibration
        if prefs.faceCaptureEnabled {
            do {
                await cameraCaptureService.setVideoDevice(deviceManager.selectedVideoDeviceID)
                await cameraCaptureService.updateCalibration(FaceCalibrationManager.shared.calibrationData)
                try await cameraCaptureService.startCapturing()
                stateManager.isFaceCaptureRunning = true
                menuBarController.updateFaceState(isCapturing: true)
                NSLog("✅ Face restored")
            } catch {
                NSLog("❌ Face restore failed: %@", error.localizedDescription)
                prefs.faceCaptureEnabled = false
            }
        }
        
        NSLog("🔧 RESTORE DONE")
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Goose Perception")
            NSLog("👁️ Menu bar icon set")
        } else {
            NSLog("❌ Failed to get status item button")
        }
        
        menuBarController = MenuBarController(
            statusItem: statusItem,
            onToggleCapture: { [weak self] in self?.toggleScreenCapture() },
            onOpenDashboard: { [weak self] in self?.openDashboard() },
            onAnalyzeNow: { [weak self] in self?.runAnalysis() },
            onToggleVoice: { [weak self] in self?.toggleVoiceCapture() },
            onToggleFace: { [weak self] in self?.toggleFaceCapture() },
            onQuit: { NSApp.terminate(nil) }
        )
        
        statusItem.menu = menuBarController.menu
    }
    
    private func runAnalysis() {
        guard !stateManager.isAnalysisRunning else {
            ToastNotificationManager.shared.showToast("Analysis already running", isError: false)
            return
        }
        
        Task {
            stateManager.isAnalysisRunning = true
            menuBarController.updateAnalysisState(isAnalyzing: true)
            ToastNotificationManager.shared.showToast("Running analysis...")
            
            await analysisScheduler.runAnalysisNow()
            
            stateManager.isAnalysisRunning = false
            menuBarController.updateAnalysisState(isAnalyzing: false)
            menuBarController.updateCaptureState(isCapturing: stateManager.isScreenCaptureRunning)
            ToastNotificationManager.shared.showSuccess("Analysis complete")
        }
    }
    
    // MARK: - Toggle Methods
    
    private func toggleScreenCapture() {
        guard stateManager.servicesReady else {
            ToastNotificationManager.shared.showError("Services not ready yet")
            return
        }
        
        let newState = !stateManager.isScreenCaptureRunning
        
        // Update UI immediately
        stateManager.isScreenCaptureRunning = newState
        menuBarController.updateCaptureState(isCapturing: newState)
        
        // Save preference immediately
        prefs.screenCaptureEnabled = newState
        
        Task {
            if newState {
                do {
                    try await screenCaptureService.startCapturing()
                    ActivityLogStore.shared.log(.screen, "Screen capture started")
                    ToastNotificationManager.shared.showSuccess("Screen capture started")
                } catch {
                    // Revert on failure
                    stateManager.isScreenCaptureRunning = false
                    menuBarController.updateCaptureState(isCapturing: false)
                    prefs.screenCaptureEnabled = false
                    stateManager.lastError = error.localizedDescription
                    ToastNotificationManager.shared.showError("Enable Screen Recording in System Settings")
                }
            } else {
                await screenCaptureService.stopCapturing()
                ActivityLogStore.shared.log(.screen, "Screen capture stopped")
                ToastNotificationManager.shared.showSuccess("Screen capture stopped")
            }
        }
    }
    
    private func toggleVoiceCapture() {
        guard stateManager.servicesReady else {
            ToastNotificationManager.shared.showError("Services not ready yet")
            return
        }

        let newState = !stateManager.isVoiceCaptureRunning

        // Update UI immediately
        stateManager.isVoiceCaptureRunning = newState
        menuBarController.updateVoiceState(isCapturing: newState)

        // Save preference immediately
        prefs.voiceCaptureEnabled = newState

        Task {
            if newState {
                do {
                    // Set the selected audio device before starting
                    audioCaptureService.setAudioDevice(DeviceManager.shared.selectedAudioDeviceID)
                    try await audioCaptureService.startCapturing()
                    ActivityLogStore.shared.log(.voice, "Voice capture started")
                    ToastNotificationManager.shared.showSuccess("Voice capture started")
                } catch {
                    // Revert on failure
                    stateManager.isVoiceCaptureRunning = false
                    menuBarController.updateVoiceState(isCapturing: false)
                    prefs.voiceCaptureEnabled = false
                    stateManager.lastError = error.localizedDescription
                    ToastNotificationManager.shared.showError("Voice capture failed")
                }
            } else {
                audioCaptureService.stopCapturing()
                ActivityLogStore.shared.log(.voice, "Voice capture stopped")
                ToastNotificationManager.shared.showSuccess("Voice capture stopped")
            }
        }
    }

    private func toggleFaceCapture() {
        guard stateManager.servicesReady else {
            ToastNotificationManager.shared.showError("Services not ready yet")
            return
        }

        let newState = !stateManager.isFaceCaptureRunning

        // Update UI immediately
        stateManager.isFaceCaptureRunning = newState
        menuBarController.updateFaceState(isCapturing: newState)

        // Save preference immediately
        prefs.faceCaptureEnabled = newState

        Task {
            if newState {
                do {
                    // Set the selected camera device before starting
                    await cameraCaptureService.setVideoDevice(DeviceManager.shared.selectedVideoDeviceID)
                    try await cameraCaptureService.startCapturing()
                    ActivityLogStore.shared.log(.face, "Face detection started")
                    ToastNotificationManager.shared.showSuccess("Face detection started")
                } catch {
                    // Revert on failure
                    stateManager.isFaceCaptureRunning = false
                    menuBarController.updateFaceState(isCapturing: false)
                    prefs.faceCaptureEnabled = false
                    stateManager.lastError = error.localizedDescription
                    ToastNotificationManager.shared.showError("Camera access failed")
                }
            } else {
                cameraCaptureService.stopCapturing()
                ActivityLogStore.shared.log(.face, "Face detection stopped")
                ToastNotificationManager.shared.showSuccess("Face detection stopped")
            }
        }
    }
    
    // MARK: - Dashboard
    
    private var dashboardWindow: NSWindow?
    private var dashboardWindowDelegate: DashboardWindowDelegate?

    private func openDashboard() {
        // Guard against opening before services are initialized
        guard stateManager.servicesReady, database != nil else {
            ToastNotificationManager.shared.showError("Services still loading, please wait...")
            return
        }

        // Check if window exists and is valid
        if let window = dashboardWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Clear any stale reference
        dashboardWindow = nil
        dashboardWindowDelegate = nil

        let dashboardView = DashboardView(database: database)
        let hostingController = NSHostingController(rootView: dashboardView)
        hostingController.preferredContentSize = NSSize(width: 1000, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Goose Perception Dashboard"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 800, height: 500)
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        window.isReleasedWhenClosed = false

        // Set up delegate to clear reference when window closes
        let delegate = DashboardWindowDelegate { [weak self] in
            self?.dashboardWindow = nil
            self?.dashboardWindowDelegate = nil
        }
        window.delegate = delegate
        dashboardWindowDelegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        dashboardWindow = window
    }
    
    private func preloadLLMModel() {
        Task {
            do {
                NSLog("🧠 Pre-loading LLM model...")
                _ = try await llmService.loadModel()
                NSLog("🧠 LLM model ready")
                stateManager.isVLMEnabled = true
            } catch {
                NSLog("⚠️ LLM pre-load failed: %@", error.localizedDescription)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when dashboard window is closed - this is a menu bar app
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("👋 Shutting down...")
        Task {
            await screenCaptureService?.stopCapturing()
            audioCaptureService?.stopCapturing()
            cameraCaptureService?.stopCapturing()
            await directoryActivityService?.stopCapturing()
        }
    }
}

// MARK: - Dashboard Window Delegate

class DashboardWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
