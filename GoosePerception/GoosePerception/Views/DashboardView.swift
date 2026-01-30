import SwiftUI
import AVFoundation

struct DashboardView: View {
    let database: Database?
    
    @State private var captures: [ScreenCapture] = []
    @State private var insights: [Insight] = []
    @State private var projects: [Project] = []
    @State private var collaborators: [Collaborator] = []
    @State private var interests: [Interest] = []
    @State private var todos: [Todo] = []
    @State private var actions: [Action] = []
    @State private var directoryActivity: [DirectoryActivity] = []
    @State private var appUsage: [AppUsage] = []
    @State private var moodSummary: MoodSummary?
    @State private var captureCount = 0
    @State private var insightCount = 0
    @State private var knowledgeCount = 0
    @State private var selectedTab: SidebarTab = .services  // Default to Services
    
    enum SidebarTab: String, CaseIterable {
        case services = "Services"
        case knowledge = "Knowledge"
        case insights = "Insights"
        case actions = "Actions"
        case activity = "Activity"
        case captures = "Captures"
        case llm = "LLM"
    }
    
    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Control") {
                    sidebarRow(.services, icon: "power", count: nil)
                }
                
                Section("Output") {
                    sidebarRow(.knowledge, icon: "brain.head.profile", count: knowledgeCount)
                    sidebarRow(.insights, icon: "lightbulb.fill", count: insightCount)
                    sidebarRow(.actions, icon: "checklist", count: actions.filter { $0.isPending }.count)
                }
                
                Section("Data") {
                    sidebarRow(.activity, icon: "list.bullet.rectangle", count: nil)
                    sidebarRow(.captures, icon: "camera.fill", count: nil)
                    sidebarRow(.llm, icon: "brain", count: nil)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
        } detail: {
            switch selectedTab {
            case .services:
                SimpleServicesView()
            case .knowledge:
                KnowledgeView(projects: projects, collaborators: collaborators, interests: interests, todos: todos, directoryActivity: directoryActivity, appUsage: appUsage, moodSummary: moodSummary) {
                    Task {
                        guard let db = database else { return }
                        try? await db.clearAllData()
                        await loadData()
                    }
                }
            case .insights:
                InsightsListView(insights: insights, database: database)
            case .actions:
                ActionsListView(actions: actions, database: database)
            case .activity:
                ActivityLogView()
            case .captures:
                CapturesListView(captures: captures)
            case .llm:
                LLMSessionView()
            }
        }
        .task {
            await loadData()
        }
        .onReceive(refreshTimer) { _ in
            Task { await loadData() }
        }
    }
    
    @ViewBuilder
    private func sidebarRow(_ tab: SidebarTab, icon: String, count: Int?) -> some View {
        HStack {
            Label(tab.rawValue, systemImage: icon)
            Spacer()
            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .tag(tab)
    }
    
    private func loadData() async {
        guard let db = database else { return }
        do {
            captures = try await db.getRecentCaptures(hours: 24)
            insights = try await db.getAllInsights()
            projects = try await db.getAllProjects()
            collaborators = try await db.getAllCollaborators()
            interests = try await db.getAllInterests()
            todos = try await db.getAllTodos()
            actions = try await db.getAllActions()
            directoryActivity = try await db.getAllDirectoryActivity()
            appUsage = try await db.getAllAppUsage()
            moodSummary = try await db.getMoodSummary(hours: 2)
            captureCount = try await db.getTodaysCaptureCount()
            insightCount = try await db.getTodaysInsightCount()
            knowledgeCount = projects.count + collaborators.count + interests.count + directoryActivity.count + appUsage.count
        } catch {
            print("Failed to load data: \(error)")
        }
    }
}

// MARK: - Knowledge View

struct KnowledgeView: View {
    let projects: [Project]
    let collaborators: [Collaborator]
    let interests: [Interest]
    let todos: [Todo]
    let directoryActivity: [DirectoryActivity]
    let appUsage: [AppUsage]
    let moodSummary: MoodSummary?
    var onClearData: (() -> Void)?
    
    @State private var showClearConfirmation = false
    
    private var totalCount: Int {
        projects.count + collaborators.count + interests.count + directoryActivity.count + appUsage.count
    }
    
