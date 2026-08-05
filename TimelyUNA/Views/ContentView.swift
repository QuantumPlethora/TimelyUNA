import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = SimulationState()
    @State private var selectedTab: AppTab = .dawn

    enum AppTab: String, CaseIterable, Identifiable {
        case dawn = "Dawn"
        case finder = "Finder"
        case jump = "Jump"
        case sextant = "Sextant"
        case cosmos = "Cosmos"
        case learn = "Learn"
        case about = "About"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .dawn: "sun.max"
            case .finder: "scope"
            case .jump: "sparkles"
            case .sextant: "location.viewfinder"
            case .cosmos: "hurricane"
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
                    case .finder:
                        PlanetFinderView()
                    case .jump:
                        QuantumJumpView()
                    case .sextant:
                        NavigationStack { SunSextantView() }
                    case .cosmos:
                        NavigationStack { ChronosModeView() }
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
            LinearGradient(colors: [.black, CosmicPalette.deepNavy, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Canvas { context, size in
                for index in 0..<100 {
                    let x = random(index * 17) * size.width
                    let y = random(index * 43 + 11) * size.height
                    let d = 0.7 + random(index * 71 + 7) * 1.8
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(0.2 + random(index * 29) * 0.6)))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func random(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private struct CosmicHeader: View {
    var body: some View {
        VStack(spacing: 7) {
            Text("TimelyUNA")
                .font(.custom("Papyrus", size: 48))
                .foregroundStyle(CosmicPalette.paleGold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack {
                Rectangle().fill(CosmicPalette.line).frame(height: 1)
                Image(systemName: "sparkle").foregroundStyle(CosmicPalette.gold)
                Rectangle().fill(CosmicPalette.line).frame(height: 1)
            }

            Text("Light-SpaceTime Sextant • Planetary Perspective Engine")
                .font(.custom("Papyrus", size: 15))
                .foregroundStyle(CosmicPalette.gold)
                .multilineTextAlignment(.center)

            Text("There it is. There it was. TimelyUNA shows you both.")
                .font(.custom("Papyrus", size: 19))
                .foregroundStyle(CosmicPalette.paleGold)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct CosmicTabBar: View {
    @Binding var selection: ContentView.AppTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(ContentView.AppTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                            Text(tab.rawValue).font(.custom("Papyrus", size: 13))
                        }
                        .foregroundStyle(selection == tab ? CosmicPalette.paleGold : CosmicPalette.gold)
                        .frame(width: 70, height: 55)
                        .background(selection == tab ? CosmicPalette.gold.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
        }
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CosmicPalette.line))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

private struct DawnExperienceView: View {
    @State private var showActual = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 14) {
                        Text("THE SUN IS LATE TO ITS OWN DAWN")
                            .font(.custom("Papyrus", size: 20))
                            .foregroundStyle(CosmicPalette.gold)

                        HStack {
                            PositionBadge(title: "VISIBLE NOW", detail: "Light from 8m 19s ago", symbol: "sun.max.fill")
                            Image(systemName: "arrow.right").foregroundStyle(CosmicPalette.gold)
                            if showActual {
                                PositionBadge(title: "ACTUAL NOW", detail: "Already ahead", symbol: "scope")
                            }
                        }

                        Text("At sunrise, we see the past. The true Sun is already ahead.")
                            .font(.custom("Papyrus", size: 22))
                            .foregroundStyle(CosmicPalette.paleGold)
                            .multilineTextAlignment(.center)

                        Button(showActual ? "Hide Actual Now" : "Show Actual Now") {
                            withAnimation { showActual.toggle() }
                        }
                        .buttonStyle(CosmicButtonStyle())
                    }
                }

                CosmicCard {
                    Text("A black hole is a star so bright it forgot to let go of its light.")
                        .font(.custom("Papyrus", size: 23))
                        .foregroundStyle(CosmicPalette.paleGold)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private enum ObserverWorld: String, CaseIterable, Identifiable {
    case earth = "Earth"
    case mars = "Mars"
    var id: Self { self }
    var symbol: String { self == .earth ? "globe.americas.fill" : "circle.circle.fill" }
}

private enum TargetWorld: String, CaseIterable, Identifiable {
    case mercury = "Mercury"
    case venus = "Venus"
    case earth = "Earth"
    case mars = "Mars"
    case jupiter = "Jupiter"
    case saturn = "Saturn"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .mercury: "circle.fill"
        case .venus: "circle.fill"
        case .earth: "globe.americas.fill"
        case .mars: "circle.circle.fill"
        case .jupiter: "circle.grid.cross.fill"
        case .saturn: "circle.dotted.circle.fill"
        }
    }
}

private struct PlanetFinderView: View {
    @State private var observer: ObserverWorld = .earth
    @State private var target: TargetWorld = .saturn
    @State private var showActual = true

    private var availableTargets: [TargetWorld] {
        TargetWorld.allCases.filter { !($0.rawValue == observer.rawValue) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 16) {
                        Text("PLANET FINDER")
                            .font(.custom("Papyrus", size: 27))
                            .foregroundStyle(CosmicPalette.paleGold)

                        Picker("Observer", selection: $observer) {
                            ForEach(ObserverWorld.allCases) { world in Text("From \(world.rawValue)").tag(world) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: observer) { _, newValue in
                            if target.rawValue == newValue.rawValue { target = newValue == .earth ? .mars : .earth }
                        }

                        Picker("Target", selection: $target) {
                            ForEach(availableTargets) { planet in Text(planet.rawValue).tag(planet) }
                        }
                        .pickerStyle(.menu)

                        SkyPositionCanvas(observer: observer, target: target, showActual: showActual)
                            .frame(height: 300)

                        Text("Aim at the VISIBLE NOW marker to find \(target.rawValue) in the sky. ACTUAL NOW represents its modeled present location after accounting for light-travel delay.")
                            .font(.custom("Papyrus", size: 18))
                            .foregroundStyle(CosmicPalette.paleGold)
                            .multilineTextAlignment(.center)

                        Toggle("Show Actual Now", isOn: $showActual)
                            .font(.custom("Papyrus", size: 17))
                            .tint(CosmicPalette.gold)
                    }
                }

                CosmicCard {
                    VStack(spacing: 8) {
                        Text("NIGHT-SKY MODE")
                            .font(.custom("Papyrus", size: 18))
                            .foregroundStyle(CosmicPalette.gold)
                        Text("Camera + motion sensors can later place these markers over the real sky. This screen establishes the observer/target model and the Visible Now versus Actual Now interface.")
                            .font(.custom("Papyrus", size: 17))
                            .foregroundStyle(CosmicPalette.paleGold)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private struct SkyPositionCanvas: View {
    let observer: ObserverWorld
    let target: TargetWorld
    let showActual: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [.indigo.opacity(0.28), .black], startPoint: .top, endPoint: .bottom))

                ForEach(0..<28, id: \.self) { i in
                    Circle().fill(.white.opacity(0.55)).frame(width: i.isMultiple(of: 5) ? 2 : 1)
                        .position(x: CGFloat((i * 47) % 310) / 310 * proxy.size.width, y: CGFloat((i * 79) % 230) / 230 * proxy.size.height)
                }

                VStack {
                    HStack {
                        Label("VIEWED FROM \(observer.rawValue.uppercased())", systemImage: observer.symbol)
                        Spacer()
                    }
                    .font(.custom("Papyrus", size: 15))
                    .foregroundStyle(CosmicPalette.gold)
                    .padding()
                    Spacer()
                }

                PositionMarker(title: "VISIBLE NOW", symbol: target.symbol, filled: true)
                    .position(x: proxy.size.width * 0.38, y: proxy.size.height * 0.55)

                if showActual {
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width * 0.43, y: proxy.size.height * 0.55))
                        path.addLine(to: CGPoint(x: proxy.size.width * 0.70, y: proxy.size.height * 0.40))
                    }
                    .stroke(CosmicPalette.gold, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

                    PositionMarker(title: "ACTUAL NOW", symbol: "scope", filled: false)
                        .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.38)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(target.rawValue) viewed from \(observer.rawValue). Visible Now shows where to look. Actual Now shows the modeled present location.")
    }
}

private struct PositionMarker: View {
    let title: String
    let symbol: String
    let filled: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(CosmicPalette.gold, lineWidth: 2).frame(width: 58, height: 58)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(filled ? CosmicPalette.paleGold : CosmicPalette.gold)
            }
            Text(title)
                .font(.custom("Papyrus", size: 13))
                .foregroundStyle(CosmicPalette.paleGold)
        }
    }
}

private struct QuantumJumpView: View {
    @State private var observer: ObserverWorld = .earth
    @State private var jumping = false
    @State private var target: TargetWorld = .earth

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 18) {
                        Text(observer == .earth ? "YOU ARE ON EARTH" : "YOU ARE STANDING ON MARS")
                            .font(.custom("Papyrus", size: 26))
                            .foregroundStyle(CosmicPalette.paleGold)

                        Image(systemName: observer.symbol)
                            .font(.system(size: 100, weight: .thin))
                            .foregroundStyle(observer == .earth ? .cyan : .orange)
                            .shadow(color: CosmicPalette.gold.opacity(0.5), radius: 18)
                            .scaleEffect(jumping ? 0.15 : 1)
                            .opacity(jumping ? 0.2 : 1)

                        Text(observer == .earth
                             ? "Quantum jump to Mars, then turn around and look home."
                             : "Look back toward Earth, Venus, Mercury—and the Sun—from an entirely different sky.")
                            .font(.custom("Papyrus", size: 21))
                            .foregroundStyle(CosmicPalette.paleGold)
                            .multilineTextAlignment(.center)

                        Button(observer == .earth ? "Quantum Jump to Mars" : "Quantum Jump Home") {
                            withAnimation(.easeInOut(duration: 0.8)) { jumping = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
                                observer = observer == .earth ? .mars : .earth
                                target = observer == .mars ? .earth : .mars
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { jumping = false }
                            }
                        }
                        .buttonStyle(CosmicButtonStyle())
                    }
                }

                if observer == .mars {
                    CosmicCard {
                        VStack(spacing: 15) {
                            Text("MARTIAN SKY: LOOK INWARD")
                                .font(.custom("Papyrus", size: 23))
                                .foregroundStyle(CosmicPalette.gold)

                            Picker("World", selection: $target) {
                                Text("Earth").tag(TargetWorld.earth)
                                Text("Venus").tag(TargetWorld.venus)
                                Text("Mercury").tag(TargetWorld.mercury)
                            }
                            .pickerStyle(.segmented)

                            SkyPositionCanvas(observer: .mars, target: target, showActual: true)
                                .frame(height: 280)

                            Text(target == .earth ? "Quantum jump complete. You are now looking home." : "Every planet owns a different sky—and every sky arrives late.")
                                .font(.custom("Papyrus", size: 20))
                                .foregroundStyle(CosmicPalette.paleGold)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private struct ScienceLiteracyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FactCard(title: "The Sun", body: "Sunlight reaches Earth in about 8 minutes 19 seconds.")
                FactCard(title: "Visible Now", body: "Visible Now answers the immediate human question: where do I aim to see it?")
                FactCard(title: "Actual Now", body: "Actual Now represents the object's modeled present location after accounting for light-travel delay.")
                FactCard(title: "Mars Perspective", body: "From Mars, Earth becomes a wandering planet. Venus and Mercury occupy a completely different apparent geometry.")
                FactCard(title: "TimelyUNA", body: "Because every dawn is already history—and every world has its own delayed sky.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private struct FactCard: View {
    let title: String
    let body: String

    var body: some View {
        CosmicCard {
            VStack(spacing: 8) {
                Text(title).font(.custom("Papyrus", size: 24)).foregroundStyle(CosmicPalette.gold)
                Text(body).font(.custom("Papyrus", size: 19)).foregroundStyle(CosmicPalette.paleGold).multilineTextAlignment(.center)
            }
        }
    }
}

private struct PositionBadge: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.custom("Papyrus", size: 16))
            Image(systemName: symbol).font(.system(size: 48, weight: .light))
            Text(detail).font(.custom("Papyrus", size: 13)).multilineTextAlignment(.center)
        }
        .foregroundStyle(CosmicPalette.paleGold)
        .frame(maxWidth: .infinity)
    }
}

private struct CosmicCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(CosmicPalette.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(CosmicPalette.line))
    }
}

private struct CosmicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Papyrus", size: 20))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CosmicPalette.gold.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    ContentView()
}