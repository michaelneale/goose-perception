//
// TodosRefiner.swift
//
// Extracts TODOs from screen captures and voice separately
//

import Foundation

/// Extracts TODOs from screen content (task lists, code TODOs, emails)
struct ScreenTodosRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract Screen TODOs"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Extract TODOs and pending tasks visible on screen. Look for:
- TODO comments in code
- Task lists in apps (Reminders, Things, Todoist, Jira, Linear, etc.)
- Action items in emails
- Unchecked checkboxes
- "Follow up" or "Need to" items

Return a JSON array of task descriptions only:
["Review PR #123", "Reply to Alice's email"]

If no tasks found, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nExisting TODOs (skip duplicates): \(existingItems.prefix(5).joined(separator: "; "))"
        }
        return prompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for description in output {
            let todo = Todo(description: description, source: "screen")
            _ = try await database.insertTodo(todo)
        }
    }
}

/// Extracts TODOs from spoken words (commitments, reminders mentioned aloud)
struct VoiceTodosRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract Voice TODOs"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Extract TODOs from spoken words. Look for verbal commitments like:
- "I need to..."
- "Don't forget to..."
- "Remind me to..."
- "I'll do that later"
- "I should..."
- Action items agreed in conversation

Return a JSON array of task descriptions only:
["Call the dentist", "Send the report to Bob"]

If no tasks found, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nExisting TODOs (skip duplicates): \(existingItems.prefix(5).joined(separator: "; "))"
        }
        return prompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for description in output {
            let todo = Todo(description: description, source: "voice")
            _ = try await database.insertTodo(todo)
        }
    }
}

/// Legacy refiner for backward compatibility
struct TodosRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract TODOs"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        ScreenTodosRefiner(existingItems: existingItems).systemPrompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for description in output {
            let todo = Todo(description: description, source: "analysis")
            _ = try await database.insertTodo(todo)
        }
    }
}
