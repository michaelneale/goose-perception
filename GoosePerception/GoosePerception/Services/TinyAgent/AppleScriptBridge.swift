//
// AppleScriptBridge.swift
//
// Executes AppleScript commands for Mac automation.
//

import Foundation
import AppKit

/// Bridge for executing AppleScript on macOS
actor AppleScriptBridge {
    static let shared = AppleScriptBridge()
    
    private init() {}
    
    /// Execute an AppleScript and return the result
    func execute(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: AppleScriptError.executionFailed(errorMessage))
                } else if let result = result {
                    continuation.resume(returning: result.stringValue ?? "")
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    /// Execute via osascript command (alternative method)
    func executeViaShell(_ script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    
                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: AppleScriptError.executionFailed(errorMessage))
                    } else {
                        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum AppleScriptError: Error, LocalizedError {
    case executionFailed(String)
    case invalidArguments(String)
    case notAvailable(String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "AppleScript execution failed: \(message)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .notAvailable(let app):
            return "\(app) is not available"
        }
    }
}

// MARK: - AppleScript Templates

extension AppleScriptBridge {
    
    // MARK: - Contacts
    
    func getPhoneNumber(name: String) async throws -> String {
        let script = """
        tell application "Contacts"
            set matchingPeople to (every person whose name contains "\(escapeForAppleScript(name))")
            if (count of matchingPeople) > 0 then
                set thePerson to item 1 of matchingPeople
                set thePhones to phones of thePerson
                if (count of thePhones) > 0 then
                    return value of item 1 of thePhones
                else
                    return "No phone number found"
                end if
            else
                return "Contact not found"
            end if
        end tell
        """
        return try await execute(script)
    }
    
    func getEmailAddress(name: String) async throws -> String {
        let script = """
        tell application "Contacts"
            set matchingPeople to (every person whose name contains "\(escapeForAppleScript(name))")
            if (count of matchingPeople) > 0 then
                set thePerson to item 1 of matchingPeople
                set theEmails to emails of thePerson
                if (count of theEmails) > 0 then
                    return value of item 1 of theEmails
                else
                    return "No email found"
                end if
            else
                return "Contact not found"
            end if
        end tell
        """
        return try await execute(script)
    }
    
    // MARK: - Calendar
    
