//
// LLMService.swift
//
// In-process LLM using MLX with focused single-purpose calls
//

import Foundation
import os.log
import MLX
import MLXLLM
import MLXLMCommon

private let llmLogger = Logger(subsystem: "com.goose.perception", category: "LLMService")

// MARK: - Session Entry (groups a single LLM call: system + user + response)

struct LLMSessionEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let title: String  // e.g., "Extract Projects", "Extract Collaborators"
    let systemPrompt: String
    let userPrompt: String
    var response: String?
    var error: String?
    var isComplete: Bool = false
    
    var isSuccess: Bool { response != nil && error == nil }
}

/// Shared session log for UI - shows grouped conversations
@MainActor
class LLMSessionStore: ObservableObject {
    static let shared = LLMSessionStore()
    
    @Published var sessions: [LLMSessionEntry] = []
    @Published var currentSession: LLMSessionEntry?
    
    // Track in-flight sessions for concurrent calls
    private var inFlightSessions: [UUID: LLMSessionEntry] = [:]
    
    func startSession(title: String, system: String, user: String) -> UUID {
        let session = LLMSessionEntry(
            timestamp: Date(),
            title: title,
            systemPrompt: system,
            userPrompt: user
        )
        inFlightSessions[session.id] = session
        currentSession = session
        return session.id
    }
    
    func completeSession(id: UUID, response: String) {
        if var session = inFlightSessions.removeValue(forKey: id) {
            session.response = response
            session.isComplete = true
            sessions.append(session)
            
            // Clear currentSession if it matches
            if currentSession?.id == id {
                currentSession = nil
            }
            
            NSLog("📝 Session completed: %@ - %d chars", session.title, response.count)
        } else {
            NSLog("⚠️ Session not found for completion: %@", id.uuidString)
        }
    }
    
    func failSession(id: UUID, error: String) {
        if var session = inFlightSessions.removeValue(forKey: id) {
            session.error = error
            session.isComplete = true
            sessions.append(session)
            
            if currentSession?.id == id {
                currentSession = nil
            }
        }
    }
    
    func clear() {
        sessions.removeAll()
        inFlightSessions.removeAll()
        currentSession = nil
    }
}

// MARK: - Legacy Log Entry (kept for backward compat)

struct LLMLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let content: String
    
    enum LogType: String {
        case systemPrompt = "System"
        case userPrompt = "User"
        case response = "Response"
        case error = "Error"
        case info = "Info"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LLMLogEntry, rhs: LLMLogEntry) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class LLMLogStore: ObservableObject {
    static let shared = LLMLogStore()
    @Published var entries: [LLMLogEntry] = []
    
    func append(_ entry: LLMLogEntry) {
        entries.append(entry)
        if entries.count > 100 {
            entries.removeFirst(entries.count - 100)
        }
    }
    
    func clear() {
        entries.removeAll()
    }
}

// MARK: - Analysis Result

struct AnalysisResult {
    var projects: [String] = []
    var collaborators: [String] = []
    var interests: [String] = []
    var todos: [String] = []
}

// MARK: - LLM Errors

enum LLMError: Error, LocalizedError {
    case modelNotLoaded
    case generationInProgress
    case loadingInProgress
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM model not loaded."
        case .generationInProgress: return "Generation already in progress."
        case .loadingInProgress: return "Model is still loading."
        case .invalidResponse: return "Invalid response from model."
        }
    }
}

// MARK: - LLM Service

@MainActor
class LLMService: ObservableObject {
    
    enum LoadState: Equatable {
        case idle
        case loading(progress: Double)
        case loaded
        case failed(String)
    }
    
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isGenerating = false
    
    private var modelContainer: ModelContainer?
    
