//
// Action.swift
//
// Actions are things the system decides to do (popups, notifications, etc.)
// Separate from TODOs which are extracted knowledge from screen text.
//

import Foundation
import GRDB

struct Action: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var type: String              // "popup", "notification"
    var title: String
    var message: String
    var source: String            // Which generator created it
    var priority: Int             // 1-10, higher = more urgent
    var createdAt: Date
    var shownAt: Date?            // When displayed to user
    var dismissedAt: Date?        // If user dismissed
    var completedAt: Date?        // If user marked as done
    var snoozedUntil: Date?       // If snoozed
    
    static let databaseTableName = "actions"
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case message
        case source
        case priority
        case createdAt = "created_at"
        case shownAt = "shown_at"
        case dismissedAt = "dismissed_at"
        case completedAt = "completed_at"
        case snoozedUntil = "snoozed_until"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        type: String,
        title: String,
        message: String,
        source: String,
        priority: Int,
        createdAt: Date = Date(),
        shownAt: Date? = nil,
        dismissedAt: Date? = nil,
        completedAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.source = source
        self.priority = priority
        self.createdAt = createdAt
        self.shownAt = shownAt
        self.dismissedAt = dismissedAt
        self.completedAt = completedAt
        self.snoozedUntil = snoozedUntil
    }
    
    // MARK: - Convenience
    
    /// Action is pending if not dismissed and not completed (shown doesn't matter)
    var isPending: Bool {
        dismissedAt == nil && completedAt == nil && !isSnoozed
    }
    
    var isSnoozed: Bool {
        if let snoozedUntil = snoozedUntil {
            return Date() < snoozedUntil
        }
        return false
    }
    
    var isCompleted: Bool {
        completedAt != nil
    }
    
    var isDismissed: Bool {
        dismissedAt != nil
    }
    
    /// Create a popup action
    static func popup(title: String, message: String, source: String, priority: Int) -> Action {
        Action(type: "popup", title: title, message: message, source: source, priority: priority)
    }
    
    /// Create a notification action
    static func notification(title: String, message: String, source: String, priority: Int) -> Action {
        Action(type: "notification", title: title, message: message, source: source, priority: priority)
    }
}
