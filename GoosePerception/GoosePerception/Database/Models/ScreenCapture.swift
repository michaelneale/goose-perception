import Foundation
import GRDB

struct ScreenCapture: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var timestamp: Date
    var focusedApp: String?
    var focusedWindow: String?
    var allWindows: String? // JSON array
    var ocrText: String?
    var vlmDescription: String?
    var processed: Bool
    
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
        processed: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.focusedApp = focusedApp
        self.focusedWindow = focusedWindow
        self.allWindows = allWindows
        self.ocrText = ocrText
        self.vlmDescription = vlmDescription
        self.processed = processed
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
