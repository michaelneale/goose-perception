import Foundation
import GRDB

struct VoiceSegment: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var timestamp: Date
    var endTimestamp: Date?
    var transcript: String
    var confidence: Double?
    
    static let databaseTableName = "voice_segments"
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case endTimestamp = "end_timestamp"
        case transcript
        case confidence
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        endTimestamp: Date? = nil,
        transcript: String,
        confidence: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.transcript = transcript
        self.confidence = confidence
    }
    
    var duration: TimeInterval? {
        guard let end = endTimestamp else { return nil }
        return end.timeIntervalSince(timestamp)
    }
}
