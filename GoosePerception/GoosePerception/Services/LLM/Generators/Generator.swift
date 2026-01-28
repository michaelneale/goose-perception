//
// Generator.swift
//
// Protocols for Insight and Action generators
//

import Foundation

/// Context passed to generators - includes accumulated knowledge and recent activity
struct GeneratorContext {
    let projects: [Project]
    let collaborators: [Collaborator]
    let interests: [Interest]
    let pendingTodos: [Todo]
    let recentInsights: [Insight]
    let faceEvents: [FaceEvent]
    let captures: [ScreenCapture]
    let voiceSegments: [VoiceSegment]
    
    var moodSummary: String {
        guard !faceEvents.isEmpty else { return "unknown" }
        
        var emotionCounts: [String: Int] = [:]
        for event in faceEvents {
            if let emotion = event.emotion {
                emotionCounts[emotion, default: 0] += 1
            }
        }
        
        guard !emotionCounts.isEmpty else { return "unknown" }
        
        let sorted = emotionCounts.sorted { $0.value > $1.value }
        return sorted.first?.key ?? "unknown"
    }
    
    var dominantMood: String {
        moodSummary
    }
    
    var isStressed: Bool {
        let stressMoods = ["stressed", "frustrated", "angry", "anxious", "tired"]
        return stressMoods.contains(where: { moodSummary.lowercased().contains($0) })
    }
    
    var workDurationMinutes: Int {
        guard let first = captures.min(by: { $0.timestamp < $1.timestamp }),
              let last = captures.max(by: { $0.timestamp < $1.timestamp }) else {
            return 0
        }
        return Int(last.timestamp.timeIntervalSince(first.timestamp) / 60)
    }
    
    var distinctAppsUsed: Int {
        Set(captures.compactMap { $0.focusedApp }).count
    }
    
    var hour: Int {
        Calendar.current.component(.hour, from: Date())
    }
    
    var isLateNight: Bool {
        hour >= 22 || hour < 6
    }
}

// MARK: - Insight Generator Protocol

protocol InsightGenerator {
    var name: String { get }
    var cooldownMinutes: Double { get }
    
    func shouldGenerate(context: GeneratorContext) -> Bool
    @MainActor func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight?
}

extension InsightGenerator {
    var cooldownMinutes: Double { 60 }
}

// MARK: - Action Generator Protocol

/// Context for action generators - reads from accumulated insights and knowledge
struct ActionContext {
    let insights: [Insight]              // Recent insights from DB
    let recentActions: [Action]          // Recent actions (for cooldown/backoff)
    let recentDismissed: [Action]        // Recently dismissed (for backoff)
    let pendingTodos: [Todo]             // TODOs from knowledge
    let currentMood: String?             // Latest mood from face detection
    let workDurationMinutes: Int
    let hour: Int
    
    /// Count insights containing a keyword (case insensitive)
    func insightCount(containing keyword: String) -> Int {
        insights.filter { $0.content.lowercased().contains(keyword.lowercased()) }.count
    }
    
    /// Check if mood is OK for popup (not stressed/frustrated)
    var isMoodOKForPopup: Bool {
        guard let mood = currentMood?.lowercased() else { return true }
        let badMoods = ["stressed", "frustrated", "angry", "anxious"]
        return !badMoods.contains(where: { mood.contains($0) })
    }
    
    /// Check if we've shown a popup recently (within 20 min)
    var hasRecentPopup: Bool {
        recentActions.contains { action in
            guard action.type == "popup", let shown = action.shownAt else { return false }
            return Date().timeIntervalSince(shown) < 20 * 60
        }
    }
    
    /// Count recent dismissals (for backoff)
    var recentDismissalCount: Int {
        recentDismissed.count
    }
    
    var isLateNight: Bool {
        hour >= 22 || hour < 6
    }
}

protocol ActionGenerator {
    var name: String { get }
    var cooldownMinutes: Double { get }
    
    func shouldTrigger(context: ActionContext) -> Bool
    func generate(context: ActionContext) -> Action?
}

extension ActionGenerator {
    var cooldownMinutes: Double { 30 }
    
    /// Check if this generator is in cooldown based on recent actions
    func isInCooldown(context: ActionContext) -> Bool {
        let myActions = context.recentActions.filter { $0.source == name }
        guard let last = myActions.first else { return false }
        let minutesSince = Date().timeIntervalSince(last.createdAt) / 60
        return minutesSince < cooldownMinutes
    }
    
    /// Determine action type: popup if mood OK and no recent popup, else notification
    func actionType(context: ActionContext) -> String {
        if context.isMoodOKForPopup && !context.hasRecentPopup {
            return "popup"
        }
        return "notification"
    }
    
    /// Should back off due to repeated dismissals?
    func shouldBackOff(context: ActionContext) -> Bool {
        // If user dismissed 3+ actions recently, back off
        context.recentDismissalCount >= 3
    }
}
