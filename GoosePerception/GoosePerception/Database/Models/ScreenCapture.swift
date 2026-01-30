import Foundation
import GRDB

struct ScreenCapture: Codable, FetchableRecord, MutablePersistableRecord, Hashable {
    static func == (lhs: ScreenCapture, rhs: ScreenCapture) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var id: Int64?
    var timestamp: Date
    var focusedApp: String?
    var focusedWindow: String?
    var allWindows: String? // JSON array
    var ocrText: String?
    var vlmDescription: String?
    var processed: Bool
    var collaboratorsExtracted: Bool
    var projectsExtracted: Bool
    var interestsExtracted: Bool
    var todosExtracted: Bool
    
    static let databaseTableName = "screen_captures"
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case focusedApp = "focused_app"
        case focusedWindow = "focused_window"
        case allWindows = "all_windows"
        case ocrText = "ocr_text"
        case vlmDescription = "vlm_description"
        case processed
        case collaboratorsExtracted = "collaborators_extracted"
        case projectsExtracted = "projects_extracted"
        case interestsExtracted = "interests_extracted"
        case todosExtracted = "todos_extracted"
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        focusedApp: String? = nil,
        focusedWindow: String? = nil,
        allWindows: String? = nil,
        ocrText: String? = nil,
        vlmDescription: String? = nil,
        processed: Bool = false,
        collaboratorsExtracted: Bool = false,
        projectsExtracted: Bool = false,
        interestsExtracted: Bool = false,
        todosExtracted: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.focusedApp = focusedApp
        self.focusedWindow = focusedWindow
        self.allWindows = allWindows
        self.ocrText = ocrText
        self.vlmDescription = vlmDescription
        self.processed = processed
        self.collaboratorsExtracted = collaboratorsExtracted
        self.projectsExtracted = projectsExtracted
        self.interestsExtracted = interestsExtracted
        self.todosExtracted = todosExtracted
    }
}

// Convenience for setting window info as JSON
extension ScreenCapture {
    struct WindowInfo: Codable {
        let appName: String
        let windowTitle: String
        let isActive: Bool
    }
    
    mutating func setAllWindows(_ windows: [WindowInfo]) {
        if let data = try? JSONEncoder().encode(windows),
           let json = String(data: data, encoding: .utf8) {
            allWindows = json
        }
    }
    
    func getAllWindowsDecoded() -> [WindowInfo] {
        guard let json = allWindows,
              let data = json.data(using: .utf8),
              let windows = try? JSONDecoder().decode([WindowInfo].self, from: data) else {
            return []
        }
        return windows
    }
}
