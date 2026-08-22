import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Cinematic xSky Jump recomposed around a protected `PlanetStage` viewport.
/// No information panel, button, or nav may overlap the planet.
///
/// Phone layouts put the entire page (including the planet) in a vertical `ScrollView`
/// so vertical swipes over Earth/Mars scroll the page. Horizontal planet orbit and
/// pinch-zoom remain on `XSkyPlanetStage` via simultaneous directional gestures.
struct XSkyJumpView: View {
    @StateObject private var state = XSkyJumpState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var hapticMidFired = false
    @State private var planetFrame: CGRect = .null
    @State private var chromeFrames: [String: CGRect] = [:]
    /// Temporary visual verification; leave false for inspection builds.
    private let debugPlanetOutline = false

    var body: some View {
        // Layout participates in the safe area (bottom tab bar via safeAreaInset in ContentView).
        // Avoid ignoresSafeArea here so GeometryReader never expands under the tab bar.
        GeometryReader { geo in
            let layout = layoutMode(for: geo.size)

            Group {
                switch layout {
                case .phonePortrait:
                    phonePortraitLayout(available: geo.size)
                case .phoneLandscape:
                    phoneLandscapeLayout(available: geo.size)
                case .wideTwoColumn:
                    wideTwoColumnLayout(available: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            state.startEphemerisUpdates()
            if ProcessInfo.processInfo.arguments.contains("-xskyMars") {
                state.observer = .mars
                state.phase = .mars
                state.lookTarget = .earth
            }
            state.resetView()
        }
        .onDisappear {
            state.stopEphemerisUpdates()
        }
        .onChange(of: state.jumpProgress) { _, p in
            handleJumpHaptics(progress: p)
        }
        .onChange(of: state.phase) { _, phase in
            if phase == .mars || phase == .earth {
                hapticArrival()
            }
        }
        .onPreferenceChange(XSkyPlanetStageFrameKey.self) { planetFrame = $0 }
        .onPreferenceChange(XSkyChromeFrameKey.self) { chromeFrames = $0 }
        .onChange(of: chromeFrames) { _, new in
            XSkyLayoutVerifier.verify(planet: planetFrame, chrome: new)
        }
        .onChange(of: planetFrame) { _, new in
            XSkyLayoutVerifier.verify(planet: new, chrome: chromeFrames)
        }
    }

    // MARK: - Layout modes

    private enum LayoutMode {
        case phonePortrait
        case phoneLandscape
        case wideTwoColumn
    }

    private func layoutMode(for size: CGSize) -> LayoutMode {
        let isLandscape = size.width > size.height
        #if os(iOS)
        if horizontalSizeClass == .compact {
            return isLandscape ? .phoneLandscape : .phonePortrait
        }
        // iPad (regular) — spacious two-column in both orientations.
        return .wideTwoColumn
        #else
        // Mac: two-column whenever width allows; narrow windows fall back gracefully.
        if size.width >= 700 {
            return .wideTwoColumn
        }
        return isLandscape ? .phoneLandscape : .phonePortrait
        #endif
    }

    // MARK: - iPhone portrait
    // Full-page ScrollView: title → summary → PlanetStage → caption → jump → controls
    // Vertical drag over the planet scrolls this ScrollView.

    private func phonePortraitLayout(available: CGSize) -> some View {
        let stageHeight = planetStageHeight(availableHeight: available.height, wide: false)

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                pageTitle
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .xSkyChromeFrame("title")

                journeySummaryCompact
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .xSkyChromeFrame("summary")

                planetStage
                    .frame(height: stageHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    activeWorldCaption
                        .xSkyChromeFrame("caption")

                    reachablePrimaryJumpButton

                    controlsStack
                        .opacity(state.showChrome ? 1 : 0)
                        .allowsHitTesting(state.showChrome && !state.isJumping)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: state.showChrome)
                        .xSkyChromeFrame("controls")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                // Extra bottom inset so the last paragraph + launch button clear the tab bar.
                .padding(.bottom, bottomScrollClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
    }

    // MARK: - iPhone landscape
    // Single vertical ScrollView over the full page so vertical pans on the planet scroll.

    private func phoneLandscapeLayout(available: CGSize) -> some View {
        let planetFraction: CGFloat = 0.58
        let stageHeight = min(max(available.height * 0.88, 200), max(240, available.height - 24))

        return ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    pageTitle
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .xSkyChromeFrame("title")
                    planetStage
                        .frame(height: stageHeight)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: max(180, available.width * planetFraction))
                .padding(.leading, 10)
                .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    journeySummaryCompact
                        .xSkyChromeFrame("summary")
                    activeWorldCaption
                        .xSkyChromeFrame("caption")
                    reachablePrimaryJumpButton
                    controlsStack
                        .opacity(state.showChrome ? 1 : 0)
                        .allowsHitTesting(state.showChrome && !state.isJumping)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: state.showChrome)
                        .xSkyChromeFrame("controls")
                }
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .padding(.bottom, bottomScrollClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - iPad / Mac
    // Leading PlanetStage (larger) | trailing journey + controls.
    // Outer ScrollView so vertical pans over the planet still move the page when needed.

    private func wideTwoColumnLayout(available: CGSize) -> some View {
        let planetFraction: CGFloat = available.width >= 1100 ? 0.62 : 0.58
        let stageHeight = planetStageHeight(availableHeight: available.height, wide: true)

        return ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 18) {
                planetStage
                    .frame(height: stageHeight)
                    .frame(maxWidth: .infinity)
                    .frame(width: max(320, available.width * planetFraction - 12))
                    .padding(.leading, 16)
                    .padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 16) {
                    pageTitle
                        .xSkyChromeFrame("title")
                    journeySummaryCompact
                        .xSkyChromeFrame("summary")
                    activeWorldCaption
                        .xSkyChromeFrame("caption")
                    reachablePrimaryJumpButton
                    controlsStack
                        .opacity(state.showChrome ? 1 : 0)
                        .allowsHitTesting(state.showChrome && !state.isJumping)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: state.showChrome)
                        .xSkyChromeFrame("controls")
                }
                .padding(.trailing, 18)
                .padding(.vertical, 14)
                .padding(.bottom, bottomScrollClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Space past the last educational control so it can rest fully above the bottom nav.
    /// Compact phones need extra room for the tab bar safeAreaInset + home indicator.
    private var bottomScrollClearance: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .compact ? 88 : 48
        #else
        return 48
        #endif
    }

    // MARK: - PlanetStage

    private var planetStage: some View {
        XSkyPlanetStage(
            state: state,
            debugOutline: debugPlanetOutline,
            onStageFrame: { planetFrame = $0 }
        )
        .accessibilitySortPriority(5)
    }

    private func planetStageHeight(availableHeight: CGFloat, wide: Bool) -> CGFloat {
        if wide {
            // iPad / Mac: larger proportional canvas (about 55–62% of available height).
            let proposed = availableHeight * 0.58
            return min(availableHeight * 0.72, max(360, proposed))
        }
        // Compact iPhone: preserve a substantial sky while keeping the landing caption
        // and primary jump action in the same viewport above the bottom tab bar.
        let proposed = availableHeight * 0.43
        let lower = availableHeight * 0.40
        let upper = availableHeight * 0.47
        return min(upper, max(lower, proposed))
    }

    // MARK: - Chrome pieces (never overlaid on PlanetStage)

    private var pageTitle: some View {
        Text("xSky Jump")
            .font(TimelyUNATheme.titleFont)
            .foregroundStyle(TimelyUNATheme.acid)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// FROM / TO journey chips — never truncated to single letters on compact widths.
    private var journeySummaryCompact: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                fromToCluster
                Spacer(minLength: 8)
                metricsCluster
            }
            VStack(alignment: .leading, spacing: 10) {
                fromToCluster
                metricsCluster
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "From \(state.departureName) to \(state.destinationName), \(state.distanceDescription), light delay \(state.lightDelayDescription)"
        )
    }

    private var fromToCluster: some View {
        HStack(spacing: 8) {
            labeledWorldChip(label: "FROM", value: state.departureName)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TimelyUNATheme.goldDeep)
                .accessibilityHidden(true)
            labeledWorldChip(label: "TO", value: state.destinationName)
        }
    }

