import SwiftUI

/// Canvas visualization of Earth, apparent Sun, actual Sun, and optional rocket flight.
struct SunCanvasView: View {
    var rocketProgress: Double = 0
    var showRocket: Bool = false
    var showHit: Bool = false

    private let stars: [Star] = Star.makeField(count: 180)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !showRocket && !showHit)) { timeline in
            Canvas { context, size in
                drawScene(context: context, size: size, time: timeline.date)
            }
        }
        .background(Color.black)
    }

    private func drawScene(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height
        let scaleX = w / 720
        let scaleY = h / 420
        let s = min(scaleX, scaleY)

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        // Stars
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
        orbit.addEllipse(in: CGRect(
            x: 400 * scaleX - 280 * s,
            y: 210 * scaleY - 280 * s,
            width: 560 * s,
            height: 560 * s
        ))
        context.stroke(orbit, with: .color(TimelyUNATheme.accent.opacity(0.15)), lineWidth: 1)

        let earth = p(220, 210)
        let apparent = p(520, 160)
        let actual = p(580, 210)

        // Actual sun
        drawSun(
            context: context,
            center: actual,
            radius: 28 * s,
            glowRadius: 52 * s,
            core: TimelyUNATheme.actualSun,
            glow: Color(red: 1, green: 0.97, blue: 0.8)
        )
        drawLabel(context: context, text: "ACTUAL SUN", at: CGPoint(x: actual.x, y: actual.y + 48 * s), color: TimelyUNATheme.gold, size: 13 * s, bold: true)
        drawLabel(context: context, text: "(where it is RIGHT NOW)", at: CGPoint(x: actual.x, y: actual.y + 63 * s), color: TimelyUNATheme.gold, size: 10 * s, bold: false)

        // Apparent sun
        drawSun(
            context: context,
            center: apparent,
            radius: 24 * s,
            glowRadius: 45 * s,
            core: TimelyUNATheme.apparentSun,
            glow: Color(red: 1, green: 0.97, blue: 0.8)
        )
        drawLabel(context: context, text: "APPARENT SUN", at: CGPoint(x: apparent.x, y: apparent.y + 42 * s), color: Color(red: 0.91, green: 0.83, blue: 0.64), size: 13 * s, bold: true)
        drawLabel(context: context, text: "(light left 8min 19s ago)", at: CGPoint(x: apparent.x, y: apparent.y + 57 * s), color: Color(red: 0.91, green: 0.83, blue: 0.64), size: 10 * s, bold: false)

        // Earth glow
        let earthGlow = CGRect(x: earth.x - 38 * s, y: earth.y - 38 * s, width: 76 * s, height: 76 * s)
        context.fill(
            Path(ellipseIn: earthGlow),
            with: .radialGradient(
                Gradient(colors: [Color.blue.opacity(0.35), .clear]),
                center: earth,
                startRadius: 0,
                endRadius: 38 * s
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x - 24 * s, y: earth.y - 24 * s, width: 48 * s, height: 48 * s)),
            with: .color(TimelyUNATheme.earthBlue)
        )
        // Continents
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x - 17 * s, y: earth.y - 11 * s, width: 22 * s, height: 14 * s)),
            with: .color(TimelyUNATheme.earthGreen)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x + 0 * s, y: earth.y + 2 * s, width: 16 * s, height: 10 * s)),
            with: .color(TimelyUNATheme.earthGreen)
        )
        drawLabel(context: context, text: "EARTH", at: CGPoint(x: earth.x, y: earth.y + 42 * s), color: Color(red: 0.66, green: 0.83, blue: 1), size: 14 * s, bold: true)

        // Photon path (dashed) to apparent
        var photonPath = Path()
        photonPath.move(to: CGPoint(x: earth.x + 20 * s, y: earth.y - 8 * s))
        photonPath.addLine(to: CGPoint(x: apparent.x - 18 * s, y: apparent.y + 5 * s))
        context.stroke(
            photonPath,
            with: .color(TimelyUNATheme.actualSun),
            style: StrokeStyle(lineWidth: 2.5 * s, dash: [6 * s, 4 * s])
        )
        drawLabel(
            context: context,
            text: "☉ photons (8min 19s)",
            at: CGPoint(x: earth.x + 120 * s, y: earth.y - 22 * s),
            color: Color(red: 1, green: 0.87, blue: 0.53),
            size: 10 * s,
            bold: false
        )

        // True direction line
        var truePath = Path()
        let trueEnd = CGPoint(x: actual.x - 25 * s, y: actual.y)
        truePath.move(to: CGPoint(x: earth.x + 20 * s, y: earth.y + 10 * s))
        truePath.addLine(to: trueEnd)
        context.stroke(truePath, with: .color(TimelyUNATheme.gold), lineWidth: 2 * s)

        var arrow = Path()
        arrow.move(to: trueEnd)
        arrow.addLine(to: CGPoint(x: trueEnd.x - 13 * s, y: trueEnd.y - 8 * s))
        arrow.addLine(to: CGPoint(x: trueEnd.x - 13 * s, y: trueEnd.y + 8 * s))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(TimelyUNATheme.gold))

        drawLabel(
            context: context,
            text: "True current direction",
            at: CGPoint(x: earth.x + 140 * s, y: earth.y + 28 * s),
            color: TimelyUNATheme.gold,
            size: 10 * s,
            bold: false
        )

        // Rocket
        if showRocket && rocketProgress > 0 {
            let start = CGPoint(x: earth.x + 25 * s, y: earth.y + 5 * s)
            let end = CGPoint(x: actual.x - 30 * s, y: actual.y)
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

            drawLabel(context: context, text: "SPCX", at: CGPoint(x: rx + 28 * s, y: ry + 3 * s), color: .white, size: 9 * s, bold: true)
        }

        // Title
        drawLabel(
            context: context,
            text: "TIMELYUNA LIGHT-TIME SEXTANT",
            at: CGPoint(x: 20 * scaleX + 140 * s, y: 28 * scaleY),
            color: TimelyUNATheme.gold,
            size: 15 * s,
            bold: true,
            centered: false
        )
        drawLabel(
            context: context,
            text: "Correcting for the finite speed of light",
            at: CGPoint(x: 20 * scaleX + 120 * s, y: 45 * scaleY),
            color: TimelyUNATheme.gold.opacity(0.85),
            size: 11 * s,
            bold: false,
            centered: false
        )

        if showHit {
            drawLabel(
                context: context,
                text: "DIRECT HIT ON TRUE POSITION!",
                at: CGPoint(x: w * 0.5, y: h * 0.22),
                color: TimelyUNATheme.gold,
                size: 18 * s,
                bold: true
            )
            drawLabel(
                context: context,
                text: "Light-delay navigation successful ★",
                at: CGPoint(x: w * 0.5, y: h * 0.22 + 22 * s),
                color: Color(red: 1, green: 0.87, blue: 0.53),
                size: 12 * s,
                bold: false
            )
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

    private func drawLabel(
        context: GraphicsContext,
        text: String,
        at point: CGPoint,
        color: Color,
        size: CGFloat,
        bold: Bool,
        centered: Bool = true
    ) {
        let font = Font.system(size: max(8, size), weight: bold ? .bold : .regular, design: .serif)
        let resolved = context.resolve(
            Text(text).font(font).foregroundColor(color)
        )
        var origin = point
        if centered {
            origin.x -= resolved.measure(in: CGSize(width: 1000, height: 100)).width / 2
        }
        context.draw(resolved, at: origin, anchor: .leading)
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
