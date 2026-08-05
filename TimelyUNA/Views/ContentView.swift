import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = SimulationState()
    @State private var selectedTab: AppTab = .dawn

    enum AppTab: String, CaseIterable, Identifiable {
        case dawn = "Dawn"
        case sextant = "Sextant"
        case mars = "Mars"
        case cosmos = "Cosmos"
        case chart = "Chart"
        case learn = "Learn"
        case about = "About"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .dawn: "sun.max"
            case .sextant: "scope"
            case .mars: "circle.circle"
            case .cosmos: "hurricane"
            case .chart: "chart.xyaxis.line"
            case .learn: "book.closed"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            CosmicBackground()

            VStack(spacing: 0) {
                CosmicHeader()
                CosmicTabBar(selection: $selectedTab)

                Group {
                    switch selectedTab {
                    case .dawn:
                        DawnExperienceView()
                    case .sextant:
                        NavigationStack { SunSextantView() }
                    case .mars:
                        ComingSoonView(
                            title: "Mars",
                            symbol: "circle.circle",
                            message: "See Mars where its light says it was—and where orbital motion says it is now."
                        )
                    case .cosmos:
                        NavigationStack { ChronosModeView() }
                    case .chart:
                        ComingSoonView(
                            title: "Light-Time Chart",
                            symbol: "chart.xyaxis.line",
                            message: "Compare the arrival time of light from the Sun, planets, stars, and galaxies."
                        )
                    case .learn:
                        ScienceLiteracyView()
                    case .about:
                        NavigationStack { AboutView() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environmentObject(simulation)
        .tint(CosmicPalette.gold)
        .preferredColorScheme(.dark)
    }
}

private enum CosmicPalette {
    static let gold = Color(red: 0.86, green: 0.66, blue: 0.30)
    static let paleGold = Color(red: 0.98, green: 0.90, blue: 0.68)
    static let deepNavy = Color(red: 0.01, green: 0.025, blue: 0.055)
    static let panel = Color(red: 0.035, green: 0.045, blue: 0.07)
    static let line = gold.opacity(0.55)
}

private struct CosmicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, CosmicPalette.deepNavy, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                for index in 0..<95 {
                    let x = pseudoRandom(index * 17) * size.width
                    let y = pseudoRandom(index * 43 + 11) * size.height
                    let diameter = 0.7 + pseudoRandom(index * 71 + 7) * 1.8
                    let opacity = 0.18 + pseudoRandom(index * 29 + 3) * 0.62
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func pseudoRandom(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private struct CosmicHeader: View {
    var body: some View {
        VStack(spacing: 9) {
            Text("TimelyUNA")
                .font(.custom("Papyrus", size: 54))
                .foregroundStyle(CosmicPalette.paleGold)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .shadow(color: CosmicPalette.gold.opacity(0.25), radius: 10)

            HStack(spacing: 10) {
                Rectangle().fill(CosmicPalette.line).frame(height: 1)
                Image(systemName: "sparkle")
                    .foregroundStyle(CosmicPalette.gold)
                Rectangle().fill(CosmicPalette.line).frame(height: 1)
            }

            Text("Light-SpaceTime Sextant • Science Literacy Engine")
                .font(.custom("Papyrus", size: 17))
                .foregroundStyle(CosmicPalette.gold)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)

            Text("We do not see the universe as it is.\nWe see it as its light arrives.")
                .font(.custom("Papyrus", size: 23))
                .foregroundStyle(CosmicPalette.paleGold)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .padding(.top, 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct CosmicTabBar: View {
    @Binding var selection: ContentView.AppTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ContentView.AppTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = tab
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 20, weight: .light))
                            Text(tab.rawValue)
                                .font(.custom("Papyrus", size: 14))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selection == tab ? CosmicPalette.paleGold : CosmicPalette.gold.opacity(0.9))
                        .frame(width: 72, height: 60)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(CosmicPalette.gold.opacity(0.18))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(CosmicPalette.line, lineWidth: 1)
                                    }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .padding(5)
        }
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CosmicPalette.line, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct DawnExperienceView: View {
    @State private var apparentOffset = 0.42
    @State private var showActualPosition = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ApparentActualCard(
                    apparentOffset: apparentOffset,
                    showActualPosition: showActualPosition
                )

                QuoteCard()

                SunControlCard(
                    apparentOffset: $apparentOffset,
                    showActualPosition: $showActualPosition
                )

                TodayLightFactCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ApparentActualCard: View {
    let apparentOffset: Double
    let showActualPosition: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.30), Color.orange.opacity(0.17), .black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, size in
                    let horizon = size.height * 0.72
                    var mountains = Path()
                    mountains.move(to: CGPoint(x: 0, y: horizon))
                    mountains.addLine(to: CGPoint(x: size.width * 0.16, y: horizon - 22))
                    mountains.addLine(to: CGPoint(x: size.width * 0.34, y: horizon - 7))
                    mountains.addLine(to: CGPoint(x: size.width * 0.55, y: horizon - 38))
                    mountains.addLine(to: CGPoint(x: size.width * 0.76, y: horizon - 14))
                    mountains.addLine(to: CGPoint(x: size.width, y: horizon - 27))
                    mountains.addLine(to: CGPoint(x: size.width, y: size.height))
                    mountains.addLine(to: CGPoint(x: 0, y: size.height))
                    mountains.closeSubpath()
                    context.fill(mountains, with: .linearGradient(
                        Gradient(colors: [.black.opacity(0.72), .black]),
                        startPoint: CGPoint(x: 0, y: horizon),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                }

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let apparentX = 72 + CGFloat(apparentOffset) * 34
                    let actualX = width - 76

                    Path { path in
                        path.move(to: CGPoint(x: apparentX, y: 118))
                        path.addLine(to: CGPoint(x: width / 2, y: 250))
                        if showActualPosition {
                            path.move(to: CGPoint(x: actualX, y: 118))
                            path.addLine(to: CGPoint(x: width / 2, y: 250))
                        }
                    }
                    .stroke(CosmicPalette.gold, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))

                    VStack(spacing: 8) {
                        Text("APPARENT SUN")
                            .font(.custom("Papyrus", size: 20))
                        SunGlyph()
                        Text("WHERE WE SEE IT")
                            .font(.custom("Papyrus", size: 15))
                        Text("Light that left 8m 19s ago")
                            .font(.custom("Papyrus", size: 13))
                    }
                    .foregroundStyle(CosmicPalette.paleGold)
                    .position(x: apparentX, y: 102)

                    if showActualPosition {
                        VStack(spacing: 8) {
                            Text("ACTUAL SUN")
                                .font(.custom("Papyrus", size: 20))
                            TargetGlyph()
                            Text("WHERE IT REALLY IS")
                                .font(.custom("Papyrus", size: 15))
                            Text("~4 Sun diameters ahead")
                                .font(.custom("Papyrus", size: 13))
                        }
                        .foregroundStyle(CosmicPalette.paleGold)
                        .position(x: actualX, y: 102)
                        .transition(.opacity.combined(with: .scale))
                    }

                    Image(systemName: "figure.stand")
                        .font(.system(size: 25))
                        .foregroundStyle(.black)
                        .position(x: width / 2, y: 246)
                }

                VStack {
                    Spacer()
                    Text("At sunrise, we see the past.\nThe true Sun is already ahead.")
                        .font(.custom("Papyrus", size: 20))
                        .foregroundStyle(CosmicPalette.paleGold)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
            }
            .frame(height: 340)

            Divider().overlay(CosmicPalette.line)

            HStack(spacing: 0) {
                MetricView(
                    symbol: "stopwatch",
                    title: "LIGHT-TIME DELAY",
                    value: "8m 19s",
                    detail: "From Sun to Earth"
                )

                Rectangle()
                    .fill(CosmicPalette.line)
                    .frame(width: 1, height: 92)

                MetricView(
                    symbol: "globe.americas.fill",
                    title: "EARTH’S ORBIT",
                    value: "≈ 30 km/s",
                    detail: "Vastly differing motion"
                )
            }
            .padding(.vertical, 12)
        }
        .background(CosmicPalette.panel.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CosmicPalette.line, lineWidth: 1)
        }
    }
}

