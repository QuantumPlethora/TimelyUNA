import SwiftUI

struct ChronosCanvasView: View {
    let phase: SimulationState.ChronosPhase

    private let stars: [ChronoStar] = ChronoStar.makeField(count: 220)
    private let dinos: [Dino] = Dino.defaultHerd

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: phase != .telescopeActive)) { timeline in
            Canvas { context, size in
                switch phase {
                case .idle, .jumped:
                    drawSpace(context: context, size: size)
                case .telescopeActive:
                    drawDinoEra(context: context, size: size, time: timeline.date)
                }
            }
        }
        .background(Color.black)
    }

    private func drawSpace(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        for star in stars {
            var c = context
            c.opacity = star.alpha
            c.fill(
                Path(ellipseIn: CGRect(x: star.x * w, y: star.y * h, width: star.size, height: star.size)),
                with: .color(.white)
            )
        }

        // Milky Way hint
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.45, y: h * 0.22, width: w * 0.45, height: h * 0.28)),
            with: .color(Color(red: 0.7, green: 0.63, blue: 0.86).opacity(0.08))
        )

        let earth = CGPoint(x: w * 0.72, y: h * 0.42)
        context.fill(
            Path(ellipseIn: CGRect(x: earth.x - 7, y: earth.y - 7, width: 14, height: 14)),
            with: .color(Color(red: 0.29, green: 0.61, blue: 1))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: earth.x - 9, y: earth.y - 9, width: 18, height: 18)),
            with: .color(.white.opacity(0.5)),
            lineWidth: 1
        )

        drawWrappedText(
            context,
            "EARTH (65,000,000 ly away)",
            in: CGRect(x: w * 0.28, y: h * 0.42 - 38, width: w * 0.68, height: 44),
            size: 12,
            color: TimelyUNATheme.accent,
            bold: true,
            centered: true
        )
        drawWrappedText(
            context,
            "You are looking at light that left during the age of dinosaurs",
            in: CGRect(x: 18, y: h * 0.42 + 22, width: max(1, w - 36), height: 54),
            size: 10,
            color: TimelyUNATheme.accent.opacity(0.9),
            bold: false,
            centered: true
        )
        drawWrappedText(
            context,
            "QUANTUM VANTAGE POINT",
            in: CGRect(x: 18, y: 18, width: max(1, w - 36), height: 28),
            size: 12,
            color: TimelyUNATheme.accentMuted,
            bold: false,
            centered: false
        )
    }

    private func drawDinoEra(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height
        let t = time.timeIntervalSinceReferenceDate

        // Sky
        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h * 0.55)),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.23, green: 0.37, blue: 0.54),
                    Color(red: 0.35, green: 0.56, blue: 0.42)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: h * 0.55)
            )
        )

        // Ground
        context.fill(
            Path(CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5)),
            with: .color(Color(red: 0.23, green: 0.35, blue: 0.16))
        )

        // Hills
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.08, y: h * 0.48, width: w * 0.4, height: h * 0.22)),
            with: .color(Color(red: 0.16, green: 0.29, blue: 0.12))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.5, y: h * 0.5, width: w * 0.48, height: h * 0.26)),
            with: .color(Color(red: 0.16, green: 0.29, blue: 0.12))
        )

        // Cretaceous sun
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.2 - 22, y: h * 0.22 - 22, width: 44, height: 44)),
            with: .color(Color(red: 1, green: 0.87, blue: 0.47))
        )

        for dino in dinos {
            let travel = (t * dino.speed * 18).truncatingRemainder(dividingBy: w + 90)
            let x = travel - 50
            let y = dino.y * h
            drawDino(context: context, type: dino.type, at: CGPoint(x: x, y: y), scale: max(0.8, w / 640))
        }

        drawWrappedText(
            context,
            "CRETACEOUS EARTH • 65 MILLION YEARS AGO",
            in: CGRect(x: 18, y: 18, width: max(1, w - 36), height: 48),
            size: 14,
            color: TimelyUNATheme.gold,
            bold: true,
            centered: true
        )
        drawWrappedText(
            context,
            "You are seeing Earth as it was when T. rex walked",
            in: CGRect(x: 18, y: 58, width: max(1, w - 36), height: 44),
            size: 11,
            color: Color(red: 1, green: 0.87, blue: 0.53),
            bold: false,
            centered: true
        )
        drawWrappedText(
            context,
            "🦖 \"Rawr... the light finally arrived\"",
            in: CGRect(x: w * 0.36, y: h * 0.20, width: max(1, w * 0.58), height: 48),
            size: 10,
            color: TimelyUNATheme.gold.opacity(0.75),
            bold: false,
            centered: true
        )
        drawWrappedText(
            context,
            "🦕 \"Took you long enough\"",
            in: CGRect(x: 18, y: h * 0.70, width: max(1, w * 0.62), height: 38),
            size: 10,
            color: TimelyUNATheme.gold.opacity(0.75),
            bold: false,
            centered: false
        )
        drawWrappedText(
            context,
            "Note: Artistic interpretation. Real quantum telescopes are still in the realm of dreams.",
            in: CGRect(x: 18, y: h - 58, width: max(1, w - 36), height: 52),
            size: 9,
            color: TimelyUNATheme.gold.opacity(0.85),
            bold: true,
            centered: false
        )
    }

    private func drawDino(context: GraphicsContext, type: Dino.Kind, at origin: CGPoint, scale: CGFloat) {
        let s = scale
        switch type {
        case .trex:
            context.fill(Path(CGRect(x: origin.x - 18 * s, y: origin.y - 8 * s, width: 32 * s, height: 16 * s)), with: .color(Color(red: 0.29, green: 0.48, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x + 10 * s, y: origin.y - 14 * s, width: 14 * s, height: 12 * s)), with: .color(Color(red: 0.29, green: 0.48, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x - 32 * s, y: origin.y - 3 * s, width: 16 * s, height: 8 * s)), with: .color(Color(red: 0.29, green: 0.48, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x - 8 * s, y: origin.y + 4 * s, width: 6 * s, height: 14 * s)), with: .color(Color(red: 0.29, green: 0.48, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x + 6 * s, y: origin.y + 4 * s, width: 6 * s, height: 14 * s)), with: .color(Color(red: 0.29, green: 0.48, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x + 18 * s, y: origin.y - 10 * s, width: 4 * s, height: 4 * s)), with: .color(.black))
        case .sauropod:
            context.fill(Path(CGRect(x: origin.x - 22 * s, y: origin.y - 10 * s, width: 38 * s, height: 18 * s)), with: .color(Color(red: 0.23, green: 0.42, blue: 0.29)))
            context.fill(Path(CGRect(x: origin.x + 12 * s, y: origin.y - 16 * s, width: 12 * s, height: 12 * s)), with: .color(Color(red: 0.23, green: 0.42, blue: 0.29)))
            context.fill(Path(CGRect(x: origin.x + 20 * s, y: origin.y - 18 * s, width: 5 * s, height: 5 * s)), with: .color(Color(red: 0.16, green: 0.35, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x + 20 * s, y: origin.y - 10 * s, width: 5 * s, height: 5 * s)), with: .color(Color(red: 0.16, green: 0.35, blue: 0.23)))
            context.fill(Path(CGRect(x: origin.x - 35 * s, y: origin.y - 5 * s, width: 15 * s, height: 8 * s)), with: .color(Color(red: 0.23, green: 0.42, blue: 0.29)))
            context.fill(Path(CGRect(x: origin.x - 14 * s, y: origin.y + 4 * s, width: 7 * s, height: 12 * s)), with: .color(Color(red: 0.23, green: 0.42, blue: 0.29)))
            context.fill(Path(CGRect(x: origin.x + 8 * s, y: origin.y + 4 * s, width: 7 * s, height: 12 * s)), with: .color(Color(red: 0.23, green: 0.42, blue: 0.29)))
        }
    }

    /// Canvas text does not wrap automatically. Build measured lines that stay inside
    /// the supplied rectangle so compact phones never crop educational copy.
    private func drawWrappedText(
        _ context: GraphicsContext,
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        color: Color,
        bold: Bool,
        centered: Bool
    ) {
        let font = Font.system(size: max(8, size), weight: bold ? .bold : .regular, design: .serif)
        let words = text.split { $0.isWhitespace }.map(String.init)
        guard !words.isEmpty else { return }

        var lines: [String] = []
        var currentLine = ""

        for word in words {
            let candidate = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            let candidateText = context.resolve(Text(candidate).font(font))
            let candidateWidth = candidateText.measure(
                in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 200)
            ).width

            if candidateWidth <= rect.width || currentLine.isEmpty {
                currentLine = candidate
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        let lineHeight = max(11, size * 1.28)
        for (index, line) in lines.enumerated() {
            let y = rect.minY + CGFloat(index) * lineHeight
            guard y + lineHeight <= rect.maxY + 1 else { break }

            let resolved = context.resolve(Text(line).font(font).foregroundColor(color))
            let point = CGPoint(x: centered ? rect.midX : rect.minX, y: y)
            context.draw(resolved, at: point, anchor: centered ? .top : .topLeading)
        }
    }
}

private struct ChronoStar: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let size: Double
    let alpha: Double

    static func makeField(count: Int) -> [ChronoStar] {
        var result: [ChronoStar] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(
                ChronoStar(
                    id: i,
                    x: Double((i * 89 + 7) % 1000) / 1000.0,
                    y: Double((i * 61 + 19) % 1000) / 1000.0,
                    size: 0.5 + Double(i % 5) * 0.3,
                    alpha: 0.3 + Double(i % 8) * 0.08
                )
            )
        }
        return result
    }
}

private struct Dino: Identifiable {
    enum Kind { case trex, sauropod }
    let id: Int
    let baseX: Double
    let y: Double
    let type: Kind
    let speed: Double

    static let defaultHerd: [Dino] = [
        Dino(id: 0, baseX: 0.12, y: 0.52, type: .trex, speed: 0.9),
        Dino(id: 1, baseX: 0.35, y: 0.68, type: .sauropod, speed: 0.55),
        Dino(id: 2, baseX: 0.70, y: 0.55, type: .trex, speed: 1.1),
        Dino(id: 3, baseX: 0.88, y: 0.72, type: .sauropod, speed: 0.7)
    ]
}
