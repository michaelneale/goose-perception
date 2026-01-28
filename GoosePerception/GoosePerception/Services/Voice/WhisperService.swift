//
// WhisperService.swift
//
// Uses WhisperKit for high-quality local speech recognition.
// No dependency on system settings or Siri model downloads.
//

import Foundation
import AVFoundation
import WhisperKit

// MARK: - Whisper Transcription Service

/// Service for speech-to-text transcription using WhisperKit
///
/// Uses the openai_whisper-tiny.en model for fast English transcription.
/// Model is downloaded on first use and cached locally.
actor WhisperService {
    private var whisperKit: WhisperKit?
    
    private(set) var isLoaded = false
    private(set) var isTranscribing = false
    private(set) var loadProgress: Double = 0.0
    
    /// Model to use - tiny.en is fast and accurate for English (~40MB)
    /// Options: openai_whisper-tiny, openai_whisper-tiny.en, openai_whisper-base, openai_whisper-base.en
    static let defaultModel = "openai_whisper-tiny.en"
    
    /// Progress callback for model download
    var progressCallback: (@Sendable (Double, String) -> Void)?
    
    // MARK: - Initialization
    
    func initialize(model: String = defaultModel) async throws {
        guard !isLoaded else { return }
        
        NSLog("🎤 Initializing WhisperKit with model: %@...", model)
        
        // Notify progress
        await notifyProgress(0.1, "Loading WhisperKit...")
        
        do {
            // Initialize WhisperKit - it will download the model if needed
            // Use verbose logging to see download progress
            let config = WhisperKitConfig(
                model: model,
                verbose: true,
                logLevel: .debug
            )
            NSLog("🎤 Creating WhisperKit with config (this may download ~40-150MB model)...")
            whisperKit = try await WhisperKit(config)
            
            isLoaded = true
            await notifyProgress(1.0, "WhisperKit ready")
            NSLog("🎤 WhisperKit ready with model: %@", model)
        } catch {
            NSLog("❌ WhisperKit initialization failed: %@", error.localizedDescription)
            throw WhisperError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    func unload() {
        whisperKit = nil
        isLoaded = false
        loadProgress = 0.0
        print("🎤 WhisperService unloaded")
    }
    
    private func notifyProgress(_ progress: Double, _ message: String) async {
        loadProgress = progress
        if let callback = progressCallback {
            callback(progress, message)
        }
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio from a file URL
    func transcribe(audioURL: URL) async throws -> TranscriptionResultData {
        guard let whisper = whisperKit else {
            throw WhisperError.notInitialized
        }
        
        guard !isTranscribing else {
            throw WhisperError.transcriptionInProgress
        }
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        do {
            let results = try await whisper.transcribe(audioPath: audioURL.path)
            
            // Extract text and segments from results
            let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Build segment data from all results
            var segments: [TranscriptionSegmentData] = []
            for result in results {
                // segments is not optional in WhisperKit 0.15.0
                for segment in result.segments {
                    segments.append(TranscriptionSegmentData(
                        text: segment.text,
                        start: Float(segment.start),
                        end: Float(segment.end),
                        confidence: Double(segment.avgLogprob)
                    ))
                }
            }
            
            // Calculate average confidence
            let avgConfidence = segments.isEmpty ? 0.8 :
                segments.reduce(0.0) { $0 + $1.confidence } / Double(segments.count)
            
            return TranscriptionResultData(
                text: fullText,
                segments: segments,
                confidence: max(0, min(1, (avgConfidence + 1) / 2)) // Normalize log prob to 0-1
            )
        } catch {
            print("❌ Transcription failed: \(error)")
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Result Types

struct TranscriptionResultData {
    let text: String
    let segments: [TranscriptionSegmentData]
    let confidence: Double
}

struct TranscriptionSegmentData {
    let text: String
    let start: Float
    let end: Float
    let confidence: Double
    
    var duration: Float { end - start }
}

// MARK: - Errors

enum WhisperError: Error, LocalizedError {
    case notInitialized
    case modelLoadFailed(String)
    case transcriptionInProgress
    case transcriptionFailed(String)
    case audioProcessingFailed(String)
    case microphonePermissionDenied
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "WhisperKit not initialized. Call initialize() first."
        case .modelLoadFailed(let message):
            return "Failed to load Whisper model: \(message)"
        case .transcriptionInProgress:
            return "Transcription already in progress."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .audioProcessingFailed(let message):
            return "Failed to process audio: \(message)"
        case .microphonePermissionDenied:
            return "Microphone permission denied. Enable in System Preferences > Privacy > Microphone."
        }
    }
}

// MARK: - Audio Capture Service

/// Captures audio from the microphone and transcribes using WhisperKit
final class AudioCaptureService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempAudioURL: URL?
    
    private let whisperService: WhisperService
    private let database: Database
    
    private var _isCapturing = false
    
    /// Duration of audio chunks to transcribe (in seconds)
    private let chunkDuration: TimeInterval = 10.0
    
    /// Buffer to accumulate audio samples
    private var audioBuffer: AVAudioPCMBuffer?
    private var recordingStartTime: Date?
    private var lastTranscriptionTime: Date?
    
    /// Callback for new transcriptions
    private var transcriptionCallback: (@Sendable (String) -> Void)?
    
    /// Serial queue for audio engine operations
    private let audioQueue = DispatchQueue(label: "com.gooseperception.audio", qos: .userInitiated)
    
    /// Lock for thread-safe property access
    private let lock = NSLock()
    
    var isCapturing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCapturing
    }
    
    init(whisperService: WhisperService, database: Database) {
        self.whisperService = whisperService
        self.database = database
    }
    
    func setTranscriptionCallback(_ callback: @escaping @Sendable (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.transcriptionCallback = callback
    }
    
    func startCapturing() async throws {
        lock.lock()
        if _isCapturing {
            lock.unlock()
            return
        }
        lock.unlock()
        
        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw WhisperError.microphonePermissionDenied
            }
        } else if micStatus != .authorized {
            throw WhisperError.microphonePermissionDenied
        }
        
        // Initialize WhisperKit if needed
        if await !whisperService.isLoaded {
            print("🎤 Loading WhisperKit model (first time may download ~150MB)...")
            Task { @MainActor in
                ActivityLogStore.shared.log(.voice, "Loading WhisperKit model (may download ~150MB)...")
            }
            try await whisperService.initialize()
        }
        
        // Setup audio engine on dedicated queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioQueue.async { [self] in
                do {
                    let engine = AVAudioEngine()
                    let inputNode = engine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    
                    // Create temp directory for audio files
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("GoosePerception", isDirectory: true)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    // Start new audio file
                    try self.startNewAudioFileSync(in: tempDir, format: recordingFormat)
                    
                    self.lock.lock()
                    self.recordingStartTime = Date()
                    self.lastTranscriptionTime = Date()
                    self.lock.unlock()
                    
                    // Track audio levels for UI feedback
                    var frameCount = 0
                    var lastLevelLog = Date()
                    
                    // Install audio tap
                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
                        guard let self = self else { return }
                        
                        // Write buffer to file synchronously on audio queue
                        self.writeBufferSync(buffer)
                        
                        // Calculate RMS level for feedback
                        let channelData = buffer.floatChannelData?[0]
                        let frameLength = Int(buffer.frameLength)
                        var rms: Float = 0
                        if let data = channelData, frameLength > 0 {
                            for i in 0..<frameLength {
                                rms += data[i] * data[i]
                            }
                            rms = sqrt(rms / Float(frameLength))
                        }
                        
                        // Update UI audio level (throttled)
                        frameCount += 1
                        if frameCount % 5 == 0 {
                            let level = min(rms * 10, 1.0)
                            Task { @MainActor in
                                ServiceStateManager.shared.audioLevel = level
                            }
                        }
                        
                        // Log periodically
                        let now = Date()
                        if now.timeIntervalSince(lastLevelLog) >= 15 && rms > 0.001 {
                            lastLevelLog = now
                            Task { @MainActor in
                                ActivityLogStore.shared.log(.voice, "🎤 Listening... (level: \(String(format: "%.0f", rms * 1000)))")
                            }
                        }
                        
                        // Check if we should transcribe the chunk
                        self.checkAndTranscribeChunkSync()
                    }
                    
                    engine.prepare()
                    try engine.start()
                    
                    self.lock.lock()
                    self.audioEngine = engine
                    self._isCapturing = true
                    self.lock.unlock()
                    
                    print("🎤 Audio capture started (WhisperKit)")
                    Task { @MainActor in
                        ActivityLogStore.shared.log(.voice, "🎤 Voice capture started - listening with WhisperKit")
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func startNewAudioFileSync(in directory: URL, format: AVAudioFormat) throws {
        // Close existing file
        lock.lock()
        audioFile = nil
        
        // Create new temp file
        let filename = "audio_\(Int(Date().timeIntervalSince1970)).wav"
        let url = directory.appendingPathComponent(filename)
        tempAudioURL = url
        lock.unlock()
        
        // Create audio file with proper settings for Whisper (16kHz mono preferred)
        // But we'll use the input format and let WhisperKit handle conversion
        lock.lock()
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        lock.unlock()
    }
    
    private func writeBufferSync(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let file = audioFile
        lock.unlock()
        
        guard let file = file else { return }
        
        do {
            try file.write(from: buffer)
        } catch {
            print("❌ Failed to write audio buffer: \(error)")
        }
    }
    
    private func checkAndTranscribeChunkSync() {
        lock.lock()
        let lastTime = lastTranscriptionTime
        lock.unlock()
        
        guard let lastTime = lastTime else { return }
        
        let elapsed = Date().timeIntervalSince(lastTime)
        
        // Transcribe every chunkDuration seconds
        if elapsed >= chunkDuration {
            Task {
                await self.transcribeCurrentChunk()
            }
        }
    }
    
    private func transcribeCurrentChunk() async {
        lock.lock()
        let audioURL = tempAudioURL
        let engine = audioEngine
        lock.unlock()
        
        guard let audioURL = audioURL, let engine = engine else { return }
        
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        
        // Close current file and start a new one
        let urlToTranscribe = audioURL
        lock.lock()
        audioFile = nil
        lock.unlock()
        
        // Start new file for continued recording
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoosePerception", isDirectory: true)
        
        do {
            try startNewAudioFileSync(in: tempDir, format: inputFormat)
        } catch {
            print("❌ Failed to start new audio file: \(error)")
            return
        }
        
        lock.lock()
        lastTranscriptionTime = Date()
        lock.unlock()
        
        // Transcribe the completed chunk
        do {
            let result = try await whisperService.transcribe(audioURL: urlToTranscribe)
            
            if !result.text.isEmpty {
                handleTranscription(result.text, confidence: result.confidence)
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: urlToTranscribe)
        } catch {
            print("❌ Transcription failed: \(error)")
            Task { @MainActor in
                ActivityLogStore.shared.log(.voice, "⚠️ Transcription error: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleTranscription(_ transcript: String, confidence: Double) {
        // Skip blank/empty transcriptions
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let blankPatterns = ["BLANK_AUDIO", "[BLANK", "(BLANK", "[ Silence ]", "[silence]", "[Music]", "[music]"]
        
        let isBlank = trimmed.isEmpty || blankPatterns.contains { trimmed.uppercased().contains($0.uppercased()) }
        
        if isBlank {
            print("🎤 Skipping blank/silent audio segment")
            return
        }
        
        // Store in database
        Task {
            do {
                let segment = VoiceSegment(
                    timestamp: Date().addingTimeInterval(-self.chunkDuration),
                    endTimestamp: Date(),
                    transcript: transcript,
                    confidence: confidence
                )
                _ = try await self.database.insertVoiceSegment(segment)
            } catch {
                print("❌ Failed to store voice segment: \(error)")
            }
        }
        
        // Notify callback
        lock.lock()
        let callback = transcriptionCallback
        lock.unlock()
        
        if let callback = callback {
            callback(transcript)
        }
        
        // Update UI
        Task { @MainActor in
            ServiceStateManager.shared.lastTranscription = String(transcript.suffix(100))
        }
        
        print("🎤 Transcribed: \(transcript.prefix(50))...")
    }
    
    func stopCapturing() {
        lock.lock()
        if !_isCapturing {
            lock.unlock()
            return
        }
        let audioURL = tempAudioURL
        let engine = audioEngine
        _isCapturing = false
        audioEngine = nil
        audioFile = nil
        tempAudioURL = nil
        lock.unlock()
        
        // Transcribe any remaining audio
        if let audioURL = audioURL {
            Task {
                do {
                    let result = try await self.whisperService.transcribe(audioURL: audioURL)
                    if !result.text.isEmpty {
                        self.handleTranscription(result.text, confidence: result.confidence)
                    }
                } catch {
                    print("⚠️ Final transcription failed: \(error)")
                }
                
                // Clean up
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        
        // Stop engine on audio queue
        audioQueue.async {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
        }
        
        Task { @MainActor in
            ServiceStateManager.shared.audioLevel = 0
        }
        
        print("🎤 Audio capture stopped")
    }
}

// MARK: - Legacy Compatibility

/// SpeechService alias for backward compatibility
typealias SpeechService = WhisperService

/// SpeechError alias for backward compatibility  
typealias SpeechError = WhisperError
