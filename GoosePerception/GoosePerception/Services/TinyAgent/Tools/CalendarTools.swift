//
// CalendarTools.swift
//
// TinyAgent tools for Calendar app integration.
//

import Foundation

// MARK: - Create Calendar Event

struct CreateCalendarEventTool: TinyAgentTool {
    let name = TinyAgentToolName.createCalendarEvent
    
    var promptDescription: String {
        """
        create_calendar_event(title: str, start_date: str, end_date: str, location: str, invitees: list[str], notes: str, calendar: str) -> str
         - Create a calendar event.
         - The format for start_date and end_date is 'YYYY-MM-DD HH:MM:SS'.
         - For invitees, you need a list of email addresses; use an empty list if not applicable.
         - For location, notes, and calendar, use an empty string or None if not applicable.
         - Returns the status of the event creation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 7 else {
            throw AppleScriptError.invalidArguments("create_calendar_event requires 7 arguments")
        }
        
        guard let title = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("title must be a string")
        }
        
        guard let startDateStr = arguments[1] as? String,
              let endDateStr = arguments[2] as? String else {
            throw AppleScriptError.invalidArguments("start_date and end_date must be strings")
        }
        
        // Parse dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        guard let startDate = dateFormatter.date(from: startDateStr) else {
            throw AppleScriptError.invalidArguments("Invalid start_date format. Use YYYY-MM-DD HH:MM:SS")
        }
        
        guard let endDate = dateFormatter.date(from: endDateStr) else {
            throw AppleScriptError.invalidArguments("Invalid end_date format. Use YYYY-MM-DD HH:MM:SS")
        }
        
        let location = (arguments[3] as? String).flatMap { $0.isEmpty ? nil : $0 }
        
        var invitees: [String] = []
        if let inviteeList = arguments[4] as? [Any] {
            invitees = inviteeList.compactMap { $0 as? String }
        }
        
        let notes = (arguments[5] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let calendarName = (arguments[6] as? String).flatMap { $0.isEmpty ? nil : $0 }
        
        return try await AppleScriptBridge.shared.createCalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location,
            invitees: invitees,
            notes: notes,
            calendarName: calendarName
        )
    }
}
