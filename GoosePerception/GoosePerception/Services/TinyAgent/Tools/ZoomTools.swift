//
// ZoomTools.swift
//
// TinyAgent tools for Zoom meeting creation.
// Note: Requires Zoom API credentials configured.
//

import Foundation

// MARK: - Get Zoom Meeting Link

struct GetZoomMeetingLinkTool: TinyAgentTool {
    let name = TinyAgentToolName.getZoomMeetingLink
    
    var promptDescription: String {
        """
        get_zoom_meeting_link(topic: str, start_time: str, duration_minutes: int, invitees: list[str]) -> str
         - Create a Zoom meeting and return the meeting link.
         - topic is the meeting title.
         - start_time is in format 'YYYY-MM-DD HH:MM:SS'.
         - duration_minutes is the meeting duration (default 60).
         - invitees is a list of email addresses to invite.
         - Returns the Zoom meeting link, or an error if Zoom is not configured.
        """
    }
    
    /// Zoom API credentials (should be loaded from config)
    private var zoomAccessToken: String? {
        // Try to load from UserDefaults or config file
        UserDefaults.standard.string(forKey: "zoomAccessToken")
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 4 else {
            throw AppleScriptError.invalidArguments("get_zoom_meeting_link requires topic, start_time, duration_minutes, and invitees arguments")
        }
        
        guard let topic = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("topic must be a string")
        }
        
        guard let startTimeStr = arguments[1] as? String else {
            throw AppleScriptError.invalidArguments("start_time must be a string")
        }
        
        let durationMinutes: Int
        if let duration = arguments[2] as? Int {
            durationMinutes = duration
        } else if let duration = arguments[2] as? Double {
            durationMinutes = Int(duration)
        } else {
            durationMinutes = 60
        }
        
        var invitees: [String] = []
        if let inviteeList = arguments[3] as? [Any] {
            invitees = inviteeList.compactMap { $0 as? String }
        }
        
        // Check if Zoom is configured
        guard let accessToken = zoomAccessToken, !accessToken.isEmpty else {
            return "Zoom is not configured. Please add your Zoom access token in settings."
        }
        
        // Parse start time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        guard let startDate = dateFormatter.date(from: startTimeStr) else {
            throw AppleScriptError.invalidArguments("Invalid start_time format. Use YYYY-MM-DD HH:MM:SS")
        }
        
        // Convert to ISO8601 for Zoom API
        let isoFormatter = ISO8601DateFormatter()
        let isoStartTime = isoFormatter.string(from: startDate)
        
        // Create Zoom meeting via API
        return try await createZoomMeeting(
            accessToken: accessToken,
            topic: topic,
            startTime: isoStartTime,
            duration: durationMinutes,
            invitees: invitees
        )
    }
    
    private func createZoomMeeting(
        accessToken: String,
        topic: String,
        startTime: String,
        duration: Int,
        invitees: [String]
    ) async throws -> String {
        let url = URL(string: "https://api.zoom.us/v2/users/me/meetings")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "topic": topic,
            "type": 2,  // Scheduled meeting
            "start_time": startTime,
            "duration": duration,
            "timezone": TimeZone.current.identifier,
            "settings": [
                "host_video": true,
                "participant_video": true,
                "join_before_host": true,
                "mute_upon_entry": false,
                "auto_recording": "none"
            ]
        ]
        
        if !invitees.isEmpty {
            body["settings"] = [
                "meeting_invitees": invitees.map { ["email": $0] }
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleScriptError.executionFailed("Invalid response from Zoom API")
        }
        
        if httpResponse.statusCode == 201 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let joinUrl = json["join_url"] as? String {
                return joinUrl
            }
            throw AppleScriptError.executionFailed("Could not parse Zoom response")
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppleScriptError.executionFailed("Zoom API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
    }
}
