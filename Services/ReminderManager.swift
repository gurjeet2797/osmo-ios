import EventKit
import Foundation

final class ReminderManager: Sendable {
    static let shared = ReminderManager()

    private let store = EKEventStore()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
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
                error: "Reminders access denied"
            )
        }

        switch action.toolName {
        case "ios_reminders.list_reminders":
            return await listReminders(action)
        case "ios_reminders.create_reminder":
            return createReminder(action)
        case "ios_reminders.complete_reminder":
            return completeReminder(action)
        case "ios_reminders.delete_reminder":
            return deleteReminder(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown reminder action: \(action.toolName)"
            )
        }
    }

    // MARK: - Private

    private func listReminders(_ action: DeviceAction) async -> DeviceActionResult {
        let includeCompleted = action.args["include_completed"]?.boolValue ?? false
        let listName = action.args["list_name"]?.stringValue

        var calendars: [EKCalendar]? = nil
        if let listName {
            calendars = store.calendars(for: .reminder).filter { $0.title.localizedCaseInsensitiveContains(listName) }
        }

        let predicate = includeCompleted
            ? store.predicateForReminders(in: calendars)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)

        // Extract sendable data inside the closure to avoid sending non-Sendable EKReminder
        let data: [[String: AnyCodable]] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let mapped: [[String: AnyCodable]] = (reminders ?? []).map { r in
                    var dict: [String: AnyCodable] = [
                        "title": .string(r.title ?? ""),
                        "reminder_id": .string(r.calendarItemIdentifier),
                        "is_completed": .bool(r.isCompleted),
                        "list": .string(r.calendar?.title ?? ""),
                    ]
                    if let due = r.dueDateComponents, let date = Calendar.current.date(from: due) {
                        dict["due_date"] = .string(date.ISO8601Format())
                    }
                    if r.priority > 0 {
                        dict["priority"] = .int(r.priority)
                    }
                    return dict
                }
                continuation.resume(returning: mapped)
            }
        }

        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: ["reminders": .array(data.map { .object($0) })],
            error: nil
        )
    }

    private func createReminder(_ action: DeviceAction) -> DeviceActionResult {
        let reminder = EKReminder(eventStore: store)
        reminder.title = action.args["title"]?.stringValue ?? "New Reminder"

        if let notes = action.args["notes"]?.stringValue {
            reminder.notes = notes
        }

        if let priority = action.args["priority"]?.intValue {
            reminder.priority = priority
        }

        if let dueDate = parseDate(action.args["due_date"]) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        }

        // Find target list or use default
        if let listName = action.args["list_name"]?.stringValue {
            let match = store.calendars(for: .reminder).first {
                $0.title.localizedCaseInsensitiveContains(listName)
            }
            reminder.calendar = match ?? store.defaultCalendarForNewReminders()
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }

        do {
            try store.save(reminder, commit: true)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["reminder_id": .string(reminder.calendarItemIdentifier)],
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

    private func completeReminder(_ action: DeviceAction) -> DeviceActionResult {
        guard let reminderId = action.args["reminder_id"]?.stringValue,
              let reminder = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Reminder not found"
            )
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try store.save(reminder, commit: true)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [:],
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

    private func deleteReminder(_ action: DeviceAction) -> DeviceActionResult {
        guard let reminderId = action.args["reminder_id"]?.stringValue,
              let reminder = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Reminder not found"
            )
        }

        do {
            try store.remove(reminder, commit: true)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [:],
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

    private func parseDate(_ value: AnyCodable?) -> Date? {
        guard let string = value?.stringValue else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
