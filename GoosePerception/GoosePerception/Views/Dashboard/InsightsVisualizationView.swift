import SwiftUI

// MARK: - Insights Visualization View
/// A rich, visual dashboard showing user behavior patterns, collaborations, mood trends, and work sessions

struct InsightsVisualizationView: View {
    let database: Database?
    
    @State private var appUsage: [AppUsage] = []
    @State private var collaborators: [Collaborator] = []
    @State private var moodSummary: MoodSummary?
    @State private var faceEvents: [FaceEvent] = []
    @State private var captures: [ScreenCapture] = []
    @State private var insights: [Insight] = []
    @State private var projects: [Project] = []
    @State private var interests: [Interest] = []
    @State private var timeRange: TimeRange = .today
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case all = "All Time"
        
        var hours: Int {
            switch self {
            case .today: return 24
            case .week: return 168
            case .all: return 720  // 30 days
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Understanding your work patterns")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Main grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // Activity timeline
                    TimelineCard(captures: captures, faceEvents: faceEvents)
                    
                    // Mood journey
                    MoodJourneyCard(faceEvents: faceEvents, moodSummary: moodSummary)
                    
                    // People/Collaborators orbital
                    CollaboratorOrbitCard(collaborators: collaborators)
                    
                    // Focus distribution
                    FocusDistributionCard(appUsage: appUsage)
                }
                .padding(.horizontal)
                
                // Full-width cards
                VStack(spacing: 16) {
                    // Work sessions timeline
                    WorkSessionsCard(captures: captures)
                    
                    // Interest cloud
                    InterestCloudCard(interests: interests, projects: projects)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 20)
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: timeRange) {
            Task { await loadData() }
        }
    }
    
    private func loadData() async {
        guard let db = database else { return }
        do {
            captures = try await db.getRecentCaptures(hours: timeRange.hours)
            appUsage = try await db.getAllAppUsage()
            collaborators = try await db.getAllCollaborators()
            moodSummary = try await db.getMoodSummary(hours: timeRange.hours)
            faceEvents = try await db.getRecentFaceEvents(hours: timeRange.hours)
            insights = try await db.getAllInsights()
            projects = try await db.getAllProjects()
            interests = try await db.getAllInterests()
        } catch {
            print("Failed to load insights data: \(error)")
        }
    }
}

// MARK: - Timeline Card
/// Shows activity over time with intensity heat visualization

struct TimelineCard: View {
    let captures: [ScreenCapture]
    let faceEvents: [FaceEvent]
    
    private var hourlyActivity: [(hour: Int, count: Int, hasEmotion: Bool)] {
        let calendar = Calendar.current
        var hourCounts: [Int: (count: Int, hasEmotion: Bool)] = [:]
        
        for capture in captures {
            let hour = calendar.component(.hour, from: capture.timestamp)
            let existing = hourCounts[hour] ?? (0, false)
            hourCounts[hour] = (existing.count + 1, existing.hasEmotion)
        }
        
        for event in faceEvents where event.emotion != nil {
            let hour = calendar.component(.hour, from: event.timestamp)
            if let existing = hourCounts[hour] {
                hourCounts[hour] = (existing.count, true)
            }
        }
        
        return (6..<24).map { hour in
            let data = hourCounts[hour] ?? (0, false)
            return (hour, data.count, data.hasEmotion)
        }
    }
    
    private var maxCount: Int {
        hourlyActivity.map(\.count).max() ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Activity Timeline")
                    .font(.headline)
                Spacer()
            }
            