    private var appItems: [KnowledgeItem] {
        appUsage.map { KnowledgeItem(name: $0.appName, count: $0.useCount, lastSeen: $0.lastUsed, subtitle: $0.formattedTotalTime) }
    }
    
    private var directoryItems: [KnowledgeItem] {
        directoryActivity.map { KnowledgeItem(name: $0.displayName, count: $0.activityCount, lastSeen: $0.lastActivity, subtitle: $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) }
    }
    
    private var projectItems: [KnowledgeItem] {
        projects.map { KnowledgeItem(name: $0.name, count: $0.mentionCount, lastSeen: $0.lastSeen) }
    }
    
    private var collaboratorItems: [KnowledgeItem] {
        collaborators.map { KnowledgeItem(name: $0.name, count: $0.mentionCount, lastSeen: $0.lastSeen) }
    }
    
    private var interestItems: [KnowledgeItem] {
        interests.map { KnowledgeItem(name: $0.topic, count: $0.engagementCount, lastSeen: $0.lastSeen) }
    }
    
    private var todoItems: [KnowledgeItem] {
        todos.filter { !$0.completed }.map { KnowledgeItem(name: $0.description, count: 1, lastSeen: $0.createdAt) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Text("Knowledge").font(.largeTitle).fontWeight(.bold)
                    Spacer()
                    Text("\(totalCount) items")
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all data")
                }
                .padding(.horizontal)
                .padding(.top)
                .alert("Clear All Data?", isPresented: $showClearConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        onClearData?()
                    }
                } message: {
                    Text("This will delete all captured data, knowledge, insights, and actions. This cannot be undone.")
                }
                
                // Mood Summary
                if let mood = moodSummary, !mood.isEmpty {
                    MoodSummaryCard(mood: mood)
                        .padding(.horizontal)
                }
                
                // App Usage
                KnowledgeSection(title: "Apps", icon: "app.fill", color: .indigo, items: appItems)
                
                // Directory Activity
                KnowledgeSection(title: "Directories", icon: "folder.fill", color: .cyan, items: directoryItems)
                
                // Projects
                KnowledgeSection(title: "Projects", icon: "hammer.fill", color: .blue, items: projectItems)
                
                // Collaborators
                KnowledgeSection(title: "Collaborators", icon: "person.2.fill", color: .green, items: collaboratorItems)
                
                // Interests
                KnowledgeSection(title: "Interests", icon: "star.fill", color: .orange, items: interestItems)
                
                // TODOs
                KnowledgeSection(title: "TODOs", icon: "checklist", color: .purple, items: todoItems)
            }
            .padding(.bottom)
        }
    }
}

struct KnowledgeItem: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let lastSeen: Date
    var subtitle: String? = nil
}

/// Format a date as a static relative time string (doesn't auto-update)
func formatRelativeTime(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    
    if seconds < 60 {
        return "just now"
    } else if seconds < 3600 {
        let minutes = seconds / 60
        return "\(minutes)m ago"
    } else if seconds < 86400 {
        let hours = seconds / 3600
        return "\(hours)h ago"
    } else {
        let days = seconds / 86400
        return "\(days)d ago"
    }
}

struct KnowledgeSection: View {
    let title: String
    let icon: String
    let color: Color
    let items: [KnowledgeItem]
    
    @State private var isExpanded = true
    
