# Implementing Automated Agent Actions

## Current State

The app has the **observation** layer complete:
- Screen capture → OCR → LLM analysis → Projects/Collaborators/Actions/Insights
- Pattern detection (overwork, context switching, late night)
- Insight popups to show information to user

**Missing**: The **action** layer that can trigger external agents (goose, claude, codex) to actually do things.

---

## Goal

When configured, the app should be able to:
1. Detect a condition (trigger)
2. Compose a task with relevant context
3. Execute via an external CLI agent (goose, claude, amp)
4. Track outcome and learn from it

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Trigger Engine                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Time-based  │  │Pattern-based│  │ State-based │  │  Threshold  │ │
│  │ (cron-like) │  │ (detectors) │  │ (emotions)  │  │ (counts)    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
│         └────────────────┴────────────────┴────────────────┘         │
│                                  │                                    │
│                          ┌───────▼───────┐                           │
│                          │ Recipe Matcher │                           │
│                          └───────┬───────┘                           │
└──────────────────────────────────┼───────────────────────────────────┘
                                   │
                           ┌───────▼───────┐
                           │ Approval Gate │
                           │ (auto/ask/off)│
                           └───────┬───────┘
                                   │
                           ┌───────▼───────┐
                           │ Context       │
                           │ Compiler      │  ← Pulls from DB: projects,
                           │               │    collaborators, recent activity
                           └───────┬───────┘
                                   │
                           ┌───────▼───────┐
                           │ Agent Runner  │
                           │ (CLI bridge)  │
                           └───────┬───────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │  goose   │        │  claude  │        │   amp    │
        │   CLI    │        │   CLI    │        │   CLI    │
        └──────────┘        └──────────┘        └──────────┘
```

---

## Implementation Plan

### Phase 1: Recipe System

#### 1.1 Recipe Data Model

Add to `Database/Models/`:

```swift
// Recipe.swift
struct Recipe: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var description: String?
    var enabled: Bool
    
    // Trigger definition (JSON)
    var triggerType: String        // "schedule", "pattern", "threshold", "state"
    var triggerConfig: String      // JSON with trigger-specific config
    
    // Action definition
    var actionType: String         // "goose", "claude", "amp", "popup"
    var promptTemplate: String     // Template with {{project}}, {{context}} vars
    
    // Approval
    var approvalMode: String       // "auto", "ask", "off"
    
    // Learning
    var successCount: Int
    var rejectCount: Int
    var lastTriggered: Date?
    var lastSuccess: Date?
    
    static let databaseTableName = "recipes"
}

// RecipeExecution.swift  
struct RecipeExecution: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var recipeId: Int64
    var triggeredAt: Date
    var approvalStatus: String     // "pending", "approved", "rejected", "auto"
    var executionStatus: String    // "pending", "running", "success", "failed"
    var contextSnapshot: String    // JSON of context at trigger time
    var agentOutput: String?
    var completedAt: Date?
    var userFeedback: String?      // "helpful", "not_helpful", nil
    
    static let databaseTableName = "recipe_executions"
}
```

#### 1.2 Trigger Types

```swift
// TriggerEngine.swift
enum TriggerType: String, Codable {
    case schedule     // Cron-like: "daily 9am", "weekly monday"
    case pattern      // From PatternDetectionPass: "overwork", "stress"
    case threshold    // Count-based: "pending_actions > 10"
    case state        // Emotional: "stress_level > 0.7 for 30min"
    case event        // System events (future): "new_calendar_event"
}

struct ScheduleTrigger: Codable {
    var frequency: String    // "daily", "weekly", "hourly"
    var time: String?        // "09:00"
    var dayOfWeek: Int?      // 1=Monday, 7=Sunday
}

struct PatternTrigger: Codable {
    var patternType: String  // "overwork", "late_night", "stress"
    var sustainedMinutes: Int? // How long pattern must persist
}

struct ThresholdTrigger: Codable {
    var metric: String       // "pending_actions", "unread_insights", "context_switches"
    var comparison: String   // ">", "<", ">=", "=="
    var value: Int
}

