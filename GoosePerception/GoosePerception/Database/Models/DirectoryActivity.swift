//
// DirectoryActivity.swift
//
// Tracks which directories the user works in (1-2 levels below ~/)
//

import Foundation
import GRDB

struct DirectoryActivity: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var path: String              // e.g., ~/Documents/reports
    var displayName: String       // e.g., "reports"
    var firstSeen: Date
    var lastActivity: Date
    var activityCount: Int
    
    static let databaseTableName = "directory_activity"
    
    enum CodingKeys: String, CodingKey {
        case id
        case path
        case displayName = "display_name"
        case firstSeen = "first_seen"
        case lastActivity = "last_activity"
        case activityCount = "activity_count"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        path: String,
        displayName: String,
        firstSeen: Date = Date(),
        lastActivity: Date = Date(),
        activityCount: Int = 1
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.firstSeen = firstSeen
        self.lastActivity = lastActivity
        self.activityCount = activityCount
    }
}
