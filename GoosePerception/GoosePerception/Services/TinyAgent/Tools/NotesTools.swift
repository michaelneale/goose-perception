//
// NotesTools.swift
//
// TinyAgent tools for Notes app integration.
//

import Foundation

// MARK: - Create Note

struct CreateNoteTool: TinyAgentTool {
    let name = TinyAgentToolName.createNote
    
    var promptDescription: String {
        """
        create_note(title: str, body: str, folder_name: str) -> str
         - Create a new note in the Notes app.
         - title is the name of the note.
         - body is the content of the note.
         - folder_name is the folder to create the note in; use None for the default folder.
         - Returns the status of the note creation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 2,
              let title = arguments[0] as? String,
              let body = arguments[1] as? String else {
            throw AppleScriptError.invalidArguments("create_note requires title and body arguments")
        }
        
        let folderName: String? = arguments.count >= 3 ? arguments[2] as? String : nil
        
        return try await AppleScriptBridge.shared.createNote(
            title: title,
            body: body,
            folderName: folderName
        )
    }
}

// MARK: - Open Note

struct OpenNoteTool: TinyAgentTool {
    let name = TinyAgentToolName.openNote
    
    var promptDescription: String {
        """
        open_note(title: str) -> str
         - Open a note by its title.
         - Returns the status of opening the note.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let title = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("open_note requires a title argument")
        }
        
        return try await AppleScriptBridge.shared.openNote(title: title)
    }
}

// MARK: - Append Note Content

struct AppendNoteContentTool: TinyAgentTool {
    let name = TinyAgentToolName.appendNoteContent
    
    var promptDescription: String {
        """
        append_note_content(title: str, content: str) -> str
         - Append content to an existing note.
         - title is the name of the note to append to.
         - content is the text to append.
         - Returns the status of the operation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 2,
              let title = arguments[0] as? String,
              let content = arguments[1] as? String else {
            throw AppleScriptError.invalidArguments("append_note_content requires title and content arguments")
        }
        
        return try await AppleScriptBridge.shared.appendNoteContent(
            title: title,
            content: content
        )
    }
}
