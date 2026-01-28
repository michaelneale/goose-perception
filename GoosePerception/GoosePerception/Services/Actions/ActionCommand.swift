//
// ActionCommand.swift
//
// DSL commands that LLM can output for macOS automation.
//

import Foundation

/// A command that can be executed on macOS
enum ActionCommand: Equatable {
    // MARK: - File Operations
    case moveFile(from: String, to: String)
    case copyFile(from: String, to: String)
    case deleteFile(path: String)
    case createFolder(path: String)
    case openFile(path: String, withApp: String?)
    case revealInFinder(path: String)
    
    // MARK: - Document Creation
    case writeFile(path: String, content: String)
    case appendFile(path: String, content: String)
    
    // MARK: - Communication
    case sendEmail(to: String, subject: String, body: String)
    case openURL(url: String)
    case copyToClipboard(text: String)
    
    // MARK: - App Control
    case openApp(name: String)
    case quitApp(name: String)
    case activateApp(name: String)
    
    // MARK: - Notifications
    case notify(title: String, message: String, sound: String?)
    case speak(text: String)
    
    // MARK: - System
    case runShortcut(name: String, input: String?)
    case runShell(command: String)  // Careful with this one!
    
    // MARK: - Unknown/Comment
    case comment(text: String)
    case unknown(line: String)
    
    // MARK: - Properties
    
    /// Human-readable description of the command
    var description: String {
        switch self {
        case .moveFile(let from, let to):
            return "Move \(shortenPath(from)) → \(shortenPath(to))"
        case .copyFile(let from, let to):
            return "Copy \(shortenPath(from)) → \(shortenPath(to))"
        case .deleteFile(let path):
            return "Delete \(shortenPath(path))"
        case .createFolder(let path):
            return "Create folder \(shortenPath(path))"
        case .openFile(let path, let app):
            if let app = app {
                return "Open \(shortenPath(path)) with \(app)"
            }
            return "Open \(shortenPath(path))"
        case .revealInFinder(let path):
            return "Reveal \(shortenPath(path)) in Finder"
        case .writeFile(let path, _):
            return "Write to \(shortenPath(path))"
        case .appendFile(let path, _):
            return "Append to \(shortenPath(path))"
        case .sendEmail(let to, let subject, _):
            return "Email \(to): \(subject)"
        case .openURL(let url):
            return "Open \(url)"
        case .copyToClipboard(let text):
            return "Copy to clipboard: \(text.prefix(30))..."
        case .openApp(let name):
            return "Open \(name)"
        case .quitApp(let name):
            return "Quit \(name)"
        case .activateApp(let name):
            return "Activate \(name)"
        case .notify(let title, _, _):
            return "Notify: \(title)"
        case .speak(let text):
            return "Speak: \(text.prefix(30))..."
        case .runShortcut(let name, _):
            return "Run shortcut: \(name)"
        case .runShell(let command):
            return "Run: \(command.prefix(30))..."
        case .comment(let text):
            return "# \(text)"
        case .unknown(let line):
            return "Unknown: \(line)"
        }
    }
    
    /// Whether this command is destructive (requires confirmation)
    var isDestructive: Bool {
        switch self {
        case .deleteFile, .moveFile, .runShell:
            return true
        default:
            return false
        }
    }
    
    /// Whether this command modifies files
    var modifiesFiles: Bool {
        switch self {
        case .moveFile, .copyFile, .deleteFile, .createFolder, .writeFile, .appendFile:
            return true
        default:
            return false
        }
    }
    
    /// Whether this command is safe to auto-execute
    var isSafeToAutoExecute: Bool {
        switch self {
        case .notify, .speak, .copyToClipboard, .openURL, .openFile, .revealInFinder, .openApp, .activateApp, .comment:
            return true
        default:
            return false
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.replacingOccurrences(of: home, with: "~")
    }
}

// MARK: - Command Keywords

extension ActionCommand {
    /// All recognized command keywords
    static let keywords: Set<String> = [
        "MOVE_FILE", "COPY_FILE", "DELETE_FILE", "CREATE_FOLDER",
        "OPEN_FILE", "REVEAL_IN_FINDER",
        "WRITE_FILE", "WRITE_DOC", "APPEND_FILE",
        "SEND_EMAIL", "OPEN_URL", "COPY_TO_CLIPBOARD",
        "OPEN_APP", "QUIT_APP", "ACTIVATE_APP",
        "NOTIFY", "SPEAK",
        "RUN_SHORTCUT", "RUN_SHELL"
    ]
}
