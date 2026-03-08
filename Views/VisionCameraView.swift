import SwiftUI
import UIKit

struct VisionCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onDismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onDismiss = onDismiss
        }

        nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                Task { @MainActor in
                    onCapture(image)
                }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in
                onDismiss()
            }
        }
    }
}
