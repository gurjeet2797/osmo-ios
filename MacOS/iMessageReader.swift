import Foundation
import SQLite3

/// Reads iMessage conversations from the local macOS chat.db.
final class iMessageReader: Sendable {

    static let shared = iMessageReader()

    private static let chatDBPath: String = {
        NSHomeDirectory() + "/Library/Messages/chat.db"
    }()

    /// Core Foundation absolute reference date (2001-01-01) offset from Unix epoch.
    private static let coreDataEpoch: TimeInterval = 978307200

    private init() {}

    // MARK: - Public API

    func searchConversations(query: String) -> [[String: String]] {
        let sql = """
            SELECT DISTINCT
                c.ROWID,
                c.guid,
                c.display_name,
                COALESCE(c.display_name, h.id) AS label
            FROM chat c
            LEFT JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
            LEFT JOIN handle h ON chj.handle_id = h.ROWID
            WHERE c.display_name LIKE ?1
               OR h.id LIKE ?1
               OR h.uncanonicalized_id LIKE ?1
            ORDER BY c.ROWID DESC
            LIMIT 20
            """
        let likeQuery = "%\(query)%"
        return runQuery(sql: sql, bindings: [likeQuery]) { stmt in
            [
                "chat_id": String(sqlite3_column_int64(stmt, 0)),
                "chat_guid": String(cString: sqlite3_column_text(stmt, 1)),
                "display_name": columnText(stmt, 2) ?? "",
                "label": columnText(stmt, 3) ?? "",
            ]
        }
    }

    func readThread(chatGuid: String, limit: Int = 50) -> [[String: String]] {
        let sql = """
            SELECT
                m.text,
                m.is_from_me,
                m.date,
                COALESCE(h.id, 'me') AS sender
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            WHERE c.guid = ?1
            ORDER BY m.date DESC
            LIMIT ?2
            """
        let rows = runQuery(sql: sql, bindings: [chatGuid, limit]) { stmt in
            [
                "text": columnText(stmt, 0) ?? "(attachment)",
                "is_from_me": String(sqlite3_column_int(stmt, 1)),
                "date": formatDate(sqlite3_column_int64(stmt, 2)),
                "sender": columnText(stmt, 3) ?? "unknown",
            ]
        }
        return rows.reversed()
    }

    func getRecentMessages(limit: Int = 20) -> [[String: String]] {
        let sql = """
            SELECT
                m.text,
                m.is_from_me,
                m.date,
                COALESCE(h.id, 'me') AS sender,
                COALESCE(c.display_name, h.id, 'unknown') AS conversation
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.text IS NOT NULL AND m.text != ''
            ORDER BY m.date DESC
            LIMIT ?1
            """
        let rows = runQuery(sql: sql, bindings: [limit]) { stmt in
            [
                "text": columnText(stmt, 0) ?? "",
                "is_from_me": String(sqlite3_column_int(stmt, 1)),
                "date": formatDate(sqlite3_column_int64(stmt, 2)),
                "sender": columnText(stmt, 3) ?? "unknown",
                "conversation": columnText(stmt, 4) ?? "unknown",
            ]
        }
        return rows.reversed()
    }

    /// Execute a device action from the backend.
    func executeAction(_ action: DeviceAction) -> DeviceActionResult {
        switch action.toolName {
        case "macos_messages.search_conversations":
            let query = action.args["query"]?.stringValue ?? ""
            let results = searchConversations(query: query)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["conversations": .array(results.map { dict in
                    .object(dict.mapValues { .string($0) })
                })],
                error: nil
            )

        case "macos_messages.read_thread":
            let chatGuid = action.args["chat_guid"]?.stringValue ?? ""
            let limit = action.args["limit"]?.intValue ?? 50
            let messages = readThread(chatGuid: chatGuid, limit: limit)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["messages": .array(messages.map { dict in
                    .object(dict.mapValues { .string($0) })
                })],
                error: nil
            )

        case "macos_messages.get_recent":
            let limit = action.args["limit"]?.intValue ?? 20
            let messages = getRecentMessages(limit: limit)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["messages": .array(messages.map { dict in
                    .object(dict.mapValues { .string($0) })
                })],
                error: nil
            )

        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown tool: \(action.toolName)"
            )
        }
    }

    // MARK: - Private

    private func runQuery<T>(sql: String, bindings: [Any], rowMapper: (OpaquePointer) -> T) -> [T] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(Self.chatDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (index, binding) in bindings.enumerated() {
            let col = Int32(index + 1)
            switch binding {
            case let s as String:
                sqlite3_bind_text(stmt, col, (s as NSString).utf8String, -1, nil)
            case let i as Int:
                sqlite3_bind_int64(stmt, col, Int64(i))
            default:
                break
            }
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowMapper(stmt!))
        }
        return results
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cStr)
    }

    private func formatDate(_ nanoseconds: Int64) -> String {
        // chat.db stores dates as nanoseconds since 2001-01-01
        let seconds = TimeInterval(nanoseconds) / 1_000_000_000.0
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
