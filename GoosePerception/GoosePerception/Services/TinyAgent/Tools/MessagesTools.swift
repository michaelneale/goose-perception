//
// MessagesTools.swift
//
// TinyAgent tools for Messages app integration (SMS/iMessage).
//

import Foundation

// MARK: - Send SMS

struct SendSMSTool: TinyAgentTool {
    let name = TinyAgentToolName.sendSMS
    
    var promptDescription: String {
        """
        send_sms(recipients: list[str], message: str) -> str
         - Send an SMS to a list of phone numbers.
         - The recipients argument can be a single phone number or a list of phone numbers.
         - Returns the status of the SMS.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 2 else {
            throw AppleScriptError.invalidArguments("send_sms requires recipients and message arguments")
        }
        
        var recipients: [String] = []
        if let recipientList = arguments[0] as? [Any] {
            recipients = recipientList.compactMap { $0 as? String }
        } else if let recipient = arguments[0] as? String {
            recipients = [recipient]
        }
        
        guard let message = arguments[1] as? String else {
            throw AppleScriptError.invalidArguments("message must be a string")
        }
        
        return try await AppleScriptBridge.shared.sendSMS(
            recipients: recipients,
            message: message
        )
    }
}
