//
// AutomationResultSheet.swift
//
// Shows the result of running automation: LLM response, parsed commands, execution results
//

import SwiftUI

/// View model for automation execution
@MainActor
class AutomationViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isLoadingContext = false
    @Published var stage: Stage = .idle
    @Published var systemPrompt: String?
    @Published var userPrompt: String?
    @Published var llmResponse: String?
    @Published var parsedCommands: [ActionCommand] = []
    @Published var executionResults: [CommandResult] = []
    @Published var error: String?
    @Published var contextSummary: ContextSummary?
    
    // Store the built context for reuse when running
    private var builtContext: ActionLLMContext?
    
    struct ContextSummary {
        var mood: String?
        var workMinutes: Int
        var projects: [String]
        var todos: [String]
        var insights: [String]
        var files: [String]
        var trigger: String
    }
    
    enum Stage: String {
        case idle = "Ready"
        case buildingContext = "Building context..."
        case callingLLM = "Asking LLM..."
        case parsingCommands = "Parsing commands..."
        case executing = "Executing..."
        case complete = "Complete"
        case failed = "Failed"
    }
    
    /// Load context and prompts without executing (called on sheet open)
    func loadPreview(for action: Action, database: Database?) async {
        isLoadingContext = true
        error = nil
        
        do {
            // Build context
            let context = await buildContext(for: action, database: database)
            builtContext = context
            
            // Capture context summary for display
            contextSummary = ContextSummary(
                mood: context.currentMood,
                workMinutes: context.workDurationMinutes,
                projects: context.recentProjects,
                todos: context.pendingTodos,
                insights: context.recentInsights,
                files: context.recentFiles,
                trigger: context.trigger.description
            )
            
            // Get prompts without running
            guard let actionService = ActionService.shared else {
                throw AutomationError.serviceNotInitialized
            }
            
            let prompts = await actionService.getPrompts(context: context)
            systemPrompt = prompts.system
            userPrompt = prompts.user
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingContext = false
    }
    
    /// Run the automation (uses pre-built context if available)
    func run(for action: Action, database: Database?) async {
        isRunning = true
        error = nil
        llmResponse = nil
        parsedCommands = []
        executionResults = []
        
        do {
            // Use pre-built context or build fresh
            let context: ActionLLMContext
            if let existing = builtContext {
                context = existing
            } else {
                stage = .buildingContext
                context = await buildContext(for: action, database: database)
                builtContext = context
                
                // Update context summary if not already set
                if contextSummary == nil {
                    contextSummary = ContextSummary(
                        mood: context.currentMood,
                        workMinutes: context.workDurationMinutes,
                        projects: context.recentProjects,
                        todos: context.pendingTodos,
                        insights: context.recentInsights,
                        files: context.recentFiles,
                        trigger: context.trigger.description
                    )
                }
            }
            
            // Call LLM
            stage = .callingLLM
            guard let actionService = ActionService.shared else {
                throw AutomationError.serviceNotInitialized
            }
            
            let result = try await actionService.run(context: context)
            
            // Update UI with results
            systemPrompt = result.systemPrompt
            userPrompt = result.userPrompt
            llmResponse = result.llmResponse
            parsedCommands = result.commands
            executionResults = result.results
            
            stage = .complete
            
        } catch {
            self.error = error.localizedDescription
            stage = .failed
        }
        
        isRunning = false
    }
    
    /// Refresh the context (e.g., if user wants updated data)
    func refreshContext(for action: Action, database: Database?) async {
        builtContext = nil
        await loadPreview(for: action, database: database)
    }
    
    private func buildContext(for action: Action, database: Database?) async -> ActionLLMContext {
        var context = ActionLLMContext(
            trigger: .manual(prompt: "\(action.title): \(action.message)")
        )
        
        // Enrich with data from database
        if let db = database {
            do {
                // Get mood
                let oneHourAgo = Date().addingTimeInterval(-3600)
                let faceEvents = try await db.getRecentFaceEvents(since: oneHourAgo)
                if !faceEvents.isEmpty {
                    let emotions = faceEvents.compactMap { $0.emotion }
                    if let mostCommon = emotions.mostFrequent() {
                        context.currentMood = mostCommon
                    }
                }
                
                // Get work duration (from captures)
                let captures = try await db.getRecentCaptures(hours: 4)
                if let first = captures.last?.timestamp {
                    context.workDurationMinutes = Int(Date().timeIntervalSince(first) / 60)
                }
                
                // Get projects
                let projects = try await db.getAllProjects()
                context.recentProjects = projects.prefix(5).map { $0.name }
                
                // Get pending todos
                let todos = try await db.getPendingTodos()
                context.pendingTodos = todos.prefix(5).map { $0.description }
                
                // Get recent insights
                let insights = try await db.getRecentInsights(hours: 2)
                context.recentInsights = insights.prefix(3).map { $0.content }
                
                // Get recent files
                let files = try await db.getRecentDirectoryActivity(hours: 1)
                context.recentFiles = files.prefix(5).map { $0.path }
                
            } catch {
                NSLog("Failed to enrich context: \(error)")
            }
        }
        
        return context
    }
}

enum AutomationError: Error, LocalizedError {
    case serviceNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "ActionService not initialized"
        }
    }
}

// MARK: - Result Sheet View

