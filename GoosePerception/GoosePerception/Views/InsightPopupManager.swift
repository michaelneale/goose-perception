import SwiftUI
import AppKit

// MARK: - Popup Data Types

/// Item in the popup queue
struct PopupItem {
    let title: String
    let content: String
    let icon: String
    let iconColor: Color
    let isAction: Bool
    var actionId: Int64?
}

// MARK: - Generic Popup View

struct GenericPopupView: View {
    let title: String
    let content: String
    let icon: String
    let iconColor: Color
    var showComplete: Bool = false
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    var onComplete: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.title2)
                
                Text(title)
                    .font(.headline)
                
                Spacer()
            }
            
            Text(content)
                .font(.body)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Spacer()
                
                Button("Snooze") {
                    onSnooze()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                
                if showComplete, let onComplete = onComplete {
                    Button("Done") {
                        onComplete()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

// MARK: - Legacy Insight Popup View (for compatibility)

struct InsightPopupView: View {
    let content: String
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    
    var body: some View {
        GenericPopupView(
            title: "Insight",
            content: content,
            icon: "lightbulb.fill",
            iconColor: .yellow,
            onDismiss: onDismiss,
            onSnooze: onSnooze
        )
    }
}

// MARK: - Popup Manager

/// Manages insight and action popup windows
@MainActor
class InsightPopupManager {
    private var currentWindow: NSWindow?
    private var currentItem: PopupItem?
    private var pendingItems: [PopupItem] = []
    private var snoozedItems: [(item: PopupItem, showAt: Date)] = []
    private var isShowing = false
    private var snoozeCheckTask: Task<Void, Never>?
    
    /// Callback when action is dismissed/completed
    var onActionDismissed: ((Int64) -> Void)?
    var onActionCompleted: ((Int64) -> Void)?
    
    /// Duration to snooze (15 minutes)
    private let snoozeDuration: TimeInterval = 15 * 60
    
    init() {
        startSnoozeChecker()
    }
    
    private func startSnoozeChecker() {
        snoozeCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self.checkSnoozedItems()
            }
        }
    }
    
    private func checkSnoozedItems() {
        let now = Date()
        let ready = snoozedItems.filter { $0.showAt <= now }
        snoozedItems.removeAll { $0.showAt <= now }
        
        for item in ready {
            pendingItems.append(item.item)
        }
        
        if !ready.isEmpty {
            showNextIfNeeded()
        }
    }
    
    /// Show an insight popup
    func showInsight(_ content: String) {
        let item = PopupItem(
            title: "Insight",
            content: content,
            icon: "lightbulb.fill",
            iconColor: .yellow,
            isAction: false
        )
        pendingItems.append(item)
        showNextIfNeeded()
    }
    
    /// Show an action popup with title and message
    func showAction(id: Int64, title: String, message: String, source: String) {
        let iconColor: Color
        switch source.lowercased() {
        case "wellness": iconColor = .pink
        case "reminder": iconColor = .purple
        case "focus": iconColor = .blue
        case "late night": iconColor = .indigo
        default: iconColor = .orange
        }
        
        var item = PopupItem(
            title: title,
            content: message,
            icon: "bell.fill",
            iconColor: iconColor,
            isAction: true
        )
        item.actionId = id
        pendingItems.append(item)
        showNextIfNeeded()
    }
    
    private func showNextIfNeeded() {
        guard !isShowing, let item = pendingItems.first else { return }
        pendingItems.removeFirst()
        
        isShowing = true
        currentItem = item
        
        let popupView = GenericPopupView(
            title: item.title,
            content: item.content,
            icon: item.icon,
            iconColor: item.iconColor,
            showComplete: item.isAction,
            onDismiss: { [weak self] in
                self?.dismissCurrent()
            },
            onSnooze: { [weak self] in
                self?.snoozeCurrent()
            },
            onComplete: item.isAction ? { [weak self] in
                self?.completeCurrent()
            } : nil
        )
        
        let hostingController = NSHostingController(rootView: popupView)
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.title = item.isAction ? "Action" : "Insight"
        window.contentViewController = hostingController
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        
        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.maxY - windowFrame.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        currentWindow = window
        
        // Auto-dismiss after 30 seconds (45 for actions)
        let autoDismissDelay = item.isAction ? 45.0 : 30.0
        Task {
            try? await Task.sleep(for: .seconds(autoDismissDelay))
            if self.isShowing {
                self.dismissCurrent()
            }
        }
    }
    
    private func dismissCurrent() {
        // Notify if it was an action
        if let item = currentItem, item.isAction, let actionId = item.actionId {
            onActionDismissed?(actionId)
        }
        
        currentWindow?.close()
        currentWindow = nil
        currentItem = nil
        isShowing = false
        
        // Show next item after a brief delay
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            self.showNextIfNeeded()
        }
    }
    
    private func snoozeCurrent() {
        // Add to snoozed list to re-show later
        if let item = currentItem {
            let showAt = Date().addingTimeInterval(snoozeDuration)
            snoozedItems.append((item: item, showAt: showAt))
            NSLog("💤 Snoozed for 15 minutes")
            ToastNotificationManager.shared.showToast("Snoozed for 15 min", duration: 2.0)
        }
        
        currentWindow?.close()
        currentWindow = nil
        currentItem = nil
        isShowing = false
        
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            self.showNextIfNeeded()
        }
    }
    
    private func completeCurrent() {
        // Notify if it was an action
        if let item = currentItem, item.isAction, let actionId = item.actionId {
            onActionCompleted?(actionId)
        }
        
        currentWindow?.close()
        currentWindow = nil
        currentItem = nil
        isShowing = false
        
        ToastNotificationManager.shared.showSuccess("Marked complete")
        
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            self.showNextIfNeeded()
        }
    }
}

// MARK: - Toast Notification Manager

/// Toast notification manager - shows brief floating notifications
@MainActor
final class ToastNotificationManager {
    static let shared = ToastNotificationManager()
    
    private var toastWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    func showToast(_ message: String, duration: TimeInterval = 3.0, isError: Bool = false) {
        dismissTask?.cancel()
        toastWindow?.close()
        
        let toastView = ToastView(message: message, isError: isError)
        let hostingController = NSHostingController(rootView: toastView)
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Position at top center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 400
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.orderFront(nil)
        toastWindow = window
        
        NSLog("🔔 Toast: %@", message)
        
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                self.toastWindow?.close()
                self.toastWindow = nil
            }
        }
    }
    
    func showSuccess(_ message: String) {
        showToast(message, duration: 2.0, isError: false)
    }
    
    func showError(_ message: String) {
        showToast(message, duration: 4.0, isError: true)
    }
}

struct ToastView: View {
    let message: String
    var isError: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(isError ? .red : .green)
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    GenericPopupView(
        title: "Wellness Check",
        content: "You've been working on the GoosePerception project for 2 hours. Consider taking a break!",
        icon: "bell.fill",
        iconColor: .pink,
        showComplete: true,
        onDismiss: {},
        onSnooze: {},
        onComplete: {}
    )
    .frame(width: 380, height: 180)
}
