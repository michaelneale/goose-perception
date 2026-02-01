//
// InsightGenerators.swift
//
// Insight generators that observe accumulated knowledge and produce observations
//

import Foundation

// MARK: - Work Summary Generator

struct WorkSummaryGenerator: InsightGenerator {
    let name = "Work Summary"
    let cooldownMinutes: Double = 120
    
    func shouldGenerate(context: GeneratorContext) -> Bool {
        context.captures.count >= 10 && context.projects.count > 0
    }
    
    func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight? {
        guard llm.isLoaded else { return nil }
        
        let projectNames = context.projects.prefix(5).map { $0.name }.joined(separator: ", ")
        let duration = context.workDurationMinutes
        let appCount = context.distinctAppsUsed
        
        let system = """
You summarize user's work session in 1-2 sentences.
Be specific about projects and activities. Be encouraging.
Output only the summary, no formatting.
"""
        
        let prompt = """
Projects worked on: \(projectNames)
Work duration: \(duration) minutes
Apps used: \(appCount)
Current mood: \(context.dominantMood)
"""
        
        let response = try await llm.quickQuery(system: system, prompt: prompt, title: "Work Summary")
        guard !response.isEmpty else { return nil }
        
        return .observation(response.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Pattern Generator

struct PatternGenerator: InsightGenerator {
    let name = "Pattern Detector"
    let cooldownMinutes: Double = 240  // Every 4 hours
    
    func shouldGenerate(context: GeneratorContext) -> Bool {
        // Need enough data to detect patterns
        context.projects.count >= 2 && context.captures.count >= 20
    }
    
    func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight? {
        guard llm.isLoaded else { return nil }
        
        // Analyze project focus patterns
        let topProjects = context.projects
            .sorted { $0.mentionCount > $1.mentionCount }
            .prefix(5)
            .map { "\($0.name) (\($0.mentionCount)x)" }
            .joined(separator: ", ")
        
        let topCollaborators = context.collaborators
            .sorted { $0.mentionCount > $1.mentionCount }
            .prefix(3)
            .map { $0.name }
            .joined(separator: ", ")
        
        let system = """
Observe work patterns and note any interesting observations.
Keep it to 1 sentence. Focus on helpful insights.
Output only the pattern, no formatting.
"""
        
        let prompt = """
Top projects by focus: \(topProjects)
Frequent collaborators: \(topCollaborators.isEmpty ? "none" : topCollaborators)
Time of day: \(context.hour):00
Current mood: \(context.dominantMood)
"""
        
        let response = try await llm.quickQuery(system: system, prompt: prompt, title: "Pattern Detection")
        guard !response.isEmpty else { return nil }
        
        return .pattern(response.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Progress Generator

struct ProgressGenerator: InsightGenerator {
    let name = "Progress Tracker"
    let cooldownMinutes: Double = 60
    
    func shouldGenerate(context: GeneratorContext) -> Bool {
        !context.pendingTodos.isEmpty
    }
    
    func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight? {
        let pendingCount = context.pendingTodos.count
        
        // Simple progress summary without LLM
        let content: String
        if pendingCount == 1 {
            content = "You have 1 pending task: \(context.pendingTodos.first?.description ?? "unknown")"
        } else if pendingCount <= 3 {
            content = "You have \(pendingCount) pending tasks"
        } else {
            content = "You have \(pendingCount) pending tasks - consider prioritizing"
        }
        
        return .observation(content)
    }
}

// MARK: - Collaboration Generator

struct CollaborationGenerator: InsightGenerator {
    let name = "Collaboration Tracker"
    let cooldownMinutes: Double = 180  // Every 3 hours
    
    func shouldGenerate(context: GeneratorContext) -> Bool {
        context.collaborators.count > 0 && context.voiceSegments.count >= 5
    }
    
    func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight? {
        guard llm.isLoaded else { return nil }
        
        let recentCollaborators = context.collaborators
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(3)
            .map { $0.name }
            .joined(separator: ", ")
        
        let voiceMinutes = context.voiceSegments.count * 2  // Rough estimate
        
        let system = """
Summarize collaboration activity in 1 sentence.
Be positive and specific. Output only the summary.
"""
        
        let prompt = """
Recent collaborators: \(recentCollaborators)
Approximate voice activity: \(voiceMinutes) minutes
"""
        
        let response = try await llm.quickQuery(system: system, prompt: prompt, title: "Collaboration")
        guard !response.isEmpty else { return nil }
        
        return .observation(response.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Wellness Insight Generator

struct WellnessInsightGenerator: InsightGenerator {
    let name = "Wellness"
    let cooldownMinutes: Double = 30  // Check frequently but only create insight when warranted
    
    // Stress indicators in voice
    private let stressWords = ["damn", "dammit", "ugh", "frustrated", "annoying", "stupid", 
                               "hate", "angry", "tired", "exhausted", "stressed"]
    
    // Stress emotions from face detection
    private let stressEmotions = ["angry", "frustrated", "stressed", "anxious", "tired", "sad"]
    
    func shouldGenerate(context: GeneratorContext) -> Bool {
        // Always check - the generate() method decides if insight is warranted
        return context.captures.count >= 5
    }
    
    func generate(context: GeneratorContext, llm: LLMService) async throws -> Insight? {
        var reasons: [String] = []
        
        // Check 1: Work duration
        let duration = context.workDurationMinutes
        if duration >= 120 {
            reasons.append("working for \(duration / 60) hours")
        }
        
        // Check 2: Late night
        let hour = context.hour
        if hour >= 22 || hour < 6 {
            let timeStr = hour >= 22 ? "\(hour):00" : "early morning"
            reasons.append("working at \(timeStr)")
        }
        
        // Check 3: Stress from face emotions
        if !context.faceEvents.isEmpty {
            var stressCount = 0
            var totalWithEmotion = 0
            
            for event in context.faceEvents {
                if let emotion = event.emotion?.lowercased() {
                    totalWithEmotion += 1
                    if stressEmotions.contains(where: { emotion.contains($0) }) {
                        stressCount += 1
                    }
                }
            }
            
            if totalWithEmotion > 0 {
                let stressRatio = Double(stressCount) / Double(totalWithEmotion)
                if stressRatio > 0.3 {
                    reasons.append("showing signs of \(context.dominantMood)")
                }
            }
        }
        
        // Check 4: Stress words in voice
        if !context.voiceSegments.isEmpty {
            let allVoiceText = context.voiceSegments.map { $0.transcript.lowercased() }.joined(separator: " ")
            let voiceStressCount = stressWords.filter { allVoiceText.contains($0) }.count
            if voiceStressCount >= 2 {
                reasons.append("expressing frustration")
            }
        }
        
        // Only create insight if we have reasons
        guard !reasons.isEmpty else { return nil }
        
        // Use LLM to create a natural insight message
        guard llm.isLoaded else {
            // Fallback without LLM
            let reasonStr = reasons.joined(separator: ", ")
            return .observation("You've been \(reasonStr). Consider taking a short break.")
        }
        
        let system = """
You create brief, caring wellness observations in 1 sentence.
Be supportive, not preachy. Output only the observation.
"""
        
        let prompt = """
User has been: \(reasons.joined(separator: ", "))
Work duration: \(duration) minutes
Time: \(hour):00
Mood: \(context.dominantMood)
"""
        
        let response = try await llm.quickQuery(system: system, prompt: prompt, title: "Wellness")
        guard !response.isEmpty else { return nil }
        
        return .observation(response.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
