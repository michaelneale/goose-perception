//
// AppUsage.swift
//
// Tracks which apps the user uses, aggregated from screen captures
//

import Foundation
import GRDB

struct AppUsage: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var appName: String
    var bundleId: String?
    var firstSeen: Date
    var lastUsed: Date
    var useCount: Int
    var totalSeconds: Int         // Estimated: useCount * capture interval (~20s)
    
    static let databaseTableName = "app_usage"
    
    enum CodingKeys: String, CodingKey {
        case id
        case appName = "app_name"
        case bundleId = "bundle_id"
        case firstSeen = "first_seen"
        case lastUsed = "last_used"
        case useCount = "use_count"
        case totalSeconds = "total_seconds"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        appName: String,
        bundleId: String? = nil,
        firstSeen: Date = Date(),
        lastUsed: Date = Date(),
        useCount: Int = 1,
        totalSeconds: Int = 20
    ) {
        self.id = id
        self.appName = appName
        self.bundleId = bundleId
        self.firstSeen = firstSeen
        self.lastUsed = lastUsed
        self.useCount = useCount
        self.totalSeconds = totalSeconds
    }
}

extension AppUsage {
    /// Format total time as human-readable string
    var formattedTotalTime: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}