private struct SunGlyph: View {
    var body: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(.yellow)
            .shadow(color: .yellow.opacity(0.7), radius: 12)
    }
}

private struct TargetGlyph: View {
    var body: some View {
        Image(systemName: "scope")
            .font(.system(size: 54, weight: .thin))
            .foregroundStyle(CosmicPalette.gold)
            .shadow(color: CosmicPalette.gold.opacity(0.7), radius: 10)
    }
}

private struct MetricView: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(CosmicPalette.gold)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Papyrus", size: 13))
                Text(value)
                    .font(.custom("Papyrus", size: 25))
                Text(detail)
                    .font(.custom("Papyrus", size: 12))
                    .foregroundStyle(CosmicPalette.paleGold.opacity(0.78))
            }
        }
        .foregroundStyle(CosmicPalette.paleGold)
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.72)
    }
}

private struct QuoteCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.system(size: 29))
                .foregroundStyle(CosmicPalette.gold.opacity(0.75))

            Text("A black hole is a star so bright\nit forgot to let go of its light.")
                .font(.custom("Papyrus", size: 22))
                .foregroundStyle(CosmicPalette.paleGold)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: 56, height: 56)
                    .shadow(color: CosmicPalette.gold.opacity(0.75), radius: 15)
                Circle()
                    .stroke(CosmicPalette.gold.opacity(0.72), lineWidth: 3)
                    .frame(width: 62, height: 34)
                    .rotationEffect(.degrees(-25))
            }
        }
        .padding(22)
        .background(CosmicPalette.panel.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(CosmicPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SunControlCard: View {
    @Binding var apparentOffset: Double
    @Binding var showActualPosition: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Move the apparent Sun")
                .font(.custom("Papyrus", size: 24))
                .foregroundStyle(CosmicPalette.paleGold)

            HStack(spacing: 14) {
                stepButton(symbol: "chevron.left", delta: -0.05)

                Slider(value: $apparentOffset, in: 0...1)
                    .tint(CosmicPalette.gold)
                    .accessibilityLabel("Apparent Sun position")

                stepButton(symbol: "chevron.right", delta: 0.05)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showActualPosition.toggle()
                }
            } label: {
                Label(
                    showActualPosition ? "Hide Actual Position" : "Show Actual Position",
                    systemImage: showActualPosition ? "scope" : "scope"
                )
                .font(.custom("Papyrus", size: 22))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [CosmicPalette.gold.opacity(0.95), Color.brown.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay { Capsule().stroke(CosmicPalette.paleGold.opacity(0.65), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(CosmicPalette.panel.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(CosmicPalette.line, lineWidth: 1)
        }
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        Button {
            apparentOffset = min(1, max(0, apparentOffset + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CosmicPalette.paleGold)
                .frame(width: 50, height: 50)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(CosmicPalette.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TodayLightFactCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today’s Light Fact", systemImage: "sparkles")
                .font(.custom("Papyrus", size: 21))
                .foregroundStyle(CosmicPalette.gold)

            Text("The sunlight touching your face left the Sun about 8 minutes and 19 seconds ago.")
                .font(.custom("Papyrus", size: 18))
                .foregroundStyle(CosmicPalette.paleGold)

            Text("Because the Sun is always late to its own Dawn!")
                .font(.custom("Papyrus", size: 17))
                .foregroundStyle(CosmicPalette.gold)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(CosmicPalette.panel.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(CosmicPalette.line, lineWidth: 1)
        }
    }
}

private struct ScienceLiteracyView: View {
    private let facts = [
        ("Sunlight", "8m 19s", "The Sun we see is already in the past."),
        ("Moonlight", "≈ 1.3s", "Even the Moon arrives slightly late."),
        ("Mars", "3–22 min", "Its light-time changes as both worlds orbit."),
        ("Andromeda", "≈ 2.5M years", "Its light began traveling before modern humans existed.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(facts, id: \.0) { fact in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(fact.0)
                                .font(.custom("Papyrus", size: 23))
                            Spacer()
                            Text(fact.1)
                                .font(.custom("Papyrus", size: 20))
                                .foregroundStyle(CosmicPalette.gold)
                        }
                        Text(fact.2)
                            .font(.custom("Papyrus", size: 17))
                            .foregroundStyle(CosmicPalette.paleGold.opacity(0.84))
                    }
                    .foregroundStyle(CosmicPalette.paleGold)
                    .padding(20)
                    .background(CosmicPalette.panel.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(CosmicPalette.line, lineWidth: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private struct ComingSoonView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(CosmicPalette.gold)
                .shadow(color: CosmicPalette.gold.opacity(0.4), radius: 15)
            Text(title)
                .font(.custom("Papyrus", size: 36))
                .foregroundStyle(CosmicPalette.paleGold)
            Text(message)
                .font(.custom("Papyrus", size: 20))
                .foregroundStyle(CosmicPalette.paleGold.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Text("Coming into view.")
                .font(.custom("Papyrus", size: 18))
                .foregroundStyle(CosmicPalette.gold)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
