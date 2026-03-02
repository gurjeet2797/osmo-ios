import Foundation

/// Persists conversations to a JSON file in Application Support.
final class ConversationStore: Sendable {

    private static let fileName = "conversations.json"

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Osmo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    func load() -> [Conversation] {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Conversation].self, from: data)
        } catch {
            // Corrupted file — start fresh
            return []
        }
    }

    func save(_ conversations: [Conversation]) {
        let url = Self.fileURL
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversations)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort persistence — don't crash
        }
    }
}
