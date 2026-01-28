//
// Refiner.swift
//
// Protocol for LLM refiners that extract structured data from context
//

import Foundation

/// Context passed to refiners for analysis
struct RefinerContext {
    let captures: [ScreenCapture]
    let voiceTranscripts: [VoiceSegment]
    let faceEvents: [FaceEvent]
    
    var moodSummary: String {
        guard !faceEvents.isEmpty else { return "No mood data" }
        
        var emotionCounts: [String: Int] = [:]
        for event in faceEvents {
            if let emotion = event.emotion {
                emotionCounts[emotion, default: 0] += 1
            }
        }
        
        guard !emotionCounts.isEmpty else { return "No mood data" }
        
        let sorted = emotionCounts.sorted { $0.value > $1.value }
        let total = emotionCounts.values.reduce(0, +)
        
        if let top = sorted.first {
            let percentage = Int(Double(top.value) / Double(total) * 100)
            let others = sorted.dropFirst().prefix(2).map { $0.key }.joined(separator: ", ")
            if others.isEmpty {
                return "\(top.key) (\(percentage)%)"
            } else {
                return "\(top.key) (\(percentage)%), also: \(others)"
            }
        }
        return "Mixed"
    }
    
    var transcriptSummary: String {
        voiceTranscripts.map { $0.transcript }.joined(separator: " ")
    }
    
    /// Format context for LLM consumption with deduplication
    func formatForLLM() -> String {
        var lines: [String] = []
        
        // Group captures by window key to deduplicate
        var windowData: [String: (count: Int, latestOCR: String?, latestTimestamp: Date)] = [:]
        
        for capture in captures {
            let app = capture.focusedApp ?? "Unknown"
            let window = capture.focusedWindow ?? ""
            let key = "\(app)|\(window)"
            
            if let existing = windowData[key] {
                if capture.timestamp > existing.latestTimestamp {
                    windowData[key] = (existing.count + 1, capture.ocrText, capture.timestamp)
                } else {
                    windowData[key] = (existing.count + 1, existing.latestOCR, existing.latestTimestamp)
                }
            } else {
                windowData[key] = (1, capture.ocrText, capture.timestamp)
            }
        }
        
        // Format deduplicated windows
        lines.append("=== SCREEN ACTIVITY ===")
        let sortedWindows = windowData.sorted { $0.value.latestTimestamp > $1.value.latestTimestamp }
        
        for (key, data) in sortedWindows.prefix(10) {
            let parts = key.split(separator: "|", maxSplits: 1)
            let app = String(parts.first ?? "Unknown")
            let window = parts.count > 1 ? String(parts[1]) : ""
            
            let countStr = data.count > 1 ? " (\(data.count)x focused)" : ""
            lines.append("\n[\(app)] \(window)\(countStr)")
            
            if let ocr = data.latestOCR, !ocr.isEmpty {
                let preview = String(ocr.prefix(400)).replacingOccurrences(of: "\n", with: " ")
                lines.append("Content: \(preview)")
            }
        }
        
        // Voice transcripts
        if !voiceTranscripts.isEmpty {
            lines.append("\n=== SPOKEN WORDS ===")
            let allText = transcriptSummary
            lines.append(String(allText.prefix(500)))
        }
        
        // Mood from face events
        if moodSummary != "No mood data" {
            lines.append("\n=== DETECTED MOOD ===")
            lines.append(moodSummary)
        }
        
        return lines.joined(separator: "\n")
    }
}

/// Protocol for LLM refiners
protocol Refiner {
    associatedtype Output
    
    /// Display name for logging
    var name: String { get }
    
    /// System prompt for the LLM
    var systemPrompt: String { get }
    
    /// Parse the LLM response into structured output
    func parse(response: String) -> Output
    
    /// Store the extracted data to the database
    func store(output: Output, database: Database) async throws
}

// MARK: - JSON Parsing Helpers

func parseJSONStringArray(_ response: String) -> [String] {
    guard let jsonStart = response.firstIndex(of: "["),
          let jsonEnd = response.lastIndex(of: "]") else { return [] }
    
    let jsonString = String(response[jsonStart...jsonEnd])
    guard let data = jsonString.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
    
    return array.filter { !$0.isEmpty }
}

func parseJSONObjectArray(_ response: String) -> [[String: Any]] {
    guard let jsonStart = response.firstIndex(of: "["),
          let jsonEnd = response.lastIndex(of: "]") else { return [] }
    
    let jsonString = String(response[jsonStart...jsonEnd])
    guard let data = jsonString.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    
    return array
}

func parseJSONObject(_ response: String) -> [String: Any]? {
    guard let jsonStart = response.firstIndex(of: "{"),
          let jsonEnd = response.lastIndex(of: "}") else { return nil }
    
    let jsonString = String(response[jsonStart...jsonEnd])
    guard let data = jsonString.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    
    return dict
}
