import Foundation
import GRDB

struct FaceEvent: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var timestamp: Date
    var userHash: String?
    var present: Bool
    var emotion: String?
    var confidence: Double?
    
    static let databaseTableName = "face_events"
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case userHash = "user_hash"
        case present
        case emotion
        case confidence
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        userHash: String? = nil,
        present: Bool,
        emotion: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userHash = userHash
        self.present = present
        self.emotion = emotion
        self.confidence = confidence
    }
}

// Emotion types
extension FaceEvent {
    enum Emotion: String, CaseIterable {
        case happy
        case content
        case sad
        case surprised
        case angry
        case tired
        case serious
        case neutral
        
        var emoji: String {
            switch self {
            case .happy: return "😊"
            case .content: return "🙂"
            case .sad: return "😢"
            case .surprised: return "😮"
            case .angry: return "😠"
            case .tired: return "😴"
            case .serious: return "😐"
            case .neutral: return "😶"
            }
        }
    }
    
    var emotionType: Emotion? {
        guard let emotion = emotion else { return nil }
        return Emotion(rawValue: emotion)
    }
}
