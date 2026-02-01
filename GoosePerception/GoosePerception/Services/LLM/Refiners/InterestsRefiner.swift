//
// InterestsRefiner.swift
//
// Extracts topics and interests from activity
//

import Foundation

struct InterestsRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract Interests"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Identify topics the user is interested in based on their activity.
Look for technologies, subjects, or themes in screen text and spoken words.

Return a JSON array of topic strings only:
["Swift", "machine learning", "iOS development"]

If no clear topics, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nAlready known interests: \(existingItems.joined(separator: ", "))"
            prompt += "\nInclude these if still relevant, plus any new ones."
        }
        return prompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for topic in output {
            try await database.upsertInterest(topic: topic)
        }
    }
}
