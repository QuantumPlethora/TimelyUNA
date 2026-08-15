import SwiftUI

/// Canvas visualization of Earth, apparent Sun, actual Sun, and optional rocket flight.
/// Labels are clamped inside the frame; the SwiftUI host reserves the title/badge band above.
struct SunCanvasView: View {
    var rocketProgress: Double = 0
    var showRocket: Bool = false
    var showHit: Bool = false
    /// When false, title/subtitle are drawn by the host (preferred on compact iPhone).
    var drawsChromeLabels: Bool = false

    private let stars: [Star] = Star.makeField(count: 180)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
            Canvas { context, size in
                drawScene(context: context, size: size, time: timeline.date)
            }
        }
        .background(Color.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Live simulation. Earth, Apparent Sun, Actual Sun, eight minute light delay, and true direction."
        )
    }

    private func drawScene(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height
        // Reserve top band so scene markers never sit under host chrome labels.
        let topReserve: CGFloat = drawsChromeLabels ? max(48, h * 0.14) : max(12, h * 0.04)
        let bottomReserve: CGFloat = max(20, h * 0.06)
        let sidePad: CGFloat = max(10, w * 0.03)
        let plot = CGRect(
            x: sidePad,
            y: topReserve,
            width: max(1, w - sidePad * 2),
            height: max(1, h - topReserve - bottomReserve)
        )

        let scaleX = plot.width / 720
        let scaleY = plot.height / 420
        let s = min(scaleX, scaleY)
        // Prefer slightly larger labels on small phones without shrinking the scene too far.
        let labelScale = max(0.85, min(1.15, s / 0.45))

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: plot.minX + x * scaleX, y: plot.minY + y * scaleY)
        }

        // Stars (full frame, decorative)
        for star in stars {
            var starContext = context
            starContext.opacity = star.alpha
            let rect = CGRect(
                x: star.x * w,
                y: star.y * h,
                width: star.size * s * 1.2,
                height: star.size * s * 1.2
            )
            starContext.fill(Path(ellipseIn: rect), with: .color(.white))
        }

        // Faint orbital path
        var orbit = Path()
        let earth = p(200, 230)
        let apparent = p(500, 140)
        let actual = p(590, 230)
        orbit.addEllipse(in: CGRect(
            x: earth.x - 40 * s,
            y: earth.y - 40 * s,
            width: 360 * s,
            height: 360 * s
        ))
        context.stroke(orbit, with: .color(TimelyUNATheme.accent.opacity(0.12)), lineWidth: 1)

        // Actual sun
        drawSun(
            context: context,
            center: actual,
            radius: 26 * s,
            glowRadius: 48 * s,
            core: TimelyUNATheme.actualSun,
            glow: Color(red: 1, green: 0.97, blue: 0.8)
        )

        // Apparent sun
        drawSun(
            context: context,
            center: apparent,
            radius: 22 * s,
            glowRadius: 42 * s,
            core: TimelyUNATheme.apparentSun,
            glow: Color(red: 1, green: 0.97, blue: 0.8)
        )

        // Earth glow
        let earthGlow = CGRect(x: earth.x - 36 * s, y: earth.y - 36 * s, width: 72 * s, height: 72 * s)
        context.fill(
            Path(ellipseIn: earthGlow),
            with: .radialGradient(
                Gradient(colors: [Color.blue.opacity(0.35), .clear]),
                center: earth,
                startRadius: 0,
                endRadius: 36 * s
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x - 22 * s, y: earth.y - 22 * s, width: 44 * s, height: 44 * s)),
            with: .color(TimelyUNATheme.earthBlue)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x - 15 * s, y: earth.y - 10 * s, width: 20 * s, height: 12 * s)),
            with: .color(TimelyUNATheme.earthGreen)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x + 0 * s, y: earth.y + 2 * s, width: 14 * s, height: 9 * s)),
            with: .color(TimelyUNATheme.earthGreen)
        )

        // Lightlike path: Apparent (emission) → Earth. Photon travels this way.
        let photonFrom = CGPoint(x: apparent.x - 16 * s, y: apparent.y + 4 * s)
        let photonTo = CGPoint(x: earth.x + 18 * s, y: earth.y - 6 * s)
        var photonPath = Path()
        photonPath.move(to: photonFrom)
        photonPath.addLine(to: photonTo)
        context.stroke(
            photonPath,
            with: .color(TimelyUNATheme.actualSun),
            style: StrokeStyle(lineWidth: 2.2 * s, dash: [6 * s, 4 * s])
        )

        // True direction line
        let trueStart = CGPoint(x: earth.x + 18 * s, y: earth.y + 8 * s)
        let trueEnd = CGPoint(x: actual.x - 22 * s, y: actual.y)
        var truePath = Path()
        truePath.move(to: trueStart)
        truePath.addLine(to: trueEnd)
        context.stroke(truePath, with: .color(TimelyUNATheme.gold), lineWidth: 2 * s)

        var arrow = Path()
        arrow.move(to: trueEnd)
        arrow.addLine(to: CGPoint(x: trueEnd.x - 12 * s, y: trueEnd.y - 7 * s))
        arrow.addLine(to: CGPoint(x: trueEnd.x - 12 * s, y: trueEnd.y + 7 * s))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(TimelyUNATheme.gold))

        // Rocket
        if showRocket && rocketProgress > 0 {
            let start = CGPoint(x: earth.x + 22 * s, y: earth.y + 4 * s)
            let end = CGPoint(x: actual.x - 26 * s, y: actual.y)
            let t = rocketProgress
            let rx = start.x + (end.x - start.x) * t
            let ry = start.y + (end.y - start.y) * t

            var rocket = Path()
            rocket.move(to: CGPoint(x: rx, y: ry - 6 * s))
            rocket.addLine(to: CGPoint(x: rx + 14 * s, y: ry))
            rocket.addLine(to: CGPoint(x: rx, y: ry + 6 * s))
            rocket.closeSubpath()
            context.fill(rocket, with: .color(Color(white: 0.88)))
            context.fill(
                Path(CGRect(x: rx - 4 * s, y: ry - 3 * s, width: 8 * s, height: 6 * s)),
                with: .color(TimelyUNATheme.accent)
            )

            if t < 0.95 {
                let flicker = 1.0 + 0.3 * sin(time.timeIntervalSinceReferenceDate * 40)
                var flame = Path()
                flame.move(to: CGPoint(x: rx - 4 * s, y: ry - 2 * s))
                flame.addLine(to: CGPoint(x: rx - (14 + 4 * flicker) * s, y: ry))
                flame.addLine(to: CGPoint(x: rx - 4 * s, y: ry + 2 * s))
                flame.closeSubpath()
                context.fill(flame, with: .color(Color(red: 1, green: 0.53, blue: 0)))
            }
        }

        // Optional in-canvas chrome (wide layouts only).
        if drawsChromeLabels {
            drawClampedLabel(
                context: context,
                text: "TIMELYUNA LIGHT-TIME",
                preferred: CGPoint(x: sidePad + 8, y: 10),
                color: TimelyUNATheme.gold,
                size: 13 * labelScale,
                bold: true,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                anchor: .topLeading
            )
            drawClampedLabel(
                context: context,
                text: "Correcting for the finite speed of light",
                preferred: CGPoint(x: sidePad + 8, y: 28),
                color: TimelyUNATheme.gold.opacity(0.85),
                size: 10 * labelScale,
                bold: false,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                anchor: .topLeading
            )
        }

        let frame = CGRect(x: 4, y: 4, width: w - 8, height: h - 8)
        let compact = w < 360

        // Annotation regions — separate so titles never stack on the same point.
        // Apparent Sun: above marker, slightly left on narrow widths.
        let apparentLabel = compact ? "Apparent Sun" : "Apparent Sun"
        drawAnnotation(
            context: context,
            title: apparentLabel,
            subtitle: compact ? "8m 19s light delay" : "8m 19s light delay",
            anchor: apparent,
            titleOffset: CGPoint(x: compact ? -8 : 0, y: -42 * s),
            color: Color(red: 0.91, green: 0.83, blue: 0.64),
            size: 12 * labelScale,
            bounds: frame,
            leaderTo: apparent
        )

        // Actual Sun: below-right of marker.
        drawAnnotation(
            context: context,
            title: "Actual Sun",
            subtitle: compact ? "True now" : "Where it is now",
            anchor: actual,
            titleOffset: CGPoint(x: compact ? -10 : 4, y: 34 * s),
            color: TimelyUNATheme.gold,
            size: 12 * labelScale,
            bounds: frame,
            leaderTo: actual
        )

        // Earth: below.
        drawAnnotation(
            context: context,
            title: "Earth",
            subtitle: nil,
            anchor: earth,
            titleOffset: CGPoint(x: 0, y: 36 * s),
            color: Color(red: 0.66, green: 0.83, blue: 1),
            size: 12 * labelScale,
            bounds: frame,
            leaderTo: nil
        )

        // Shared emission, two independent trajectories.
        drawDivergingEmission(
            context: context,
            emission: photonFrom,
            photonEnd: photonTo,
            ghostEnd: CGPoint(x: actual.x - 22 * s, y: actual.y),
            time: time,
            scale: s
        )

        // Photon delay mid-path (above dashed line).
        let midPhoton = CGPoint(
            x: (photonFrom.x + photonTo.x) * 0.5,
            y: (photonFrom.y + photonTo.y) * 0.5 - 16 * s
        )
        drawClampedLabel(
            context: context,
            text: "8m 19s light delay",
            preferred: midPhoton,
            color: Color(red: 1, green: 0.87, blue: 0.53),
            size: 10 * labelScale,
            bold: false,
            bounds: frame,
            anchor: .center
        )

        // True direction: under the gold line, offset toward mid.
        let midTrue = CGPoint(
            x: (trueStart.x + trueEnd.x) * 0.48,
            y: (trueStart.y + trueEnd.y) * 0.5 + 16 * s
        )
        drawClampedLabel(
            context: context,
            text: "True direction",
            preferred: midTrue,
            color: TimelyUNATheme.gold,
            size: 10 * labelScale,
            bold: false,
            bounds: frame,
            anchor: .center
        )

        if showHit {
            drawClampedLabel(
                context: context,
                text: "DIRECT HIT ON TRUE POSITION!",
                preferred: CGPoint(x: w * 0.5, y: plot.minY + 18),
                color: TimelyUNATheme.gold,
                size: 14 * labelScale,
                bold: true,
                bounds: frame,
                anchor: .center
            )
        }
    }

    private func drawDivergingEmission(
        context: GraphicsContext,
        emission: CGPoint,
        photonEnd: CGPoint,
        ghostEnd: CGPoint,
        time: Date,
        scale s: CGFloat
    ) {
        let period = 4.2
        let raw = time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let fly: CGFloat
        if raw < 0.12 {
            fly = 0
        } else {
            let u = (raw - 0.12) / 0.88
            fly = u * u * (3 - 2 * u)
        }
        let px = emission.x + (photonEnd.x - emission.x) * fly
        let py = emission.y + (photonEnd.y - emission.y) * fly
        let gx = emission.x + (ghostEnd.x - emission.x) * fly
        let gy = emission.y + (ghostEnd.y - emission.y) * fly

        context.fill(
            Path(ellipseIn: CGRect(x: px - 3 * s, y: py - 3 * s, width: 6 * s, height: 6 * s)),
            with: .color(TimelyUNATheme.actualSun)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: px - 9 * s, y: py - 9 * s, width: 18 * s, height: 18 * s)),
            with: .radialGradient(
                Gradient(colors: [TimelyUNATheme.actualSun.opacity(0.4), .clear]),
                center: CGPoint(x: px, y: py),
                startRadius: 0,
                endRadius: 10 * s
            )
        )

        let gr = 8 * s
        context.fill(
            Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
            with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.5), TimelyUNATheme.gold.opacity(0.35), .clear]),
                center: CGPoint(x: gx, y: gy),
                startRadius: 0,
                endRadius: gr * 1.4
            )
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
            with: .color(TimelyUNATheme.gold.opacity(0.55)),
            style: StrokeStyle(lineWidth: 0.8 * s, dash: [2 * s, 2 * s])
        )
    }

    private func drawAnnotation(
        context: GraphicsContext,
        title: String,
        subtitle: String?,
        anchor: CGPoint,
        titleOffset: CGPoint,
        color: Color,
        size: CGFloat,
        bounds: CGRect,
        leaderTo: CGPoint?
    ) {
        let preferred = CGPoint(x: anchor.x + titleOffset.x, y: anchor.y + titleOffset.y)
        let titlePoint = drawClampedLabel(
            context: context,
            text: title,
            preferred: preferred,
            color: color,
            size: size,
            bold: true,
            bounds: bounds,
            anchor: .center
        )
        if let subtitle {
            _ = drawClampedLabel(
                context: context,
                text: subtitle,
                preferred: CGPoint(x: titlePoint.x, y: titlePoint.y + size + 4),
                color: color.opacity(0.9),
                size: max(9, size * 0.82),
                bold: false,
                bounds: bounds,
                anchor: .center
            )
        }
        if let target = leaderTo {
            // Short leader from label toward the body.
            var leader = Path()
            let start = CGPoint(x: titlePoint.x, y: titlePoint.y + size * 0.6)
            let end = CGPoint(
                x: target.x * 0.35 + start.x * 0.65,
                y: target.y * 0.35 + start.y * 0.65
            )
            leader.move(to: start)
            leader.addLine(to: end)
            context.stroke(leader, with: .color(color.opacity(0.45)), lineWidth: 1)
        }
    }

    /// Draws label and returns the final origin used (center of text for .center anchor).
    @discardableResult
    private func drawClampedLabel(
        context: GraphicsContext,
        text: String,
        preferred: CGPoint,
        color: Color,
        size: CGFloat,
        bold: Bool,
        bounds: CGRect,
        anchor: UnitPoint
    ) -> CGPoint {
        // System serif keeps Canvas resolve stable; host chrome uses Papyrus.
        let font = Font.system(size: max(9, size), weight: bold ? .semibold : .regular, design: .serif)
        let resolved = context.resolve(
            Text(text).font(font).foregroundColor(color)
        )
        let measured = resolved.measure(in: CGSize(width: bounds.width * 0.9, height: 80))
        let tw = measured.width
        let th = measured.height

        var origin = preferred
        switch anchor {
        case .topLeading:
            origin.x = min(max(preferred.x, bounds.minX + 2), bounds.maxX - tw - 2)
            origin.y = min(max(preferred.y, bounds.minY + 2), bounds.maxY - th - 2)
            context.draw(resolved, at: origin, anchor: .topLeading)
            return CGPoint(x: origin.x + tw / 2, y: origin.y + th / 2)
        default:
            // Center-ish: keep full glyph box inside bounds.
            origin.x = min(max(preferred.x, bounds.minX + tw / 2 + 2), bounds.maxX - tw / 2 - 2)
            origin.y = min(max(preferred.y, bounds.minY + th / 2 + 2), bounds.maxY - th / 2 - 2)
            context.draw(resolved, at: origin, anchor: .center)
            return origin
        }
    }

    private func drawSun(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        glowRadius: CGFloat,
        core: Color,
        glow: Color
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: glow, location: 0),
                    .init(color: core, location: 0.35),
                    .init(color: .clear, location: 1)
                ]),
                center: center,
                startRadius: 0,
                endRadius: glowRadius
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(core)
        )
        let highlight = radius * 0.4
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 0.45, width: highlight, height: highlight)),
            with: .color(glow.opacity(0.9))
        )
    }
}

private struct Star: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let size: Double
    let alpha: Double

    static func makeField(count: Int) -> [Star] {
        var result: [Star] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(
                Star(
                    id: i,
                    x: Double((i * 97 + 13) % 1000) / 1000.0,
                    y: Double((i * 53 + 29) % 1000) / 1000.0,
                    size: 0.6 + Double(i % 5) * 0.35,
                    alpha: 0.4 + Double(i % 7) * 0.08
                )
            )
        }
        return result
    }
}
