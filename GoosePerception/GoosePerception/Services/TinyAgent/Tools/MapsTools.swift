//
// MapsTools.swift
//
// TinyAgent tools for Maps app integration.
//

import Foundation

// MARK: - Open Location

struct MapsOpenLocationTool: TinyAgentTool {
    let name = TinyAgentToolName.mapsOpenLocation
    
    var promptDescription: String {
        """
        maps_open_location(location: str) -> str
         - Open a location in Apple Maps.
         - location is the address or place name to open.
         - Returns the status of the operation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let location = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("maps_open_location requires a location argument")
        }
        
        return try await AppleScriptBridge.shared.mapsOpenLocation(location: location)
    }
}

// MARK: - Show Directions

struct MapsShowDirectionsTool: TinyAgentTool {
    let name = TinyAgentToolName.mapsShowDirections
    
    var promptDescription: String {
        """
        maps_show_directions(source: str, destination: str, mode: str) -> str
         - Show directions from source to destination in Apple Maps.
         - source is the starting address (use empty string for current location).
         - destination is the ending address.
         - mode is 'd' for driving, 'w' for walking, 'r' for transit.
         - Returns the status of the operation.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 3 else {
            throw AppleScriptError.invalidArguments("maps_show_directions requires source, destination, and mode arguments")
        }
        
        let source = arguments[0] as? String ?? ""
        
        guard let destination = arguments[1] as? String else {
            throw AppleScriptError.invalidArguments("destination must be a string")
        }
        
        let mode = arguments[2] as? String ?? "d"
        
        return try await AppleScriptBridge.shared.mapsShowDirections(
            from: source,
            to: destination,
            mode: mode
        )
    }
}
