import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = SimulationState()
    @State private var selectedTab: AppTab = .dawn

    enum AppTab: String, CaseIterable, Identifiable {
        case dawn = "Dawn"
        case finder = "Finder"
        case jump = "xSky"
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
                if selectedTab == .dawn {
                    DawnHeroHeader()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    CompactHeader()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                CosmicTabBar(selection: $selectedTab)

                Group {
                    switch selectedTab {
                    case .dawn:
                        DawnExperienceView()
                    case .finder:
                        PlanetFinderView()
                    case .jump:
                        XSkyJumpView()
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
        .font(TimelyUNATheme.bodyFont)
        .tint(TimelyUNATheme.gold)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.24), value: selectedTab)
    }
}

private struct CosmicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.01, green: 0.025, blue: 0.055), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Canvas { context, size in
                for index in 0..<100 {
                    let x = random(index * 17) * size.width
                    let y = random(index * 43 + 11) * size.height
                    let diameter = 0.7 + random(index * 71 + 7) * 1.8
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                        with: .color(.white.opacity(0.2 + random(index * 29) * 0.6))
                    )
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

private struct DawnHeroHeader: View {
    var body: some View {
        VStack(spacing: 9) {
            Text("TimelyUNA")
                .font(TimelyUNATheme.displayFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 12) {
                Rectangle().fill(TimelyUNATheme.accent.opacity(0.75)).frame(height: 1)
                Image(systemName: "sparkle")
                    .foregroundStyle(TimelyUNATheme.gold)
                Rectangle().fill(TimelyUNATheme.accent.opacity(0.75)).frame(height: 1)
            }

            Text("Light-SpaceTime Sextant • Planetary Perspective Engine")
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.accent)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("There it is. There it was.\nTimelyUNA shows you both.")
                .font(TimelyUNATheme.subheadingFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct CompactHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("TimelyUNA")
                .font(TimelyUNATheme.sectionFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Image(systemName: "sparkle")
                .foregroundStyle(TimelyUNATheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TimelyUNATheme.accent.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 18)
        }
    }
}

private struct CosmicTabBar: View {
    @Binding var selection: ContentView.AppTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ContentView.AppTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.body)
                            Text(tab.rawValue)
                                .font(TimelyUNATheme.captionFont)
                                .lineLimit(1)
                        }
                        .foregroundStyle(selection == tab ? TimelyUNATheme.papyrus : TimelyUNATheme.accent)
                        .frame(width: 66, height: 50)
                        .background(
                            selection == tab ? TimelyUNATheme.accent.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(TimelyUNATheme.accent.opacity(0.7)))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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
                            .font(TimelyUNATheme.headlineFont)
                            .foregroundStyle(TimelyUNATheme.accent)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .top, spacing: 10) {
                            PositionBadge(title: "VISIBLE NOW", detail: "Light from 8m 19s ago", symbol: "sun.max.fill")
                            Image(systemName: "arrow.right")
                                .foregroundStyle(TimelyUNATheme.accent)
                                .padding(.top, 30)
                            if showActual {
                                PositionBadge(title: "ACTUAL NOW", detail: "Already ahead", symbol: "scope")
                            }
                        }

                        Text("At sunrise, we see the past. The true Sun is already ahead.")
                            .font(TimelyUNATheme.subheadingFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(showActual ? "Hide Actual Now" : "Show Actual Now") {
                            withAnimation { showActual.toggle() }
                        }
                        .buttonStyle(CosmicButtonStyle())
                    }
                }

                CosmicCard {
                    Text("A black hole is a star so bright it forgot to let go of its light.")
                        .font(TimelyUNATheme.subheadingFont)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
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
        case .mercury, .venus: "circle.fill"
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
        TargetWorld.allCases.filter { $0.rawValue != observer.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 16) {
                        Text("PLANET FINDER")
                            .font(TimelyUNATheme.sectionFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)

                        Picker("Observer", selection: $observer) {
                            ForEach(ObserverWorld.allCases) { world in
                                Text("From \(world.rawValue)").tag(world)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: observer) { _, newValue in
                            if target.rawValue == newValue.rawValue {
                                target = newValue == .earth ? .mars : .earth
                            }
                        }

                        Picker("Target", selection: $target) {
                            ForEach(availableTargets) { planet in
                                Text(planet.rawValue).tag(planet)
                            }
                        }
                        .pickerStyle(.menu)

                        SkyPositionCanvas(observer: observer, target: target, showActual: showActual)
                            .frame(height: 285)

                        Text("Aim at VISIBLE NOW to find \(target.rawValue). ACTUAL NOW shows its modeled present location after light-travel delay.")
                            .font(TimelyUNATheme.bodyFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle("Show Actual Now", isOn: $showActual)
                            .font(TimelyUNATheme.bodyFont)
                            .tint(TimelyUNATheme.accent)
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

                ForEach(0..<28, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: index.isMultiple(of: 5) ? 2 : 1)
                        .position(
                            x: CGFloat((index * 47) % 310) / 310 * proxy.size.width,
                            y: CGFloat((index * 79) % 230) / 230 * proxy.size.height
                        )
                }

                VStack {
                    HStack {
                        Label("VIEWED FROM \(observer.rawValue.uppercased())", systemImage: observer.symbol)
                            .font(TimelyUNATheme.captionFont)
                        Spacer()
                    }
                    .foregroundStyle(TimelyUNATheme.accent)
                    .padding()
                    Spacer()
                }

                PositionMarker(title: "VISIBLE NOW", symbol: target.symbol, filled: true)
                    .position(x: proxy.size.width * 0.36, y: proxy.size.height * 0.57)

                if showActual {
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width * 0.42, y: proxy.size.height * 0.55))
                        path.addLine(to: CGPoint(x: proxy.size.width * 0.69, y: proxy.size.height * 0.40))
                    }
                    .stroke(TimelyUNATheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

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
                Circle().stroke(TimelyUNATheme.accent, lineWidth: 2).frame(width: 56, height: 56)
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(filled ? TimelyUNATheme.papyrus : TimelyUNATheme.accent)
            }
            Text(title)
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct XSkyJumpView: View {
    @State private var observer: ObserverWorld = .earth
    @State private var target: TargetWorld = .earth
    @State private var jumping = false
    @State private var starStretch = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 16) {
                        Text("xSky Jump")
                            .font(TimelyUNATheme.titleFont)
                            .foregroundStyle(TimelyUNATheme.accent)

                        Text("Jump the observer. Change the sky.")
                            .font(TimelyUNATheme.subheadingFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)

                        ZStack {
                            ForEach(0..<18, id: \.self) { index in
                                Capsule()
                                    .fill(.white.opacity(0.55))
                                    .frame(width: starStretch ? 80 : 3, height: 2)
                                    .rotationEffect(.degrees(Double(index) * 20))
                                    .offset(x: CGFloat((index % 6) * 18 - 45), y: CGFloat((index / 6) * 30 - 30))
                                    .opacity(jumping ? 1 : 0)
                            }

                            Image(systemName: observer.symbol)
                                .font(.system(size: 96, weight: .thin))
                                .foregroundStyle(observer == .earth ? .cyan : .orange)
                                .shadow(color: TimelyUNATheme.accent.opacity(0.55), radius: 18)
                                .scaleEffect(jumping ? 0.18 : 1)
                                .opacity(jumping ? 0.18 : 1)
                        }
                        .frame(height: 125)

                        Text(observer == .earth ? "YOU ARE ON EARTH" : "YOU ARE STANDING ON MARS")
                            .font(TimelyUNATheme.sectionFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(observer == .earth
                             ? "xSky Jump to Mars, then turn around and look home."
                             : "Earth, Venus, Mercury, and the Sun now belong to a Martian sky.")
                            .font(TimelyUNATheme.bodyFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(observer == .earth ? "xSky Jump to Mars" : "xSky Jump Home") {
                            performJump()
                        }
                        .buttonStyle(CosmicButtonStyle())
                        .disabled(jumping)
                    }
                }

                if observer == .mars {
                    CosmicCard {
                        VStack(spacing: 15) {
                            Text("MARTIAN SKY: LOOK INWARD")
                                .font(TimelyUNATheme.headlineFont)
                                .foregroundStyle(TimelyUNATheme.accent)
                                .multilineTextAlignment(.center)

                            Picker("World", selection: $target) {
                                Text("Earth").tag(TargetWorld.earth)
                                Text("Venus").tag(TargetWorld.venus)
                                Text("Mercury").tag(TargetWorld.mercury)
                            }
                            .pickerStyle(.segmented)

                            SkyPositionCanvas(observer: .mars, target: target, showActual: true)
                                .frame(height: 270)

                            Text(target == .earth
                                 ? "xSky Jump complete. You are now looking home."
                                 : "Every planet owns a different sky—and every sky arrives late.")
                                .font(TimelyUNATheme.bodyFont)
                                .foregroundStyle(TimelyUNATheme.papyrus)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    private func performJump() {
        withAnimation(.easeIn(duration: 0.25)) {
            jumping = true
            starStretch = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            observer = observer == .earth ? .mars : .earth
            target = observer == .mars ? .earth : .mars

            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                jumping = false
                starStretch = false
            }
        }
    }
}

private struct ScienceLiteracyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FactCard(title: "The Sun", text: "Sunlight reaches Earth in about 8 minutes 19 seconds.")
                FactCard(title: "Visible Now", text: "Where arriving light tells you to look.")
                FactCard(title: "Actual Now", text: "The object's modeled present location after accounting for light-travel delay.")
                FactCard(title: "xSky Jump", text: "Change the observer and the entire sky changes with it.")
                FactCard(title: "Mars Perspective", text: "From Mars, Earth becomes a wandering planet. Venus and Mercury occupy a different geometry.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

private struct FactCard: View {
    let title: String
    let text: String

    var body: some View {
        CosmicCard {
            VStack(spacing: 8) {
                Text(title)
                    .font(TimelyUNATheme.sectionFont)
                    .foregroundStyle(TimelyUNATheme.accent)
                Text(text)
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PositionBadge: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(TimelyUNATheme.captionFont)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
            Text(detail)
                .font(TimelyUNATheme.smallCaptionFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(TimelyUNATheme.papyrus)
        .frame(maxWidth: .infinity)
    }
}

private struct CosmicCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(TimelyUNATheme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(TimelyUNATheme.accent.opacity(0.7)))
    }
}

private struct CosmicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TimelyUNATheme.buttonFont)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .background(TimelyUNATheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    ContentView()
}
