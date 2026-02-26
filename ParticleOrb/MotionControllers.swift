import Foundation

// MARK: - Motion Modulation

/// Per-frame modulation values that adjust the particle engine's parameters.
nonisolated struct MotionModulation: Sendable {
    var springStiffness: Float
    var springDamping: Float
    var noiseMultiplier: Float
    var orbitSpeedMultiplier: Float
    var breatheAmplitude: Float
    var breatheFrequency: Float
    var brightnessBase: Float
    var brightnessPulseAmp: Float
    var globalScale: Float

    /// Calm default matching current hardcoded values.
    static let idle = MotionModulation(
        springStiffness: 5.0,
        springDamping: 2.8,
        noiseMultiplier: 1.0,
        orbitSpeedMultiplier: 1.0,
        breatheAmplitude: 0.12,
        breatheFrequency: 0.5,
        brightnessBase: 0.5,
        brightnessPulseAmp: 0.15,
        globalScale: 1.0
    )
}

// MARK: - Motion Controller Protocol

nonisolated protocol MotionController: Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation
}

// MARK: - Idle Breath

/// Calm defaults that match the current hardcoded particle behavior.
nonisolated struct IdleBreath: MotionController, Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        .idle
    }
}

// MARK: - Listening Pulse

/// Tighter spring, reduced noise, 3Hz amplitude pulse for active listening.
nonisolated struct ListeningPulse: MotionController, Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        let pulse = 0.5 + 0.5 * sin(time * 3.0 * 2.0 * Float.pi)
        return MotionModulation(
            springStiffness: 7.0,
            springDamping: 3.2,
            noiseMultiplier: 0.4,
            orbitSpeedMultiplier: 0.6,
            breatheAmplitude: 0.08 + 0.06 * pulse,
            breatheFrequency: 0.8,
            brightnessBase: 0.6 + 0.15 * pulse,
            brightnessPulseAmp: 0.2,
            globalScale: 1.0
        )
    }
}

// MARK: - Thinking Spin

/// Stateful: randomizes target angular velocity every 1.5-3s, smoothly converges.
nonisolated final class ThinkingSpin: MotionController, @unchecked Sendable {
    private var targetOrbitSpeed: Float = 1.8
    private var currentOrbitSpeed: Float = 1.0
    private var nextChangeTime: Float = 0

    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        // Periodically pick a new target angular velocity
        if time >= nextChangeTime {
            targetOrbitSpeed = Float.random(in: 1.2...2.8) * (Bool.random() ? 1.0 : -1.0)
            nextChangeTime = time + Float.random(in: 1.5...3.0)
        }

        // Smooth convergence (no jitter)
        let convergenceRate: Float = 2.0
        currentOrbitSpeed += (targetOrbitSpeed - currentOrbitSpeed) * min(convergenceRate * dt, 1.0)

        return MotionModulation(
            springStiffness: 6.0,
            springDamping: 3.0,
            noiseMultiplier: 0.6,
            orbitSpeedMultiplier: abs(currentOrbitSpeed),
            breatheAmplitude: 0.06,
            breatheFrequency: 0.8,
            brightnessBase: 0.55,
            brightnessPulseAmp: 0.1,
            globalScale: 1.0
        )
    }
}

// MARK: - Success Pop

/// Soft spring, brightness burst that fades, sine-wave scale pop.
nonisolated struct SuccessPop: MotionController, Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        // stateProgress goes 0..1 over the success duration
        let pop = max(0, 1.0 - stateProgress * 2.0)  // burst in first half
        let scalePop = 1.0 + 0.12 * sin(stateProgress * Float.pi) // single sine arch
        let brightBurst = 0.3 * pop

        return MotionModulation(
            springStiffness: 4.0,
            springDamping: 2.5,
            noiseMultiplier: 0.8,
            orbitSpeedMultiplier: 0.8,
            breatheAmplitude: 0.1,
            breatheFrequency: 0.5,
            brightnessBase: 0.6 + brightBurst,
            brightnessPulseAmp: 0.1,
            globalScale: scalePop
        )
    }
}

// MARK: - Caution Wobble

/// Lateral oscillation via breathe modulation.
nonisolated struct CautionWobble: MotionController, Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        let wobble = sin(time * 4.0) * 0.08
        return MotionModulation(
            springStiffness: 5.5,
            springDamping: 2.8,
            noiseMultiplier: 0.7,
            orbitSpeedMultiplier: 0.5,
            breatheAmplitude: 0.1 + wobble,
            breatheFrequency: 2.0,
            brightnessBase: 0.55,
            brightnessPulseAmp: 0.12,
            globalScale: 1.0
        )
    }
}

// MARK: - Error Shake

/// High-frequency shake that decays, tight spring.
nonisolated struct ErrorShake: MotionController, Sendable {
    func modulate(time: Float, dt: Float, stateProgress: Float) -> MotionModulation {
        let decay = max(0, 1.0 - stateProgress * 1.5) // decays over ~67% of duration
        let shake = sin(time * 25.0) * 0.04 * decay

        return MotionModulation(
            springStiffness: 8.0,
            springDamping: 3.5,
            noiseMultiplier: 1.2 * decay,
            orbitSpeedMultiplier: 0.3 + 0.7 * (1.0 - decay),
            breatheAmplitude: 0.05 + shake,
            breatheFrequency: 1.0,
            brightnessBase: 0.4 + 0.2 * decay,
            brightnessPulseAmp: 0.2 * decay,
            globalScale: 1.0 + shake
        )
    }
}

// MARK: - Motion Controller Registry

/// Static factory for motion controllers. Maintains singleton ThinkingSpin instance.
nonisolated enum MotionControllerRegistry: Sendable {

    private static let thinkingSpin = ThinkingSpin()

    static func controller(for state: MotionState) -> any MotionController {
        switch state {
        case .idle:       return IdleBreath()
        case .armed:      return ListeningPulse()  // armed uses listening-like tightening
        case .listening:  return ListeningPulse()
        case .thinking:   return thinkingSpin
        case .success:    return SuccessPop()
        case .caution:    return CautionWobble()
        case .error:      return ErrorShake()
        case .cancelled:  return IdleBreath()
        }
    }
}
