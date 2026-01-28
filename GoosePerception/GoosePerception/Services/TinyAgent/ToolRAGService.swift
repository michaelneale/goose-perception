//
// ToolRAGService.swift
//
// Tool selection service using keyword heuristics.
// Designed to be swappable with a real classifier later.
//

import Foundation

/// Service for selecting relevant tools based on user query
actor ToolRAGService {
    static let shared = ToolRAGService()
    
    /// Minimum confidence threshold for tool selection
    var threshold: Float = 0.5
    
    private init() {}
    
    // MARK: - Keyword Mappings
    
    /// Keywords that indicate specific tools should be selected
    private let toolKeywords: [TinyAgentToolName: [String]] = [
        // Contacts
        .getPhoneNumber: [
            "phone", "call", "number", "mobile", "cell", "contact", "dial",
            "telephone", "reach", "phone number", "get number"
        ],
        .getEmailAddress: [
            "email", "mail", "address", "contact", "e-mail", "email address",
            "send email", "get email", "email of"
        ],
        
        // Calendar
        .createCalendarEvent: [
            "calendar", "event", "meeting", "schedule", "appointment", "book",
            "create event", "add event", "set up meeting", "schedule meeting",
            "invite", "block time", "mark calendar"
        ],
        
        // Reminders
        .createReminder: [
            "reminder", "remind", "todo", "task", "remember", "don't forget",
            "set reminder", "create reminder", "remind me", "to-do"
        ],
        
        // Mail
        .composeNewEmail: [
            "email", "mail", "send", "write", "compose", "draft",
            "send email", "write email", "compose email", "new email",
            "message to", "reach out"
        ],
        .replyToEmail: [
            "reply", "respond", "answer", "reply to", "respond to",
            "reply email", "email back"
        ],
        .forwardEmail: [
            "forward", "share email", "pass along", "forward to",
            "send forward", "forward email"
        ],
        
        // Notes
        .createNote: [
            "note", "write", "jot", "record", "document", "create note",
            "new note", "take note", "write down", "save note"
        ],
        .openNote: [
            "open note", "find note", "show note", "view note",
            "look at note", "read note"
        ],
        .appendNoteContent: [
            "append", "add to note", "update note", "extend note",
            "add content", "append to"
        ],
        
        // Messages
        .sendSMS: [
            "sms", "text", "message", "imessage", "send text", "text message",
            "send message", "send sms", "notify", "let know", "tell"
        ],
        
        // Maps
        .mapsOpenLocation: [
            "location", "place", "where", "find", "map", "show on map",
            "open location", "navigate to", "find place", "search location"
        ],
        .mapsShowDirections: [
            "directions", "route", "how to get", "navigate", "drive to",
            "walk to", "get directions", "show directions", "way to",
            "from", "to"  // Common in "directions from X to Y"
        ],
        
        // Files
        .openAndGetFilePath: [
            "file", "document", "find file", "open file", "search file",
            "locate", "where is", "look for file", "find document",
            "open document"
        ],
        .summarizePDF: [
            "pdf", "summarize", "summary", "read pdf", "extract",
            "summarize pdf", "pdf summary", "what's in"
        ],
        
        // Zoom
        .getZoomMeetingLink: [
            "zoom", "video call", "meeting link", "create zoom",
            "zoom meeting", "video meeting", "start zoom", "zoom link"
        ]
    ]
    
    /// Negative keywords that reduce confidence
    private let negativeKeywords: [TinyAgentToolName: [String]] = [
        .sendSMS: ["email", "mail"],  // If email is mentioned, probably not SMS
        .composeNewEmail: ["sms", "text message"],  // If SMS is mentioned, probably not email
        .getPhoneNumber: ["email address"],
        .getEmailAddress: ["phone number", "call"],
    ]
    
    /// Context boosters - keywords that boost confidence when combined
    private let contextBoosters: [String: Set<TinyAgentToolName>] = [
        "urgent": [.sendSMS, .composeNewEmail],
        "asap": [.sendSMS, .composeNewEmail],
        "tomorrow": [.createCalendarEvent, .createReminder],
        "next week": [.createCalendarEvent],
        "meeting": [.createCalendarEvent, .getZoomMeetingLink],
        "work": [.createCalendarEvent, .composeNewEmail, .createNote],
    ]
    
    // MARK: - Tool Selection
    
    /// Select relevant tools for a query
    func selectTools(for query: String) -> Set<TinyAgentToolName> {
        let scores = computeScores(for: query)
        return Set(scores.filter { $0.value >= threshold }.map { $0.key })
    }
    
    /// Select tools with scores (for debugging)
    func selectToolsWithScores(for query: String) -> [(TinyAgentToolName, Float)] {
        let scores = computeScores(for: query)
        return scores
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
    
    /// Compute confidence scores for each tool
    private func computeScores(for query: String) -> [TinyAgentToolName: Float] {
        let queryLower = query.lowercased()
        let queryWords = Set(queryLower.components(separatedBy: .whitespaces))
        
        var scores: [TinyAgentToolName: Float] = [:]
        
        for tool in TinyAgentToolName.allCases {
            var score: Float = 0.0
            
            // Check positive keywords
            if let keywords = toolKeywords[tool] {
                for keyword in keywords {
                    if queryLower.contains(keyword) {
                        // Multi-word keywords get higher scores
                        let wordCount = keyword.components(separatedBy: " ").count
                        score += Float(wordCount) * 0.3
                    }
                }
            }
            
            // Apply negative keywords
            if let negatives = negativeKeywords[tool] {
                for negative in negatives {
                    if queryLower.contains(negative) {
                        score -= 0.4
                    }
                }
            }
            
            // Apply context boosters
            for (booster, boostedTools) in contextBoosters {
                if queryLower.contains(booster) && boostedTools.contains(tool) {
                    score += 0.15
                }
            }
            
            // Cap score at 1.0
            scores[tool] = min(max(score, 0), 1.0)
        }
        
        return scores
    }
    
    // MARK: - In-Context Examples
    
    /// Get relevant in-context examples for selected tools
    func getExamples(for tools: Set<TinyAgentToolName>, maxExamples: Int = 3) -> String {
        var examples: [String] = []
        
        for tool in tools {
            if let example = toolExamples[tool], examples.count < maxExamples {
                examples.append(example)
            }
        }
        
        if examples.isEmpty {
            return ""
        }
        
        return examples.joined(separator: "\n###\n")
    }
    
    /// In-context examples for each tool
    private let toolExamples: [TinyAgentToolName: String] = [
        .getPhoneNumber: """
            Question: Get John's phone number.
            1. get_phone_number("John")
            Thought: I have successfully found the phone number.
            2. join()<END_OF_PLAN>
            """,
        
        .getEmailAddress: """
            Question: What is Sarah's email address?
            1. get_email_address("Sarah")
            Thought: I have successfully found the email address.
            2. join()<END_OF_PLAN>
            """,
        
        .createCalendarEvent: """
            Question: Schedule a meeting with the team tomorrow at 2 PM.
            1. create_calendar_event("Team Meeting", "2024-01-15 14:00:00", "2024-01-15 15:00:00", "", [], "", None)
            Thought: I have successfully created the calendar event.
            2. join()<END_OF_PLAN>
            """,
        
        .createReminder: """
            Question: Remind me to call mom tomorrow.
            1. create_reminder("Call mom", "2024-01-15 09:00:00", None, None)
            Thought: I have successfully created the reminder.
            2. join()<END_OF_PLAN>
            """,
        
        .composeNewEmail: """
            Question: Send an email to john@example.com about the project update.
            1. compose_new_email(["john@example.com"], [], "Project Update", "", [])
            Thought: I have successfully composed the email.
            2. join()<END_OF_PLAN>
            """,
        
        .sendSMS: """
            Question: Text Sarah about the meeting change.
            1. get_phone_number("Sarah")
            2. send_sms([$1], "Hey, just wanted to let you know the meeting time has changed.")
            Thought: I have successfully sent the message.
            3. join()<END_OF_PLAN>
            """,
        
        .mapsShowDirections: """
            Question: Show me directions to Apple Park.
            1. maps_show_directions("", "Apple Park", "d")
            Thought: I have successfully shown the directions.
            2. join()<END_OF_PLAN>
            """,
        
        .mapsOpenLocation: """
            Question: Find the nearest coffee shop.
            1. maps_open_location("coffee shop")
            Thought: I have opened the location in Maps.
            2. join()<END_OF_PLAN>
            """,
        
        .createNote: """
            Question: Create a note with my meeting notes.
            1. create_note("Meeting Notes", "Notes from today's meeting:\\n- Action items discussed\\n- Next steps planned", None)
            Thought: I have successfully created the note.
            2. join()<END_OF_PLAN>
            """,
        
        .openAndGetFilePath: """
            Question: Find the project proposal document.
            1. open_and_get_file_path("project proposal")
            Thought: I have found and opened the file.
            2. join()<END_OF_PLAN>
            """,
        
        .getZoomMeetingLink: """
            Question: Create a Zoom meeting for the team sync.
            1. get_zoom_meeting_link("Team Sync", "2024-01-15 10:00:00", 60, [])
            Thought: I have created the Zoom meeting.
            2. join()<END_OF_PLAN>
            """
    ]
}

// MARK: - Prompt Building Extension

extension ToolRAGService {
    
    /// Build the system prompt with selected tools
    func buildSystemPrompt(for tools: Set<TinyAgentToolName>) async -> String {
        let toolsPrompt = await ToolRegistry.shared.generateToolsPrompt(for: tools)
        let examples = getExamples(for: tools)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = dateFormatter.string(from: Date())
        
        return """
            Given a user query, create a plan to solve it with the utmost parallelizability.
            Each plan should comprise an action from the following types:
            
            \(toolsPrompt)
            
            Guidelines:
             - Each action described above contains input/output types and description.
                - You must strictly adhere to the input and output types for each action.
                - The action descriptions contain the guidelines. You MUST strictly follow those guidelines when you use the actions.
             - Each action in the plan should strictly be one of the above types. Follow the Python conventions for each action.
             - Each action MUST have a unique ID, which is strictly increasing.
             - Inputs for actions can either be constants or outputs from preceding actions. In the latter case, use the format $id to denote the ID of the previous action whose output will be the input.
             - Always call join as the last action in the plan. Say '<END_OF_PLAN>' after you call join
             - Ensure the plan maximizes parallelizability.
             - Only use the provided action types. If a query cannot be addressed using these, invoke the join action for the next steps.
             - Never explain the plan with comments (e.g. #).
             - Never introduce new actions other than the ones provided.
            
            Custom Instructions:
             - You need to start your plan with the '1.' call
             - Today's date is \(currentDate)
             - Unless otherwise specified, the default meeting duration is 60 minutes.
             - Do not use named arguments in your tool calls.
             - You MUST end your plans with the 'join()' call and a '\\n' character.
             - You MUST fill every argument in the tool calls, even if they are optional.
             - The format for dates MUST be in ISO format of 'YYYY-MM-DD HH:MM:SS', unless other specified.
             - If you want to use the result of a previous tool call, you MUST use the '$' sign followed by the index of the tool call.
             - You MUST ONLY USE join() at the very very end of the plan, or you WILL BE PENALIZED.
            
            Here are some examples:
            
            \(examples)
            """
    }
}
