import SwiftUI

struct FloatingStar: Identifiable {
    let id: Int
    /// Normalized 0...1 position, scaled to canvas size at draw time
    let normalizedPosition: CGPoint
    let size: CGFloat
    let brightness: CGFloat
    let pulseSpeed: CGFloat
    let pulsePhase: CGFloat
    let driftAngle: CGFloat
    let driftSpeed: CGFloat
    let hue: CGFloat
    let revealDelay: Double
}

struct CometParticle {
    var position: CGPoint = CGPoint(x: -100, y: -100)
    var velocity: CGPoint = CGPoint(x: 40, y: 20)
    var trail: [CGPoint] = []
    var noiseOffset1: CGFloat = CGFloat.random(in: 0...1000)
    var noiseOffset2: CGFloat = CGFloat.random(in: 0...1000)
    var breathPhase: CGFloat = CGFloat.random(in: 0...(.pi * 2))
    private static let trailLength = 12

    mutating func update(dt: CGFloat, canvasSize: CGSize, time: Double) {
        // Multi-octave sine noise for organic direction changes
        let n1 = sin(noiseOffset1 + CGFloat(time) * 0.7) * 0.6
            + sin(noiseOffset2 + CGFloat(time) * 1.3) * 0.3
            + sin(noiseOffset1 * 0.5 + CGFloat(time) * 2.1) * 0.1
        let n2 = cos(noiseOffset2 + CGFloat(time) * 0.5) * 0.6
            + cos(noiseOffset1 + CGFloat(time) * 1.1) * 0.3
            + cos(noiseOffset2 * 0.5 + CGFloat(time) * 1.9) * 0.1

        // Breathing speed variation: 20–80 pts/sec
        let breathSpeed = 50 + 30 * sin(breathPhase + CGFloat(time) * 0.4)

        // Steer velocity toward noise direction
        let targetVx = n1 * breathSpeed
        let targetVy = n2 * breathSpeed
        velocity.x += (targetVx - velocity.x) * dt * 2.0
        velocity.y += (targetVy - velocity.y) * dt * 2.0

        position.x += velocity.x * dt
        position.y += velocity.y * dt

        // Screen edge wrapping with margin
        let margin: CGFloat = 20
        if position.x < -margin { position.x = canvasSize.width + margin }
        if position.x > canvasSize.width + margin { position.x = -margin }
        if position.y < -margin { position.y = canvasSize.height + margin }
        if position.y > canvasSize.height + margin { position.y = -margin }

        // Update trail
        trail.append(position)
        if trail.count > Self.trailLength {
            trail.removeFirst(trail.count - Self.trailLength)
        }
    }

    func draw(context: GraphicsContext) {
        // Draw trail: decreasing opacity and size
        for (i, point) in trail.enumerated() {
            let progress = CGFloat(i) / CGFloat(max(trail.count - 1, 1))
            let alpha = 0.4 * (1.0 - progress)
            let radius = 0.5 + 2.5 * (1.0 - progress)
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(.white.opacity(alpha))
            )
        }

        // Draw head glow: cyan-tinted
        let glowRadius: CGFloat = 12
        let glowRect = CGRect(
            x: position.x - glowRadius,
            y: position.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hue: 0.52, saturation: 0.4, brightness: 1.0).opacity(0.25),
                    Color(hue: 0.52, saturation: 0.3, brightness: 1.0).opacity(0.08),
                    .clear,
                ]),
                center: position,
                startRadius: 0,
                endRadius: glowRadius
            )
        )

        // Draw head core: bright white
        let coreRadius: CGFloat = 4
        let coreRect = CGRect(
            x: position.x - coreRadius,
            y: position.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        )
        context.fill(
            Path(ellipseIn: coreRect),
            with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.9),
                    .white.opacity(0.3),
                    .clear,
                ]),
                center: position,
                startRadius: 0,
                endRadius: coreRadius
            )
        )
    }
}

struct CosmicBackground: View {
    var showComet: Bool = false

    @State private var stars: [FloatingStar] = CosmicBackground.makeStars()
    @State private var touchPoint: CGPoint? = nil
    @State private var touchInfluence: CGFloat = 0
    @State private var startDate = Date()
    @State private var isInteracting: Bool = false
    @State private var comet = CometParticle()
    @State private var cometVisible: Bool = false
    @State private var lastCometTime: Date = .distantPast
    @State private var previousTimelineDate: Date?

