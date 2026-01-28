//
// TinyAgentTool.swift
//
// Protocol and types for TinyAgent Mac automation tools.
//

import Foundation

/// Names of all available TinyAgent tools
enum TinyAgentToolName: String, CaseIterable, Codable {
    // Contacts
    case getPhoneNumber = "get_phone_number"
    case getEmailAddress = "get_email_address"
    
    // Calendar
    case createCalendarEvent = "create_calendar_event"
    
    // Reminders
    case createReminder = "create_reminder"
    
    // Mail
    case composeNewEmail = "compose_new_email"
    case replyToEmail = "reply_to_email"
    case forwardEmail = "forward_email"
    
    // Notes
    case createNote = "create_note"
    case openNote = "open_note"
    case appendNoteContent = "append_note_content"
    
    // Messages
    case sendSMS = "send_sms"
    
    // Maps
    case mapsOpenLocation = "maps_open_location"
    case mapsShowDirections = "maps_show_directions"
    
    // Files
    case openAndGetFilePath = "open_and_get_file_path"
    case summarizePDF = "summarize_pdf"
    
    // Zoom
    case getZoomMeetingLink = "get_zoom_meeting_link"
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .getPhoneNumber: return "Get Phone Number"
        case .getEmailAddress: return "Get Email Address"
        case .createCalendarEvent: return "Create Calendar Event"
        case .createReminder: return "Create Reminder"
        case .composeNewEmail: return "Compose Email"
        case .replyToEmail: return "Reply to Email"
        case .forwardEmail: return "Forward Email"
        case .createNote: return "Create Note"
        case .openNote: return "Open Note"
        case .appendNoteContent: return "Append to Note"
        case .sendSMS: return "Send SMS"
        case .mapsOpenLocation: return "Open Location"
        case .mapsShowDirections: return "Show Directions"
        case .openAndGetFilePath: return "Find File"
        case .summarizePDF: return "Summarize PDF"
        case .getZoomMeetingLink: return "Create Zoom Meeting"
        }
    }
    
    /// Category for grouping in UI
    var category: String {
        switch self {
        case .getPhoneNumber, .getEmailAddress: return "Contacts"
        case .createCalendarEvent: return "Calendar"
        case .createReminder: return "Reminders"
        case .composeNewEmail, .replyToEmail, .forwardEmail: return "Mail"
        case .createNote, .openNote, .appendNoteContent: return "Notes"
        case .sendSMS: return "Messages"
        case .mapsOpenLocation, .mapsShowDirections: return "Maps"
        case .openAndGetFilePath, .summarizePDF: return "Files"
        case .getZoomMeetingLink: return "Zoom"
        }
    }
}

/// Result of executing a tool
struct ToolExecutionResult {
    let toolName: TinyAgentToolName
    let success: Bool
    let output: String
    let error: String?
    let duration: TimeInterval
    
    static func success(_ toolName: TinyAgentToolName, output: String, duration: TimeInterval = 0) -> ToolExecutionResult {
        ToolExecutionResult(toolName: toolName, success: true, output: output, error: nil, duration: duration)
    }
    
    static func failure(_ toolName: TinyAgentToolName, error: String, duration: TimeInterval = 0) -> ToolExecutionResult {
        ToolExecutionResult(toolName: toolName, success: false, output: "", error: error, duration: duration)
    }
}

/// Protocol for TinyAgent tools
protocol TinyAgentTool {
    /// The tool's name identifier
    var name: TinyAgentToolName { get }
    
    /// Description for LLM prompt (signature + guidelines)
    var promptDescription: String { get }
    
    /// Execute the tool with given arguments
    func execute(arguments: [Any]) async throws -> String
}

/// Registry of all available tools
actor ToolRegistry {
    static let shared = ToolRegistry()
    
    private var tools: [TinyAgentToolName: TinyAgentTool] = [:]
    private var enabledTools: Set<TinyAgentToolName> = Set(TinyAgentToolName.allCases)
    
    private init() {}
    
    func register(_ tool: TinyAgentTool) {
        tools[tool.name] = tool
    }
    
    func getTool(_ name: TinyAgentToolName) -> TinyAgentTool? {
        guard enabledTools.contains(name) else { return nil }
        return tools[name]
    }
    
    func getAllTools() -> [TinyAgentTool] {
        tools.values.filter { enabledTools.contains($0.name) }
    }
    
    func getEnabledToolNames() -> Set<TinyAgentToolName> {
        enabledTools.intersection(Set(tools.keys))
    }
    
    func setEnabled(_ name: TinyAgentToolName, enabled: Bool) {
        if enabled {
            enabledTools.insert(name)
        } else {
            enabledTools.remove(name)
        }
    }
    
    func isEnabled(_ name: TinyAgentToolName) -> Bool {
        enabledTools.contains(name)
    }
    
    /// Generate prompt description for a set of tools
    func generateToolsPrompt(for toolNames: Set<TinyAgentToolName>) -> String {
        var lines: [String] = []
        var index = 1
        
        for name in toolNames.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let tool = tools[name] {
                lines.append("\(index). \(tool.promptDescription)")
                index += 1
            }
        }
        
        // Always add join() as the last tool
        lines.append("\(index). join():")
        lines.append(" - Collects and combines results from prior actions.")
        lines.append(" - A LLM agent is called upon invoking join to either finalize the user query or wait until the plans are executed.")
        lines.append(" - join should always be the last action in the plan, and will be called in two scenarios:")
        lines.append("   (a) if the answer can be determined by gathering the outputs from tasks to generate the final response.")
        lines.append("   (b) if the answer cannot be determined in the planning phase before you execute the plans.")
        
        return lines.joined(separator: "\n")
    }
}
