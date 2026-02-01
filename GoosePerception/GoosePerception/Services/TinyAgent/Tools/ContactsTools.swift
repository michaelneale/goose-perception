//
// ContactsTools.swift
//
// TinyAgent tools for Contacts app integration.
//

import Foundation

// MARK: - Get Phone Number

struct GetPhoneNumberTool: TinyAgentTool {
    let name = TinyAgentToolName.getPhoneNumber
    
    var promptDescription: String {
        """
        get_phone_number(name: str) -> str
         - Search for a contact by name.
         - Returns the phone number of the contact.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let name = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("get_phone_number requires a name argument")
        }
        
        return try await AppleScriptBridge.shared.getPhoneNumber(name: name)
    }
}

// MARK: - Get Email Address

struct GetEmailAddressTool: TinyAgentTool {
    let name = TinyAgentToolName.getEmailAddress
    
    var promptDescription: String {
        """
        get_email_address(name: str) -> str
         - Search for a contact by name.
         - Returns the email address of the contact.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let name = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("get_email_address requires a name argument")
        }
        
        return try await AppleScriptBridge.shared.getEmailAddress(name: name)
    }
}
