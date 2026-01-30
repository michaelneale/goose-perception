import Foundation
import GRDB

struct VoiceSegment: Codable, FetchableRecord, MutablePersistableRecord, Hashable {
    static func == (lhs: VoiceSegment, rhs: VoiceSegment) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var id: Int64?
    var timestamp: Date
    var endTimestamp: Date?
    var transcript: String
    var confidence: Double?
    var collaboratorsExtracted: Bool
    var todosExtracted: Bool
    
    static let databaseTableName = "voice_segments"
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case endTimestamp = "end_timestamp"
        case transcript
        case confidence
        case collaboratorsExtracted = "collaborators_extracted"
        case todosExtracted = "todos_extracted"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        endTimestamp: Date? = nil,
        transcript: String,
        confidence: Double? = nil,
        collaboratorsExtracted: Bool = false,
        todosExtracted: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.transcript = transcript
        self.confidence = confidence
        self.collaboratorsExtracted = collaboratorsExtracted
        self.todosExtracted = todosExtracted
    }
    
    var duration: TimeInterval? {
        guard let end = endTimestamp else { return nil }
        return end.timeIntervalSince(timestamp)
    }
}
