//
// MailTools.swift
//
// TinyAgent tools for Mail app integration.
//

import Foundation

// MARK: - Compose New Email

struct ComposeNewEmailTool: TinyAgentTool {
    let name = TinyAgentToolName.composeNewEmail
    
    var promptDescription: String {
        """
        compose_new_email(recipients: list[str], cc_recipients: list[str], subject: str, body: str, attachments: list[str]) -> str
         - Compose a new email with the given recipients, subject, and body.
         - cc_recipients is a list of email addresses for CC; use an empty list if not applicable.
         - attachments is a list of file paths; use an empty list if not applicable.
         - Returns the status of the email composition.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 5 else {
            throw AppleScriptError.invalidArguments("compose_new_email requires 5 arguments")
        }
        
        var recipients: [String] = []
        if let recipientList = arguments[0] as? [Any] {
            recipients = recipientList.compactMap { $0 as? String }
        } else if let recipient = arguments[0] as? String {
            recipients = [recipient]
        }
        
        var ccRecipients: [String] = []
        if let ccList = arguments[1] as? [Any] {
            ccRecipients = ccList.compactMap { $0 as? String }
        }
        
        let subject = arguments[2] as? String ?? ""
        let body = arguments[3] as? String ?? ""
        
        var attachments: [String] = []
        if let attachmentList = arguments[4] as? [Any] {
            attachments = attachmentList.compactMap { $0 as? String }
        }
        
        return try await AppleScriptBridge.shared.composeNewEmail(
            recipients: recipients,
            ccRecipients: ccRecipients,
            subject: subject,
            body: body,
            attachments: attachments
        )
    }
}

// MARK: - Reply to Email

struct ReplyToEmailTool: TinyAgentTool {
    let name = TinyAgentToolName.replyToEmail
    
    var promptDescription: String {
        """
        reply_to_email(reply_content: str) -> str
         - Reply to the currently selected email in Mail.
         - reply_content is the text to prepend to the reply.
         - Returns the status of the reply.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let replyContent = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("reply_to_email requires reply_content argument")
        }
        
        return try await AppleScriptBridge.shared.replyToEmail(replyContent: replyContent)
    }
}

// MARK: - Forward Email

struct ForwardEmailTool: TinyAgentTool {
    let name = TinyAgentToolName.forwardEmail
    
    var promptDescription: String {
        """
        forward_email(recipients: list[str], additional_content: str) -> str
         - Forward the currently selected email in Mail to the given recipients.
         - additional_content is optional text to add to the forwarded email.
         - Returns the status of the forward.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 2 else {
            throw AppleScriptError.invalidArguments("forward_email requires recipients and additional_content arguments")
        }
        
        var recipients: [String] = []
        if let recipientList = arguments[0] as? [Any] {
            recipients = recipientList.compactMap { $0 as? String }
        } else if let recipient = arguments[0] as? String {
            recipients = [recipient]
        }
        
        let additionalContent = arguments[1] as? String ?? ""
        
        return try await AppleScriptBridge.shared.forwardEmail(
            recipients: recipients,
            additionalContent: additionalContent
        )
    }
}
