//
// ActionService.swift
//
// Orchestrates: Context → LLM prompt → Parse DSL → Execute commands
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
    var recentFiles: [String] = []  // From directory activity
    var trigger: ActionTrigger
}

/// Result of an automated action run
struct ActionRunResult {
    let trigger: ActionTrigger
    let systemPrompt: String
    let userPrompt: String
    let llmResponse: String
    let commands: [ActionCommand]
    let results: [CommandResult]
    let timestamp: Date
    
    var allSucceeded: Bool {
        results.allSatisfy { $0.success }
    }
    
    var summary: String {
        let succeeded = results.filter { $0.success }.count
        let failed = results.count - succeeded
        if failed == 0 {
            return "Executed \(succeeded) command(s) successfully"
        } else {
            return "Executed \(succeeded) command(s), \(failed) failed"
        }
    }
}

/// Main service for automated actions
actor ActionService {
    /// Shared singleton instance
    static var shared: ActionService!
    
    /// Initialize the shared instance (call from AppDelegate)
    static func initialize(llmService: LLMService) {
        shared = ActionService(llmService: llmService)
    }
    
    private let llmService: LLMService
    private let parser = ActionDSLParser()
    private let executor = ActionExecutor()
    
    /// Default execution options (safe mode)
    var executionOptions: ExecutionOptions = .safe
    
    /// History of action runs
    private(set) var history: [ActionRunResult] = []
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Public API
    
    /// Generate and execute actions for a trigger
    func run(context: ActionLLMContext) async throws -> ActionRunResult {
        // 1. Build prompts
        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildPrompt(context: context)
        
        // 2. Call LLM
        let llmResponse = try await llmService.quickQuery(
            system: systemPrompt,
            prompt: userPrompt,
            title: "Action Generation"
        )
        
        // 3. Parse commands
        let commands = parser.parseValid(llmResponse)
        
        // 4. Execute
        let results = await executor.execute(commands, options: executionOptions)
        
        // 5. Build result
        let result = ActionRunResult(
            trigger: context.trigger,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            llmResponse: llmResponse,
            commands: commands,
            results: results,
            timestamp: Date()
        )
        
        // 6. Store in history
        history.append(result)
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        
        return result
    }
    
    /// Get the prompts that would be sent (for debugging/preview)
    func getPrompts(context: ActionLLMContext) -> (system: String, user: String) {
        (buildSystemPrompt(), buildPrompt(context: context))
    }
    
    /// Preview what commands would be generated (dry run)
    func preview(context: ActionLLMContext) async throws -> [ActionCommand] {
        let prompt = buildPrompt(context: context)
        let systemPrompt = buildSystemPrompt()
        
        let llmResponse = try await llmService.quickQuery(
            system: systemPrompt,
            prompt: prompt,
            title: "Action Preview"
        )
        
        return parser.parseValid(llmResponse)
    }
    
    /// Execute pre-parsed commands directly
    func executeCommands(_ commands: [ActionCommand]) async -> [CommandResult] {
        await executor.execute(commands, options: executionOptions)
    }
    
    /// Parse DSL text without executing
    func parseCommands(_ text: String) -> [ActionCommand] {
        parser.parse(text)
    }
    
    // MARK: - Prompt Building
    
    private func buildSystemPrompt() -> String {
        """
        You are a helpful assistant that automates macOS tasks.
        
        AVAILABLE COMMANDS:
        
        File Operations:
        - MOVE_FILE "from" "to"
        - COPY_FILE "from" "to"  
        - DELETE_FILE "path"
        - CREATE_FOLDER "path"
        - OPEN_FILE "path" ["App Name"]
        - REVEAL_IN_FINDER "path"
        
        Document Creation:
        - WRITE_FILE "path" "content"
        - WRITE_DOC "path" <<END
          multi-line content
          END
        - APPEND_FILE "path" "content"
        
        Communication:
        - SEND_EMAIL "to@email.com" "Subject" "Body"
        - OPEN_URL "https://..."
        - COPY_TO_CLIPBOARD "text"
        
        Apps:
        - OPEN_APP "App Name"
        - QUIT_APP "App Name"
        - ACTIVATE_APP "App Name"
        
        Notifications:
        - NOTIFY "Title" "Message"
        - SPEAK "Text to speak"
        
        Shortcuts:
        - RUN_SHORTCUT "Shortcut Name" ["input"]
        
        RULES:
        1. Output ONLY commands, one per line
        2. Use # for comments
        3. Use quotes around arguments with spaces
        4. Use ~ for home directory paths
        5. If no action needed, output: # No action needed
        6. Be conservative - only suggest actions that are clearly helpful
        7. Prefer non-destructive actions (NOTIFY, OPEN_FILE) over destructive ones
        """
    }
    
    private func buildPrompt(context: ActionLLMContext) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        let timeStr = formatter.string(from: context.currentTime)
        
        var lines: [String] = []
        
        lines.append("CONTEXT:")
        lines.append("Time: \(timeStr)")
        
        if let mood = context.currentMood {
            lines.append("User mood: \(mood)")
        }
        
        if context.workDurationMinutes > 0 {
            lines.append("Work session: \(context.workDurationMinutes) minutes")
        }
        
        if !context.recentProjects.isEmpty {
            lines.append("Recent projects: \(context.recentProjects.prefix(5).joined(separator: ", "))")
        }
        
        if !context.pendingTodos.isEmpty {
            lines.append("Pending tasks:")
            for todo in context.pendingTodos.prefix(5) {
                lines.append("  - \(todo)")
            }
        }
        
        if !context.recentInsights.isEmpty {
            lines.append("Recent observations:")
            for insight in context.recentInsights.prefix(3) {
                lines.append("  - \(insight)")
            }
        }
        
        if !context.recentFiles.isEmpty {
            lines.append("Recently modified files:")
            for file in context.recentFiles.prefix(5) {
                lines.append("  - \(file)")
            }
        }
        
        lines.append("")
        lines.append("TRIGGER: \(context.trigger.description)")
        lines.append("")
        lines.append("What actions should be taken? Output only the commands.")
        
        return lines.joined(separator: "\n")
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
