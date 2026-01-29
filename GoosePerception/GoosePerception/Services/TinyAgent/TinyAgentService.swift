//
// TinyAgentService.swift
//
// Main orchestrator for TinyAgent Mac automation.
// Handles: Query → ToolRAG → LLM Planning → Parse → Execute → Joinner → Result
//

import Foundation
import os.log
import MLX
import MLXLLM
import MLXLMCommon

private let logger = Logger(subsystem: "com.goose.perception", category: "TinyAgent")

// MARK: - Result Types

/// Full result of a TinyAgent run
struct TinyAgentResult {
    let query: String
    let selectedTools: Set<TinyAgentToolName>
    let systemPrompt: String
    let plannerOutput: String
    let parsedTasks: [ParsedTask]
    let executionResult: PlanExecutionResult?
    let joinnerOutput: String?
    let finalAnswer: String
    let success: Bool
    let replanCount: Int
    let totalDuration: TimeInterval
    let timestamp: Date
}

// MARK: - TinyAgent Service

@MainActor
class TinyAgentService: ObservableObject {
    
    // MARK: - Published State
    
    enum LoadState: Equatable {
        case idle
        case loading(progress: Double)
        case loaded
        case failed(String)
    }
    
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var history: [TinyAgentResult] = []
    
    // MARK: - Private Properties
    
    private var modelContainer: ModelContainer?
    private let parser = LLMCompilerParser()
    private let joinnerParser = JoinnerOutputParser()
    
    /// Maximum number of replan attempts
    let maxReplans = 2
    
    /// Model ID for TinyAgent (MLX converted)
    /// Can also use your existing model if TinyAgent-specific isn't available
    static let defaultModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"  // Fallback to existing model
    // static let tinyAgentModelId = "WannabeArchitect/TinyAgent-1.1B-MLX"  // When available
    
    var isLoaded: Bool { modelContainer != nil }
    
    // MARK: - Initialization
    
    init() {
        // Register all tools on init (fire and forget)
        Task {
            await registerTools()
        }
    }
    
    /// Register all available tools with the registry
    /// Can be called explicitly if you need to await completion
    func registerTools() async {
        let registry = ToolRegistry.shared
        
        // Contacts
        await registry.register(GetPhoneNumberTool())
        await registry.register(GetEmailAddressTool())
        
        // Calendar
        await registry.register(CreateCalendarEventTool())
        
        // Reminders
        await registry.register(CreateReminderTool())
        
        // Mail
        await registry.register(ComposeNewEmailTool())
        await registry.register(ReplyToEmailTool())
        await registry.register(ForwardEmailTool())
        
        // Notes
        await registry.register(CreateNoteTool())
        await registry.register(OpenNoteTool())
        await registry.register(AppendNoteContentTool())
        
        // Messages
        await registry.register(SendSMSTool())
        
        // Maps
        await registry.register(MapsOpenLocationTool())
        await registry.register(MapsShowDirectionsTool())
        
        // Files
        await registry.register(OpenAndGetFilePathTool())
        await registry.register(SummarizePDFTool())
        
        // Zoom
        await registry.register(GetZoomMeetingLinkTool())
        
        logger.info("Registered \(TinyAgentToolName.allCases.count) TinyAgent tools")
    }
    
    // MARK: - Model Loading
    