    func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        invitees: [String],
        notes: String?,
        calendarName: String?
    ) async throws -> String {
        let dateFormatter = ISO8601DateFormatter()
        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)
        
        var script = """
        tell application "Calendar"
            tell calendar "\(escapeForAppleScript(calendarName ?? "Calendar"))"
                set newEvent to make new event with properties {summary:"\(escapeForAppleScript(title))", start date:date "\(startStr)", end date:date "\(endStr)"
        """
        
        if let location = location, !location.isEmpty {
            script += ", location:\"\(escapeForAppleScript(location))\""
        }
        
        if let notes = notes, !notes.isEmpty {
            script += ", description:\"\(escapeForAppleScript(notes))\""
        }
        
        script += "}\n"
        
        // Add invitees
        for email in invitees {
            script += """
                make new attendee at end of attendees of newEvent with properties {email:"\(escapeForAppleScript(email))"}
            """
        }
        
        script += """
            end tell
            return "Event created successfully"
        end tell
        """
        
        return try await execute(script)
    }
    
    // MARK: - Reminders
    
    func createReminder(
        title: String,
        dueDate: Date?,
        notes: String?,
        listName: String?
    ) async throws -> String {
        // Build the AppleScript using date arithmetic instead of string parsing
        var dateSetup = ""
        var dueDateProp = ""
        
        if let dueDate = dueDate {
            // Calculate seconds from now
            let secondsFromNow = Int(dueDate.timeIntervalSinceNow)
            dateSetup = "set targetDate to (current date) + \(secondsFromNow)\n"
            dueDateProp = ", due date:targetDate"
        }
        
        var props = "name:\"\(escapeForAppleScript(title))\"\(dueDateProp)"
        
        if let notes = notes, !notes.isEmpty {
            props += ", body:\"\(escapeForAppleScript(notes))\""
        }
        
        let listClause = listName.map { "list \"\(escapeForAppleScript($0))\"" } ?? "default list"
        
        let script = """
        \(dateSetup)tell application "Reminders"
            tell \(listClause)
                make new reminder with properties {\(props)}
            end tell
            return "Reminder created successfully"
        end tell
        """
        
        return try await execute(script)
    }
    
    // MARK: - Mail
    
    func composeNewEmail(
        recipients: [String],
        ccRecipients: [String],
        subject: String,
        body: String,
        attachments: [String]
    ) async throws -> String {
        var script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(escapeForAppleScript(subject))", content:"\(escapeForAppleScript(body))", visible:true}
            tell newMessage
        """
        
        for recipient in recipients {
            script += "\n        make new to recipient with properties {address:\"\(escapeForAppleScript(recipient))\"}"
        }
        
        for cc in ccRecipients {
            script += "\n        make new cc recipient with properties {address:\"\(escapeForAppleScript(cc))\"}"
        }
        
        for path in attachments {
            script += "\n        make new attachment with properties {file name:POSIX file \"\(escapeForAppleScript(path))\"} at after last paragraph"
        }
        
        script += """
        
            end tell
            activate
            return "Email draft created"
        end tell
        """
        
        return try await execute(script)
    }
    
    func replyToEmail(replyContent: String) async throws -> String {
        let script = """
        tell application "Mail"
            set theMessage to item 1 of (selection as list)
            set theReply to reply theMessage with opening window
            tell theReply
                set content to "\(escapeForAppleScript(replyContent))" & content
            end tell
            activate
            return "Reply draft created"
        end tell
        """
        return try await execute(script)
    }
    
    func forwardEmail(recipients: [String], additionalContent: String) async throws -> String {
        var script = """
        tell application "Mail"
            set theMessage to item 1 of (selection as list)
            set theForward to forward theMessage with opening window
            tell theForward
        """
        
        for recipient in recipients {
            script += "\n        make new to recipient with properties {address:\"\(escapeForAppleScript(recipient))\"}"
        }
        
        if !additionalContent.isEmpty {
            script += "\n        set content to \"\(escapeForAppleScript(additionalContent))\" & content"
        }
        
        script += """
        
            end tell
            activate
            return "Forward draft created"
        end tell
        """
        
        return try await execute(script)
    }
    
    // MARK: - Notes
    
    func createNote(title: String, body: String, folderName: String?) async throws -> String {
        let folder = folderName ?? "Notes"
        let script = """
        tell application "Notes"
            tell folder "\(escapeForAppleScript(folder))"
                make new note with properties {name:"\(escapeForAppleScript(title))", body:"\(escapeForAppleScript(body))"}
            end tell
            return "Note created successfully"
        end tell
        """
        return try await execute(script)
    }
    
    func openNote(title: String) async throws -> String {
        let script = """
        tell application "Notes"
            set matchingNotes to (every note whose name contains "\(escapeForAppleScript(title))")
            if (count of matchingNotes) > 0 then
                set theNote to item 1 of matchingNotes
                show theNote
                activate
                return "Note opened"
            else
                return "Note not found"
            end if
        end tell
        """
        return try await execute(script)
    }
    
    func appendNoteContent(title: String, content: String) async throws -> String {
        let script = """
        tell application "Notes"
            set matchingNotes to (every note whose name contains "\(escapeForAppleScript(title))")
            if (count of matchingNotes) > 0 then
                set theNote to item 1 of matchingNotes
                set body of theNote to (body of theNote) & "\(escapeForAppleScript(content))"
                return "Content appended to note"
            else
                return "Note not found"
            end if
        end tell
        """
        return try await execute(script)
    }
    
    // MARK: - Messages
    
    func sendSMS(recipients: [String], message: String) async throws -> String {
        // Note: This uses keyboard simulation as Messages doesn't have great AppleScript support
        let recipientList = recipients.joined(separator: ", ")
        let script = """
        tell application "Messages"
            activate
            delay 0.5
        end tell
        tell application "System Events"
            tell process "Messages"
                keystroke "n" using command down
                delay 0.3
                keystroke "\(escapeForAppleScript(recipientList))"
                delay 0.3
                keystroke tab
                delay 0.2
                keystroke "\(escapeForAppleScript(message))"
            end tell
        end tell
        return "Message composed (press Enter to send)"
        """
        return try await execute(script)
    }
    
    // MARK: - Maps
    
    func mapsOpenLocation(location: String) async throws -> String {
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
        let script = """
        open location "http://maps.apple.com/?q=\(encoded)"
        return "Opened location in Maps"
        """
        return try await execute(script)
    }
    
    func mapsShowDirections(from: String, to: String, mode: String) async throws -> String {
        let fromEncoded = from.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? from
        let toEncoded = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? to
        let dirflg: String
        switch mode.lowercased() {
        case "d", "driving": dirflg = "d"
        case "w", "walking": dirflg = "w"
        case "r", "transit": dirflg = "r"
        default: dirflg = "d"
        }
        
        let script = """
        open location "http://maps.apple.com/?saddr=\(fromEncoded)&daddr=\(toEncoded)&dirflg=\(dirflg)"
        return "Showing directions in Maps"
        """
        return try await execute(script)
    }
    
    // MARK: - Files (Spotlight)
    
    func findFile(query: String) async throws -> String {
        // Use mdfind (Spotlight CLI)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", query]
        
        let stdout = Pipe()
        process.standardOutput = stdout
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        let files = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        if files.isEmpty {
            return "No files found matching '\(query)'"
        }
        
        // Return first match
        let firstFile = files[0]
        
        // Open in Finder
        NSWorkspace.shared.selectFile(firstFile, inFileViewerRootedAtPath: "")
        
        return firstFile
    }
    
    // MARK: - Helpers
    
    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
