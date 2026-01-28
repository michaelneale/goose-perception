//
// ActionGenerators.swift
//
// Action generators that read from insights and decide when to take action.
// Actions have a higher bar than insights - need accumulated evidence.
//

import Foundation

// MARK: - Wellness Action Generator

struct WellnessActionGenerator: ActionGenerator {
    let name = "Wellness"
    let cooldownMinutes: Double = 45
    
    func shouldTrigger(context: ActionContext) -> Bool {
        guard !isInCooldown(context: context) else { return false }
        guard !shouldBackOff(context: context) else { return false }
        
        // Need multiple wellness-related insights to trigger action
        let wellnessKeywords = ["break", "stress", "tired", "rest", "hour", "working"]
        let wellnessInsightCount = wellnessKeywords.reduce(0) { count, keyword in
            count + context.insightCount(containing: keyword)
        }
        
        // Trigger if 2+ wellness-related insights
        return wellnessInsightCount >= 2
    }
    
    func generate(context: ActionContext) -> Action? {
        let type = actionType(context: context)
        
        // Find the most recent wellness insight to base message on
        let wellnessInsight = context.insights.first { insight in
            let content = insight.content.lowercased()
            return content.contains("break") || content.contains("stress") || 
                   content.contains("tired") || content.contains("rest") ||
                   content.contains("hour") || content.contains("working")
        }
        
        let message = wellnessInsight?.content ?? "Consider taking a short break."
        let priority = context.isLateNight ? 7 : 5
        
        return Action(
            type: type,
            title: "Wellness Check",
            message: message,
            source: name,
            priority: priority
        )
    }
}

// MARK: - Reminder Action Generator

struct ReminderActionGenerator: ActionGenerator {
    let name = "Reminder"
    let cooldownMinutes: Double = 60
    
    func shouldTrigger(context: ActionContext) -> Bool {
        guard !isInCooldown(context: context) else { return false }
        guard !shouldBackOff(context: context) else { return false }
        
        // Check for old pending TODOs (older than 2 hours)
        let oldTodos = context.pendingTodos.filter {
            Date().timeIntervalSince($0.createdAt) > 3600 * 2
        }
        
        return !oldTodos.isEmpty
    }
    
    func generate(context: ActionContext) -> Action? {
        let oldTodos = context.pendingTodos
            .filter { Date().timeIntervalSince($0.createdAt) > 3600 * 2 }
            .prefix(3)
        
        guard let oldest = oldTodos.first else { return nil }
        
        let message = oldTodos.count == 1
            ? "Don't forget: \(oldest.description)"
            : "You have \(oldTodos.count) pending tasks, including: \(oldest.description)"
        
        // Reminders are less urgent, use notification
        return Action(
            type: "notification",
            title: "Task Reminder",
            message: message,
            source: name,
            priority: 4
        )
    }
}

// MARK: - Focus Action Generator

struct FocusActionGenerator: ActionGenerator {
    let name = "Focus"
    let cooldownMinutes: Double = 45
    
    func shouldTrigger(context: ActionContext) -> Bool {
        guard !isInCooldown(context: context) else { return false }
        guard !shouldBackOff(context: context) else { return false }
        
        // Look for pattern insights mentioning context switching or many apps
        let focusKeywords = ["switch", "apps", "focus", "distract"]
        let focusInsightCount = focusKeywords.reduce(0) { count, keyword in
            count + context.insightCount(containing: keyword)
        }
        
        return focusInsightCount >= 1
    }
    
    func generate(context: ActionContext) -> Action? {
        let type = actionType(context: context)
        
        // Find the focus-related insight
        let focusInsight = context.insights.first { insight in
            let content = insight.content.lowercased()
            return content.contains("switch") || content.contains("apps") ||
                   content.contains("focus") || content.contains("distract")
        }
        
        let message = focusInsight?.content ?? "Consider focusing on your main task."
        
        return Action(
            type: type,
            title: "Focus Suggestion",
            message: message,
            source: name,
            priority: 4
        )
    }
}

// MARK: - Late Night Action Generator

struct LateNightActionGenerator: ActionGenerator {
    let name = "Late Night"
    let cooldownMinutes: Double = 60
    
    func shouldTrigger(context: ActionContext) -> Bool {
        guard !isInCooldown(context: context) else { return false }
        guard !shouldBackOff(context: context) else { return false }
        
        // Only at night + have insights mentioning late/night/rest
        guard context.isLateNight else { return false }
        
        let lateKeywords = ["late", "night", "rest", "sleep", "wrap"]
        let lateInsightCount = lateKeywords.reduce(0) { count, keyword in
            count + context.insightCount(containing: keyword)
        }
        
        // Just need any late-night insight
        return lateInsightCount >= 1
    }
    
    func generate(context: ActionContext) -> Action? {
        let type = actionType(context: context)
        
        let lateInsight = context.insights.first { insight in
            let content = insight.content.lowercased()
            return content.contains("late") || content.contains("night") ||
                   content.contains("rest") || content.contains("wrap")
        }
        
        let message = lateInsight?.content ?? "It's late - consider wrapping up for the night."
        
        let priority: Int
        if context.hour >= 23 || context.hour < 2 {
            priority = 8
        } else {
            priority = 5
        }
        
        return Action(
            type: type,
            title: "Late Night",
            message: message,
            source: name,
            priority: priority
        )
    }
}