    private var metricsCluster: some View {
        HStack(spacing: 6) {
            Text(state.distanceDescription)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("·")
                .foregroundStyle(TimelyUNATheme.muted)
                .accessibilityHidden(true)
            Text(state.lightDelayDescription)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func labeledWorldChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TimelyUNATheme.smallCaptionFont)
                .tracking(0.9)
                .foregroundStyle(TimelyUNATheme.muted)
                .lineLimit(1)
            Text(value)
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // Keep short world names fully visible (avoid “E…” / “…”).
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var activeWorldCaption: some View {
        Text(state.standingCaption)
            .font(TimelyUNATheme.subheadingFont)
            .foregroundStyle(TimelyUNATheme.papyrus)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(state.standingCaption)
    }

    private var controlsStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Observer World")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            Picker("Observer World", selection: $state.observer) {
                Text("Earth").tag(XSkyJumpState.ObserverWorld.earth)
                Text("Mars").tag(XSkyJumpState.ObserverWorld.mars)
            }
            .pickerStyle(.segmented)
            .disabled(state.isJumping)
            .onChange(of: state.observer) { _, new in
                if !state.isJumping {
                    state.phase = new == .earth ? .earth : .mars
                    state.lookTarget = new == .earth ? .mars : .earth
                    state.resetView()
                }
            }
            .accessibilityLabel("Observer World")

