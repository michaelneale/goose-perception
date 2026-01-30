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
Extract people's names from the screen content below. Names appear in:
- Meeting titles and calendar entries (e.g., "Meeting with John Smith", "Alice / Bob")
- Calendar attendee lists
- Email sender/recipient names
- Chat message headers showing who sent messages
- @mentions in Slack, Discord, etc.
- Video call participant names (Zoom, Meet, Teams)
- Spoken names in voice transcription

Look carefully at ALL the text content for any person names. Meeting titles like "Douwe / Mic" contain the names "Douwe" and "Mic".

Return a JSON array of full names when possible, otherwise first names:
["Douwe Osinga", "Alice Smith", "Bob"]

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