struct AutomationResultSheet: View {
    let action: Action
    let database: Database?
    @StateObject private var viewModel = AutomationViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation")
                        .font(.headline)
                    Text(action.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Refresh button
                Button {
                    Task {
                        await viewModel.refreshContext(for: action, database: database)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRunning || viewModel.isLoadingContext)
                .help("Refresh context")
                
                // Status indicator
                HStack(spacing: 6) {
                    if viewModel.isRunning || viewModel.isLoadingContext {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.stage == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if viewModel.stage == .failed {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    
                    if viewModel.isLoadingContext {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.stage.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Error
                    if let error = viewModel.error {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    
                    // Context Summary (what we're sending)
                    if let ctx = viewModel.contextSummary {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                contextRow("Trigger", ctx.trigger)
                                if let mood = ctx.mood {
                                    contextRow("Mood", mood)
                                }
                                if ctx.workMinutes > 0 {
                                    contextRow("Work Duration", "\(ctx.workMinutes) min")
                                }
                                if !ctx.projects.isEmpty {
                                    contextRow("Projects", ctx.projects.joined(separator: ", "))
                                }
                                if !ctx.todos.isEmpty {
                                    contextRow("Pending Tasks", "\(ctx.todos.count) items")
                                    ForEach(ctx.todos, id: \.self) { todo in
                                        Text("  • \(todo)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !ctx.insights.isEmpty {
                                    contextRow("Recent Insights", "\(ctx.insights.count) items")
                                }
                                if !ctx.files.isEmpty {
                                    contextRow("Recent Files", "\(ctx.files.count) items")
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Label("Context", systemImage: "info.circle")
                                .font(.headline)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    // System Prompt (available commands)
                    if let system = viewModel.systemPrompt {
                        DisclosureGroup {
                            Text(system)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            Label("System Prompt (Available Commands)", systemImage: "terminal")
                                .font(.headline)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    // User Prompt (what we asked)
                    if let user = viewModel.userPrompt {
                        DisclosureGroup {
                            Text(user)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            Label("User Prompt (Sent to LLM)", systemImage: "arrow.up.circle")
                                .font(.headline)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    // LLM Response
                    if let response = viewModel.llmResponse {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("LLM Response", systemImage: "arrow.down.circle")
                                    .font(.headline)
                                
                                Text(response)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    
                    // Parsed Commands
                    if !viewModel.parsedCommands.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Parsed Commands (\(viewModel.parsedCommands.count))", systemImage: "list.bullet.rectangle")
                                    .font(.headline)
                                
                                ForEach(Array(viewModel.parsedCommands.enumerated()), id: \.offset) { index, command in
                                    HStack {
                                        Text("\(index + 1).")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                        
                                        Text(command.description)
                                            .font(.system(.body, design: .monospaced))
                                        
                                        Spacer()
                                        
                                        // Safety indicator
                                        if command.isDestructive {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                                .help("Destructive operation")
                                        } else if command.isSafeToAutoExecute {
                                            Image(systemName: "checkmark.shield.fill")
                                                .foregroundStyle(.green)
                                                .help("Safe to auto-execute")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    
                    // Execution Results
                    if !viewModel.executionResults.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                let succeeded = viewModel.executionResults.filter { $0.success }.count
                                let failed = viewModel.executionResults.count - succeeded
                                
                                Label("Execution Results", systemImage: "play.circle")
                                    .font(.headline)
                                
                                HStack {
                                    Label("\(succeeded) succeeded", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    
                                    if failed > 0 {
                                        Label("\(failed) failed", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.subheadline)
                                
                                Divider()
                                
                                ForEach(Array(viewModel.executionResults.enumerated()), id: \.offset) { index, result in
                                    HStack(alignment: .top) {
                                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(result.success ? .green : .red)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.command.description)
                                                .font(.system(.body, design: .monospaced))
                                            
                                            if let message = result.message {
                                                Text(message)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            if let error = result.error {
                                                Text(error)
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                            
                                            if result.duration > 0.01 {
                                                Text(String(format: "%.2fs", result.duration))
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    
                    // Prompt to run (shown after context loaded, before execution)
                    if viewModel.stage == .idle && viewModel.systemPrompt != nil && viewModel.llmResponse == nil {
                        GroupBox {
                            VStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.largeTitle)
                                    .foregroundStyle(.purple)
                                Text("Ready to Run")
                                    .font(.headline)
                                Text("Review the prompts above, then click Run to execute.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                    
                    // Loading state (before context is loaded)
                    if viewModel.isLoadingContext && viewModel.systemPrompt == nil {
                        ContentUnavailableView(
                            "Loading Context...",
                            systemImage: "ellipsis.circle",
                            description: Text("Gathering data from database")
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.run(for: action, database: database)
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(viewModel.stage == .complete ? "Run Again" : "Run")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRunning || viewModel.isLoadingContext)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .frame(maxWidth: 800, maxHeight: 700)
        .task {
            // Load context and prompts when sheet opens
            await viewModel.loadPreview(for: action, database: database)
        }
    }
    
    @ViewBuilder
    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Helper Extension

extension Array where Element: Hashable {
    func mostFrequent() -> Element? {
        let counts = reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

#Preview {
    AutomationResultSheet(
        action: Action(
            type: "popup",
            title: "Wellness Check",
            message: "You've been working for 2 hours. Consider taking a break.",
            source: "Wellness",
            priority: 5
        ),
        database: nil
    )
}
