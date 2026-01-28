//
// ActionDSLParser.swift
//
// Parses LLM text output into ActionCommand instances.
//

import Foundation

/// Parses DSL text into executable commands
struct ActionDSLParser {
    
    /// Parse multi-line LLM output into commands
    func parse(_ text: String) -> [ActionCommand] {
        var commands: [ActionCommand] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if line.isEmpty {
                i += 1
                continue
            }
            
            // Handle comments
            if line.hasPrefix("#") {
                commands.append(.comment(text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }
            
            // Check for heredoc syntax (<<END)
            if line.contains("<<END") {
                var heredocContent = ""
                i += 1
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "END" {
                    heredocContent += lines[i] + "\n"
                    i += 1
                }
                // Remove trailing newline
                if heredocContent.hasSuffix("\n") {
                    heredocContent = String(heredocContent.dropLast())
                }
                commands.append(parseLineWithHeredoc(line, content: heredocContent))
                i += 1
                continue
            }
            
            // Parse regular command
            commands.append(parseLine(line))
            i += 1
        }
        
        return commands
    }
    
    // MARK: - Private
    
    private func parseLine(_ line: String) -> ActionCommand {
        let tokens = tokenize(line)
        guard let keyword = tokens.first?.uppercased() else {
            return .unknown(line: line)
        }
        
        let args = Array(tokens.dropFirst())
        
        switch keyword {
        // File operations
        case "MOVE_FILE":
            guard args.count >= 2 else { return .unknown(line: line) }
            return .moveFile(from: args[0], to: args[1])
            
        case "COPY_FILE":
            guard args.count >= 2 else { return .unknown(line: line) }
            return .copyFile(from: args[0], to: args[1])
            
        case "DELETE_FILE":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .deleteFile(path: args[0])
            
        case "CREATE_FOLDER":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .createFolder(path: args[0])
            
        case "OPEN_FILE":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .openFile(path: args[0], withApp: args.count > 1 ? args[1] : nil)
            
        case "REVEAL_IN_FINDER":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .revealInFinder(path: args[0])
            
        // Document creation (single-line)
        case "WRITE_FILE":
            guard args.count >= 2 else { return .unknown(line: line) }
            return .writeFile(path: args[0], content: args.dropFirst().joined(separator: " "))
            
        case "APPEND_FILE":
            guard args.count >= 2 else { return .unknown(line: line) }
            return .appendFile(path: args[0], content: args.dropFirst().joined(separator: " "))
            
        // Communication
        case "SEND_EMAIL":
            guard args.count >= 3 else { return .unknown(line: line) }
            return .sendEmail(to: args[0], subject: args[1], body: args.dropFirst(2).joined(separator: " "))
            
        case "OPEN_URL":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .openURL(url: args[0])
            
        case "COPY_TO_CLIPBOARD":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .copyToClipboard(text: args.joined(separator: " "))
            
        // App control
        case "OPEN_APP":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .openApp(name: args.joined(separator: " "))
            
        case "QUIT_APP":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .quitApp(name: args.joined(separator: " "))
            
        case "ACTIVATE_APP":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .activateApp(name: args.joined(separator: " "))
            
        // Notifications
        case "NOTIFY":
            guard args.count >= 2 else { return .unknown(line: line) }
            let sound = args.count > 2 ? args[2] : nil
            return .notify(title: args[0], message: args[1], sound: sound)
            
        case "SPEAK":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .speak(text: args.joined(separator: " "))
            
        // System
        case "RUN_SHORTCUT":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .runShortcut(name: args[0], input: args.count > 1 ? args.dropFirst().joined(separator: " ") : nil)
            
        case "RUN_SHELL":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .runShell(command: args.joined(separator: " "))
            
        default:
            return .unknown(line: line)
        }
    }
    
    private func parseLineWithHeredoc(_ line: String, content: String) -> ActionCommand {
        let tokens = tokenize(line.replacingOccurrences(of: "<<END", with: "").trimmingCharacters(in: .whitespaces))
        guard let keyword = tokens.first?.uppercased() else {
            return .unknown(line: line)
        }
        
        let args = Array(tokens.dropFirst())
        
        switch keyword {
        case "WRITE_FILE", "WRITE_DOC":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .writeFile(path: args[0], content: content)
            
        case "APPEND_FILE":
            guard args.count >= 1 else { return .unknown(line: line) }
            return .appendFile(path: args[0], content: content)
            
        case "SEND_EMAIL":
            guard args.count >= 2 else { return .unknown(line: line) }
            return .sendEmail(to: args[0], subject: args[1], body: content)
            
        default:
            return .unknown(line: line)
        }
    }
    
    /// Tokenize a line, respecting quoted strings
    private func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var escapeNext = false
        
        for char in line {
            if escapeNext {
                current.append(char)
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            
            if char == " " && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            tokens.append(current)
        }
        
        return tokens
    }
}

// MARK: - Convenience

extension ActionDSLParser {
    /// Parse and filter to only valid commands (no unknowns)
    func parseValid(_ text: String) -> [ActionCommand] {
        parse(text).filter { command in
            if case .unknown = command { return false }
            if case .comment = command { return false }
            return true
        }
    }
    
    /// Check if text contains any valid commands
    func hasValidCommands(_ text: String) -> Bool {
        !parseValid(text).isEmpty
    }
}
