import SwiftUI

/// Deep cosmic star field with slow parallax layers and restrained shimmer.
struct XSkyStarfieldView: View {
    var parallax: CGSize = .zero
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 20.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(context: context, size: size, time: timeline.date)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.04, green: 0.03, blue: 0.10),
                    Color(red: 0.06, green: 0.04, blue: 0.14),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize, time: Date) {
        let t = reduceMotion ? 0 : time.timeIntervalSinceReferenceDate
        let px = parallax.width
        let py = parallax.height

        // Nebula wash
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.55 + px * 0.02, y: -size.height * 0.1 + py * 0.02, width: size.width * 0.7, height: size.height * 0.6)),
            with: .radialGradient(
                Gradient(colors: [TimelyUNATheme.cosmicPurple.opacity(0.16 * intensity), .clear]),
                center: CGPoint(x: size.width * 0.75, y: size.height * 0.2),
                startRadius: 10,
                endRadius: size.width * 0.45
            )
        )

        // Three depth layers
        drawLayer(context: context, size: size, count: 90, seed: 3, parallaxScale: 0.15, baseAlpha: 0.25, t: t, px: px, py: py)
        drawLayer(context: context, size: size, count: 70, seed: 11, parallaxScale: 0.35, baseAlpha: 0.4, t: t, px: px, py: py)
        drawLayer(context: context, size: size, count: 45, seed: 29, parallaxScale: 0.65, baseAlpha: 0.65, t: t, px: px, py: py)

        // Occasional faint photon trails
        if !reduceMotion && intensity > 0.4 {
            for i in 0..<4 {
                let seed = i * 97 + Int(t * 0.15)
                let y = frac(seed) * size.height
                let x0 = frac(seed + 3) * size.width
                let len = 30 + frac(seed + 7) * 50
                let shimmer = 0.08 + 0.08 * sin(t * 0.7 + Double(i))
                var trail = Path()
                trail.move(to: CGPoint(x: x0, y: y))
                trail.addLine(to: CGPoint(x: x0 + len, y: y + 4))
                context.stroke(
                    trail,
                    with: .color(TimelyUNATheme.acid.opacity(shimmer * intensity)),
                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
                )
            }
        }
    }

    private func drawLayer(
        context: GraphicsContext,
        size: CGSize,
        count: Int,
        seed: Int,
        parallaxScale: CGFloat,
        baseAlpha: Double,
        t: Double,
        px: CGFloat,
        py: CGFloat
    ) {
        for i in 0..<count {
            let s = seed * 1000 + i
            var x = frac(s * 17) * size.width + px * parallaxScale
            var y = frac(s * 43 + 5) * size.height + py * parallaxScale
            x = x.truncatingRemainder(dividingBy: size.width)
            if x < 0 { x += size.width }
            y = y.truncatingRemainder(dividingBy: size.height)
            if y < 0 { y += size.height }

            let sizeStar = 0.6 + frac(s * 7) * (parallaxScale > 0.5 ? 2.2 : 1.4)
            var alpha = baseAlpha * intensity
            if !reduceMotion {
                // Slow organic shimmer
                alpha *= 0.75 + 0.25 * sin(t * (0.35 + frac(s) * 0.4) + Double(s))
            }
            var c = context
            c.opacity = alpha
            c.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: sizeStar, height: sizeStar)),
                with: .color(.white)
            )
        }
    }

    private func frac(_ seed: Int) -> CGFloat {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}
