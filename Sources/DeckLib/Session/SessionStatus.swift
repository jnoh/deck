import Foundation
import Observation
import UserNotifications

/// Dynamic status reported by programs running inside a session.
@Observable
public final class SessionStatus: @unchecked Sendable {
    public var customState: String?
    public var desc: String?
    public var icon: String?
    public var notificationCount: Int = 0

    public var needsAttention: Bool {
        customState == "needs-input" || notificationCount > 0
    }

    public init() {}

    /// Apply a status update. Returns the session name to update (for title type).
    @discardableResult
    public func apply(_ update: StatusUpdate, sessionName: String = "") -> String? {
        switch update.type {
        case .status:
            let previousState = customState
            customState = update.state
            if let d = update.desc { desc = d }
            if let i = update.icon { icon = i }

            // Send macOS notification when transitioning to needs-input
            if update.state == "needs-input" && previousState != "needs-input" {
                sendSystemNotification(
                    title: sessionName,
                    body: update.desc ?? "Waiting for input"
                )
            }
            return nil

        case .notify:
            notificationCount += 1
            sendSystemNotification(
                title: sessionName,
                body: update.text ?? "Notification"
            )
            return nil

        case .title:
            return update.text

        case .clear:
            customState = nil
            desc = nil
            icon = nil
            notificationCount = 0
            return nil

        case .exit:
            // Handled by the poll timer, not here
            return nil
        }
    }

    public func clearAttention() {
        notificationCount = 0
    }

    nonisolated(unsafe) private static var notificationsReady = false
    private static let notificationSetup: Void = {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            notificationsReady = granted
        }
    }()

    private func sendSystemNotification(title: String, body: String) {
        _ = Self.notificationSetup

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Deck" : title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Parsed status update from the deck CLI
public struct StatusUpdate: Sendable {
    public enum UpdateType: String, Sendable {
        case status
        case notify
        case title
        case clear
        case exit
    }

    public let type: UpdateType
    public let state: String?
    public let desc: String?
    public let icon: String?
    public let text: String?
    public let level: String?

    public static func parse(json: String) -> StatusUpdate? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = dict["type"] as? String,
              let type = UpdateType(rawValue: typeStr) else {
            return nil
        }

        return StatusUpdate(
            type: type,
            state: dict["state"] as? String,
            desc: dict["desc"] as? String,
            icon: dict["icon"] as? String,
            text: dict["text"] as? String,
            level: dict["level"] as? String
        )
    }
}