struct StateTrigger: Codable {
    var emotion: String      // "stressed", "tired", "happy"
    var threshold: Double    // Confidence threshold
    var durationMinutes: Int
}
```

#### 1.3 Built-in Recipes (Default Set)

```yaml
# ~/.config/goose-perception/recipes/weekly-update.yaml
name: "Weekly Team Update"
description: "Generate a team status update from the week's activity"
enabled: true
trigger:
  type: schedule
  frequency: weekly
  dayOfWeek: 1  # Monday
  time: "09:00"
action:
  type: goose
  prompt: |
    Based on the following week's activity, draft a brief team status update:
    
    Projects worked on:
    {{projects}}
    
    Key collaborators:
    {{collaborators}}
    
    Notable actions/TODOs:
    {{actions}}
    
    Write a 2-3 paragraph professional update suitable for Slack.
approval: ask

---
name: "Break Reminder"
description: "Suggest a break when overwork detected"
enabled: true
trigger:
  type: pattern
  patternType: overwork
action:
  type: popup
  prompt: |
    You've been working for {{session_duration}} without a break.
    Consider stepping away for 10 minutes.
approval: auto

---
name: "Pending Actions Review"
description: "Remind about accumulated action items"
enabled: true
trigger:
  type: threshold
  metric: pending_actions
  comparison: ">"
  value: 15
action:
  type: popup
  prompt: |
    You have {{pending_actions}} pending action items.
    Top priorities:
    {{top_actions}}
approval: auto

---
name: "Stress Intervention"
description: "Offer help when prolonged stress detected"
enabled: true
trigger:
  type: state
  emotion: stressed
  threshold: 0.7
  durationMinutes: 30
action:
  type: popup
  prompt: |
    I've noticed you might be feeling stressed.
    Would you like me to help prioritize your tasks?
