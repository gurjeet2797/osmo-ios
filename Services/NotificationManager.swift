import Foundation
import UserNotifications

final class NotificationManager: Sendable {
    static let shared = NotificationManager()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        let hasAccess = await requestAccess()
        guard hasAccess else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Notification permission denied"
            )
        }

        switch action.toolName {
        case "ios_notifications.schedule":
            return await scheduleNotification(action)
        case "ios_notifications.cancel":
            return await cancelNotification(action)
        case "ios_notifications.cancel_all":
            return await cancelAllNotifications(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown notification action: \(action.toolName)"
            )
        }
    }

    // MARK: - Proactive Notifications

    func scheduleProactiveNotifications(_ notifications: [PendingNotification]) async {
        let hasAccess = await requestAccess()
        guard hasAccess else { return }

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.categoryIdentifier = "PROACTIVE"

            // Fire immediately since the backend already determined the right time
            let request = UNNotificationRequest(
                identifier: "proactive-\(notification.id)",
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                // Silently fail for individual notifications
            }
        }
    }

    // MARK: - Private

    private func scheduleNotification(_ action: DeviceAction) async -> DeviceActionResult {
        let title = action.args["title"]?.stringValue ?? "Osmo"
        let body = action.args["body"]?.stringValue ?? ""
        let identifier = action.args["identifier"]?.stringValue ?? UUID().uuidString

        guard let fireDate = parseDate(action.args["fire_date"]) else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Invalid or missing fire_date"
            )
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["identifier": .string(identifier)],
                error: nil
            )
        } catch {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: error.localizedDescription
            )
        }
    }

    private func cancelNotification(_ action: DeviceAction) async -> DeviceActionResult {
        guard let identifier = action.args["identifier"]?.stringValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing identifier"
            )
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: [:],
            error: nil
        )
    }

    private func cancelAllNotifications(_ action: DeviceAction) async -> DeviceActionResult {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: [:],
            error: nil
        )
    }

    private func parseDate(_ value: AnyCodable?) -> Date? {
        guard let string = value?.stringValue else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
