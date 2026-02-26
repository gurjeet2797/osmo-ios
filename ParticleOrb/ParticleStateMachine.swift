import Foundation

// MARK: - Motion State

/// Richer motion states that map from OrbPhase. Drives per-state motion controllers.
nonisolated enum MotionState: Equatable, Sendable {
    case idle
    case armed       // touch-down visual tightening
    case listening
    case thinking
    case success
    case caution
    case error
    case cancelled
}

// MARK: - Transition Phase

nonisolated enum TransitionPhase: Equatable, Sendable {
    case anticipation  // squeeze before action
    case action        // main transition
    case settle        // overshoot/settle after action
    case complete
}

// MARK: - Transition Envelope

/// Defines the 3-phase transition timing: anticipation -> action -> settle.
nonisolated struct TransitionEnvelope: Sendable {
    let anticipationDuration: Double
    let actionDuration: Double
    let settleDuration: Double
    let anticipationScale: Float  // squeeze factor (< 1.0 = squeeze)
    let settleOvershoot: Float    // overshoot factor (> 1.0 = overshoot)

    var totalDuration: Double {
        anticipationDuration + actionDuration + settleDuration
    }

    // MARK: - Presets

    static let `default` = TransitionEnvelope(
        anticipationDuration: 0.08,
        actionDuration: 0.35,
        settleDuration: 0.15,
        anticipationScale: 0.92,
        settleOvershoot: 1.06
    )

    static let quick = TransitionEnvelope(
        anticipationDuration: 0.04,
        actionDuration: 0.2,
        settleDuration: 0.1,
        anticipationScale: 0.95,
        settleOvershoot: 1.03
    )

    static let emphatic = TransitionEnvelope(
        anticipationDuration: 0.12,
        actionDuration: 0.4,
        settleDuration: 0.25,
        anticipationScale: 0.85,
        settleOvershoot: 1.12
    )
}

// MARK: - Particle State Machine

nonisolated final class ParticleStateMachine: @unchecked Sendable {

    private(set) var currentState: MotionState = .idle
    private(set) var previousState: MotionState = .idle

    private var transitionStartTime: Double = 0
    private var currentEnvelope: TransitionEnvelope = .default
    private var isTransitioning: Bool = false

    // MARK: - Envelope Scale

    /// Computed scale multiplier: squeeze during anticipation, overshoot during settle, 1.0 otherwise.
    var envelopeScale: Float {
        guard isTransitioning else { return 1.0 }
        return _lastEnvelopeScale
    }

    private var _lastEnvelopeScale: Float = 1.0

    // MARK: - Transition

    func transition(to state: MotionState, at time: Double, envelope: TransitionEnvelope = .default) {
        guard state != currentState else { return }
        previousState = currentState
        currentState = state
        currentEnvelope = envelope
        transitionStartTime = time
        isTransitioning = true
        _lastEnvelopeScale = envelope.anticipationScale
    }

    /// Advance the envelope each frame. Returns the current phase.
    func update(at time: Double) -> TransitionPhase {
        guard isTransitioning else { return .complete }

        let elapsed = time - transitionStartTime
        let env = currentEnvelope

        if elapsed < env.anticipationDuration {
            // Anticipation: squeeze
            let t = Float(elapsed / max(env.anticipationDuration, 0.001))
            _lastEnvelopeScale = 1.0 + (env.anticipationScale - 1.0) * t
            return .anticipation

        } else if elapsed < env.anticipationDuration + env.actionDuration {
            // Action: lerp from anticipation scale back toward 1.0
            let actionElapsed = elapsed - env.anticipationDuration
            let t = Float(actionElapsed / max(env.actionDuration, 0.001))
            _lastEnvelopeScale = env.anticipationScale + (1.0 - env.anticipationScale) * t
            return .action

        } else if elapsed < env.totalDuration {
            // Settle: overshoot then converge to 1.0
            let settleElapsed = elapsed - env.anticipationDuration - env.actionDuration
            let t = Float(settleElapsed / max(env.settleDuration, 0.001))
            // Damped sine for settle
            let overshoot = env.settleOvershoot - 1.0
            let decay = (1.0 - t)
            _lastEnvelopeScale = 1.0 + overshoot * decay * sin(t * Float.pi)
            return .settle

        } else {
            // Complete
            _lastEnvelopeScale = 1.0
            isTransitioning = false
            return .complete
        }
    }

    // MARK: - OrbPhase Mapping

    /// Maps an OrbPhase to a MotionState with an appropriate transition envelope.
    static func motionState(
        for orbPhase: AppViewModel.OrbPhase,
        previous: AppViewModel.OrbPhase
    ) -> (MotionState, TransitionEnvelope) {
        switch orbPhase {
        case .idle:
            return (.idle, .default)
        case .listening:
            return (.listening, .default)
        case .transcribing:
            return (.thinking, .default)
        case .sending:
            return (.thinking, .quick)
        case .success:
            return (.success, .emphatic)
        case .error:
            return (.error, .emphatic)
        }
    }
}
