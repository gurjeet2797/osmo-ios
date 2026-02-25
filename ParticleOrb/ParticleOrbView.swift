import SwiftUI

struct ParticleOrbView: View {
    @Bindable var viewModel: AppViewModel

    @State private var system = ParticleSystem()
    @State private var opacity: Double = 0.0
    @State private var startDate = Date()
    @State private var glowIntensity: Float = 0.0

    private let canvasSize: CGFloat = 220

    /// Target glow level based on orb phase
    private var targetGlow: Float {
        switch viewModel.orbPhase {
        case .listening, .transcribing:
            return 1.0
        default:
            return 0.0
        }
    }

    var body: some View {
        particleCanvas
            .frame(width: canvasSize, height: canvasSize)
            .opacity(opacity)
            .contentShape(Circle())
            .onTapGesture {
                handleTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                viewModel.showControlCenter = true
            }
            .onAppear {
                system.shapeRadius = 35.0
                withAnimation(.easeOut(duration: 1.2).delay(1.6)) {
                    opacity = 1.0
                }
            }
            .onChange(of: viewModel.orbPhase) { _, phase in
                switch phase {
                case .idle:
                    system.transitionToSwirl()
                case .listening:
                    system.transitionToListening()
                case .transcribing:
                    system.transitionToTranscribing()
                case .sending:
                    system.transitionToSending()
                case .success:
                    system.transitionToSuccess()
                case .error:
                    system.transitionToError()
                }
            }
    }

    // MARK: - Particle Canvas

    private var particleCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let target = targetGlow

            Canvas { context, size in
                system.update(at: time)

                // Smoothly ramp glowIntensity toward target (~0.5s ease)
                let speed: Float = 3.0 // higher = faster ramp
                let dt = Float(min(time - (system.lastFrameTime ?? time), 1.0 / 30.0))
                glowIntensity += (target - glowIntensity) * min(speed * dt, 1.0)
                let glow = Double(glowIntensity)

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let bobY = sin(elapsed * 0.6) * 2.0 + sin(elapsed * 1.1) * 1.0

                // Gradual glow multipliers
                let glowBoost = 1.0 + glow * 0.8
                let coreBoost = 1.0 + glow * 0.4

                for particle in system.particles {
                    let screenX = center.x + CGFloat(particle.position.x)
                    let screenY = center.y + CGFloat(particle.position.y) + bobY
                    let pos = CGPoint(x: screenX, y: screenY)

                    let alpha = Double(particle.brightness)
                    let revealAlpha = min(1.0, max(0.0, elapsed / 1.5))
                    let finalAlpha = alpha * revealAlpha

                    // Soft outer glow — gradually larger when glowing
                    let glowRadius = CGFloat(particle.size) * CGFloat(5.0 + glow * 2.0)
                    let glowRect = CGRect(
                        x: pos.x - glowRadius,
                        y: pos.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .radialGradient(
                            Gradient(colors: [
                                .white.opacity(finalAlpha * 0.18 * glowBoost),
                                .white.opacity(finalAlpha * 0.04 * glowBoost),
                                .clear
                            ]),
                            center: pos,
                            startRadius: 0,
                            endRadius: glowRadius
                        )
                    )

                    // Bright core — gradually intensified
                    let coreRadius = CGFloat(particle.size) * CGFloat(1.0 + glow * 0.3)
                    let coreRect = CGRect(
                        x: pos.x - coreRadius,
                        y: pos.y - coreRadius,
                        width: coreRadius * 2,
                        height: coreRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: coreRect),
                        with: .radialGradient(
                            Gradient(colors: [
                                .white.opacity(min(finalAlpha * 0.95 * coreBoost, 1.0)),
                                .white.opacity(finalAlpha * 0.3 * coreBoost),
                                .clear
                            ]),
                            center: pos,
                            startRadius: 0,
                            endRadius: coreRadius
                        )
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .colorEffect(
            ShaderLibrary.particleGlow(
                .float(Float(Date.now.timeIntervalSinceReferenceDate))
            )
        )
    }

    // MARK: - Actions

    private func handleTap() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()

        if viewModel.isRecording {
            viewModel.stopRecordingAndSend()
        } else {
            viewModel.startRecording()
        }
    }
}