            Text("Look toward")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            Picker("Look toward", selection: $state.lookTarget) {
                if state.observer == .mars {
                    Text("Earth").tag(XSkyJumpState.LookTarget.earth)
                } else {
                    Text("Mars").tag(XSkyJumpState.LookTarget.mars)
                }
                Text("Venus").tag(XSkyJumpState.LookTarget.venus)
                Text("Mercury").tag(XSkyJumpState.LookTarget.mercury)
                Text("Sun").tag(XSkyJumpState.LookTarget.sun)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Look toward from \(state.observer.rawValue)")

            // Visible Now / Actual Now / Lightline
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    togglePill("Visible Now", $state.showVisibleNow, TimelyUNATheme.apparentSun)
                    togglePill("Actual Now", $state.showActualNow, TimelyUNATheme.acid)
                    togglePill("Lightline", $state.showLightline, TimelyUNATheme.gold)
                }
                VStack(alignment: .leading, spacing: 8) {
                    togglePill("Visible Now", $state.showVisibleNow, TimelyUNATheme.apparentSun)
                    togglePill("Actual Now", $state.showActualNow, TimelyUNATheme.acid)
                    togglePill("Lightline", $state.showLightline, TimelyUNATheme.gold)
                }
            }

            let offset = state.lookAngularOffsetDegrees()
            if offset.magnified {
                Text("Educational magnification ×\(String(format: "%.0f", offset.factor)) — visual gap enlarged (true ≈ \(String(format: "%.2f", offset.trueSep))°). Not literal sky separation.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $state.educationalMagnification) {
                Text("Educational magnification")
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
            }
            .tint(TimelyUNATheme.acid)

            // Secondary actions remain in the detail panel. The primary jump action
            // lives directly below PlanetStage so it is reachable with the sky visible.
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    secondaryButton("Reset View", systemImage: "arrow.counterclockwise") {
                        state.resetView()
                    }
                    if state.observer == .mars {
                        secondaryButton("Return to Earth", systemImage: "globe.americas.fill") {
                            hapticLaunch()
                            hapticMidFired = false
                            state.returnToEarth(reduceMotion: reduceMotion)
                        }
                    }
                }
            }

            Text(state.isOnSurface
                 ? "Select a world above to inspect the surface sky · swipe vertically to scroll · offline educational model"
                 : "Drag planet horizontally to orbit · pinch or scroll-wheel to zoom · swipe vertically to scroll · offline educational model")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
    }

    private var primaryJumpButton: some View {
        Button {
            hapticLaunch()
            hapticMidFired = false
            state.performJump(reduceMotion: reduceMotion)
        } label: {
            Label(
                state.observer == .earth ? "xSky Jump to Mars" : "xSky Jump to Earth",
                systemImage: "sparkles"
            )
            .font(TimelyUNATheme.calloutFont)
            .foregroundStyle(TimelyUNATheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .timelyUNAGlassSurface(
                cornerRadius: 14,
                tint: state.isJumping ? TimelyUNATheme.muted : TimelyUNATheme.acid,
                backing: state.isJumping ? TimelyUNATheme.muted : TimelyUNATheme.acid,
                backingOpacity: state.isJumping ? 0.62 : 0.82,
                stroke: state.isJumping ? TimelyUNATheme.muted : TimelyUNATheme.acid,
                strokeOpacity: 0.72,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .disabled(state.isJumping)
        .accessibilityHint("Begins the cinematic light-time journey between worlds")
    }

    /// Kept adjacent to PlanetStage instead of buried beneath the detail controls.
    /// This remains fully reachable while Earth or the Martian sky is still visible.
    private var reachablePrimaryJumpButton: some View {
        primaryJumpButton
            .opacity(state.showChrome ? 1 : 0)
            .allowsHitTesting(state.showChrome && !state.isJumping)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: state.showChrome)
            .xSkyChromeFrame("primaryAction")
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .timelyUNAGlassSurface(
                    cornerRadius: 22,
                    tint: TimelyUNATheme.gold,
                    backing: .black,
                    backingOpacity: 0.28,
                    stroke: TimelyUNATheme.line,
                    strokeOpacity: 0.86,
                    isInteractive: true
                )
        }
        .buttonStyle(.plain)
        .disabled(state.isJumping)
    }

    private func togglePill(_ title: String, _ binding: Binding<Bool>, _ color: Color) -> some View {
        Button {
            AppHaptics.selection()
            binding.wrappedValue.toggle()
        } label: {
            Text("\(title) \(binding.wrappedValue ? "On" : "Off")")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(binding.wrappedValue ? TimelyUNATheme.ink : TimelyUNATheme.papyrus)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .timelyUNAGlassSurface(
                    cornerRadius: 22,
                    tint: binding.wrappedValue ? color : TimelyUNATheme.gold,
                    backing: binding.wrappedValue ? color : .black,
                    backingOpacity: binding.wrappedValue ? 0.78 : 0.18,
                    stroke: binding.wrappedValue ? color : TimelyUNATheme.line,
                    strokeOpacity: binding.wrappedValue ? 0.7 : 0.34,
                    isInteractive: true
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(binding.wrappedValue ? "on" : "off")")
    }

    // MARK: - Haptics

    private func hapticLaunch() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func hapticArrival() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func handleJumpHaptics(progress: Double) {
        #if os(iOS)
        if progress > 0.5 && !hapticMidFired {
            hapticMidFired = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
}

#Preview {
    XSkyJumpView()
        .preferredColorScheme(.dark)
}
