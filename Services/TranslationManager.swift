import Foundation
import Translation

final class TranslationManager: Sendable {
    static let shared = TranslationManager()

    static let languageCodes: [String: String] = [
        "arabic": "ar",
        "chinese": "zh-Hans",
        "mandarin": "zh-Hans",
        "dutch": "nl",
        "english": "en",
        "french": "fr",
        "german": "de",
        "hindi": "hi",
        "indonesian": "id",
        "italian": "it",
        "japanese": "ja",
        "korean": "ko",
        "polish": "pl",
        "portuguese": "pt",
        "russian": "ru",
        "spanish": "es",
        "thai": "th",
        "turkish": "tr",
        "ukrainian": "uk",
        "vietnamese": "vi",
    ]

    nonisolated(unsafe) private var continuation: CheckedContinuation<DeviceActionResult, Never>?
    nonisolated(unsafe) private var pendingAction: DeviceAction?

    private init() {}

    var currentAction: DeviceAction? { pendingAction }

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        switch action.toolName {
        case "ios_translation.translate":
            // Validate args before suspending
            guard action.args["text"]?.stringValue != nil else {
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: false,
                    result: [:],
                    error: "Missing text"
                )
            }
            guard let targetLang = action.args["target_language"]?.stringValue else {
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: false,
                    result: [:],
                    error: "Missing target_language"
                )
            }
            let langKey = targetLang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.languageCodes[langKey] != nil else {
                return DeviceActionResult(
                    actionId: action.actionId,
                    idempotencyKey: action.idempotencyKey,
                    success: false,
                    result: [:],
                    error: "Unsupported language: \(targetLang). Supported: \(Self.languageCodes.keys.sorted().joined(separator: ", "))"
                )
            }

            // Suspend until SwiftUI's .translationTask completes
            return await withCheckedContinuation { cont in
                self.continuation = cont
                self.pendingAction = action
            }
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown action: \(action.toolName)"
            )
        }
    }

    func complete(_ result: DeviceActionResult) {
        let cont = continuation
        continuation = nil
        pendingAction = nil
        cont?.resume(returning: result)
    }
}
