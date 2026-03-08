import SwiftUI
import AVFoundation

struct MacSetupView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var currentStep: SetupStep = .messageAccess
    @State private var messageAccessGranted = false
    @State private var micAccessGranted = false

    enum SetupStep: Int, CaseIterable {
        case messageAccess
        case microphone
        case signIn
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 20)

            // Title
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 6)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)

            // Action button
            Button {
                handleAction()
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)

            if currentStep == .messageAccess {
                Button {
                    // Skip — messages are optional
                    currentStep = .microphone
                } label: {
                    Text("Skip")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            Spacer()

            // Step dots
            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == currentStep ? Color.white : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var iconName: String {
        switch currentStep {
        case .messageAccess: return "message.fill"
        case .microphone: return "mic.fill"
        case .signIn: return "person.crop.circle.fill"
        }
    }

    private var title: String {
        switch currentStep {
        case .messageAccess: return "iMessage Access"
        case .microphone: return "Microphone"
        case .signIn: return "Sign In"
        }
    }

    private var subtitle: String {
        switch currentStep {
        case .messageAccess:
            return "Osmo reads your iMessages to help with scheduling context. Grant Full Disk Access if prompted."
        case .microphone:
            return "Voice commands need microphone access."
        case .signIn:
            return "Sign in with Google to connect your calendar and email."
        }
    }

    private var buttonTitle: String {
        switch currentStep {
        case .messageAccess: return messageAccessGranted ? "Continue" : "Check Access"
        case .microphone: return micAccessGranted ? "Continue" : "Allow Microphone"
        case .signIn: return "Sign in with Google"
        }
    }

    private func handleAction() {
        switch currentStep {
        case .messageAccess:
            if messageAccessGranted {
                currentStep = .microphone
            } else {
                checkMessageAccess()
            }
        case .microphone:
            if micAccessGranted {
                currentStep = .signIn
            } else {
                requestMicAccess()
            }
        case .signIn:
            Task {
                await authManager.signInWithGoogle()
            }
        }
    }

    private func checkMessageAccess() {
        let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        messageAccessGranted = FileManager.default.isReadableFile(atPath: chatDBPath)
        if messageAccessGranted {
            currentStep = .microphone
        } else {
            // Open System Settings > Privacy & Security > Full Disk Access
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func requestMicAccess() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            micAccessGranted = granted
            if granted {
                currentStep = .signIn
            }
        }
    }
}
