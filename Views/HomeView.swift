import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(AuthManager.self) private var authManager

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

            CosmicBackground()

            VStack(spacing: 0) {
                // Top bar with auth
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

                Spacer()

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

                Spacer()
            }
            .animation(.easeInOut(duration: 0.8), value: viewModel.hasUsedRecording)

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

            // Orb — pinned to bottom
            VStack(spacing: 0) {
                Spacer()

                ParticleOrbView(viewModel: viewModel)
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
        .task {
            // Wait for entrance animation to finish
            try? await Task.sleep(for: .seconds(3.0))
            // Rotate tips every 4 seconds (paused while response is showing)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.0))
                guard viewModel.lastSpokenResponse == nil else { continue }
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
