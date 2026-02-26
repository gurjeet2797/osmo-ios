import CoreGraphics
import simd

// MARK: - Shape Provider Protocol

nonisolated protocol ParticleShapeProvider {
    var id: ShapeID { get }
    func targetPositions(count: Int, radius: Float) -> [SIMD2<Float>]
}

// MARK: - Path Sampler

/// Samples evenly-distributed points along any CGPath.
nonisolated enum PathSampler {

    static func sample(path: CGPath, count: Int, fitRadius: Float) -> [SIMD2<Float>] {
        let segments = extractSegments(from: path)
        guard !segments.isEmpty, count > 0 else { return [] }

        // Cumulative arc lengths
        var cumulative: [Float] = [0]
        for seg in segments {
            let dx = seg.end.x - seg.start.x
            let dy = seg.end.y - seg.start.y
            let len = sqrt(dx * dx + dy * dy)
            cumulative.append(cumulative.last! + len)
        }
        let totalLength = cumulative.last!
        guard totalLength > 0 else { return [] }

        // Sample at equal intervals
        var points: [SIMD2<Float>] = []
        for i in 0..<count {
            let targetDist = (Float(i) / Float(count)) * totalLength
            let segIndex = findSegment(cumulative: cumulative, distance: targetDist)
            let segStart = cumulative[segIndex]
            let segLength = cumulative[segIndex + 1] - segStart
            let t = segLength > 0.001 ? (targetDist - segStart) / segLength : 0
            let seg = segments[segIndex]
            let x = seg.start.x + t * (seg.end.x - seg.start.x)
            let y = seg.start.y + t * (seg.end.y - seg.start.y)
            points.append(SIMD2<Float>(x, y))
        }

        // Normalize to fit within radius centered at origin
        return normalizePoints(points, fitRadius: fitRadius)
    }

    private struct Segment {
        let start: SIMD2<Float>
        let end: SIMD2<Float>
    }

    private static func extractSegments(from path: CGPath) -> [Segment] {
        var segments: [Segment] = []
        var current = SIMD2<Float>.zero
        var subpathStart = SIMD2<Float>.zero

        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                let p = SIMD2<Float>(Float(element.points[0].x), Float(element.points[0].y))
                current = p
                subpathStart = p

            case .addLineToPoint:
                let p = SIMD2<Float>(Float(element.points[0].x), Float(element.points[0].y))
                segments.append(Segment(start: current, end: p))
                current = p

            case .addQuadCurveToPoint:
                let cp = SIMD2<Float>(Float(element.points[0].x), Float(element.points[0].y))
                let end = SIMD2<Float>(Float(element.points[1].x), Float(element.points[1].y))
                let subdivisions = 16
                var prev = current
                for s in 1...subdivisions {
                    let t = Float(s) / Float(subdivisions)
                    let oneMinusT = 1.0 - t
                    let pt = oneMinusT * oneMinusT * current + 2.0 * oneMinusT * t * cp + t * t * end
                    segments.append(Segment(start: prev, end: pt))
                    prev = pt
                }
                current = end

            case .addCurveToPoint:
                let cp1 = SIMD2<Float>(Float(element.points[0].x), Float(element.points[0].y))
                let cp2 = SIMD2<Float>(Float(element.points[1].x), Float(element.points[1].y))
                let end = SIMD2<Float>(Float(element.points[2].x), Float(element.points[2].y))
                let subdivisions = 16
                var prev = current
                for s in 1...subdivisions {
                    let t = Float(s) / Float(subdivisions)
                    let oneMinusT = 1.0 - t
                    let pt = oneMinusT * oneMinusT * oneMinusT * current
                        + 3.0 * oneMinusT * oneMinusT * t * cp1
                        + 3.0 * oneMinusT * t * t * cp2
                        + t * t * t * end
                    segments.append(Segment(start: prev, end: pt))
                    prev = pt
                }
                current = end

            case .closeSubpath:
                if simd_distance(current, subpathStart) > 0.001 {
                    segments.append(Segment(start: current, end: subpathStart))
                }
                current = subpathStart

            @unknown default:
                break
            }
        }

        return segments
    }

    private static func findSegment(cumulative: [Float], distance: Float) -> Int {
        var lo = 0
        var hi = cumulative.count - 2
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid + 1] < distance {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    /// Sample points along a path with an optional Y anchor offset applied after normalization.
    static func sampleWithAnchor(path: CGPath, count: Int, fitRadius: Float, anchorY: Float = 0) -> [SIMD2<Float>] {
        var points = sample(path: path, count: count, fitRadius: fitRadius)
        if anchorY != 0 {
            for i in points.indices {
                points[i].y += anchorY
            }
        }
        return points
    }

    private static func normalizePoints(_ points: [SIMD2<Float>], fitRadius: Float) -> [SIMD2<Float>] {
        guard !points.isEmpty else { return points }

        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude

        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        let w = maxX - minX
        let h = maxY - minY
        let maxDim = max(w, h, 0.001)
        let scale = (fitRadius * 2.0) / maxDim
        let centerX = (minX + maxX) / 2.0
        let centerY = (minY + maxY) / 2.0

        return points.map { p in
            SIMD2<Float>(
                (p.x - centerX) * scale,
                (p.y - centerY) * scale
            )
        }
    }
}

