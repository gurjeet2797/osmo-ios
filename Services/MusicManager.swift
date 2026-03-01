import Foundation
import MusicKit

final class MusicManager: Sendable {
    static let shared = MusicManager()

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Apple Music access denied"
            )
        }

        switch action.toolName {
        case "ios_music.play":
            return await playMusic(action)
        case "ios_music.pause":
            return await pauseMusic(action)
        case "ios_music.resume":
            return await resumeMusic(action)
        case "ios_music.skip":
            return await skipTrack(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown music action: \(action.toolName)"
            )
        }
    }

    // MARK: - Private

    private func playMusic(_ action: DeviceAction) async -> DeviceActionResult {
        guard let query = action.args["query"]?.stringValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing query"
            )
        }

        let searchType = action.args["type"]?.stringValue ?? "song"

        do {
            let player = ApplicationMusicPlayer.shared

            switch searchType {
            case "album":
                var request = MusicCatalogSearchRequest(term: query, types: [Album.self])
                request.limit = 1
                let response = try await request.response()
                guard let album = response.albums.first else {
                    return failResult(action, error: "No albums found for \"\(query)\"")
                }
                let detailedAlbum = try await album.with([.tracks])
                guard let tracks = detailedAlbum.tracks else {
                    return failResult(action, error: "Could not load album tracks")
                }
                player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                try await player.play()
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: true,
                    result: [
                        "now_playing": .string(album.title),
                        "artist": .string(album.artistName),
                        "type": .string("album"),
                    ],
                    error: nil
                )

            case "playlist":
                var request = MusicCatalogSearchRequest(term: query, types: [Playlist.self])
                request.limit = 1
                let response = try await request.response()
                guard let playlist = response.playlists.first else {
                    return failResult(action, error: "No playlists found for \"\(query)\"")
                }
                let detailed = try await playlist.with([.tracks])
                guard let tracks = detailed.tracks else {
                    return failResult(action, error: "Could not load playlist tracks")
                }
                player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                try await player.play()
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: true,
                    result: [
                        "now_playing": .string(playlist.name),
                        "type": .string("playlist"),
                    ],
                    error: nil
                )

            default: // "song"
                var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
                request.limit = 1
                let response = try await request.response()
                guard let song = response.songs.first else {
                    return failResult(action, error: "No songs found for \"\(query)\"")
                }
                player.queue = [song]
                try await player.play()
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: true,
                    result: [
                        "now_playing": .string(song.title),
                        "artist": .string(song.artistName),
                        "type": .string("song"),
                    ],
                    error: nil
                )
            }
        } catch {
            return failResult(action, error: error.localizedDescription)
        }
    }

    private func pauseMusic(_ action: DeviceAction) async -> DeviceActionResult {
        ApplicationMusicPlayer.shared.pause()
        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: [:],
            error: nil
        )
    }

    private func resumeMusic(_ action: DeviceAction) async -> DeviceActionResult {
        do {
            try await ApplicationMusicPlayer.shared.play()
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [:],
                error: nil
            )
        } catch {
            return failResult(action, error: error.localizedDescription)
        }
    }

    private func skipTrack(_ action: DeviceAction) async -> DeviceActionResult {
        let direction = action.args["direction"]?.stringValue ?? "next"
        do {
            if direction == "previous" {
                try await ApplicationMusicPlayer.shared.skipToPreviousEntry()
            } else {
                try await ApplicationMusicPlayer.shared.skipToNextEntry()
            }
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [:],
                error: nil
            )
        } catch {
            return failResult(action, error: error.localizedDescription)
        }
    }

    private func failResult(_ action: DeviceAction, error: String) -> DeviceActionResult {
        DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: false,
            result: [:],
            error: error
        )
    }
}
