import EventKit
import Foundation

final class EventKitManager: Sendable {
    static let shared = EventKitManager()

    private let store = EKEventStore()

    private init() {}

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
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
                error: "Calendar access denied"
            )
        }

        switch action.toolName {
        case "ios_eventkit.list_events":
            return listEvents(action)
        case "ios_eventkit.create_event":
            return createEvent(action)
        case "ios_eventkit.update_event":
            return updateEvent(action)
        case "ios_eventkit.delete_event":
            return deleteEvent(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown device action: \(action.toolName)"
            )
        }
    }

    // MARK: - Private

    private func listEvents(_ action: DeviceAction) -> DeviceActionResult {
        let now = Date()
        let timeMin = parseDate(action.args["time_min"]) ?? now
        let timeMax = parseDate(action.args["time_max"]) ?? now.addingTimeInterval(86400)

        let predicate = store.predicateForEvents(withStart: timeMin, end: timeMax, calendars: nil)
        let events = store.events(matching: predicate)

        let eventData: [[String: AnyCodable]] = events.map { event in
            [
                "title": .string(event.title ?? ""),
                "start": .string(event.startDate.ISO8601Format()),
                "end": .string(event.endDate.ISO8601Format()),
                "event_id": .string(event.eventIdentifier),
            ]
        }

        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: ["events": .array(eventData.map { .object($0) })],
            error: nil
        )
    }

    private func createEvent(_ action: DeviceAction) -> DeviceActionResult {
        let event = EKEvent(eventStore: store)
        event.title = action.args["title"]?.stringValue ?? "New Event"
        event.startDate = parseDate(action.args["start"]) ?? Date()
        event.endDate = parseDate(action.args["end"]) ?? event.startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["event_id": .string(event.eventIdentifier)],
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

    private func updateEvent(_ action: DeviceAction) -> DeviceActionResult {
        guard let eventId = action.args["event_id"]?.stringValue,
              let event = store.event(withIdentifier: eventId) else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Event not found"
            )
        }

        if let title = action.args["title"]?.stringValue {
            event.title = title
        }
        if let start = parseDate(action.args["start"]) {
            event.startDate = start
        }
        if let end = parseDate(action.args["end"]) {
            event.endDate = end
        }

        do {
            try store.save(event, span: .thisEvent)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["event_id": .string(event.eventIdentifier)],
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

    private func deleteEvent(_ action: DeviceAction) -> DeviceActionResult {
        guard let eventId = action.args["event_id"]?.stringValue,
              let event = store.event(withIdentifier: eventId) else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Event not found"
            )
        }

        do {
            try store.remove(event, span: .thisEvent)
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
