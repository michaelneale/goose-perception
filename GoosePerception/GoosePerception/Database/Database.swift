import Foundation
import GRDB

/// Types of refiners that can process captures
enum RefinerType: String, CaseIterable {
    case collaborators
    case projects
    case interests
    case todos
    
    var columnName: String {
        switch self {
        case .collaborators: return "collaborators_extracted"
        case .projects: return "projects_extracted"
        case .interests: return "interests_extracted"
        case .todos: return "todos_extracted"
        }
    }
}

/// Main database manager for Goose Perception
actor Database {
    static let shared: Database = {
        do {
            return try Database()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()
    
    private let dbQueue: DatabaseQueue
    
    private init() throws {
        // Create app support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("GoosePerception", isDirectory: true)
        
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        let dbPath = appDirectory.appendingPathComponent("perception.sqlite")
        
        // Configure database
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        
        dbQueue = try DatabaseQueue(path: dbPath.path, configuration: config)
        
        // Run migrations
        try Self.createMigrator().migrate(dbQueue)
    }
    
    private static func createMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // MARK: - Migration v1: Initial Schema
        migrator.registerMigration("v1_initial") { db in
            // Screen captures table
            try db.create(table: "screen_captures") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("focused_app", .text)
                t.column("focused_window", .text)
                t.column("all_windows", .text) // JSON array
                t.column("ocr_text", .text)
                t.column("vlm_description", .text)
                t.column("processed", .integer).notNull().defaults(to: 0)
            }
            
            // Voice segments table
            try db.create(table: "voice_segments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("end_timestamp", .datetime)
                t.column("transcript", .text).notNull()
                t.column("confidence", .double)
            }
            
            // Face events table
            try db.create(table: "face_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("user_hash", .text)
                t.column("present", .integer).notNull()
                t.column("emotion", .text)
                t.column("confidence", .double)
            }
            
            // Work patterns table
            try db.create(table: "work_patterns") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull().indexed()
                t.column("session_start", .datetime)
                t.column("session_end", .datetime)
                t.column("dominant_emotion", .text)
                t.column("warning_type", .text) // 'overwork', 'late_night', 'stress'
                t.column("acknowledged", .integer).notNull().defaults(to: 0)
            }
            
            // Projects table
            try db.create(table: "projects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("mention_count", .integer).notNull().defaults(to: 1)
            }
            
            // Collaborators table
            try db.create(table: "collaborators") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("context", .text)
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("mention_count", .integer).notNull().defaults(to: 1)
            }
            
            // Interests table
            try db.create(table: "interests") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("topic", .text).notNull().unique()
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("engagement_count", .integer).notNull().defaults(to: 1)
            }
            
            // TODOs table
            try db.create(table: "todos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("description", .text).notNull()
                t.column("source", .text) // 'screen', 'voice', 'analysis'
                t.column("created_at", .datetime).notNull()
                t.column("due_date", .datetime)
                t.column("completed", .integer).notNull().defaults(to: 0)
                t.column("completed_at", .datetime)
            }
            
            // Insights table
            try db.create(table: "insights") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull() // 'pattern', 'observation', 'suggestion'
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("shown", .integer).notNull().defaults(to: 0)
                t.column("shown_at", .datetime)
                t.column("dismissed", .integer).notNull().defaults(to: 0)
            }
        }
        
        // MARK: - Migration v2: Activity Tracking
        migrator.registerMigration("v2_activity_tracking") { db in
            // Directory activity table - tracks which folders user works in
            try db.create(table: "directory_activity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("display_name", .text).notNull()
                t.column("first_seen", .datetime).notNull()
                t.column("last_activity", .datetime).notNull()
                t.column("activity_count", .integer).notNull().defaults(to: 1)
            }
            
            // App usage table - tracks which apps user uses
            try db.create(table: "app_usage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("app_name", .text).notNull().unique()
                t.column("bundle_id", .text)
                t.column("first_seen", .datetime).notNull()
                t.column("last_used", .datetime).notNull()
                t.column("use_count", .integer).notNull().defaults(to: 1)
                t.column("total_seconds", .integer).notNull().defaults(to: 0)
            }
        }
        
        // MARK: - Migration v3: Actions table
        migrator.registerMigration("v3_actions") { db in
            // Actions table - things the system decides to do (separate from TODOs)
            try db.create(table: "actions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()           // "popup", "notification"
                t.column("title", .text).notNull()
                t.column("message", .text).notNull()
                t.column("source", .text).notNull()         // which generator created it
                t.column("priority", .integer).notNull()    // 1-10
                t.column("created_at", .datetime).notNull()
                t.column("shown_at", .datetime)             // when displayed
                t.column("dismissed_at", .datetime)         // if dismissed
                t.column("completed_at", .datetime)         // if marked done
                t.column("snoozed_until", .datetime)        // if snoozed
            }
            
            try db.create(index: "actions_created_at", on: "actions", columns: ["created_at"])
            try db.create(index: "actions_source", on: "actions", columns: ["source"])
        }
        
        // MARK: - Migration v4: Per-refiner processing flags
        migrator.registerMigration("v4_refiner_flags") { db in
            // Add columns to track which refiners have processed each capture
            try db.alter(table: "screen_captures") { t in
                t.add(column: "collaborators_extracted", .integer).notNull().defaults(to: 0)
            }
            // Mark all existing processed captures as also having collaborators extracted
            try db.execute(sql: "UPDATE screen_captures SET collaborators_extracted = processed")
        }
        
        // MARK: - Migration v5: Additional refiner flags
        migrator.registerMigration("v5_all_refiner_flags") { db in
            // Add flags for all refiner types
            try db.alter(table: "screen_captures") { t in
                t.add(column: "projects_extracted", .integer).notNull().defaults(to: 0)
                t.add(column: "interests_extracted", .integer).notNull().defaults(to: 0)
                t.add(column: "todos_extracted", .integer).notNull().defaults(to: 0)
            }
            // Mark all existing processed captures as extracted
            try db.execute(sql: "UPDATE screen_captures SET projects_extracted = processed, interests_extracted = processed, todos_extracted = processed")
            
            // Add flags for voice segments too
            try db.alter(table: "voice_segments") { t in
                t.add(column: "collaborators_extracted", .integer).notNull().defaults(to: 0)
                t.add(column: "todos_extracted", .integer).notNull().defaults(to: 0)
            }
        }
        
        return migrator
    }
    
    // MARK: - Screen Captures
    
    func insertScreenCapture(_ capture: ScreenCapture) async throws -> Int64 {
        try await dbQueue.write { db in
            var capture = capture
            try capture.insert(db)
            return capture.id!
        }
    }
    
    func getUnprocessedCaptures(limit: Int = 50) async throws -> [ScreenCapture] {
        try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column("processed") == 0)
                .order(Column("timestamp"))
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    func markCaptureProcessed(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE screen_captures SET processed = 1 WHERE id = ?", arguments: [id])
        }
    }
    
    // MARK: - Per-Refiner Capture Queries
    
    /// Get captures that haven't had a specific refiner run yet
    func getCapturesForRefiner(_ refinerType: RefinerType, limit: Int = 100) async throws -> [ScreenCapture] {
        try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column(refinerType.columnName) == 0)
                .filter(Column("ocr_text") != nil)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Mark captures as having had a specific refiner run
    func markCapturesRefined(ids: [Int64], refinerType: RefinerType) async throws {
        guard !ids.isEmpty else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE screen_captures SET \(refinerType.columnName) = 1 WHERE id IN (\(ids.map { String($0) }.joined(separator: ",")))"
            )
        }
    }
    
    /// Get voice segments that haven't had a specific refiner run yet
    func getVoiceSegmentsForRefiner(_ refinerType: RefinerType, limit: Int = 100) async throws -> [VoiceSegment] {
        guard refinerType == .collaborators || refinerType == .todos else { return [] }
        return try await dbQueue.read { db in
            try VoiceSegment
                .filter(Column(refinerType.columnName) == 0)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Get voice segments within a time range (for temporal correlation with captures)
    func getVoiceSegmentsInTimeRange(start: Date, end: Date, buffer: TimeInterval = 300) async throws -> [VoiceSegment] {
        let bufferedStart = start.addingTimeInterval(-buffer)
        let bufferedEnd = end.addingTimeInterval(buffer)
        return try await dbQueue.read { db in
            try VoiceSegment
                .filter(Column("timestamp") >= bufferedStart && Column("timestamp") <= bufferedEnd)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }
    
    /// Mark voice segments as having had a specific refiner run
    func markVoiceSegmentsRefined(ids: [Int64], refinerType: RefinerType) async throws {
        guard !ids.isEmpty else { return }
        guard refinerType == .collaborators || refinerType == .todos else { return }
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE voice_segments SET \(refinerType.columnName) = 1 WHERE id IN (\(ids.map { String($0) }.joined(separator: ",")))"
            )
        }
    }
    
    /// Get captures that haven't been fully refined by all refiners (any flag is 0)
    func getUnrefinedCaptures(limit: Int = 50) async throws -> [ScreenCapture] {
        try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column("ocr_text") != nil)
                .filter(
                    Column("projects_extracted") == 0 ||
                    Column("collaborators_extracted") == 0 ||
                    Column("interests_extracted") == 0 ||
                    Column("todos_extracted") == 0
                )
                .order(Column("timestamp").asc)  // Oldest first
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Mark a single capture as fully refined by all refiners
    func markCaptureFullyRefined(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE screen_captures 
                    SET projects_extracted = 1, collaborators_extracted = 1, 
                        interests_extracted = 1, todos_extracted = 1, processed = 1
                    WHERE id = ?
                    """,
                arguments: [id]
            )
        }
    }
    
    // Legacy convenience methods
    func getCapturesForCollaboratorExtraction(limit: Int = 100) async throws -> [ScreenCapture] {
        try await getCapturesForRefiner(.collaborators, limit: limit)
    }
    
    func markCollaboratorsExtracted(ids: [Int64]) async throws {
        try await markCapturesRefined(ids: ids, refinerType: .collaborators)
    }
    
    func updateCaptureOCR(id: Int64, ocrText: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE screen_captures SET ocr_text = ? WHERE id = ?",
                arguments: [ocrText, id]
            )
        }
    }
    
    func updateCaptureVLM(id: Int64, vlmDescription: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE screen_captures SET vlm_description = ? WHERE id = ?",
                arguments: [vlmDescription, id]
            )
        }
    }
    
    func getRecentCaptures(hours: Int = 24) async throws -> [ScreenCapture] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column("timestamp") >= cutoff)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }
    
    func getTodaysCaptureCount() async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column("timestamp") >= startOfDay)
                .fetchCount(db)
        }
    }
    
    func getUnprocessedCaptureCount() async throws -> Int {
        try await dbQueue.read { db in
            try ScreenCapture
                .filter(Column("processed") == 0)
                .fetchCount(db)
        }
    }
    
    func getAllInsights() async throws -> [Insight] {
        try await dbQueue.read { db in
            try Insight
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func getAllTodos() async throws -> [Todo] {
        try await dbQueue.read { db in
            try Todo
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Voice Segments
    
    func insertVoiceSegment(_ segment: VoiceSegment) async throws -> Int64 {
        try await dbQueue.write { db in
            var segment = segment
            try segment.insert(db)
            return segment.id!
        }
    }
    
    func getRecentVoiceSegments(since: Date) async throws -> [VoiceSegment] {
        try await dbQueue.read { db in
            try VoiceSegment
                .filter(Column("timestamp") >= since)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Face Events
    
    func insertFaceEvent(_ event: FaceEvent) async throws -> Int64 {
        try await dbQueue.write { db in
            var event = event
            try event.insert(db)
            return event.id!
        }
    }
    
    func getLatestFaceEvent() async throws -> FaceEvent? {
        try await dbQueue.read { db in
            try FaceEvent
                .order(Column("timestamp").desc)
                .fetchOne(db)
        }
    }
    
    func getRecentFaceEvents(since: Date) async throws -> [FaceEvent] {
        try await dbQueue.read { db in
            try FaceEvent
                .filter(Column("timestamp") >= since)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }
    
    /// Get mood summary for the last N hours
    func getMoodSummary(hours: Int = 2) async throws -> MoodSummary {
        let since = Date().addingTimeInterval(-Double(hours * 3600))
        let events = try await getRecentFaceEvents(since: since)
        return MoodSummary(from: events, hours: hours)
    }
    
    // MARK: - Projects
    
    func upsertProject(name: String) async throws {
        let now = Date()
        try await dbQueue.write { db in
            if var existing = try Project.filter(Column("name") == name).fetchOne(db) {
                existing.lastSeen = now
                existing.mentionCount += 1
                try existing.update(db)
            } else {
                var project = Project(
                    name: name,
                    firstSeen: now,
                    lastSeen: now,
                    mentionCount: 1
                )
                try project.insert(db)
            }
        }
    }
    
    func getAllProjects() async throws -> [Project] {
        try await dbQueue.read { db in
            try Project.order(Column("last_seen").desc).fetchAll(db)
        }
    }
    
    // MARK: - Collaborators
    
    func upsertCollaborator(name: String) async throws {
        let now = Date()
        try await dbQueue.write { db in
            if var existing = try Collaborator.filter(Column("name") == name).fetchOne(db) {
                existing.lastSeen = now
                existing.mentionCount += 1
                try existing.update(db)
            } else {
                var collaborator = Collaborator(
                    name: name,
                    firstSeen: now,
                    lastSeen: now,
                    mentionCount: 1
                )
                try collaborator.insert(db)
            }
        }
    }
    
    func getAllCollaborators() async throws -> [Collaborator] {
        try await dbQueue.read { db in
            try Collaborator.order(Column("last_seen").desc).fetchAll(db)
        }
    }
    
    // MARK: - Interests
    
    func upsertInterest(topic: String) async throws {
        let now = Date()
        try await dbQueue.write { db in
            if var existing = try Interest.filter(Column("topic") == topic).fetchOne(db) {
                existing.lastSeen = now
                existing.engagementCount += 1
                try existing.update(db)
            } else {
                var interest = Interest(
                    topic: topic,
                    firstSeen: now,
                    lastSeen: now,
                    engagementCount: 1
                )
                try interest.insert(db)
            }
        }
    }
    
    func getAllInterests() async throws -> [Interest] {
        try await dbQueue.read { db in
            try Interest.order(Column("engagement_count").desc).fetchAll(db)
        }
    }
    
    // MARK: - TODOs
    
    func insertTodo(_ todo: Todo) async throws -> Int64 {
        try await dbQueue.write { db in
            var todo = todo
            try todo.insert(db)
            return todo.id!
        }
    }
    
    func getPendingTodos() async throws -> [Todo] {
        try await dbQueue.read { db in
            try Todo
                .filter(Column("completed") == 0)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func markTodoCompleted(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE todos SET completed = 1, completed_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    func updateTodoCompletion(id: Int64, completed: Bool) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE todos SET completed = ?, completed_at = ? WHERE id = ?",
                arguments: [completed ? 1 : 0, completed ? Date() : nil, id]
            )
        }
    }
    
    // MARK: - Insights
    
    func insertInsight(_ insight: Insight) async throws -> Int64 {
        try await dbQueue.write { db in
            var insight = insight
            try insight.insert(db)
            return insight.id!
        }
    }
    
    func getUnshownInsights() async throws -> [Insight] {
        try await dbQueue.read { db in
            try Insight
                .filter(Column("shown") == 0)
                .filter(Column("dismissed") == 0)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func markInsightShown(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE insights SET shown = 1, shown_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    func dismissInsight(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE insights SET dismissed = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }
    
    func getRecentInsights(hours: Int = 24) async throws -> [Insight] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try Insight
                .filter(Column("created_at") >= cutoff)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func getTodaysInsightCount() async throws -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return try await dbQueue.read { db in
            try Insight
                .filter(Column("created_at") >= startOfDay)
                .fetchCount(db)
        }
    }
    
    // MARK: - Directory Activity
    
    func upsertDirectoryActivity(path: String, displayName: String) async throws {
        let now = Date()
        try await dbQueue.write { db in
            if var existing = try DirectoryActivity.filter(Column("path") == path).fetchOne(db) {
                existing.lastActivity = now
                existing.activityCount += 1
                try existing.update(db)
            } else {
                var activity = DirectoryActivity(
                    path: path,
                    displayName: displayName,
                    firstSeen: now,
                    lastActivity: now,
                    activityCount: 1
                )
                try activity.insert(db)
            }
        }
    }
    
    func getAllDirectoryActivity() async throws -> [DirectoryActivity] {
        try await dbQueue.read { db in
            try DirectoryActivity.order(Column("last_activity").desc).fetchAll(db)
        }
    }
    
    func getRecentDirectoryActivity(hours: Int = 24) async throws -> [DirectoryActivity] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try DirectoryActivity
                .filter(Column("last_activity") >= cutoff)
                .order(Column("activity_count").desc)
                .fetchAll(db)
        }
    }
    
    // MARK: - App Usage
    
    func upsertAppUsage(appName: String, bundleId: String? = nil) async throws {
        let now = Date()
        try await dbQueue.write { db in
            if var existing = try AppUsage.filter(Column("app_name") == appName).fetchOne(db) {
                existing.lastUsed = now
                existing.useCount += 1
                existing.totalSeconds += 20  // Each capture is ~20s
                try existing.update(db)
            } else {
                var usage = AppUsage(
                    appName: appName,
                    bundleId: bundleId,
                    firstSeen: now,
                    lastUsed: now,
                    useCount: 1,
                    totalSeconds: 20
                )
                try usage.insert(db)
            }
        }
    }
    
    func getAllAppUsage() async throws -> [AppUsage] {
        try await dbQueue.read { db in
            try AppUsage.order(Column("use_count").desc).fetchAll(db)
        }
    }
    
    func getRecentAppUsage(hours: Int = 24) async throws -> [AppUsage] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try AppUsage
                .filter(Column("last_used") >= cutoff)
                .order(Column("use_count").desc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Actions
    
    func insertAction(_ action: Action) async throws -> Int64 {
        try await dbQueue.write { db in
            var action = action
            try action.insert(db)
            return action.id!
        }
    }
    
    func getAllActions() async throws -> [Action] {
        try await dbQueue.read { db in
            try Action.order(Column("created_at").desc).fetchAll(db)
        }
    }
    
    func getPendingActions() async throws -> [Action] {
        let now = Date()
        return try await dbQueue.read { db in
            try Action
                .filter(Column("shown_at") == nil)
                .filter(Column("dismissed_at") == nil)
                .filter(Column("completed_at") == nil)
                .filter(Column("snoozed_until") == nil || Column("snoozed_until") <= now)
                .order(Column("priority").desc, Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func getRecentActions(hours: Int = 24) async throws -> [Action] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try Action
                .filter(Column("created_at") >= cutoff)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func getRecentActionsBySource(source: String, hours: Int = 24) async throws -> [Action] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try Action
                .filter(Column("source") == source)
                .filter(Column("created_at") >= cutoff)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
    
    func getRecentShownActions(minutes: Int = 20) async throws -> [Action] {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return try await dbQueue.read { db in
            try Action
                .filter(Column("shown_at") != nil)
                .filter(Column("shown_at") >= cutoff)
                .order(Column("shown_at").desc)
                .fetchAll(db)
        }
    }
    
    func getRecentDismissedActions(hours: Int = 2) async throws -> [Action] {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return try await dbQueue.read { db in
            try Action
                .filter(Column("dismissed_at") != nil)
                .filter(Column("dismissed_at") >= cutoff)
                .fetchAll(db)
        }
    }
    
    func markActionShown(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE actions SET shown_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    func markActionDismissed(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE actions SET dismissed_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    func markActionCompleted(id: Int64) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE actions SET completed_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    func snoozeAction(id: Int64, until: Date) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE actions SET snoozed_until = ? WHERE id = ?",
                arguments: [until, id]
            )
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupOldData(retentionDays: Int) async throws {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays * 24 * 3600))
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM screen_captures WHERE timestamp < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM voice_segments WHERE timestamp < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM face_events WHERE timestamp < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM insights WHERE created_at < ? AND dismissed = 1", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM actions WHERE created_at < ?", arguments: [cutoff])
        }
    }
    
    /// Clear all data from all tables - complete reset
    func clearAllData() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM screen_captures")
            try db.execute(sql: "DELETE FROM voice_segments")
            try db.execute(sql: "DELETE FROM face_events")
            try db.execute(sql: "DELETE FROM work_patterns")
            try db.execute(sql: "DELETE FROM projects")
            try db.execute(sql: "DELETE FROM collaborators")
            try db.execute(sql: "DELETE FROM interests")
            try db.execute(sql: "DELETE FROM todos")
            try db.execute(sql: "DELETE FROM insights")
            try db.execute(sql: "DELETE FROM actions")
            try db.execute(sql: "DELETE FROM directory_activity")
            try db.execute(sql: "DELETE FROM app_usage")
        }
        NSLog("🗑️ All database data cleared")
    }
}