    func loadModel(modelId: String? = nil) async throws {
        let model = modelId ?? Self.defaultModelId
        
        guard loadState != .loading(progress: 0) else {
            throw TinyAgentError.loadingInProgress
        }
        
        loadState = .loading(progress: 0)
        logger.info("Loading TinyAgent model: \(model)")
        
        do {
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
            logger.info("TinyAgent model loaded successfully")
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }
    
    func unloadModel() {
        modelContainer = nil
        loadState = .idle
    }
    
    // MARK: - Main API
    
    /// Run TinyAgent for a user query
    func run(query: String) async throws -> TinyAgentResult {
        guard let container = modelContainer else {
            throw TinyAgentError.modelNotLoaded
        }
        
        guard !isRunning else {
            throw TinyAgentError.alreadyRunning
        }
        
        isRunning = true
        defer { isRunning = false }
        
        let startTime = Date()
        var replanCount = 0
        var lastPlannerOutput = ""
        var lastExecutionResult: PlanExecutionResult? = nil
        var joinnerOutput: String? = nil
        
        // 1. Select relevant tools using ToolRAG
        let ragResult = await ToolRAGService.shared.selectTools(for: query)
        logger.info("Selected \(ragResult.selectedTools.count) tools for query: \(ragResult.selectedTools.map { $0.rawValue })")
        
        // If no tools selected, use all enabled tools
        let toolsToUse = ragResult.selectedTools.isEmpty 
            ? await ToolRegistry.shared.getEnabledToolNames() 
            : ragResult.selectedTools
        
        // 2. Build system prompt with selected tools and relevant examples
        let systemPrompt = await ToolRAGService.shared.buildSystemPrompt(for: ragResult)
        
        // 3. Planning and execution loop (with replanning)
        var currentQuery = query
        var previousObservations = ""
        
        while replanCount <= maxReplans {
            // Build user prompt
            var userPrompt = "Question: \(currentQuery)"
            if !previousObservations.isEmpty {
                userPrompt = """
                    \(userPrompt)
                    
                    Previous attempt observations:
                    \(previousObservations)
                    
                    Please create a new plan considering the previous results.
                    """
            }
            
            // Call LLM for planning
            let plannerOutput = try await callLLM(
                container: container,
                system: systemPrompt,
                user: userPrompt
            )
            lastPlannerOutput = plannerOutput
            
            // Parse the plan
            let parseResult = parser.parse(plannerOutput)
            
            if !parseResult.isValid {
                logger.warning("Invalid plan output: \(parseResult.parseErrors.joined(separator: ", "))")
                if replanCount < maxReplans {
                    replanCount += 1
                    previousObservations = "Plan parsing failed: \(parseResult.parseErrors.joined(separator: ", "))"
                    continue
                }
                break
            }
            
            // Execute the plan
            let executionResult = await TaskExecutor.shared.execute(tasks: parseResult.tasks)
            lastExecutionResult = executionResult
            
            // Call joinner to evaluate
            let joinnerInput = """
                Question: \(query)
                \(executionResult.observationText)
                """
            
            let joinnerSystemPrompt = """
                Follow these rules:
                 - You MUST only output either Finish or Replan, or you WILL BE PENALIZED.
                 - If you need to answer some knowledge question, just answer it directly using 'Action: Finish(<your answer>)'.
                 - If you need to return the result of a summary, you MUST use 'Action: Finish(Summary)'
                 - If there is an error in one of the tool calls and it is not fixable, you should provide a user-friendly error message using 'Action: Finish(<your error message>)'.
                 - If you think the plan is not completed yet or an error in the plan is fixable, you should output Replan.
                 - If the plan succeeded and the task is complete, output 'Action: Finish(Task completed!)' or similar.
                """
            
            let joinnerOutputText = try await callLLM(
                container: container,
                system: joinnerSystemPrompt,
                user: joinnerInput
            )
            joinnerOutput = joinnerOutputText
            
            let decision = joinnerParser.parse(joinnerOutputText)
            
            switch decision {
            case .finish(let answer):
                // Success - build and return result
                let result = TinyAgentResult(
                    query: query,
                    selectedTools: toolsToUse,
                    systemPrompt: systemPrompt,
                    plannerOutput: plannerOutput,
                    parsedTasks: parseResult.tasks,
                    executionResult: executionResult,
                    joinnerOutput: joinnerOutputText,
                    finalAnswer: answer,
                    success: true,
                    replanCount: replanCount,
                    totalDuration: Date().timeIntervalSince(startTime),
                    timestamp: Date()
                )
                addToHistory(result)
                return result
                
            case .replan(let reason):
                if replanCount < maxReplans {
                    replanCount += 1
                    previousObservations = executionResult.observationText
                    if let reason = reason {
                        previousObservations += "\nReplan reason: \(reason)"
                    }
                    logger.info("Replanning (\(replanCount)/\(self.maxReplans)): \(reason ?? "no reason")")
                } else {
                    break
                }
            }
        }
        
        // Max replans reached or failed
        let result = TinyAgentResult(
            query: query,
            selectedTools: toolsToUse,
            systemPrompt: systemPrompt,
            plannerOutput: lastPlannerOutput,
            parsedTasks: parser.parse(lastPlannerOutput).tasks,
            executionResult: lastExecutionResult,
            joinnerOutput: joinnerOutput,
            finalAnswer: lastExecutionResult?.taskResults.last?.output ?? "Failed after \(replanCount) replan attempts",
            success: false,
            replanCount: replanCount,
            totalDuration: Date().timeIntervalSince(startTime),
            timestamp: Date()
        )
        addToHistory(result)
        return result
    }
    
    /// Run with just a prompt (simpler interface)
    func runSimple(_ prompt: String) async throws -> String {
        let result = try await run(query: prompt)
        return result.finalAnswer
    }
    
    // MARK: - Private Methods
    
    private func callLLM(container: ModelContainer, system: String, user: String) async throws -> String {
        try await Task.detached { [container, system, user] in
            let session = ChatSession(container, instructions: system)
            var output = ""
            for try await chunk in session.streamResponse(to: user) {
                output += chunk
                if output.count > 4000 { break }  // Safety limit
            }
            Stream.gpu.synchronize()
            return output
        }.value
    }
    
    private func addToHistory(_ result: TinyAgentResult) {
        history.append(result)
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }
}

// MARK: - Errors

enum TinyAgentError: Error, LocalizedError {
    case modelNotLoaded
    case loadingInProgress
    case alreadyRunning
    case planningFailed(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "TinyAgent model not loaded"
        case .loadingInProgress:
            return "Model is still loading"
        case .alreadyRunning:
            return "TinyAgent is already running a query"
        case .planningFailed(let reason):
            return "Planning failed: \(reason)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        }
    }
}
