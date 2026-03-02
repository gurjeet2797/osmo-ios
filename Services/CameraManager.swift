import AVFoundation
import Foundation
import Photos
import SwiftUI
import UIKit

final class CameraManager: Sendable {
    static let shared = CameraManager()

    nonisolated(unsafe) private var continuation: CheckedContinuation<DeviceActionResult, Never>?
    nonisolated(unsafe) private var pendingAction: DeviceAction?

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        guard AVCaptureDevice.default(for: .video) != nil else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Camera not available on this device"
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

// MARK: - AVFoundation auto-capture camera

struct CameraView: View {
    let action: DeviceAction
    let onDismiss: () -> Void

    var body: some View {
        _CameraHostView(action: action, onDismiss: onDismiss)
            .background(Color.black)
            .ignoresSafeArea()
    }
}

private struct _CameraHostView: UIViewControllerRepresentable {
    let action: DeviceAction
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> AutoCaptureViewController {
        AutoCaptureViewController(action: action, onDismiss: onDismiss)
    }

    func updateUIViewController(_ vc: AutoCaptureViewController, context: Context) {}
}

final class AutoCaptureViewController: UIViewController {
    private let action: DeviceAction
    private let onDismiss: () -> Void
    private let isVideo: Bool

    private let session = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var countdownLabel: UILabel?
    private var statusLabel: UILabel?
    private var cancelButton: UIButton?

    // Video state
    private var isRecording = false
    private var recordingTimer: Timer?
    private var maxDuration: TimeInterval

    init(action: DeviceAction, onDismiss: @escaping () -> Void) {
        self.action = action
        self.onDismiss = onDismiss
        self.isVideo = action.toolName == "ios_camera.record_video"
        self.maxDuration = action.args["max_duration"]?.doubleValue ?? 15
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCountdown()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Setup

    private func setupCamera() {
        session.sessionPreset = isVideo ? .high : .photo

        let cameraArg = action.args["camera"]?.stringValue ?? "back"
        let position: AVCaptureDevice.Position = cameraArg == "front" ? .front : .back

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        if isVideo {
            // Add microphone
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(micInput) {
                session.addInput(micInput)
            }
            let movieOut = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOut) {
                session.addOutput(movieOut)
                self.movieOutput = movieOut
            }
        } else {
            let photoOut = AVCapturePhotoOutput()
            if session.canAddOutput(photoOut) {
                session.addOutput(photoOut)
                self.photoOutput = photoOut
            }
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    private func setupUI() {
        // Countdown label (center)
        let countdown = UILabel()
        countdown.font = .systemFont(ofSize: 72, weight: .bold)
        countdown.textColor = .white
        countdown.textAlignment = .center
        countdown.translatesAutoresizingMaskIntoConstraints = false
        countdown.layer.shadowColor = UIColor.black.cgColor
        countdown.layer.shadowRadius = 8
        countdown.layer.shadowOpacity = 0.8
        countdown.layer.shadowOffset = .zero
        view.addSubview(countdown)
        self.countdownLabel = countdown

        // Status label (bottom)
        let status = UILabel()
        status.font = .systemFont(ofSize: 17, weight: .medium)
        status.textColor = .white.withAlphaComponent(0.8)
        status.textAlignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        status.text = isVideo ? "Recording starts in..." : "Taking photo in..."
        view.addSubview(status)
        self.statusLabel = status

        // Cancel button (top right)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)
        self.cancelButton = cancel

        NSLayoutConstraint.activate([
            countdown.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdown.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Countdown → auto capture

    private func startCountdown() {
        var remaining = 2
        countdownLabel?.text = "\(remaining)"

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            remaining -= 1
            if remaining > 0 {
                self.countdownLabel?.text = "\(remaining)"
            } else {
                timer.invalidate()
                self.countdownLabel?.text = ""
                self.capture()
            }
        }
    }

    private func capture() {
        if isVideo {
            startRecording()
        } else {
            takePhoto()
        }
    }

    // MARK: - Photo

    private func takePhoto() {
        guard let photoOutput else { return }
        statusLabel?.text = "Capturing..."
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Video

    private func startRecording() {
        guard let movieOutput, !isRecording else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        isRecording = true
        statusLabel?.text = "Recording..."
        statusLabel?.textColor = UIColor.systemRed

        // Show a stop button
        cancelButton?.setTitle("Stop", for: .normal)

        movieOutput.startRecording(to: tempURL, recordingDelegate: self)

        // Auto-stop after max duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        movieOutput?.stopRecording()
        statusLabel?.text = "Saving..."
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        if isRecording {
            stopRecording()
            return
        }
        cleanup()
        CameraManager.shared.complete(DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: false,
            result: [:],
            error: "Cancelled by user"
        ))
        onDismiss()
    }

    private func cleanup() {
        recordingTimer?.invalidate()
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }
}

// MARK: - Photo delegate

extension AutoCaptureViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        cleanup()

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            CameraManager.shared.complete(DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: error?.localizedDescription ?? "Failed to capture photo"
            ))
            onDismiss()
            return
        }

        // PHPhotoLibrary callbacks are @Sendable and fire on background threads.
        // Use Task { @MainActor in } to hop back for @MainActor-isolated calls.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [action, onDismiss] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    CameraManager.shared.complete(DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: false,
                        result: [:],
                        error: "Photo library access denied"
                    ))
                    onDismiss()
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, saveError in
                Task { @MainActor in
                    CameraManager.shared.complete(DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: success,
                        result: success ? ["saved": .bool(true), "type": .string("photo")] : [:],
                        error: saveError?.localizedDescription
                    ))
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Video delegate

extension AutoCaptureViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        cleanup()

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [action, onDismiss] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    CameraManager.shared.complete(DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: false,
                        result: [:],
                        error: "Photo library access denied"
                    ))
                    onDismiss()
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { success, saveError in
                try? FileManager.default.removeItem(at: outputFileURL)
                Task { @MainActor in
                    CameraManager.shared.complete(DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: success,
                        result: success ? ["saved": .bool(true), "type": .string("video")] : [:],
                        error: saveError?.localizedDescription
                    ))
                    onDismiss()
                }
            }
        }
    }
}