    private static let starCount = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: isInteracting || cometVisible ? 1.0 / 60.0 : 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = timeline.date.timeIntervalSince(startDate)

            Canvas { context, canvasSize in
                context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.black))

                drawNebulaClouds(context: context, size: canvasSize, time: t)

                let positions = computePositions(canvasSize: canvasSize, time: t)

                for i in 0..<stars.count {
                    let star = stars[i]
                    let revealAlpha = min(1.0, max(0.0, (elapsed - star.revealDelay) / 0.6))
                    if revealAlpha > 0 {
                        drawStar(context: context, star: star, position: positions[i], time: t, revealAlpha: CGFloat(revealAlpha))
                    }
                }

                if let touch = touchPoint, touchInfluence > 0.01 {
                    drawTouchGlow(context: context, center: touch)
                }

                drawConstellationLines(context: context, positions: positions, time: t, elapsed: elapsed)

                if cometVisible {
                    comet.draw(context: context)
                }
            }
            .onChange(of: timeline.date) { _, newDate in
                updateComet(canvasDate: newDate, time: t)
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        touchPoint = value.location
                        isInteracting = true
                        withAnimation(.easeIn(duration: 0.2)) {
                            touchInfluence = 1.0
                        }
                    }
                    .onEnded { _ in
                        isInteracting = false
                        withAnimation(.easeOut(duration: 0.8)) {
                            touchInfluence = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                            if touchInfluence < 0.01 {
                                touchPoint = nil
                            }
                        }
                    }
            )
        }
        .visualEffect { content, proxy in
            content.colorEffect(
                ShaderLibrary.auroraWash(
                    .float2(Float(proxy.size.width), Float(proxy.size.height)),
                    .float(Float(Date.now.timeIntervalSinceReferenceDate))
                )
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Star Positions

    private func computePositions(canvasSize: CGSize, time: Double) -> [CGPoint] {
        stars.map { star in
            let baseX = star.normalizedPosition.x * canvasSize.width
            let baseY = star.normalizedPosition.y * canvasSize.height
            let driftX = cos(CGFloat(time) * star.driftSpeed + star.driftAngle) * 2.0
            let driftY = sin(CGFloat(time) * star.driftSpeed * 0.7 + star.driftAngle) * 2.0
            var pos = CGPoint(x: baseX + driftX, y: baseY + driftY)

            if let touch = touchPoint, touchInfluence > 0.01 {
                let dx = pos.x - touch.x
                let dy = pos.y - touch.y
                let dist = sqrt(dx * dx + dy * dy)
                let influence: CGFloat = 150
                if dist < influence && dist > 0 {
                    let t = 1.0 - dist / influence
                    let force = t * t * 40 * touchInfluence
                    pos.x += (dx / dist) * force
                    pos.y += (dy / dist) * force
                }
            }

            return pos
        }
    }

    // MARK: - Drawing

    private func drawNebulaClouds(context: GraphicsContext, size: CGSize, time: Double) {
        for i in 0..<3 {
            let fi = CGFloat(i)
            let centerX = size.width * (0.3 + 0.4 * CGFloat(sin(time * 0.05 + Double(fi) * 2.0)))
            let centerY = size.height * (0.2 + 0.6 * CGFloat(cos(time * 0.04 + Double(fi) * 1.5)))
            let radius = size.width * (0.3 + 0.1 * CGFloat(sin(time * 0.08 + Double(fi))))

            let colors: [Color] = [
                Color(red: 0.15, green: 0.05, blue: 0.3).opacity(0.08),
                Color(red: 0.05, green: 0.1, blue: 0.25).opacity(0.04),
                Color.clear
            ]

            let center = CGPoint(x: centerX, y: centerY)
            context.fill(
                Path(ellipseIn: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(Gradient(colors: colors), center: center, startRadius: 0, endRadius: radius)
            )
        }
    }

    private func drawStar(context: GraphicsContext, star: FloatingStar, position pos: CGPoint, time: Double, revealAlpha: CGFloat) {
        let pulse = CGFloat(sin(time * Double(star.pulseSpeed) + Double(star.pulsePhase))) * 0.35 + 0.65
        let alpha = star.brightness * pulse * revealAlpha

        let glowRadius = star.size * 6 * pulse
        let glowRect = CGRect(
            x: pos.x - glowRadius,
            y: pos.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )

        let hueColor = Color(hue: Double(star.hue), saturation: 0.3, brightness: 1.0)
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    hueColor.opacity(Double(alpha) * 0.12),
                    hueColor.opacity(Double(alpha) * 0.04),
                    .clear
                ]),
                center: pos,
                startRadius: 0,
                endRadius: glowRadius
            )
        )

        let coreRadius = star.size * 1.5 * pulse
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
                    .white.opacity(Double(alpha)),
                    .white.opacity(Double(alpha) * 0.3),
                    .clear
                ]),
                center: pos,
                startRadius: 0,
                endRadius: coreRadius
            )
        )
    }

    private func drawTouchGlow(context: GraphicsContext, center: CGPoint) {
        let radius: CGFloat = 60 * touchInfluence
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hue: 0.65, saturation: 0.3, brightness: 1.0).opacity(0.08 * Double(touchInfluence)),
                    Color(hue: 0.65, saturation: 0.3, brightness: 1.0).opacity(0.02 * Double(touchInfluence)),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func drawConstellationLines(context: GraphicsContext, positions: [CGPoint], time: Double, elapsed: Double) {
        let constellationAlpha = min(1.0, max(0.0, (elapsed - 2.0) / 1.0))
        guard constellationAlpha > 0 else { return }

        let threshold: CGFloat = 100
        let count = positions.count
        for i in 0..<count {
            for j in (i + 1)..<min(count, i + 8) {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < threshold {
                    let alpha = (1.0 - dist / threshold) * 0.08 * constellationAlpha
                    var path = Path()
                    path.move(to: positions[i])
                    path.addLine(to: positions[j])
                    context.stroke(
                        path,
                        with: .color(.white.opacity(alpha)),
                        lineWidth: 0.3
                    )
                }
            }
        }
    }

    // MARK: - Comet

    private func updateComet(canvasDate: Date, time: Double) {
        let prev = previousTimelineDate ?? canvasDate
        let dt = CGFloat(canvasDate.timeIntervalSince(prev))
        previousTimelineDate = canvasDate

        guard dt > 0, dt < 0.5 else { return }

        if showComet && !cometVisible {
            spawnComet(canvasSize: nil, time: time)
        }

        if !showComet && !cometVisible {
            // Occasional random bursts during normal use
            let sinceLastComet = canvasDate.timeIntervalSince(lastCometTime)
            if sinceLastComet > Double.random(in: 30...60) {
                spawnComet(canvasSize: nil, time: time)
            }
        }

        if cometVisible {
            // Use a reasonable default canvas size for wrapping
            let screenBounds = UIScreen.main.bounds
            comet.update(dt: dt, canvasSize: screenBounds.size, time: time)
        }
    }

    private func spawnComet(canvasSize: CGSize?, time: Double) {
        let bounds = canvasSize ?? UIScreen.main.bounds.size
        comet = CometParticle()
        comet.position = CGPoint(
            x: CGFloat.random(in: 0...bounds.width),
            y: CGFloat.random(in: 0...bounds.height)
        )
        cometVisible = true
        lastCometTime = Date()

        // Auto-hide after burst duration (10s) if not in persistent showComet mode
        if !showComet {
            Task {
                try? await Task.sleep(for: .seconds(10))
                cometVisible = false
            }
        }
    }

    // MARK: - Star Generation

    private static func makeStars() -> [FloatingStar] {
        (0..<starCount).map { i in
            FloatingStar(
                id: i,
                normalizedPosition: CGPoint(
                    x: CGFloat.random(in: 0...1),
                    y: CGFloat.random(in: 0...1)
                ),
                size: CGFloat.random(in: 0.6...2.8),
                brightness: CGFloat.random(in: 0.3...1.0),
                pulseSpeed: CGFloat.random(in: 0.5...2.5),
                pulsePhase: CGFloat.random(in: 0...(.pi * 2)),
                driftAngle: CGFloat.random(in: 0...(.pi * 2)),
                driftSpeed: CGFloat.random(in: 0.1...0.5),
                hue: CGFloat.random(in: 0.55...0.75),
                revealDelay: Double.random(in: 0...2.5)
            )
        }
    }
}

struct ConstellationBackground: View {
    var body: some View {
        CosmicBackground()
    }
}
