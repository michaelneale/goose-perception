//
// RemindersTools.swift
//
// TinyAgent tools for Reminders app integration.
//

import Foundation

// MARK: - Create Reminder

struct CreateReminderTool: TinyAgentTool {
    let name = TinyAgentToolName.createReminder
    
    var promptDescription: String {
        """
        create_reminder(title: str, due_date: str, notes: str, list_name: str) -> str
         - Create a reminder.
         - The format for due_date is 'YYYY-MM-DD HH:MM:SS'. Use None if no due date.
         - For notes and list_name, use None if not applicable.
         - Returns the status of the reminder creation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let title = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("create_reminder requires a title argument")
        }
        
        var dueDate: Date? = nil
        if arguments.count >= 2, let dueDateStr = arguments[1] as? String, !dueDateStr.isEmpty, dueDateStr.lowercased() != "none" {
            // Try multiple date formats
            let formats = [
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd HH:mm",
                "yyyy-MM-dd",
                "MM/dd/yyyy HH:mm:ss",
                "MM/dd/yyyy HH:mm",
                "MM/dd/yyyy",
                "MMMM d, yyyy 'at' h:mm a",
                "MMMM d, yyyy"
            ]
            
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US")
            
            for format in formats {
                dateFormatter.dateFormat = format
                if let parsed = dateFormatter.date(from: dueDateStr) {
                    dueDate = parsed
                    break
                }
            }
            
            // If still nil, try natural language parsing
            if dueDate == nil {
                // Handle relative dates like "tomorrow", "tomorrow at 9am"
                let calendar = Calendar.current
                let now = Date()
                let lowered = dueDateStr.lowercased()
                
                if lowered.contains("tomorrow") {
                    var date = calendar.date(byAdding: .day, value: 1, to: now)!
                    // Check for time component
                    if let atRange = lowered.range(of: "at ") {
                        let timeStr = String(lowered[atRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        dateFormatter.dateFormat = "h:mm a"
                        if let time = dateFormatter.date(from: timeStr) {
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                            date = calendar.date(bySettingHour: timeComponents.hour ?? 9, minute: timeComponents.minute ?? 0, second: 0, of: date)!
                        } else {
                            // Try just hour like "9am" or "11:00"
                            dateFormatter.dateFormat = "ha"
                            if let time = dateFormatter.date(from: timeStr.replacingOccurrences(of: " ", with: "")) {
                                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                                date = calendar.date(bySettingHour: timeComponents.hour ?? 9, minute: timeComponents.minute ?? 0, second: 0, of: date)!
                            }
                        }
                    } else {
                        // Default to 9am
                        date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
                    }
                    dueDate = date
                }
            }
        }
        
        let notes: String? = arguments.count >= 3 ? arguments[2] as? String : nil
        let listName: String? = arguments.count >= 4 ? arguments[3] as? String : nil
        
        return try await AppleScriptBridge.shared.createReminder(
            title: title,
            dueDate: dueDate,
            notes: notes,
            listName: listName
        )
    }
}
