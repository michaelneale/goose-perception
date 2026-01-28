//
// ProjectsRefiner.swift
//
// Extracts project names from screen content
//

import Foundation

struct ProjectsRefiner: Refiner {
    typealias Output = [String]
    
    let name = "Extract Projects"
    
    var existingItems: [String] = []
    
    var systemPrompt: String {
        var prompt = """
Extract project/repository names from user activity. Look for:
- Repository names in code editors (GitHub, GitLab, etc.)
- Project folders in file paths
- Jira/Linear/GitHub project names
- Workspace or folder names
- App names being developed

Return a JSON array of project names only:
["project-name", "another-project"]

If no projects found, respond: []
"""
        if !existingItems.isEmpty {
            prompt += "\n\nAlready known projects: \(existingItems.joined(separator: ", "))"
            prompt += "\nInclude these if still relevant, plus any new ones."
        }
        return prompt
    }
    
    func parse(response: String) -> Output {
        parseJSONStringArray(response)
    }
    
    func store(output: Output, database: Database) async throws {
        for name in output {
            try await database.upsertProject(name: name)
        }
    }
}