// MARK: - SVG Path Parser

/// Minimal SVG path `d` attribute parser. Supports: M, L, H, V, C, Q, Z (and lowercase).
nonisolated enum SVGPathParser {
    static func parse(_ d: String) -> CGPath? {
        let path = CGMutablePath()
        let chars = Array(d)
        var index = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0

        func skipWhitespaceAndCommas() {
            while index < chars.count && (chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\r" || chars[index] == "\t") {
                index += 1
            }
        }

        func parseNumber() -> CGFloat? {
            skipWhitespaceAndCommas()
            guard index < chars.count else { return nil }

            var numStr = ""
            if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
                numStr.append(chars[index])
                index += 1
            }

            var hasDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    numStr.append(c)
                    index += 1
                } else if c == "." && !hasDot {
                    hasDot = true
                    numStr.append(c)
                    index += 1
                } else {
                    break
                }
            }

            // Handle exponent (e.g., 1e-5)
            if index < chars.count && (chars[index] == "e" || chars[index] == "E") {
                numStr.append(chars[index])
                index += 1
                if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
                    numStr.append(chars[index])
                    index += 1
                }
                while index < chars.count && chars[index].isNumber {
                    numStr.append(chars[index])
                    index += 1
                }
            }

            return numStr.isEmpty ? nil : CGFloat(Double(numStr) ?? 0)
        }

        while index < chars.count {
            skipWhitespaceAndCommas()
            guard index < chars.count else { break }

            let cmd = chars[index]
            guard cmd.isLetter else { index += 1; continue }
            index += 1

            switch cmd {
            case "M":
                guard let x = parseNumber(), let y = parseNumber() else { break }
                currentX = x; currentY = y
                startX = x; startY = y
                path.move(to: CGPoint(x: x, y: y))
                // Subsequent coordinate pairs are implicit lineTo
                while let x = parseNumber(), let y = parseNumber() {
                    currentX = x; currentY = y
                    path.addLine(to: CGPoint(x: x, y: y))
                }

            case "m":
                guard let dx = parseNumber(), let dy = parseNumber() else { break }
                currentX += dx; currentY += dy
                startX = currentX; startY = currentY
                path.move(to: CGPoint(x: currentX, y: currentY))
                while let dx = parseNumber(), let dy = parseNumber() {
                    currentX += dx; currentY += dy
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "L":
                while let x = parseNumber(), let y = parseNumber() {
                    currentX = x; currentY = y
                    path.addLine(to: CGPoint(x: x, y: y))
                }

            case "l":
                while let dx = parseNumber(), let dy = parseNumber() {
                    currentX += dx; currentY += dy
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "H":
                while let x = parseNumber() {
                    currentX = x
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "h":
                while let dx = parseNumber() {
                    currentX += dx
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "V":
                while let y = parseNumber() {
                    currentY = y
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "v":
                while let dy = parseNumber() {
                    currentY += dy
                    path.addLine(to: CGPoint(x: currentX, y: currentY))
                }

            case "C":
                while let x1 = parseNumber(), let y1 = parseNumber(),
                      let x2 = parseNumber(), let y2 = parseNumber(),
                      let x = parseNumber(), let y = parseNumber() {
                    path.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: x1, y: y1),
                        control2: CGPoint(x: x2, y: y2)
                    )
                    currentX = x; currentY = y
                }

            case "c":
                while let dx1 = parseNumber(), let dy1 = parseNumber(),
                      let dx2 = parseNumber(), let dy2 = parseNumber(),
                      let dx = parseNumber(), let dy = parseNumber() {
                    path.addCurve(
                        to: CGPoint(x: currentX + dx, y: currentY + dy),
                        control1: CGPoint(x: currentX + dx1, y: currentY + dy1),
                        control2: CGPoint(x: currentX + dx2, y: currentY + dy2)
                    )
                    currentX += dx; currentY += dy
                }

            case "Q":
                while let x1 = parseNumber(), let y1 = parseNumber(),
                      let x = parseNumber(), let y = parseNumber() {
                    path.addQuadCurve(
                        to: CGPoint(x: x, y: y),
                        control: CGPoint(x: x1, y: y1)
                    )
                    currentX = x; currentY = y
                }

            case "q":
                while let dx1 = parseNumber(), let dy1 = parseNumber(),
                      let dx = parseNumber(), let dy = parseNumber() {
                    path.addQuadCurve(
                        to: CGPoint(x: currentX + dx, y: currentY + dy),
                        control: CGPoint(x: currentX + dx1, y: currentY + dy1)
                    )
                    currentX += dx; currentY += dy
                }

            case "Z", "z":
                path.closeSubpath()
                currentX = startX; currentY = startY

            default:
                break
            }
        }

        return path
    }
}

// MARK: - Built-in Shapes

nonisolated struct OrbitShape: ParticleShapeProvider {
    let id: ShapeID = .orbit

    func targetPositions(count: Int, radius: Float) -> [SIMD2<Float>] {
        (0..<count).map { i in
            let angle = Float(i) / Float(count) * 2 * .pi
            let ring = Float(i % 3)
            let r = radius * (0.6 + ring * 0.25) + Float.random(in: -3...3)
            return SIMD2<Float>(cos(angle) * r, sin(angle) * r)
        }
    }
}

nonisolated struct MicrophoneShape: ParticleShapeProvider {
    let id: ShapeID = .microphone

    func targetPositions(count: Int, radius: Float) -> [SIMD2<Float>] {
        // Cute microphone — thinner lines, taller, well-spaced parts
        let path = CGMutablePath()
        let r = CGFloat(radius)

        // Capsule body — narrower, taller, filled with fewer concentric layers
        let bodyW: CGFloat = r * 0.5
        let bodyH: CGFloat = r * 0.9
        let bodyTop: CGFloat = -r * 0.75
        for inset in stride(from: CGFloat(0), through: bodyW * 0.35, by: 3.0) {
            let w = bodyW - inset
            let h = bodyH - inset * (bodyH / bodyW)
            guard w > 0, h > 0 else { break }
            path.addRoundedRect(
                in: CGRect(x: -w / 2, y: bodyTop + inset * 0.5, width: w, height: h),
                cornerWidth: w / 2,
                cornerHeight: w / 2
            )
        }

        // U-shaped cradle — thinner arms, more gap below body
        let cradleW: CGFloat = r * 0.42
        let gap: CGFloat = r * 0.12
        let cradleTop: CGFloat = bodyTop + bodyH * 0.55 + gap
        let cradleBot: CGFloat = cradleTop + r * 0.28
        let armThick: CGFloat = r * 0.06
        // Left arm
        path.addRect(CGRect(x: -cradleW - armThick / 2, y: cradleTop, width: armThick, height: cradleBot - cradleTop))
        // Right arm
        path.addRect(CGRect(x: cradleW - armThick / 2, y: cradleTop, width: armThick, height: cradleBot - cradleTop))
        // Bottom arc (thinner — 2 strokes)
        for offset in stride(from: -armThick * 0.4, through: armThick * 0.4, by: armThick * 0.4) {
            let arcR = cradleW + offset
            path.move(to: CGPoint(x: -arcR, y: cradleBot))
            path.addArc(
                center: CGPoint(x: 0, y: cradleBot),
                radius: arcR,
                startAngle: .pi,
                endAngle: 0,
                clockwise: true
            )
        }

        // Stem — thin, with gap below cradle
        let stemGap: CGFloat = r * 0.08
        let stemTop = cradleBot + cradleW + stemGap
        let stemBot = stemTop + r * 0.2
        let stemW: CGFloat = r * 0.05
        path.addRect(CGRect(x: -stemW / 2, y: stemTop, width: stemW, height: stemBot - stemTop))

        // Base — thin horizontal line with gap
        let baseGap: CGFloat = r * 0.06
        let baseY = stemBot + baseGap
        let baseW: CGFloat = r * 0.4
        let baseH: CGFloat = r * 0.045
        path.addRoundedRect(
            in: CGRect(x: -baseW / 2, y: baseY, width: baseW, height: baseH),
            cornerWidth: baseH / 2,
            cornerHeight: baseH / 2
        )

        return PathSampler.sample(path: path, count: count, fitRadius: radius)
    }
}

// MARK: - Shape Registry

nonisolated enum ShapeRegistry {
    private nonisolated(unsafe) static let providers: [ShapeID: any ParticleShapeProvider] = [
        .orbit: OrbitShape(),
        .microphone: MicrophoneShape(),
    ]

    static func targets(for shapeID: ShapeID, count: Int, radius: Float) -> [SIMD2<Float>] {
        guard let provider = providers[shapeID] else {
            return OrbitShape().targetPositions(count: count, radius: radius)
        }
        return provider.targetPositions(count: count, radius: radius)
    }

    /// Generate target positions from arbitrary SVG path data.
    static func fromSVG(_ svgPathData: String, count: Int, radius: Float) -> [SIMD2<Float>] {
        guard let path = SVGPathParser.parse(svgPathData) else { return [] }
        return PathSampler.sample(path: path, count: count, fitRadius: radius)
    }
}