            if captures.isEmpty {
                emptyState("No activity captured yet")
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(hourlyActivity, id: \.hour) { item in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barGradient(intensity: Double(item.count) / Double(maxCount), hasEmotion: item.hasEmotion))
                                .frame(width: 14, height: max(4, CGFloat(item.count) / CGFloat(maxCount) * 60))
                            
                            if item.hour % 3 == 0 {
                                Text("\(item.hour)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 80)
                
                HStack {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("Active").font(.caption2).foregroundStyle(.secondary)
                    Circle().fill(Color.pink).frame(width: 8, height: 8)
                    Text("Mood tracked").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
    
    private func barGradient(intensity: Double, hasEmotion: Bool) -> LinearGradient {
        let baseColor = hasEmotion ? Color.pink : Color.blue
        return LinearGradient(
            colors: [baseColor.opacity(0.3 + intensity * 0.7), baseColor],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Mood Journey Card
/// Visualizes emotional state over time with a flowing line

struct MoodJourneyCard: View {
    let faceEvents: [FaceEvent]
    let moodSummary: MoodSummary?
    
    private let moodOrder = ["angry", "fear", "sad", "neutral", "surprise", "happy"]
    
    private var moodPoints: [(date: Date, level: Int, mood: String)] {
        faceEvents.compactMap { event in
            guard let emotion = event.emotion,
                  let level = moodOrder.firstIndex(of: emotion.lowercased()) else { return nil }
            return (event.timestamp, level, emotion)
        }
        .sorted { $0.date < $1.date }
    }
    
    private func moodColor(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "happy": return .green
        case "neutral": return .blue
        case "sad": return .indigo
        case "angry": return .red
        case "surprise": return .orange
        case "fear": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.pink)
                Text("Mood Journey")
                    .font(.headline)
                Spacer()
                if let mood = moodSummary, !mood.isEmpty {
                    Text(mood.moodEmoji)
                        .font(.title2)
                }
            }
            
            if moodPoints.isEmpty {
                emptyState("Face detection will track your mood")
            } else {
                GeometryReader { geo in
                    ZStack {
                        // Background gradient zones
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.green.opacity(0.1))
                            Rectangle().fill(Color.blue.opacity(0.05))
                            Rectangle().fill(Color.indigo.opacity(0.1))
                        }
                        
                        // Mood line
                        Path { path in
                            let width = geo.size.width
                            let height = geo.size.height
                            let xStep = width / CGFloat(max(1, moodPoints.count - 1))
                            
                            for (index, point) in moodPoints.enumerated() {
                                let x = CGFloat(index) * xStep
                                let y = height - (CGFloat(point.level) / CGFloat(moodOrder.count - 1)) * height
                                
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(
                            LinearGradient(colors: [.pink, .purple, .blue], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        
                        // Mood dots
                        ForEach(Array(moodPoints.enumerated()), id: \.offset) { index, point in
                            let width = geo.size.width
                            let height = geo.size.height
                            let xStep = width / CGFloat(max(1, moodPoints.count - 1))
                            let x = CGFloat(index) * xStep
                            let y = height - (CGFloat(point.level) / CGFloat(moodOrder.count - 1)) * height
                            
                            Circle()
                                .fill(moodColor(point.mood))
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Legend
                HStack(spacing: 8) {
                    ForEach(["😊", "😐", "😔"], id: \.self) { emoji in
                        Text(emoji).font(.caption)
                    }
                    Spacer()
                    Text("\(moodPoints.count) samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
}

// MARK: - Collaborator Orbit Card
/// Shows people you interact with in an orbital/constellation style

struct CollaboratorOrbitCard: View {
    let collaborators: [Collaborator]
    
    private var sortedCollaborators: [Collaborator] {
        collaborators.sorted { $0.mentionCount > $1.mentionCount }
    }
    
    private func collaboratorColor(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.green)
                Text("Your Circle")
                    .font(.headline)
                Spacer()
                Text("\(collaborators.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            }
            
            if collaborators.isEmpty {
                emptyState("Collaborators will appear here")
            } else {
                GeometryReader { geo in
                    ZStack {
                        // Center "You" circle
                        Circle()
                            .fill(RadialGradient(
                                colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            ))
                            .frame(width: 50, height: 50)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        
                        // Orbiting collaborators
                        ForEach(Array(sortedCollaborators.prefix(8).enumerated()), id: \.element.id) { index, collab in
                            let angle = Double(index) * (2 * .pi / Double(min(8, sortedCollaborators.count)))
                            let radius: CGFloat = 35 + CGFloat(index % 2) * 15
                            let x = geo.size.width / 2 + cos(angle) * radius
                            let y = geo.size.height / 2 + sin(angle) * radius
                            let size = 20 + min(10, CGFloat(collab.mentionCount) * 2)
                            
                            VStack(spacing: 2) {
                                Circle()
                                    .fill(collaboratorColor(collab.name))
                                    .frame(width: size, height: size)
                                    .overlay(
                                        Text(String(collab.name.prefix(1)).uppercased())
                                            .font(.system(size: size * 0.4, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                Text(collab.name.components(separatedBy: " ").first ?? collab.name)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
}

// MARK: - Focus Distribution Card
/// Pie/donut chart of app usage

struct FocusDistributionCard: View {
    let appUsage: [AppUsage]
    
    private var topApps: [(app: AppUsage, percentage: Double)] {
        let total = appUsage.reduce(0) { $0 + $1.totalSeconds }
        guard total > 0 else { return [] }
        
        return appUsage
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(5)
            .map { ($0, Double($0.totalSeconds) / Double(total)) }
    }
    
    private let appColors: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan]
    
    private func appEmoji(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("terminal") || lowered.contains("iterm") { return "⌨️" }
        if lowered.contains("code") || lowered.contains("xcode") { return "💻" }
        if lowered.contains("chrome") || lowered.contains("safari") || lowered.contains("firefox") { return "🌐" }
        if lowered.contains("slack") || lowered.contains("discord") { return "💬" }
        if lowered.contains("zoom") || lowered.contains("meet") { return "📹" }
        if lowered.contains("mail") { return "✉️" }
        if lowered.contains("notes") || lowered.contains("notion") { return "📝" }
        if lowered.contains("spotify") || lowered.contains("music") { return "🎵" }
        if lowered.contains("finder") { return "📁" }
        return "📱"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.purple)
                Text("Focus Time")
                    .font(.headline)
                Spacer()
            }
            
            if topApps.isEmpty {
                emptyState("App usage will appear here")
            } else {
                HStack(spacing: 16) {
                    // Donut chart
                    ZStack {
                        ForEach(Array(topApps.enumerated()), id: \.offset) { index, item in
                            let startAngle = topApps.prefix(index).reduce(0) { $0 + $1.percentage } * 360
                            let endAngle = startAngle + item.percentage * 360
                            
                            DonutSlice(
                                startAngle: Angle(degrees: startAngle - 90),
                                endAngle: Angle(degrees: endAngle - 90),
                                thickness: 12
                            )
                            .fill(appColors[index % appColors.count])
                        }
                        
                        // Center text
                        VStack(spacing: 0) {
                            Text(appUsage.first?.appName.components(separatedBy: " ").first ?? "")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text(appEmoji(appUsage.first?.appName ?? ""))
                                .font(.title3)
                        }
                    }
                    .frame(width: 80, height: 80)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(topApps.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(appColors[index % appColors.count])
                                    .frame(width: 8, height: 8)
                                Text(item.app.appName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(item.percentage * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let thickness: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius - thickness
        
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Work Sessions Card
/// Horizontal timeline showing focused work blocks

struct WorkSessionsCard: View {
    let captures: [ScreenCapture]
    
    private struct WorkSession: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let app: String
        let captureCount: Int
        
        var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
    }
    
    private var sessions: [WorkSession] {
        guard !captures.isEmpty else { return [] }
        
        let sorted = captures.sorted { $0.timestamp < $1.timestamp }
        var result: [WorkSession] = []
        
        var sessionStart = sorted[0].timestamp
        var sessionApp = sorted[0].focusedApp ?? "Unknown"
        var sessionCount = 1
        var lastTime = sessionStart
        
        for capture in sorted.dropFirst() {
            // Gap of more than 5 minutes = new session
            if capture.timestamp.timeIntervalSince(lastTime) > 300 {
                result.append(WorkSession(start: sessionStart, end: lastTime, app: sessionApp, captureCount: sessionCount))
                sessionStart = capture.timestamp
                sessionApp = capture.focusedApp ?? "Unknown"
                sessionCount = 1
            } else {
                sessionCount += 1
            }
            lastTime = capture.timestamp
        }
        
        // Add final session
        result.append(WorkSession(start: sessionStart, end: lastTime, app: sessionApp, captureCount: sessionCount))
        
        return result.filter { $0.duration > 60 }  // Only sessions longer than 1 min
    }
    
    private func sessionColor(_ app: String) -> Color {
        let lowered = app.lowercased()
        if lowered.contains("code") || lowered.contains("xcode") { return .blue }
        if lowered.contains("terminal") { return .green }
        if lowered.contains("chrome") || lowered.contains("safari") { return .orange }
        if lowered.contains("slack") || lowered.contains("zoom") { return .purple }
        return .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text("Work Sessions")
                    .font(.headline)
                Spacer()
                if !sessions.isEmpty {
                    Text("\(sessions.count) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if sessions.isEmpty {
                emptyState("Work sessions will appear as you capture activity")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(sessionColor(session.app))
                                        .frame(width: max(20, session.duration / 60), height: 24)
                                }
                                
                                Text(session.app.components(separatedBy: " ").first ?? session.app)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 60)
                                
                                Text(formatDuration(session.duration))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins < 60 {
            return "\(mins)m"
        } else {
            return "\(mins / 60)h \(mins % 60)m"
        }
    }
}

// MARK: - Interest Cloud Card
/// Tag cloud of topics and projects

struct InterestCloudCard: View {
    let interests: [Interest]
    let projects: [Project]
    
    private struct CloudItem: Identifiable {
        let id = UUID()
        let text: String
        let weight: Int
        let isProject: Bool
    }
    
    private var items: [CloudItem] {
        let interestItems = interests.map { CloudItem(text: $0.topic, weight: $0.engagementCount, isProject: false) }
        let projectItems = projects.map { CloudItem(text: $0.name, weight: $0.mentionCount, isProject: true) }
        return (interestItems + projectItems).sorted { $0.weight > $1.weight }
    }
    
    private func fontSize(for weight: Int, maxWeight: Int) -> CGFloat {
        let minSize: CGFloat = 10
        let maxSize: CGFloat = 18
        let ratio = CGFloat(weight) / CGFloat(max(1, maxWeight))
        return minSize + (maxSize - minSize) * ratio
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.cyan)
                Text("Topics & Projects")
                    .font(.headline)
                Spacer()
            }
            
            if items.isEmpty {
                emptyState("Topics and projects you work on will appear here")
            } else {
                let maxWeight = items.map(\.weight).max() ?? 1
                
                FlowLayout(spacing: 8) {
                    ForEach(items.prefix(20)) { item in
                        Text(item.text)
                            .font(.system(size: fontSize(for: item.weight, maxWeight: maxWeight)))
                            .fontWeight(item.weight > maxWeight / 2 ? .medium : .regular)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                item.isProject
                                    ? Color.blue.opacity(0.15)
                                    : Color.cyan.opacity(0.1)
                            )
                            .foregroundStyle(item.isProject ? .blue : .cyan)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
}

// MARK: - Helpers (FlowLayout is defined in AutomationResultSheet.swift)

private func emptyState(_ message: String) -> some View {
    Text(message)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, minHeight: 60)
        .multilineTextAlignment(.center)
}
