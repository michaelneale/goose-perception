import Foundation
import GRDB

// MARK: - Mood Summary

struct MoodSummary {
    let dominantMood: String
    let moodCounts: [String: Int]
    let totalEvents: Int
    let hours: Int
    let lastUpdated: Date?
    
    var isEmpty: Bool { totalEvents == 0 }
    
    var moodEmoji: String {
        switch dominantMood.lowercased() {
        case "happy", "joyful": return "😊"
        case "neutral", "calm": return "😐"
        case "focused", "concentrated": return "🧐"
        case "tired", "fatigued": return "😴"
        case "stressed", "anxious": return "😰"
        case "frustrated", "angry": return "😤"
        case "sad": return "😢"
        case "surprised": return "😲"
        default: return "🙂"
        }
    }
    
    var topMoods: [(mood: String, percentage: Int)] {
        guard totalEvents > 0 else { return [] }
        return moodCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (mood: $0.key, percentage: Int(Double($0.value) / Double(totalEvents) * 100)) }
    }
    
    init(from events: [FaceEvent], hours: Int) {
        self.hours = hours
        self.totalEvents = events.count
        self.lastUpdated = events.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        
        var counts: [String: Int] = [:]
        for event in events {
            if let emotion = event.emotion, !emotion.isEmpty {
                counts[emotion, default: 0] += 1
            }
        }
        self.moodCounts = counts
        self.dominantMood = counts.max(by: { $0.value < $1.value })?.key ?? "unknown"
    }
}

// MARK: - Project

struct Project: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var firstSeen: Date
    var lastSeen: Date
    var mentionCount: Int
    
    static let databaseTableName = "projects"
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case mentionCount = "mention_count"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        name: String,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        mentionCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.mentionCount = mentionCount
    }
}

// MARK: - Collaborator

struct Collaborator: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var firstSeen: Date
    var lastSeen: Date
    var mentionCount: Int
    
    static let databaseTableName = "collaborators"
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case mentionCount = "mention_count"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        name: String,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        mentionCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.mentionCount = mentionCount
    }
}

// MARK: - Interest

struct Interest: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var topic: String
    var firstSeen: Date
    var lastSeen: Date
    var engagementCount: Int
    
    static let databaseTableName = "interests"
    
    enum CodingKeys: String, CodingKey {
        case id
        case topic
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case engagementCount = "engagement_count"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        topic: String,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        engagementCount: Int = 1
    ) {
        self.id = id
        self.topic = topic
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.engagementCount = engagementCount
    }
}

// MARK: - Todo

struct Todo: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var description: String
    var source: String?
    var createdAt: Date
    var dueDate: Date?
    var completed: Bool
    var completedAt: Date?
    
    static let databaseTableName = "todos"
    
    enum CodingKeys: String, CodingKey {
        case id
        case description
        case source
        case createdAt = "created_at"
        case dueDate = "due_date"
        case completed
        case completedAt = "completed_at"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        description: String,
        source: String? = nil,
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        completed: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.description = description
        self.source = source
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.completed = completed
        self.completedAt = completedAt
    }
}

extension Todo {
    enum Source: String {
        case screen
        case voice
        case analysis
    }
    
    var sourceType: Source? {
        guard let source = source else { return nil }
        return Source(rawValue: source)
    }
}

// MARK: - Insight

struct Insight: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var type: String
    var content: String
    var createdAt: Date
    var shown: Bool
    var shownAt: Date?
    var dismissed: Bool
    
    static let databaseTableName = "insights"
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case content
        case createdAt = "created_at"
        case shown
        case shownAt = "shown_at"
        case dismissed
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        type: String,
        content: String,
        createdAt: Date = Date(),
        shown: Bool = false,
        shownAt: Date? = nil,
        dismissed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.createdAt = createdAt
        self.shown = shown
        self.shownAt = shownAt
        self.dismissed = dismissed
    }
}

extension Insight {
    enum InsightType: String {
        case pattern
        case observation
        case suggestion
    }
    
    var insightType: InsightType? {
        InsightType(rawValue: type)
    }
    
    static func pattern(_ content: String) -> Insight {
        Insight(type: InsightType.pattern.rawValue, content: content)
    }
    
    static func observation(_ content: String) -> Insight {
        Insight(type: InsightType.observation.rawValue, content: content)
    }
    
    static func suggestion(_ content: String) -> Insight {
        Insight(type: InsightType.suggestion.rawValue, content: content)
    }
}

// MARK: - WorkPattern

struct WorkPattern: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var date: Date
    var sessionStart: Date?
    var sessionEnd: Date?
    var dominantEmotion: String?
    var warningType: String?
    var acknowledged: Bool
    
    static let databaseTableName = "work_patterns"
    
    enum CodingKeys: String, CodingKey {
        case id
        case date
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case dominantEmotion = "dominant_emotion"
        case warningType = "warning_type"
        case acknowledged
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        date: Date = Date(),
        sessionStart: Date? = nil,
        sessionEnd: Date? = nil,
        dominantEmotion: String? = nil,
        warningType: String? = nil,
        acknowledged: Bool = false
    ) {
        self.id = id
        self.date = date
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
        self.dominantEmotion = dominantEmotion
        self.warningType = warningType
        self.acknowledged = acknowledged
    }
}

extension WorkPattern {
    enum WarningType: String {
        case overwork
        case lateNight = "late_night"
        case stress
    }
    
    var warning: WarningType? {
        guard let warningType = warningType else { return nil }
        return WarningType(rawValue: warningType)
    }
    
    var sessionDuration: TimeInterval? {
        guard let start = sessionStart, let end = sessionEnd else { return nil }
        return end.timeIntervalSince(start)
    }
}
