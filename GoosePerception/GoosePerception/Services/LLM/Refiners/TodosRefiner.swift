//
// TodosRefiner.swift
//
// Extracts TODOs and pending tasks from activity
//

import Foundation

struct TodosRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract TODOs"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Find TODOs and pending tasks from user activity. Look for:
- TODO comments in code on screen
- Tasks in to-do apps
- Items user needs to follow up on
- Commitments made in chat
- Things the user said they need to do

Return a JSON array of task strings only:
["Review PR #123", "Reply to Alice's email"]

If no tasks found, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nPending TODOs: \(existingItems.prefix(5).joined(separator: "; "))"
            prompt += "\nInclude new TODOs only, skip duplicates."
        }
        return prompt
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
