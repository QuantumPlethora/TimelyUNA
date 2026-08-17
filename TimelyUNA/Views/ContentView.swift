import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = SimulationState()
    @StateObject private var location = ObserverLocationService()
    @StateObject private var persistence = HorizonPersistence()
    @StateObject private var clock = HorizonClock()
    @StateObject private var sunriseReminder = SunriseReminderService()
    @State private var selectedTab: AppTab = ProcessInfo.processInfo.arguments.contains("-openXSkyJump")
        ? .jump
        : .horizon
    /// Trails `selectedTab` until CrystalTabHost reveals the destination.
    @State private var displayedTab: AppTab = ProcessInfo.processInfo.arguments.contains("-openXSkyJump")
        ? .jump
        : .horizon
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum AppTab: String, CaseIterable, Identifiable {
        case horizon = "Horizon"
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
            case .horizon: "sun.horizon.fill"
            case .dawn: "sunrise.fill"
            case .finder: "scope"
            case .jump: "sparkles"
            case .sextant: "location.viewfinder"
            case .cosmos: "hurricane"
            case .learn: "book.closed"
            case .about: "info.circle"
            }
        }
    }

    /// Compact phones use bottom tabs; Mac and regular-width iPad keep the top horizontal bar.
    private var usesBottomTabs: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            CosmicBackground()

            if usesBottomTabs {
                compactPhoneShell
            } else {
                wideShell
            }
        }
        .environmentObject(simulation)
        .environmentObject(location)
        .environmentObject(persistence)
        .environmentObject(clock)
        .environmentObject(sunriseReminder)
        .font(TimelyUNATheme.bodyFont)
        .tint(TimelyUNATheme.gold)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: usesBottomTabs)
        .onAppear {
            clock.start()
            Task { await sunriseReminder.refreshStatus() }
        }
        .onDisappear { clock.stop() }
    }

    // MARK: - Mac / iPad (regular width)

    private var wideShell: some View {
        VStack(spacing: 0) {
            if displayedTab != .horizon {
                CompactHeader()
                    .transition(.opacity)
            }

            CosmicTabBar(selection: $selectedTab, compact: false)

            crystalTabBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - iPhone compact

    private var compactPhoneShell: some View {
        // Bottom navigation participates in layout via safeAreaInset so ScrollViews
        // (including Sextant) can scroll their last content above the bar + home indicator.
        VStack(spacing: 0) {
            if displayedTab != .horizon {
                CompactHeader()
            }

            crystalTabBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CosmicTabBar(selection: $selectedTab, compact: true)
                .background {
                    // Extend solid bar into the home-indicator region without covering content.
                    Color.black
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
        }
    }

    private var crystalTabBody: some View {
        CrystalTabHost(selection: $selectedTab, displayed: $displayedTab, order: AppTab.allCases) { tab in
            tabRoot(for: tab)
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: AppTab) -> some View {
        switch tab {
        case .horizon:
            TrueHorizonView()
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
}

// MARK: - Background

struct CosmicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TimelyUNATheme.backgroundDeep,
                    TimelyUNATheme.background,
                    Color(red: 0.06, green: 0.03, blue: 0.12),
                    TimelyUNATheme.backgroundDeep
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft purple nebula
            RadialGradient(
                colors: [TimelyUNATheme.cosmicPurple.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Warm horizon glow
            RadialGradient(
                colors: [TimelyUNATheme.orange.opacity(0.12), .clear],
                center: .bottom,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Canvas { context, size in
                for index in 0..<120 {
                    let x = random(index * 17) * size.width
                    let y = random(index * 43 + 11) * size.height
                    let diameter = 0.7 + random(index * 71 + 7) * 1.8
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                        with: .color(.white.opacity(0.18 + random(index * 29) * 0.55))
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

// MARK: - Headers

private struct CompactHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            // Compact chrome — short name avoids truncation on small phones.
            Text(Brand.productShortName)
                .font(TimelyUNATheme.sectionFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Image(systemName: "sparkle")
                .foregroundStyle(TimelyUNATheme.acid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TimelyUNATheme.line)
                .frame(height: 1)
                .padding(.horizontal, 18)
        }
    }
}

private struct CosmicTabBar: View {
    @Binding var selection: ContentView.AppTab
    /// Bottom bar on compact iPhone; top bar on Mac / iPad regular.
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                compactBottomBar
            } else {
                wideTopBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(compact ? "Main navigation, bottom" : "Main navigation")
    }

    /// Compact iPhone: intentional horizontal scrolling so About is fully reachable (44×44 targets).
    private var compactBottomBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ContentView.AppTab.allCases) { tab in
                        tabButton(tab, compact: true)
                            .id(tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            // Horizontal-only scrolling; vertical page scroll is owned by tab content ScrollViews.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.black.opacity(0.92),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
        // Edge affordance: soft fade hints that more tabs exist off-screen.
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(Color.black)
    }

    private var wideTopBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ContentView.AppTab.allCases) { tab in
                    tabButton(tab, compact: false)
                }
            }
            .padding(4)
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(TimelyUNATheme.line, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: ContentView.AppTab, compact: Bool) -> some View {
        Button {
            AppHaptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(compact ? .body.weight(.semibold) : .body)
                    .frame(height: 22)
                Text(tab.rawValue)
                    .font(TimelyUNATheme.captionFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selection == tab ? TimelyUNATheme.papyrus : TimelyUNATheme.muted)
            .frame(minWidth: compact ? 64 : 66, minHeight: 44)
            .frame(height: compact ? 48 : 50)
            .padding(.horizontal, compact ? 6 : 0)
            .background(
                selection == tab ? TimelyUNATheme.acid.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if selection == tab {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TimelyUNATheme.acid.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

// MARK: - Placeholder feature tabs (Phase 2 expands these)

private struct DawnExperienceView: View {
    @EnvironmentObject private var location: ObserverLocationService
    @EnvironmentObject private var clock: HorizonClock
    @State private var showActual = true

    private var delayLabel: String {
        guard let lat = location.latitude, let lon = location.longitude, location.hasLiveCoordinates else {
            return "live delay after location"
        }
        let snap = SolarEngine.snapshot(date: clock.now, latitude: lat, longitude: lon)
        return SolarFormat.lightDelayCompact(snap.lightTimeSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CosmicCard {
                    VStack(spacing: 14) {
                        Text("THE SUN IS LATE TO ITS OWN HORIZON")
                            .font(TimelyUNATheme.headlineFont)
                            .foregroundStyle(TimelyUNATheme.acid)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .top, spacing: 10) {
                            PositionBadge(title: "VISIBLE NOW", detail: "Light from \(delayLabel) ago", symbol: "sun.max.fill")
                            Image(systemName: "arrow.right")
                                .foregroundStyle(TimelyUNATheme.goldDeep)
                                .padding(.top, 30)
                            if showActual {
                                PositionBadge(title: "ACTUAL NOW", detail: "Already ahead", symbol: "scope")
                            }
                        }

                        Text("At sunrise, we see the past. The true Sun is already ahead by roughly one photon delay.")
                            .font(TimelyUNATheme.subheadingFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(showActual ? "Hide Actual Now" : "Show Actual Now") {
                            AppHaptics.selection()
                            withAnimation { showActual.toggle() }
                        }
                        .buttonStyle(CosmicButtonStyle())
                    }
                }

                CosmicCard {
                    Text("Every Dawn is already history.")
                        .font(TimelyUNATheme.subheadingFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

// Planet Finder lives in Views/PlanetFinderView.swift (Phase 1 instrument).
// xSky Jump lives in Views/XSkyJump/XSkyJumpView.swift (cinematic SceneKit stage).

private struct ScienceLiteracyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FactCard(title: "The Sun", text: "Sunlight reaches Earth after a delay set by today’s Earth–Sun distance—typically about eight minutes.")
                FactCard(title: "Visible Now", text: "Where arriving light tells you to look.")
                FactCard(title: "Actual Now", text: "The object's modeled present location after accounting for light-travel delay.")
                FactCard(title: "xSky Jump", text: "Change the observer and the entire sky changes with it.")
                FactCard(title: "Mars Perspective", text: "From Mars, Earth becomes a wandering planet. Venus and Mercury occupy a different geometry.")
                FactCard(title: "Educational boundary", text: "True Horizon calculations are educational estimates—not navigation-grade results.")
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
                    .foregroundStyle(TimelyUNATheme.acid)
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

struct CosmicCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(TimelyUNATheme.line, lineWidth: 1)
                    )
            )
    }
}

struct CosmicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TimelyUNATheme.buttonFont)
            .foregroundStyle(TimelyUNATheme.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .background(TimelyUNATheme.acid.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    ContentView()
}