    private let maxVisibleItems = 8
    private let itemHeight: CGFloat = 32
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.headline)
                    Text("(\(items.count))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            
            if isExpanded {
                if items.isEmpty {
                    Text("No \(title.lowercased()) discovered yet")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.name)
                                            .lineLimit(1)
                                        Spacer()
                                        if item.count > 1 {
                                            Text("\(item.count)×")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(formatRelativeTime(item.lastSeen))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: items.count > maxVisibleItems ? CGFloat(maxVisibleItems) * itemHeight : nil)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Mood Summary Card

struct MoodSummaryCard: View {
    let mood: MoodSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.pink)
                Text("Recent Mood")
                    .font(.headline)
                Spacer()
                Text("Last \(mood.hours)h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                // Dominant mood with emoji
                VStack {
                    Text(mood.moodEmoji)
                        .font(.system(size: 36))
                    Text(mood.dominantMood.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(minWidth: 80)
                
                Divider()
                    .frame(height: 50)
                
                // Mood breakdown
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(mood.topMoods, id: \.mood) { item in
                        HStack {
                            Text(item.mood.capitalized)
                                .font(.caption)
                            Spacer()
                            Text("\(item.percentage)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if mood.topMoods.isEmpty {
                        Text("No mood data")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Event count
                VStack(alignment: .trailing) {
                    Text("\(mood.totalEvents)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let lastUpdated = mood.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.pink.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.pink.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

// MARK: - LLM Session View (Simple scrolling list)

struct LLMSessionView: View {
    @ObservedObject private var sessionStore = LLMSessionStore.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LLM Activity")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if sessionStore.currentSession != nil {
                    ProgressView().scaleEffect(0.7)
                }
                
                Text("\(sessionStore.sessions.count) calls")
                    .foregroundStyle(.secondary)
                
                Button("Clear") {
                    sessionStore.clear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            if sessionStore.sessions.isEmpty && sessionStore.currentSession == nil {
                ContentUnavailableView(
                    "No LLM Activity Yet",
                    systemImage: "brain",
                    description: Text("Run analysis to see LLM calls")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let current = sessionStore.currentSession {
                            LLMCallCard(session: current, isCurrent: true)
                        }
                        
                        ForEach(sessionStore.sessions.reversed()) { session in
                            LLMCallCard(session: session, isCurrent: false)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct LLMCallCard: View {
    let session: LLMSessionEntry
    let isCurrent: Bool
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text(session.title)
                    .font(.headline)
                
                Spacer()
                
                Text(session.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if isCurrent {
                    ProgressView().scaleEffect(0.6)
                }
            }
            
            // Response preview or status
            if let response = session.response {
                Text(response.prefix(150) + (response.count > 150 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
            } else if let error = session.error {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isCurrent {
                Text("Processing...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            // Expand to show full details
            if isExpanded && !isCurrent {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt:").font(.caption.bold()).foregroundStyle(.blue)
                    Text(session.systemPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    Text("Input (\(session.userPrompt.count) chars):").font(.caption.bold()).foregroundStyle(.green)
                    Text(session.userPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    
                    if let response = session.response {
                        Text("Response:").font(.caption.bold()).foregroundStyle(.purple)
                        Text(response)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.orange.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            if !isCurrent {
                withAnimation { isExpanded.toggle() }
            }
        }
    }
}

// MARK: - Simple Services View

struct SimpleServicesView: View {
    @ObservedObject private var state = ServiceStateManager.shared
    @ObservedObject private var deviceManager = DeviceManager.shared

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Perception").font(.largeTitle).fontWeight(.bold)
                    Text("Enable services to start capturing").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            VStack(spacing: 16) {
                ServiceCard(title: "Screen Capture", subtitle: "Screenshots every 20s with OCR", icon: "camera.fill", color: .blue, isEnabled: screenBinding, isReady: state.servicesReady)
                VoiceServiceCard(isEnabled: voiceBinding, isReady: state.servicesReady, audioLevel: state.audioLevel, lastTranscription: state.lastTranscription, deviceManager: deviceManager)
                FaceServiceCard(isEnabled: faceBinding, isReady: state.servicesReady, isPresent: state.isFacePresent, emotion: state.currentEmotion, confidence: state.emotionConfidence, deviceManager: deviceManager)
            }
            .padding(.horizontal, 32)
            
            Divider().padding(.horizontal, 32)
            
            HStack(spacing: 12) {
                Image(systemName: "brain").font(.title2).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analysis").fontWeight(.medium)
                    Text(state.isAnalysisRunning ? "Running..." : "Auto every 20 min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isAnalysisRunning {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("Run Now") {
                        NotificationCenter.default.post(name: .runAnalysisNow, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 32)
            
            if let error = state.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(error).font(.caption).lineLimit(2)
                    Spacer()
                    Button("✕") { state.lastError = nil }.buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(state.servicesReady ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(state.servicesReady ? "Ready" : "Loading...").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var screenBinding: Binding<Bool> {
        Binding(get: { state.isScreenCaptureRunning }, set: { _ in NotificationCenter.default.post(name: .toggleScreenCapture, object: nil) })
    }
    
    private var voiceBinding: Binding<Bool> {
        Binding(get: { state.isVoiceCaptureRunning }, set: { _ in NotificationCenter.default.post(name: .toggleVoiceCapture, object: nil) })
    }
    
    private var faceBinding: Binding<Bool> {
        Binding(get: { state.isFaceCaptureRunning }, set: { _ in NotificationCenter.default.post(name: .toggleFaceCapture, object: nil) })
    }
}

struct ServiceCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var isEnabled: Bool
    var isReady: Bool = true
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(isEnabled ? color.opacity(0.15) : Color.secondary.opacity(0.1)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.title2).foregroundStyle(isEnabled ? color : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isEnabled).toggleStyle(.switch).labelsHidden().disabled(!isReady)
        }
        .padding(16)
        .background(isEnabled ? color.opacity(0.05) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isEnabled ? color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

struct VoiceServiceCard: View {
    @Binding var isEnabled: Bool
    var isReady: Bool
    var audioLevel: Float
    var lastTranscription: String
    @ObservedObject var deviceManager: DeviceManager

    private let color = Color.green

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(isEnabled ? color.opacity(0.15) : Color.secondary.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: "mic.fill").font(.title2).foregroundStyle(isEnabled ? color : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Capture").font(.headline)
                    Text("Speech-to-text transcription").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                // Audio level indicator - always show when enabled
                if isEnabled {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(CGFloat(i) < CGFloat(audioLevel * 10) ? color : color.opacity(0.2))
                                .frame(width: 3, height: CGFloat(8 + i * 3))
                        }
                    }
                    .frame(height: 20)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
                }

                Toggle("", isOn: $isEnabled).toggleStyle(.switch).labelsHidden().disabled(!isReady)
            }

            // Device picker
            HStack {
                Text("Microphone:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $deviceManager.selectedAudioDeviceID) {
                    ForEach(deviceManager.audioInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                .disabled(isEnabled)
            }
            .padding(.leading, 60)

            // Show last transcription if voice is active
            if isEnabled && !lastTranscription.isEmpty {
                Text(lastTranscription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 60)
            }
        }
        .padding(16)
        .background(isEnabled ? color.opacity(0.05) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isEnabled ? color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

struct FaceServiceCard: View {
    @Binding var isEnabled: Bool
    var isReady: Bool
    var isPresent: Bool
    var emotion: String
    var confidence: Double
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var calibrationManager = FaceCalibrationManager.shared

    private let color = Color.orange

    private var emotionIcon: String {
        switch emotion.lowercased() {
        case "happy": return "😊"
        case "content": return "🙂"
        case "sad": return "😢"
        case "angry": return "😠"
        case "frustrated": return "😤"
        case "surprised": return "😮"
        case "tired": return "😴"
        case "serious": return "😐"
        case "focused": return "🧐"
        case "neutral": return "😶"
        default: return "😶"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(isEnabled ? color.opacity(0.15) : Color.secondary.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: "face.smiling").font(.title2).foregroundStyle(isEnabled ? color : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Face Detection").font(.headline)
                    Text("Presence & emotion tracking").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                // Mood indicator when face is detected
                if isEnabled && isPresent && !emotion.isEmpty {
                    HStack(spacing: 4) {
                        Text(emotionIcon).font(.title2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(emotion.capitalized).font(.caption).fontWeight(.medium)
                            Text("\(Int(confidence * 100))%").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.1))
                    .cornerRadius(8)
                } else if isEnabled && !isPresent {
                    Text("No face")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                Toggle("", isOn: $isEnabled).toggleStyle(.switch).labelsHidden().disabled(!isReady)
            }

            // Device picker
            HStack {
                Text("Camera:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $deviceManager.selectedVideoDeviceID) {
                    ForEach(deviceManager.videoInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                .disabled(isEnabled)
            }
            .padding(.leading, 60)

            // Calibration section
            HStack {
                if calibrationManager.isCalibrating {
                    ProgressView(value: calibrationManager.calibrationProgress)
                        .frame(width: 100)
                    Text(calibrationManager.calibrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        calibrationManager.cancelCalibration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    if calibrationManager.isCalibrated {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Calibrated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let age = calibrationManager.calibrationAge {
                            Text("(\(age))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Not calibrated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(calibrationManager.isCalibrated ? "Recalibrate" : "Calibrate") {
                        calibrationManager.startCalibration()
                        // Notify to update camera service
                        NotificationCenter.default.post(name: .startFaceCalibration, object: nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isEnabled || !isPresent)
                }
            }
            .padding(.leading, 60)
        }
        .padding(16)
        .background(isEnabled ? color.opacity(0.05) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isEnabled ? color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var activityLog = ActivityLogStore.shared
    @State private var filter: ActivityLogStore.LogEntry.Source? = nil
    
    var filteredEntries: [ActivityLogStore.LogEntry] {
        if let filter = filter { return activityLog.entries.filter { $0.source == filter } }
        return activityLog.entries
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity").font(.title2).fontWeight(.semibold)
                Spacer()
                Picker("Filter", selection: $filter) {
                    Text("All").tag(nil as ActivityLogStore.LogEntry.Source?)
                    ForEach([ActivityLogStore.LogEntry.Source.screen, .voice, .face, .llm, .system], id: \.self) { source in
                        Text(source.rawValue).tag(source as ActivityLogStore.LogEntry.Source?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                Button("Clear") { activityLog.clear() }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding()
            
            Divider()
            
            if filteredEntries.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "waveform.path", description: Text("Enable services to see activity"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: ActivityLogStore.LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.source.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorFor(entry.source).opacity(0.2))
                    .foregroundStyle(colorFor(entry.source))
                    .cornerRadius(4)
                
                Text(entry.timestamp, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(entry.message).font(.caption).lineLimit(isExpanded ? nil : 1)
                Spacer()
                
                if entry.detail != nil {
                    Button { withAnimation { isExpanded.toggle() } } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isExpanded, let detail = entry.detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func colorFor(_ source: ActivityLogStore.LogEntry.Source) -> Color {
        switch source {
        case .screen: return .blue
        case .voice: return .green
        case .face: return .orange
        case .llm: return .purple
        case .system: return .gray
        }
    }
}

// MARK: - Captures List View

struct CapturesListView: View {
    let captures: [ScreenCapture]
    
    // Compute diversity stats
    private var uniqueApps: [String: Int] {
        var counts: [String: Int] = [:]
        for capture in captures {
            let app = capture.focusedApp ?? "Unknown"
            counts[app, default: 0] += 1
        }
        return counts
    }
    
    private var uniqueWindows: Int {
        Set(captures.compactMap { $0.focusedWindow }).count
    }
    
    private var topApps: [(app: String, count: Int)] {
        uniqueApps.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Captures").font(.title2).fontWeight(.semibold)
                Spacer()
                Text("\(captures.count) today").foregroundStyle(.secondary)
            }
            .padding()
            
            // Diversity summary
            if !captures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Label("\(uniqueApps.count) apps", systemImage: "app.fill")
                            .foregroundStyle(.blue)
                        Label("\(uniqueWindows) windows", systemImage: "macwindow")
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                    
                    // App breakdown bar
                    HStack(spacing: 2) {
                        ForEach(topApps, id: \.app) { item in
                            let fraction = CGFloat(item.count) / CGFloat(max(captures.count, 1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(appColor(item.app))
                                .frame(width: max(fraction * 200, 8), height: 12)
                                .help("\(item.app): \(item.count) captures (\(Int(fraction * 100))%)")
                        }
                        if uniqueApps.count > 5 {
                            Text("+\(uniqueApps.count - 5)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Legend
                    HStack(spacing: 12) {
                        ForEach(topApps.prefix(4), id: \.app) { item in
                            HStack(spacing: 4) {
                                Circle().fill(appColor(item.app)).frame(width: 8, height: 8)
                                Text(item.app).font(.caption2).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            if captures.isEmpty {
                ContentUnavailableView("No Captures Yet", systemImage: "camera", description: Text("Enable screen capture to start"))
            } else {
                List(captures, id: \.id) { capture in
                    CaptureRow(capture: capture)
                }
            }
        }
    }
    
    private func appColor(_ app: String) -> Color {
        // Generate consistent color from app name
        let hash = app.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}

struct CaptureRow: View {
    let capture: ScreenCapture
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(capture.timestamp, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(capture.focusedApp ?? "Unknown").fontWeight(.medium)
                if let window = capture.focusedWindow {
                    Text("— \(window)").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let ocr = capture.ocrText, !ocr.isEmpty {
                    Button { isExpanded.toggle() } label: { Text("\(ocr.count) chars").font(.caption) }.buttonStyle(.plain)
                }
            }
            
            if isExpanded, let ocr = capture.ocrText {
                Text(String(ocr.prefix(500)) + (ocr.count > 500 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - Insights List View

struct InsightsListView: View {
    let insights: [Insight]
    let database: Database?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Insights").font(.title2).fontWeight(.semibold)
                Spacer()
                Text("\(insights.count) total").foregroundStyle(.secondary)
            }
            .padding()
            
            Divider()
            
            if insights.isEmpty {
                ContentUnavailableView("No Insights Yet", systemImage: "lightbulb", description: Text("Run analysis to generate insights"))
            } else {
                List(insights, id: \.id) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(insight.type.capitalized).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(formatRelativeTime(insight.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(insight.content).font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Actions List View

struct ActionsListView: View {
    let actions: [Action]
    let database: Database?
    @State private var testQuery: String = ""
    @State private var showTestSheet = false
    @State private var testAction: Action?
    @State private var permissionTestResult: String = ""
    @State private var isTestingPermissions = false
    
    var pendingActions: [Action] {
        actions.filter { $0.isPending }.sorted { $0.createdAt > $1.createdAt }
    }
    
    var completedActions: [Action] {
        actions.filter { $0.isCompleted }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }
    
    var dismissedActions: [Action] {
        actions.filter { $0.isDismissed && !$0.isCompleted }.sorted { ($0.dismissedAt ?? $0.createdAt) > ($1.dismissedAt ?? $1.createdAt) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Actions").font(.title2).fontWeight(.semibold)
                Spacer()
                Text("\(pendingActions.count) pending").foregroundStyle(.secondary)
            }
            .padding()
            
            Divider()
            
            // Test TinyAgent section
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                    Text("Run Automation")
                        .font(.headline)
                    Spacer()
                }
                
                HStack {
                    TextField("Try: \"Send a text to John about the meeting\" or \"Create a reminder for tomorrow\"", text: $testQuery)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        testAction = Action(
                            type: "automation",
                            title: "Test Query",
                            message: testQuery,
                            source: "Manual Test",
                            priority: 5
                        )
                        showTestSheet = true
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(testQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: [])
                }
                
                Text("Examples: \"Get John's phone number\", \"Create a calendar event for lunch tomorrow\", \"Open Maps to San Francisco\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Divider().padding(.vertical, 4)
                
                // Direct permission test
                HStack {
                    Text("Test Permissions:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Contacts") {
                        testPermission(app: "Contacts", script: "tell application \"Contacts\" to get name of first person")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Reminders") {
                        testPermission(app: "Reminders", script: "tell application \"Reminders\" to get name of first list")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Calendar") {
                        testPermission(app: "Calendar", script: "tell application \"Calendar\" to get name of first calendar")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Notes") {
                        testPermission(app: "Notes", script: "tell application \"Notes\" to get name of first note")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if isTestingPermissions {
                        ProgressView().controlSize(.small)
                    }
                    
                    Spacer()
                }
                
                if !permissionTestResult.isEmpty {
                    Text(permissionTestResult)
                        .font(.caption)
                        .foregroundStyle(permissionTestResult.contains("✅") ? .green : .orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.05))
            
            Divider()
            
            if actions.isEmpty && testQuery.isEmpty {
                ContentUnavailableView("No Actions Yet", systemImage: "checklist", description: Text("Actions from wellness checks and analysis will appear here.\n\nOr try typing a query above to run automation!"))
            } else if actions.isEmpty {
                ContentUnavailableView("No Actions Yet", systemImage: "checklist", description: Text("Actions from wellness checks and analysis will appear here"))
            } else {
                List {
                    if !pendingActions.isEmpty {
                        Section("Pending") {
                            ForEach(pendingActions, id: \.id) { action in
                                ActionRow(action: action, database: database)
                            }
                        }
                    }
                    
                    if !completedActions.isEmpty {
                        Section("Completed") {
                            ForEach(completedActions.prefix(10), id: \.id) { action in
                                ActionRow(action: action, database: database)
                            }
                        }
                    }
                    
                    if !dismissedActions.isEmpty {
                        Section("Dismissed") {
                            ForEach(dismissedActions.prefix(5), id: \.id) { action in
                                ActionRow(action: action, database: database)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTestSheet) {
            if let action = testAction {
                AutomationResultSheet(action: action, database: database)
            }
        }
    }
    
    private func testPermission(app: String, script: String) {
        isTestingPermissions = true
        permissionTestResult = "Testing \(app)..."
        
        Task {
            // Use osascript via shell - more reliable for triggering permission prompts
            let result = await runOsascript(script)
            await MainActor.run {
                permissionTestResult = result
                isTestingPermissions = false
            }
        }
    }
    
    private func runOsascript(_ script: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: "✅ \(output.isEmpty ? "OK" : String(output.prefix(50)))")
                    } else {
                        continuation.resume(returning: "⚠️ \(error.prefix(100))")
                    }
                } catch {
                    continuation.resume(returning: "❌ \(error.localizedDescription)")
                }
            }
        }
    }
}

struct ActionRow: View {
    let action: Action
    let database: Database?
    @State private var isCompleted: Bool
    @State private var isDismissed: Bool
    @State private var showAutomationSheet = false
    
    init(action: Action, database: Database?) {
        self.action = action
        self.database = database
        self._isCompleted = State(initialValue: action.isCompleted)
        self._isDismissed = State(initialValue: action.isDismissed)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Complete button
            Button {
                isCompleted.toggle()
                Task {
                    if isCompleted {
                        try? await database?.markActionCompleted(id: action.id!)
                    }
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(isDismissed)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.headline)
                    .strikethrough(isCompleted || isDismissed)
                    .foregroundStyle(isCompleted || isDismissed ? .secondary : .primary)
                
                Text(action.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Type badge
                    Text(action.type)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(action.type == "popup" ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundStyle(action.type == "popup" ? .orange : .blue)
                        .cornerRadius(4)
                    
                    // Source badge
                    Text(action.source)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor(action.source).opacity(0.15))
                        .foregroundStyle(sourceColor(action.source))
                        .cornerRadius(4)
                    
                    // Priority
                    if action.priority >= 7 {
                        Text("High")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    
                    Spacer()
                    
                    Text(formatRelativeTime(action.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Action buttons for pending items
            if !isCompleted && !isDismissed {
                VStack(spacing: 4) {
                    Button {
                        isDismissed = true
                        Task {
                            try? await database?.markActionDismissed(id: action.id!)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        // Snooze for 2+ hours (random)
                        let snoozeMinutes = Int.random(in: 120...180)
                        let snoozeUntil = Date().addingTimeInterval(Double(snoozeMinutes * 60))
                        Task {
                            try? await database?.snoozeAction(id: action.id!, until: snoozeUntil)
                        }
                    } label: {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showAutomationSheet = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .help("Run automation")
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showAutomationSheet) {
            AutomationResultSheet(action: action, database: database)
        }
    }
    
    private func sourceColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "wellness": return .pink
        case "reminder": return .purple
        case "focus": return .blue
        case "late night": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Activity Log Store

@MainActor
class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let source: Source
        let message: String
        let detail: String?
        
        enum Source: String {
            case screen = "Screen"
            case voice = "Voice"
            case face = "Face"
            case llm = "LLM"
            case system = "System"
        }
    }
    
    @Published var entries: [LogEntry] = []
    
    func log(_ source: LogEntry.Source, _ message: String, detail: String? = nil) {
        entries.append(LogEntry(timestamp: Date(), source: source, message: message, detail: detail))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }
    
    func clear() { entries.removeAll() }
    private init() {}
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleScreenCapture = Notification.Name("toggleScreenCapture")
    static let toggleVoiceCapture = Notification.Name("toggleVoiceCapture")
    static let toggleFaceCapture = Notification.Name("toggleFaceCapture")
    static let runAnalysisNow = Notification.Name("runAnalysisNow")
    static let startFaceCalibration = Notification.Name("startFaceCalibration")
    static let updateFaceCalibration = Notification.Name("updateFaceCalibration")
}

#Preview {
    DashboardView(database: nil)
        .frame(width: 900, height: 600)
}