approval: ask
```

---

### Phase 2: Agent Runner (CLI Bridge)

#### 2.1 AgentRunner Service

```swift
// Services/AgentRunner/AgentRunner.swift
actor AgentRunner {
    
    enum AgentType: String {
        case goose
        case claude
        case amp
    }
    
    struct AgentResult {
        let success: Bool
        let output: String
        let duration: TimeInterval
        let error: String?
    }
    
    /// Check if agent CLI is available
    func isAgentAvailable(_ agent: AgentType) -> Bool {
        let path = agentPath(agent)
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    /// Run agent with prompt
    func run(
        agent: AgentType,
        prompt: String,
        timeout: TimeInterval = 300
    ) async throws -> AgentResult {
        let path = agentPath(agent)
        
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AgentError.notInstalled(agent)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        
        // Agent-specific arguments
        switch agent {
        case .goose:
            // goose run --prompt "..."
            process.arguments = ["run", "--prompt", prompt]
        case .claude:
            // claude -p "..."
            process.arguments = ["-p", prompt]
        case .amp:
            // amp -x "..."
            process.arguments = ["-x", prompt]
        }
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        let startTime = Date()
        try process.run()
        
        // Wait with timeout
        let completed = await withTimeout(seconds: timeout) {
            process.waitUntilExit()
        }
        
        guard completed else {
            process.terminate()
            throw AgentError.timeout
        }
        
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startTime)
        
        return AgentResult(
            success: process.terminationStatus == 0,
            output: output,
            duration: duration,
            error: process.terminationStatus != 0 ? errOutput : nil
        )
    }
    
    private func agentPath(_ agent: AgentType) -> String {
        // Check common locations
        let paths = [
            "/usr/local/bin/\(agent.rawValue)",
            "/opt/homebrew/bin/\(agent.rawValue)",
            "~/.local/bin/\(agent.rawValue)",
            "~/.cargo/bin/\(agent.rawValue)"  // for amp
        ]
        
        for path in paths {
            let expanded = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        
        return "/usr/local/bin/\(agent.rawValue)"  // Default
    }
}
```

#### 2.2 Context Compiler

Pulls relevant context from DB to inject into prompts:

```swift
// Services/AgentRunner/ContextCompiler.swift
actor ContextCompiler {
    private let database: Database
    
    func compile(for recipe: Recipe) async throws -> [String: String] {
        var context: [String: String] = [:]
        
        // Projects
        let projects = try await database.getAllProjects()
        context["projects"] = projects
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(10)
            .map { "- \($0.name): \($0.description ?? "N/A")" }
            .joined(separator: "\n")
        
        // Collaborators
        let collaborators = try await database.getAllCollaborators()
        context["collaborators"] = collaborators
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(10)
            .map { "- \($0.name): \($0.context ?? "N/A")" }
            .joined(separator: "\n")
        
        // Pending actions
        let actions = try await database.getAllActions()
        let pending = actions.filter { !$0.completed }
        context["pending_actions"] = "\(pending.count)"
        context["actions"] = pending
            .prefix(10)
            .map { "- \($0.description)" }
            .joined(separator: "\n")
        context["top_actions"] = pending
            .prefix(5)
            .map { "- \($0.description)" }
            .joined(separator: "\n")
        
        // Recent insights
        let insights = try await database.getUnshownInsights()
        context["insights"] = insights
            .prefix(5)
            .map { "- \($0.content)" }
            .joined(separator: "\n")
        
        // Time context
        context["current_time"] = ISO8601DateFormatter().string(from: Date())
        context["day_of_week"] = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1]
        
        return context
    }
    
    func applyTemplate(_ template: String, context: [String: String]) -> String {
        var result = template
        for (key, value) in context {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}
```

---

### Phase 3: Trigger Engine & Scheduler

```swift
// Services/TriggerEngine/TriggerEngine.swift
@MainActor
class TriggerEngine: ObservableObject {
    private let database: Database
    private let agentRunner: AgentRunner
    private let contextCompiler: ContextCompiler
    private let patternDetector: PatternDetectionPass
    
    @Published var pendingApprovals: [RecipeExecution] = []
    @Published var recentExecutions: [RecipeExecution] = []
    
    private var schedulerTask: Task<Void, Never>?
    private var patternMonitorTask: Task<Void, Never>?
    
    func start() {
        // 1. Start schedule checker (every minute)
        schedulerTask = Task {
            while !Task.isCancelled {
                await checkScheduledRecipes()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        
        // 2. Start pattern monitor (piggyback on analysis)
        // Hook into AnalysisScheduler callbacks
    }
    
    private func checkScheduledRecipes() async {
        let recipes = try? await database.getEnabledRecipes()
            .filter { $0.triggerType == "schedule" }
        
        for recipe in recipes ?? [] {
            if shouldTrigger(recipe) {
                await triggerRecipe(recipe)
            }
        }
    }
    
    func onPatternDetected(_ pattern: WorkPattern) async {
        // Find recipes that match this pattern
        let recipes = try? await database.getEnabledRecipes()
            .filter { $0.triggerType == "pattern" }
        
        for recipe in recipes ?? [] {
            if matchesPattern(recipe, pattern) {
                await triggerRecipe(recipe)
            }
        }
    }
    
    private func triggerRecipe(_ recipe: Recipe) async {
        // 1. Create execution record
        var execution = RecipeExecution(
            recipeId: recipe.id!,
            triggeredAt: Date(),
            approvalStatus: recipe.approvalMode == "auto" ? "auto" : "pending",
            executionStatus: "pending",
            contextSnapshot: "{}"  // Filled below
        )
        
        // 2. Compile context
        let context = try? await contextCompiler.compile(for: recipe)
        execution.contextSnapshot = (try? JSONEncoder().encode(context)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        // 3. Check approval mode
        switch recipe.approvalMode {
        case "auto":
            await executeRecipe(recipe, execution: &execution, context: context ?? [:])
            
        case "ask":
            // Add to pending approvals, show UI
            execution.approvalStatus = "pending"
            _ = try? await database.insertRecipeExecution(&execution)
            pendingApprovals.append(execution)
            showApprovalPopup(recipe, execution: execution)
            
        default: // "off"
            return
        }
    }
    
    func approveExecution(_ execution: RecipeExecution) async {
        var exec = execution
        exec.approvalStatus = "approved"
        
        let recipe = try? await database.getRecipe(id: execution.recipeId)
        guard let recipe else { return }
        
        let context = (try? JSONDecoder().decode([String: String].self, from: exec.contextSnapshot.data(using: .utf8) ?? Data())) ?? [:]
        
        await executeRecipe(recipe, execution: &exec, context: context)
    }
    
    func rejectExecution(_ execution: RecipeExecution) async {
        var exec = execution
        exec.approvalStatus = "rejected"
        exec.executionStatus = "failed"
        exec.completedAt = Date()
        try? await database.updateRecipeExecution(exec)
        
        // Update recipe reject count
        if var recipe = try? await database.getRecipe(id: execution.recipeId) {
            recipe.rejectCount += 1
            try? await database.updateRecipe(recipe)
        }
        
        pendingApprovals.removeAll { $0.id == execution.id }
    }
    
    private func executeRecipe(
        _ recipe: Recipe,
        execution: inout RecipeExecution,
        context: [String: String]
    ) async {
        execution.executionStatus = "running"
        try? await database.updateRecipeExecution(execution)
        
        // Apply template
        let prompt = contextCompiler.applyTemplate(recipe.promptTemplate, context: context)
        
        // Execute based on action type
        switch recipe.actionType {
        case "popup":
            showInsightPopup(prompt)
            execution.executionStatus = "success"
            
        case "goose", "claude", "amp":
            let agent = AgentRunner.AgentType(rawValue: recipe.actionType)!
            do {
                let result = try await agentRunner.run(agent: agent, prompt: prompt)
                execution.agentOutput = result.output
                execution.executionStatus = result.success ? "success" : "failed"
            } catch {
                execution.executionStatus = "failed"
                execution.agentOutput = error.localizedDescription
            }
            
        default:
            execution.executionStatus = "failed"
        }
        
        execution.completedAt = Date()
        try? await database.updateRecipeExecution(execution)
        
        // Update recipe stats
        if var updatedRecipe = try? await database.getRecipe(id: recipe.id!) {
            updatedRecipe.lastTriggered = Date()
            if execution.executionStatus == "success" {
                updatedRecipe.successCount += 1
                updatedRecipe.lastSuccess = Date()
            }
            try? await database.updateRecipe(updatedRecipe)
        }
    }
}
```

---

### Phase 4: UI Integration

#### 4.1 Approval Popup

When `approvalMode == "ask"`, show a popup:

```swift
// Views/Popups/RecipeApprovalPopup.swift
struct RecipeApprovalPopup: View {
    let recipe: Recipe
    let execution: RecipeExecution
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                Text(recipe.name)
                    .font(.headline)
            }
            
            // Description
            Text(recipe.description ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Preview of what will happen
            GroupBox("Action Preview") {
                Text(previewText)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(10)
            }
            
            // Agent indicator
            if recipe.actionType != "popup" {
                HStack {
                    Image(systemName: "terminal")
                    Text("Will run: \(recipe.actionType)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button("Dismiss", action: onReject)
                    .keyboardShortcut(.escape)
                
                Button("Run Action", action: onApprove)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
```

#### 4.2 Recipes Settings View

```swift
// Views/SettingsView+Recipes.swift
struct RecipesSettingsView: View {
    @State private var recipes: [Recipe] = []
    @State private var selectedRecipe: Recipe?
    
    var body: some View {
        HSplitView {
            // Recipe list
            List(recipes, selection: $selectedRecipe) { recipe in
                RecipeRow(recipe: recipe)
            }
            .frame(minWidth: 200)
            
            // Recipe detail/editor
            if let recipe = selectedRecipe {
                RecipeDetailView(recipe: recipe)
            } else {
                Text("Select a recipe")
                    .foregroundColor(.secondary)
            }
        }
        .toolbar {
            Button(action: addRecipe) {
                Image(systemName: "plus")
            }
        }
    }
}
```

#### 4.3 Execution History View

Add to Dashboard:

```swift
// Views/Dashboard/ExecutionHistoryView.swift  
struct ExecutionHistoryView: View {
    let executions: [RecipeExecution]
    
    var body: some View {
        Table(executions) {
            TableColumn("Time") { exec in
                Text(exec.triggeredAt, style: .relative)
            }
            TableColumn("Recipe") { exec in
                Text(recipeName(exec.recipeId))
            }
            TableColumn("Status") { exec in
                StatusBadge(status: exec.executionStatus)
            }
            TableColumn("Feedback") { exec in
                FeedbackButtons(execution: exec)
            }
        }
    }
}
```

---

## Database Migrations

Add to `Database.swift` migrations:

```swift
// Migration: Add recipes table
migrator.registerMigration("addRecipes") { db in
    try db.create(table: "recipes") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("name", .text).notNull()
        t.column("description", .text)
        t.column("enabled", .boolean).notNull().defaults(to: true)
        t.column("trigger_type", .text).notNull()
        t.column("trigger_config", .text).notNull()
        t.column("action_type", .text).notNull()
        t.column("prompt_template", .text).notNull()
        t.column("approval_mode", .text).notNull().defaults(to: "ask")
        t.column("success_count", .integer).notNull().defaults(to: 0)
        t.column("reject_count", .integer).notNull().defaults(to: 0)
        t.column("last_triggered", .datetime)
        t.column("last_success", .datetime)
    }
    
    try db.create(table: "recipe_executions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("recipe_id", .integer).notNull().references("recipes")
        t.column("triggered_at", .datetime).notNull()
        t.column("approval_status", .text).notNull()
        t.column("execution_status", .text).notNull()
        t.column("context_snapshot", .text).notNull()
        t.column("agent_output", .text)
        t.column("completed_at", .datetime)
        t.column("user_feedback", .text)
    }
}
```

---

## File Structure Addition

```
GoosePerception/
├── Services/
│   ├── AgentRunner/
│   │   ├── AgentRunner.swift        # CLI execution
│   │   └── ContextCompiler.swift    # Template + context
│   └── TriggerEngine/
│       ├── TriggerEngine.swift      # Main orchestrator
│       ├── TriggerTypes.swift       # Trigger definitions
│       └── RecipeLoader.swift       # YAML → Recipe
├── Database/Models/
│   ├── Recipe.swift
│   └── RecipeExecution.swift
├── Views/
│   ├── Popups/
│   │   └── RecipeApprovalPopup.swift
│   └── Settings/
│       └── RecipesSettingsView.swift
└── Resources/
    └── DefaultRecipes/
        ├── weekly-update.yaml
        ├── break-reminder.yaml
        └── actions-review.yaml
```

---

## Implementation Order

1. **Database**: Add Recipe, RecipeExecution models + migrations
2. **AgentRunner**: CLI bridge to goose/claude/amp
3. **ContextCompiler**: Template variable injection
4. **TriggerEngine**: Schedule + pattern triggers
5. **UI**: Approval popup, recipes settings, execution history
6. **Default Recipes**: Ship sensible defaults
7. **Learning**: Track success/reject, auto-disable bad recipes

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| YAML recipes in config dir | User-editable, version-controllable |
| Approval modes (auto/ask/off) | Gradual trust building |
| CLI bridge (not library) | Works with any agent, no SDK dependency |
| Context compilation | Rich prompts without user effort |
| Execution tracking | Learn which recipes work |
| Pattern-based triggers | Leverage existing PatternDetectionPass |

---

## Safety Rails

1. **No auto by default** - All recipes start as `ask` mode
2. **Reject learning** - Recipes auto-disable after N rejects
3. **Quiet hours** - Global setting to suppress all triggers
4. **Rate limiting** - Max 1 execution per recipe per hour
5. **Audit log** - Full history of all executions
6. **Easy kill switch** - One toggle to disable all automation

---

## Integration Points

- **AnalysisScheduler**: Already has callbacks for new actions/insights → hook TriggerEngine
- **PatternDetectionPass**: Already detects overwork/stress → route to TriggerEngine
- **InsightPopupManager**: Reuse for recipe approval popups
- **SettingsView**: Add Recipes tab for management
