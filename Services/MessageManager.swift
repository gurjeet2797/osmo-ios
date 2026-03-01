import Foundation
import MessageUI
import SwiftUI
import UIKit

final class MessageManager: Sendable {
    static let shared = MessageManager()

    nonisolated(unsafe) private var continuation: CheckedContinuation<DeviceActionResult, Never>?
    nonisolated(unsafe) private var pendingAction: DeviceAction?

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        guard MFMessageComposeViewController.canSendText() else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Device cannot send messages"
            )
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.pendingAction = action
        }
    }

    var currentAction: DeviceAction? { pendingAction }

    func complete(_ result: DeviceActionResult) {
        let cont = continuation
        continuation = nil
        pendingAction = nil
        cont?.resume(returning: result)
    }
}

// MARK: - SwiftUI wrapper for MFMessageComposeViewController

struct MessageComposeView: UIViewControllerRepresentable {
    let action: DeviceAction
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action, onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator

        if let recipients = action.args["recipients"] {
            if case .array(let arr) = recipients {
                controller.recipients = arr.compactMap(\.stringValue)
            }
        }
        if let body = action.args["body"]?.stringValue {
            controller.body = body
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let action: DeviceAction
        let onDismiss: () -> Void

        init(action: DeviceAction, onDismiss: @escaping () -> Void) {
            self.action = action
            self.onDismiss = onDismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let success = result == .sent
            MessageManager.shared.complete(DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: success,
                result: success ? ["sent": .bool(true)] : [:],
                error: result == .failed ? "Message failed to send" : (result == .cancelled ? "Cancelled by user" : nil)
            ))
            onDismiss()
        }
    }
}
