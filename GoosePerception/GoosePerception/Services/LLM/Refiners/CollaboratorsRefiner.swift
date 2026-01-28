//
// CollaboratorsRefiner.swift
//
// Extracts people's names from messaging apps, email, calendar
//

import Foundation

struct CollaboratorsRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract Collaborators"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Extract people's names from user activity. Look for names in:
- Slack channels, DMs, message lists
- Discord servers, channels, DMs
- Gmail, email senders/recipients
- iMessage, Messages app
- Calendar invites, meeting participants
- @mentions anywhere
- Window titles showing conversations
- Names spoken aloud

Return a JSON array of names only:
["Alice Smith", "Bob Jones"]

If no names found, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nAlready known collaborators: \(existingItems.joined(separator: ", "))"
            prompt += "\nInclude these if mentioned, plus any new ones."
        }
        return prompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for name in output {
            try await database.upsertCollaborator(name: name)
        }
    }
}