    static let defaultModel = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    
    var isLoaded: Bool { modelContainer != nil }
    var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }
    
    // MARK: - Model Loading
    
    func loadModel(modelId: String? = nil) async throws {
        let model = modelId ?? Self.defaultModel
        
        guard loadState != .loading(progress: 0) else {
            throw LLMError.loadingInProgress
        }
        
        loadState = .loading(progress: 0)
        NSLog("🧠 Loading model: %@", model)
        
        let container = try await Task.detached { [weak self] in
            let config = ModelConfiguration(id: model)
            let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Task { @MainActor in
                    self?.loadState = .loading(progress: progress.fractionCompleted)
                }
            }
            return container
        }.value
        
        self.modelContainer = container
        loadState = .loaded
        NSLog("🧠 Model loaded successfully")
    }
    
    func unloadModel() {
        modelContainer = nil
        loadState = .idle
    }
    
    // MARK: - Context for Analysis
    
    struct AnalysisContext {
        let captures: [ScreenCapture]
        let voiceTranscripts: [VoiceSegment]
        let faceEvents: [FaceEvent]
        
        var moodSummary: String {
            guard !faceEvents.isEmpty else { return "No mood data" }
            
            // Count emotions
            var emotionCounts: [String: Int] = [:]
            for event in faceEvents {
                if let emotion = event.emotion {
                    emotionCounts[emotion, default: 0] += 1
                }
            }
            
            guard !emotionCounts.isEmpty else { return "No mood data" }
            
            // Find dominant emotion
            let sorted = emotionCounts.sorted { $0.value > $1.value }
            let total = emotionCounts.values.reduce(0, +)
            
            if let top = sorted.first {
                let percentage = Int(Double(top.value) / Double(total) * 100)
                let others = sorted.dropFirst().prefix(2).map { $0.key }.joined(separator: ", ")
                if others.isEmpty {
                    return "\(top.key) (\(percentage)%)"
                } else {
                    return "\(top.key) (\(percentage)%), also: \(others)"
                }
            }
            return "Mixed"
        }
        
        var transcriptSummary: String {
            guard !voiceTranscripts.isEmpty else { return "" }
            
            let allText = voiceTranscripts.map { $0.transcript }.joined(separator: " ")
            // Limit to 500 chars
            return String(allText.prefix(500))
        }
    }
    
    // MARK: - Text Formatting
    
    private func formatContextForLLM(_ context: AnalysisContext) -> String {
        var lines: [String] = []
        
        // Voice transcripts
        if !context.transcriptSummary.isEmpty {
            lines.append("=== SPOKEN (voice transcription) ===")
            lines.append(context.transcriptSummary)
            lines.append("")
        }
        
        // Mood
        if context.moodSummary != "No mood data" {
            lines.append("=== MOOD ===")
            lines.append("User appears: \(context.moodSummary)")
            lines.append("")
        }
        
        // Screen activity
        lines.append("=== SCREEN ACTIVITY ===")
        lines.append(formatCapturesForLLM(context.captures))
        
        return lines.joined(separator: "\n")
    }
    
    private func formatCapturesForLLM(_ captures: [ScreenCapture]) -> String {
        var lines: [String] = []
        var allOtherWindows: Set<String> = []
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        // Group captures by window to deduplicate
        // Key: "App — Window", Value: (count, latestCapture, firstTime, lastTime)
        var windowGroups: [String: (count: Int, latest: ScreenCapture, firstTime: Date, lastTime: Date)] = [:]
        
        for capture in captures {
            let app = capture.focusedApp ?? "Unknown"
            let window = capture.focusedWindow ?? ""
            let key = window.isEmpty ? app : "\(app) — \(window)"
            
            if let existing = windowGroups[key] {
                windowGroups[key] = (
                    count: existing.count + 1,
                    latest: capture.timestamp > existing.latest.timestamp ? capture : existing.latest,
                    firstTime: min(existing.firstTime, capture.timestamp),
                    lastTime: max(existing.lastTime, capture.timestamp)
                )
            } else {
                windowGroups[key] = (count: 1, latest: capture, firstTime: capture.timestamp, lastTime: capture.timestamp)
            }
            
            // Collect other windows
            for windowInfo in capture.getAllWindowsDecoded() {
                if !windowInfo.isActive && !windowInfo.windowTitle.isEmpty {
                    allOtherWindows.insert("\(windowInfo.appName): \(windowInfo.windowTitle)")
                }
            }
        }
        
        // Sort by most recent activity
        let sortedGroups = windowGroups.sorted { $0.value.lastTime > $1.value.lastTime }
        
        // Show deduplicated windows with OCR from latest capture only
        for (idx, (windowKey, group)) in sortedGroups.prefix(10).enumerated() {
            let firstTime = dateFormatter.string(from: group.firstTime)
            let lastTime = dateFormatter.string(from: group.lastTime)
            
            if group.count > 1 {
                lines.append("[\(idx + 1)] \(windowKey) — \(group.count)x focused (\(firstTime)-\(lastTime))")
            } else {
                lines.append("[\(idx + 1)] \(windowKey) — \(firstTime)")
            }
            
            // OCR from latest capture only
            if let ocrText = group.latest.ocrText, !ocrText.isEmpty {
                let ocrPreview = String(ocrText.prefix(300))
                lines.append(ocrPreview)
            }
            lines.append("")
        }
        
        // Show consolidated list of other windows seen
        if !allOtherWindows.isEmpty {
            lines.append("---")
            lines.append("OTHER WINDOWS SEEN:")
            for window in allOtherWindows.sorted().prefix(15) {
                lines.append("• \(window)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Single LLM Call (with session tracking)
    
    private func runLLMCall(title: String, system: String, user: String) async throws -> String {
        guard let container = modelContainer else {
            throw LLMError.modelNotLoaded
        }
        
        // Start session tracking
        let sessionId = LLMSessionStore.shared.startSession(title: title, system: system, user: user)
        
        do {
            let output = try await Task.detached { [container, system, user] in
                let session = ChatSession(container, instructions: system)
                var output = ""
                for try await chunk in session.streamResponse(to: user) {
                    output += chunk
                    if output.count > 2000 { break }
                }
                Stream.gpu.synchronize()
                return output
            }.value
            
            // Complete session
            LLMSessionStore.shared.completeSession(id: sessionId, response: output)
            return output
            
        } catch {
            LLMSessionStore.shared.failSession(id: sessionId, error: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Refiners
    
    /// Run a refiner and return its output
    private func runRefiner<R: Refiner>(_ refiner: R, context: AnalysisContext) async throws -> R.Output {
        let contextText = formatContextForLLM(context)
        let response = try await runLLMCall(
            title: refiner.name,
            system: refiner.systemPrompt,
            user: contextText
        )
        return refiner.parse(response: response)
    }
    
    func extractProjects(_ context: AnalysisContext, existing: [String] = []) async throws -> [String] {
        var refiner = ProjectsRefiner()
        refiner.existingItems = existing
        return try await runRefiner(refiner, context: context)
    }
    
    func extractCollaborators(_ context: AnalysisContext, existing: [String] = []) async throws -> [String] {
        var refiner = CollaboratorsRefiner()
        refiner.existingItems = existing
        return try await runRefiner(refiner, context: context)
    }
    
    func extractInterests(_ context: AnalysisContext, existing: [String] = []) async throws -> [String] {
        var refiner = InterestsRefiner()
        refiner.existingItems = existing
        return try await runRefiner(refiner, context: context)
    }
    
    func extractTodos(_ context: AnalysisContext, existing: [String] = []) async throws -> [String] {
        var refiner = TodosRefiner()
        refiner.existingItems = existing
        return try await runRefiner(refiner, context: context)
    }
    
    struct AccumulatedContext {
        var projects: [String] = []
        var collaborators: [String] = []
        var interests: [String] = []
        var pendingTodos: [String] = []
    }
    
    
    /// Check if user should take a break based on activity patterns
    func checkWellnessFromActivity(_ context: AnalysisContext, workDurationMinutes: Int, isLateNight: Bool) async throws -> (shouldSuggestBreak: Bool, reason: String?) {
        var contextLines: [String] = []
        
        contextLines.append("Work duration: \(workDurationMinutes) minutes")
        contextLines.append("Time: \(isLateNight ? "Late night (after 10pm)" : "Regular hours")")
        
        if context.moodSummary != "No mood data" {
            contextLines.append("Detected mood: \(context.moodSummary)")
        }
        
        if !context.transcriptSummary.isEmpty {
            contextLines.append("Recent speech: \(context.transcriptSummary.prefix(200))")
        }
        
        // Add sample of what user is working on
        if let firstCapture = context.captures.first {
            let app = firstCapture.focusedApp ?? "Unknown"
            let window = firstCapture.focusedWindow ?? ""
            contextLines.append("Current focus: \(app) - \(window)")
        }
        
        let system = """
You are a wellness assistant. Based on the user's work activity, determine if they should take a break.

Consider:
- Working more than 90 minutes without a break is unhealthy
- Late night work (after 10pm) suggests they should rest
- Signs of stress or frustration in mood/speech
- High intensity focused work needs breaks

Respond with JSON only:
{"suggest_break": true/false, "reason": "brief explanation or null"}

Be helpful but not annoying. Only suggest a break if genuinely warranted.
"""
        
        let response = try await runLLMCall(
            title: "Wellness Check",
            system: system,
            user: contextLines.joined(separator: "\n")
        )
        
        // Parse the response
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            return (false, nil)
        }
        
        let jsonString = String(response[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, nil)
        }
        
        let shouldBreak = dict["suggest_break"] as? Bool ?? false
        let reason = dict["reason"] as? String
        
        return (shouldBreak, reason)
    }
    
    // MARK: - Full Analysis
    
    func analyzeCaptures(_ captures: [ScreenCapture], voiceSegments: [VoiceSegment] = [], faceEvents: [FaceEvent] = [], accumulated: AccumulatedContext = AccumulatedContext()) async throws -> AnalysisResult {
        guard modelContainer != nil else {
            throw LLMError.modelNotLoaded
        }
        
        guard !isGenerating else {
            throw LLMError.generationInProgress
        }
        
        if case .loading = loadState {
            throw LLMError.loadingInProgress
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Build context with all available data
        let context = AnalysisContext(
            captures: captures,
            voiceTranscripts: voiceSegments,
            faceEvents: faceEvents
        )
        
        NSLog("🧠 Analyzing: %d captures, %d voice segments, %d face events, mood: %@",
              captures.count, voiceSegments.count, faceEvents.count, context.moodSummary)
        
        var result = AnalysisResult()
        
        // Run each analysis type separately, passing existing items for context
        do {
            result.projects = try await extractProjects(context, existing: accumulated.projects)
        } catch {
            NSLog("🧠 Projects extraction failed: %@", error.localizedDescription)
        }
        
        do {
            result.collaborators = try await extractCollaborators(context, existing: accumulated.collaborators)
        } catch {
            NSLog("🧠 Collaborators extraction failed: %@", error.localizedDescription)
        }
        
        do {
            result.interests = try await extractInterests(context, existing: accumulated.interests)
        } catch {
            NSLog("🧠 Interests extraction failed: %@", error.localizedDescription)
        }
        
        do {
            result.todos = try await extractTodos(context, existing: accumulated.pendingTodos)
        } catch {
            NSLog("🧠 TODOs extraction failed: %@", error.localizedDescription)
        }
        
        NSLog("🧠 Refinement complete: %d projects, %d collaborators, %d interests, %d todos",
              result.projects.count, result.collaborators.count, result.interests.count, result.todos.count)
        
        return result
    }
    
    // MARK: - Quick Query (for insights and simple checks)
    
    func quickQuery(system: String, prompt: String, title: String = "Quick Query") async throws -> String {
        guard let container = modelContainer else {
            throw LLMError.modelNotLoaded
        }
        
        // Track session for LLM Activity view
        let sessionId = LLMSessionStore.shared.startSession(title: title, system: system, user: prompt)
        
        let output = try await Task.detached { [container, system, prompt] in
            let session = ChatSession(container, instructions: system)
            var output = ""
            for try await chunk in session.streamResponse(to: prompt) {
                output += chunk
                if output.count > 100 { break } // Short response expected
            }
            Stream.gpu.synchronize()
            return output
        }.value
        
        LLMSessionStore.shared.completeSession(id: sessionId, response: output)
        return output
    }
    
    // MARK: - Self Test
    
    func runSelfTest() async throws -> Bool {
        if !isLoaded {
            try await loadModel()
        }
        
        guard let container = modelContainer else {
            throw LLMError.modelNotLoaded
        }
        
        let output = try await Task.detached { [container] in
            let session = ChatSession(container)
            let response = try await session.respond(to: "Say 'Hello from MLX!' and nothing else.")
            Stream.gpu.synchronize()
            return response
        }.value
        
        return output.lowercased().contains("hello")
    }
    
    // MARK: - JSON Parsing
    
    private func parseStringArray(_ response: String) -> [String] {
        guard let jsonStart = response.firstIndex(of: "["),
              let jsonEnd = response.lastIndex(of: "]") else { return [] }
        
        let jsonString = String(response[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        
        return array.filter { !$0.isEmpty }
    }
}
