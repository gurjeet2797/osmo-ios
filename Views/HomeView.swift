import AVFoundation
import Speech
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboarding

    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.88
    @State private var titleBlur: CGFloat = 8
    @State private var lineWidth: CGFloat = 0
    @State private var subtitleOpacity: Double = 0
    @State private var bottomBarOpacity: Double = 0
    @State private var tipIndex: Int = 0
    @State private var tipOpacity: Double = 1.0

    private let tips: [String] = [
        "what can i help with?",
        "try: \"remind me to call mom at 5pm\"",
        "say: \"take a photo\"",
        "try: \"play some lo-fi music\"",
        "say: \"set brightness to 50%\"",
        "try: \"text Sarah i'm on my way\"",
        "say: \"what's on my calendar today?\"",
        "try: \"turn on the flashlight\"",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CosmicBackground(showComet: onboarding.isActive)

            VStack(spacing: 0) {
                // Top bar with auth — hidden during onboarding
                if !onboarding.isActive {
                    HStack {
                        Spacer()
                        if authManager.isAuthenticated {
                            Menu {
                                if let email = authManager.userEmail {
                                    Text(email)
                                }
                                Button("Sign Out", role: .destructive) {
                                    authManager.signOut()
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        } else {
                            Button {
                                Task { await authManager.signInWithGoogle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 14))
                                    Text("Sign In")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.06))
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                            }
                            .disabled(authManager.isAuthenticating)
                            .opacity(authManager.isAuthenticating ? 0.5 : 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .opacity(bottomBarOpacity)
                }

                Spacer()

                if onboarding.isActive {
                    // MARK: - Onboarding content
                    onboardingContent
                } else {
                    // MARK: - Normal greeting + tips
                    normalContent
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.8), value: viewModel.hasUsedRecording)
            .animation(.easeInOut(duration: 0.5), value: onboarding.isActive)

            // Auth error toast
            if let error = authManager.authError {
                VStack {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.3))
                                .stroke(Color.red.opacity(0.4), lineWidth: 0.5)
                        )
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Orb — always visible, particle count grows during onboarding
            VStack(spacing: 0) {
                Spacer()

                ParticleOrbView(
                    viewModel: viewModel,
                    visibleParticleCount: onboarding.isActive ? onboardingParticleCount : 0
                )
                .opacity(bottomBarOpacity)
                .padding(.bottom, -20)
            }
            .ignoresSafeArea(edges: .bottom)

            // Live transcript + status — floating above bottom
            VStack(spacing: 2) {
                Spacer()

                if viewModel.isRecording && !viewModel.liveTranscript.isEmpty {
                    Text(viewModel.liveTranscript)
                        .font(.system(size: 14, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            runEntrance()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            // Auto-advance onboarding when sign-in completes
            if isAuth && onboarding.isActive && onboarding.currentStep == .connect {
                onboarding.advance()
            }
        }
        .task {
            // Wait for entrance animation to finish
            try? await Task.sleep(for: .seconds(3.0))
            // Rotate tips every 4 seconds (paused while response is showing or onboarding)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.0))
                guard viewModel.lastSpokenResponse == nil, !onboarding.isActive else { continue }
                withAnimation(.easeOut(duration: 0.5)) {
                    tipOpacity = 0
                }
                try? await Task.sleep(for: .seconds(0.5))
                tipIndex = (tipIndex + 1) % tips.count
                withAnimation(.easeIn(duration: 0.5)) {
                    tipOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Onboarding Content

    @ViewBuilder
    private var onboardingContent: some View {
        // Title + subtitle centered
        VStack(spacing: 16) {
            Text(onboarding.titleText)
                .font(.system(size: 32, weight: .thin))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)

            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60, height: 0.5)

            Text(onboarding.subtitleText)
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .opacity(onboarding.stepOpacity)

        Spacer()

        // Button between text and orb — easy thumb reach
        if let label = onboarding.buttonLabel {
            Button {
                handleOnboardingAction()
            } label: {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.06))
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .opacity(onboarding.stepOpacity)
            .padding(.bottom, 40)
        }
    }

    /// Particle count grows evenly across onboarding steps: ~25 per step → 150 at done
    private var onboardingParticleCount: Int {
        let stepsCount = OnboardingManager.Step.allCases.count
        let perStep = 150 / stepsCount  // 25 per step
        let stepIndex = OnboardingManager.Step.allCases.firstIndex(of: onboarding.currentStep) ?? 0
        return max(perStep, perStep * (stepIndex + 1))
    }

    // MARK: - Normal Content

    @ViewBuilder
    private var normalContent: some View {
        // Personalized greeting — fades away after first recording
        if !viewModel.hasUsedRecording {
            Text(greetingText)
                .font(.system(size: 32, weight: .thin))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)
                .opacity(titleOpacity)
                .scaleEffect(titleScale)
                .blur(radius: titleBlur)
                .transition(.opacity)

            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: lineWidth, height: 0.5)
                .padding(.top, 12)
                .transition(.opacity)
        }

        // Subtitle area: LLM response (typewriter) or rotating tips
        Group {
            if viewModel.lastSpokenResponse != nil {
                Text(viewModel.displayedResponse)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .transition(.opacity)
            } else {
                Text(tips[tipIndex])
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(tipOpacity)
                    .transition(.opacity)
            }
        }
        .opacity(subtitleOpacity)
        .padding(.top, viewModel.hasUsedRecording ? 0 : 10)
        .padding(.horizontal, 32)
        .frame(minHeight: 20)
        .animation(.easeInOut(duration: 0.4), value: viewModel.lastSpokenResponse == nil)
    }

    // MARK: - Onboarding Actions

    private func handleOnboardingAction() {
        switch onboarding.currentStep {
        case .welcome, .voiceFirst:
            onboarding.advance()
        case .connect:
            Task { await authManager.signInWithGoogle() }
            // Auto-advance handled by onChange(of: authManager.isAuthenticated)
        case .microphone:
            Task {
                SFSpeechRecognizer.requestAuthorization { _ in }
                AVAudioApplication.requestRecordPermission { _ in
                    Task { @MainActor in onboarding.advance() }
                }
            }
        case .calendar:
            Task {
                _ = await EventKitManager.shared.requestAccess()
                onboarding.advance()
            }
        case .done:
            break
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        if let name = authManager.firstName {
            return "Hi, \(name)"
        }
        return "Hi there"
    }

    private func runEntrance() {
        // Title reveals with blur-to-sharp
        withAnimation(.easeOut(duration: 1.8)) {
            titleOpacity = 1
            titleScale = 1.0
            titleBlur = 0
        }

        // Line extends
        withAnimation(.easeOut(duration: 1.0).delay(0.6)) {
            lineWidth = 60
        }

        // Subtitles fade in
        withAnimation(.easeOut(duration: 0.8).delay(1.0)) {
            subtitleOpacity = 1
        }

        // Bottom bar appears last
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            bottomBarOpacity = 1
        }
    }
}
