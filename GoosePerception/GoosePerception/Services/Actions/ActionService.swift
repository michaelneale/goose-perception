//
// ActionService.swift
//
// Thin wrapper around TinyAgentService for backward compatibility.
// This delegates all work to the TinyAgent system.
//

import Foundation

/// Trigger types for automated actions
enum ActionTrigger {
    case manual(prompt: String)
    case wellness(insight: String)
    case reminder(todos: [String])
    case endOfDay(summary: String)
    case scheduled(name: String)
    
    var description: String {
        switch self {
        case .manual(let prompt): return "User request: \(prompt)"
        case .wellness(let insight): return "Wellness: \(insight)"
        case .reminder(let todos): return "Reminder: \(todos.count) pending tasks"
        case .endOfDay(let summary): return "End of day: \(summary)"
        case .scheduled(let name): return "Scheduled: \(name)"
        }
    }
}

/// Context provided to LLM for action generation
struct ActionLLMContext {
    var currentTime: Date = Date()
    var currentMood: String?
    var workDurationMinutes: Int = 0
    var recentProjects: [String] = []
    var pendingTodos: [String] = []
    var recentInsights: [String] = []
    var recentFiles: [String] = []
    var trigger: ActionTrigger
}

/// Result of an automated action run (wraps TinyAgentResult)
struct ActionRunResult {
    let trigger: ActionTrigger
    let systemPrompt: String
    let userPrompt: String
    let llmResponse: String
    let tinyAgentResult: TinyAgentResult?
    let timestamp: Date
    
    var allSucceeded: Bool {
        tinyAgentResult?.success ?? false
    }
    
    var summary: String {
        guard let result = tinyAgentResult else {
            return "No result"
        }
        if result.success {
            let taskCount = result.executionResult?.taskResults.count ?? 0
            return "Executed \(taskCount) task(s) successfully"
        } else {
            return "Failed: \(result.finalAnswer)"
        }
    }
    
    /// Tasks that were executed
    var executedTasks: [TaskExecutionResult] {
        tinyAgentResult?.executionResult?.taskResults ?? []
    }
    
    /// Parsed tasks from the plan
    var parsedTasks: [ParsedTask] {
        tinyAgentResult?.parsedTasks ?? []
    }
}

/// Main service for automated actions - delegates to TinyAgentService
@MainActor
class ActionService: ObservableObject {
    /// Shared singleton instance
    static var shared: ActionService!
    
    /// Initialize the shared instance (call from AppDelegate)
    static func initialize(tinyAgentService: TinyAgentService) {
        shared = ActionService(tinyAgentService: tinyAgentService)
    }
    
    private let tinyAgentService: TinyAgentService
    
    /// History of action runs
    @Published private(set) var history: [ActionRunResult] = []
    
    /// Whether the service is ready
    var isReady: Bool {
        tinyAgentService.isLoaded
    }
    
    /// Current load state
    var loadState: TinyAgentService.LoadState {
        tinyAgentService.loadState
    }
    
    init(tinyAgentService: TinyAgentService) {
        self.tinyAgentService = tinyAgentService
    }
    
    // MARK: - Public API
    
    /// Ensure model is loaded
    func ensureLoaded() async throws {
        if !tinyAgentService.isLoaded {
            try await tinyAgentService.loadModel()
        }
    }
    
    /// Generate and execute actions for a trigger
    func run(context: ActionLLMContext) async throws -> ActionRunResult {
        try await ensureLoaded()
        
        // Build query from context
        let query = buildQuery(from: context)
        
        // Run TinyAgent
        let tinyResult = try await tinyAgentService.run(query: query)
        
        // Wrap in ActionRunResult
        let result = ActionRunResult(
            trigger: context.trigger,
            systemPrompt: tinyResult.systemPrompt,
            userPrompt: query,
            llmResponse: tinyResult.plannerOutput,
            tinyAgentResult: tinyResult,
            timestamp: Date()
        )
        
        // Store in history
        history.append(result)
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        
        return result
    }
    
    /// Get the prompts that would be sent (for debugging/preview)
    func getPrompts(context: ActionLLMContext) async -> (system: String, user: String) {
        let query = buildQuery(from: context)
        let selectedTools = await ToolRAGService.shared.selectTools(for: query)
        let toolsToUse = selectedTools.isEmpty 
            ? await ToolRegistry.shared.getEnabledToolNames() 
            : selectedTools
        let systemPrompt = await ToolRAGService.shared.buildSystemPrompt(for: toolsToUse)
        return (systemPrompt, query)
    }
    
    /// Run with a simple text prompt
    func runSimple(_ prompt: String) async throws -> String {
        try await ensureLoaded()
        return try await tinyAgentService.runSimple(prompt)
    }
    
    // MARK: - Private Methods
    
    private func buildQuery(from context: ActionLLMContext) -> String {
        var parts: [String] = []
        
        // Main trigger/request
        parts.append(context.trigger.description)
        
        // Add context as additional info
        if let mood = context.currentMood {
            parts.append("User mood: \(mood)")
        }
        
        if context.workDurationMinutes > 0 {
            parts.append("Work duration: \(context.workDurationMinutes) minutes")
        }
        
        if !context.recentProjects.isEmpty {
            parts.append("Working on: \(context.recentProjects.prefix(3).joined(separator: ", "))")
        }
        
        if !context.pendingTodos.isEmpty {
            parts.append("Pending tasks: \(context.pendingTodos.prefix(3).joined(separator: "; "))")
        }
        
        return parts.joined(separator: ". ")
    }
}

// MARK: - Convenience Extensions

extension ActionService {
    /// Quick action: end of day summary
    func runEndOfDay(projects: [String], todos: [String], workMinutes: Int) async throws -> ActionRunResult {
        let context = ActionLLMContext(
            workDurationMinutes: workMinutes,
            recentProjects: projects,
            pendingTodos: todos,
            trigger: .endOfDay(summary: "\(workMinutes) min work, \(todos.count) pending tasks")
        )
        return try await run(context: context)
    }
    
    /// Quick action: wellness check
    func runWellnessAction(insight: String, mood: String?, workMinutes: Int) async throws -> ActionRunResult {
        let context = ActionLLMContext(
            currentMood: mood,
            workDurationMinutes: workMinutes,
            trigger: .wellness(insight: insight)
        )
        return try await run(context: context)
    }
    
    /// Quick action: manual prompt
    func runManual(prompt: String, context: ActionLLMContext? = nil) async throws -> ActionRunResult {
        var ctx = context ?? ActionLLMContext(trigger: .manual(prompt: prompt))
        ctx.trigger = .manual(prompt: prompt)
        return try await run(context: ctx)
    }
}
