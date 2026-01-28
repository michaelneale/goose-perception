import Foundation
@preconcurrency import AVFoundation
import CoreImage
import os.log

private let logger = Logger(subsystem: "com.goose.perception", category: "CameraCapture")

/// Delegate class for handling camera frame callbacks
/// This is needed because AVCaptureVideoDataOutputSampleBufferDelegate requires NSObject
final class CameraFrameHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onFrame: (CMSampleBuffer) -> Void
    
    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame(sampleBuffer)
    }
}

/// Service for capturing camera frames for face detection
/// Privacy-preserving: no images are stored, only face events
actor CameraCaptureService {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameHandler: CameraFrameHandler?
    private let faceDetector = FaceDetector()
    private let emotionSmoother = EmotionSmoother()
    private let database: Database
    
    private(set) var isCapturing = false
    private var lastDetectionTime: Date?
    private var detectionInterval: TimeInterval = 2.0 // seconds between detections
    
    // Callbacks for presence changes
    private var presenceCallback: ((Bool) -> Void)?
    private var emotionCallback: ((String, Double) -> Void)?
    
    // Serial queue for camera operations
    private let cameraQueue = DispatchQueue(label: "com.gooseperception.camera", qos: .userInitiated)
    
    // Processing queue for face detection (separate from camera queue)
    private let processingQueue = DispatchQueue(label: "com.gooseperception.faceprocessing", qos: .utility)
    
    init(database: Database) {
        self.database = database
    }
    
    nonisolated func setPresenceCallback(_ callback: @escaping (Bool) -> Void) {
        Task { await self.setPresenceCallbackInternal(callback) }
    }
    
    private func setPresenceCallbackInternal(_ callback: @escaping (Bool) -> Void) {
        self.presenceCallback = callback
    }
    
    nonisolated func setEmotionCallback(_ callback: @escaping (String, Double) -> Void) {
        Task { await self.setEmotionCallbackInternal(callback) }
    }
    
    private func setEmotionCallbackInternal(_ callback: @escaping (String, Double) -> Void) {
        self.emotionCallback = callback
    }
    
    func startCapturing() async throws {
        guard !isCapturing else {
            logger.info("Camera already capturing, skipping start")
            return
        }
        
        // Check camera permission
        let hasPermission = await checkCameraPermission()
        guard hasPermission else {
            logger.error("Camera permission denied")
            throw CameraError.permissionDenied
        }
        
        logger.info("Starting camera capture...")
        
        // Setup capture session
        do {
            let session = AVCaptureSession()
            session.sessionPreset = .low // Low resolution for privacy and performance
            
            // Get camera
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                logger.error("No front camera available")
                throw CameraError.cameraNotAvailable
            }
            
            // Add input
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                logger.error("Cannot add camera input")
                throw CameraError.inputNotSupported
            }
            session.addInput(input)
            
            // Add output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            
            // Create frame handler with callback - use nonisolated handler
            let handler = CameraFrameHandler { [weak self] sampleBuffer in
                guard let self = self else { return }
                // Process on a separate queue to avoid blocking camera
                self.processingQueue.async {
                    Task {
                        await self.handleFrame(sampleBuffer)
                    }
                }
            }
            
            output.setSampleBufferDelegate(handler, queue: cameraQueue)
            
            guard session.canAddOutput(output) else {
                logger.error("Cannot add video output")
                throw CameraError.outputNotSupported
            }
            session.addOutput(output)
            
            // Configure for low frame rate (we only need periodic captures)
            if let connection = output.connection(with: .video) {
                connection.videoRotationAngle = 0
            }
            
            // Set low frame rate to save power (with safety checks)
            // Note: Not all cameras/formats support arbitrary frame durations
            do {
                try camera.lockForConfiguration()
                
                // Check if the active format supports the desired frame rate range
                let format = camera.activeFormat
                let ranges = format.videoSupportedFrameRateRanges
                if let range = ranges.first, range.minFrameRate <= 2.0 {
                    // Only set if 2 FPS is within supported range
                    camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 2) // 2 FPS max
                    camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 1) // 1 FPS min
                    logger.info("Set camera to low frame rate mode (1-2 FPS)")
                } else {
                    logger.info("Camera doesn't support low frame rate, using default")
                }
                
                camera.unlockForConfiguration()
            } catch {
                logger.warning("Could not configure camera frame rate: \(error.localizedDescription)")
                // Continue anyway - frame rate config is optional
            }
            
            // Store references
            self.captureSession = session
            self.videoOutput = output
            self.frameHandler = handler
            self.isCapturing = true
            
            // Start the session on camera queue
            cameraQueue.async {
                session.startRunning()
            }
            
            // Give it a moment to start
            try? await Task.sleep(for: .milliseconds(100))
            
            logger.info("Camera capture session started successfully")
        } catch {
            logger.error("Camera setup failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    nonisolated func stopCapturing() {
        Task { await self.stopCapturingInternal() }
    }
    
    private func stopCapturingInternal() {
        logger.info("Stopping camera capture...")
        
        let session = captureSession
        captureSession = nil
        videoOutput = nil
        frameHandler = nil
        isCapturing = false
        
        cameraQueue.async {
            session?.stopRunning()
        }
        
        logger.info("Camera capture stopped")
    }
    
    func setDetectionInterval(_ interval: TimeInterval) {
        detectionInterval = max(0.5, min(10, interval))
    }
    
    // MARK: - Private Methods
    
    private nonisolated func checkCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    /// Handle frame - called on actor
    private func handleFrame(_ sampleBuffer: CMSampleBuffer) async {
        // Rate limit detection
        let now = Date()
        
        if let lastTime = lastDetectionTime, now.timeIntervalSince(lastTime) < detectionInterval {
            return
        }
        
        self.lastDetectionTime = now
        
        // Convert to CGImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = createCGImage(from: pixelBuffer) else {
            return
        }
        
        // Process face detection
        do {
            let detection = try await faceDetector.detectFace(in: cgImage)
            
            // Smooth emotion if present
            let finalEmotion: (emotion: String, confidence: Double)?
            if let emotion = detection.emotion {
                finalEmotion = await emotionSmoother.addDetection(emotion.emotion, confidence: emotion.confidence)
            } else {
                finalEmotion = nil
            }
            
            // Store event in database
            let event = FaceEvent(
                timestamp: now,
                userHash: detection.userHash,
                present: detection.isPresent,
                emotion: finalEmotion?.emotion,
                confidence: finalEmotion?.confidence
            )
            
            _ = try? await database.insertFaceEvent(event)
            
            // Notify callbacks on main thread
            let presenceCb = presenceCallback
            let emotionCb = emotionCallback
            
            await MainActor.run {
                presenceCb?(detection.isPresent)
                if let emotion = finalEmotion {
                    emotionCb?(emotion.emotion, emotion.confidence)
                }
            }
        } catch {
            logger.error("Face detection error: \(error.localizedDescription)")
        }
    }
    
    private nonisolated func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - Errors

enum CameraError: Error, LocalizedError {
    case permissionDenied
    case cameraNotAvailable
    case inputNotSupported
    case outputNotSupported
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable in System Preferences > Privacy & Security > Camera."
        case .cameraNotAvailable:
            return "No camera available."
        case .inputNotSupported:
            return "Camera input not supported."
        case .outputNotSupported:
            return "Video output not supported."
        }
    }
}
