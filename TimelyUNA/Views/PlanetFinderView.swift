import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Phase 1 Finder — practical “point me toward it” instrument.
/// Reuses SolarEngine, PlanetaryEphemeris, ObserverLocationService, HorizonClock, ARCelestialMath.
struct PlanetFinderView: View {
    @EnvironmentObject private var location: ObserverLocationService
    @EnvironmentObject private var clock: HorizonClock
    @EnvironmentObject private var persistence: HorizonPersistence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var motion = FinderMotionService()

    @State private var target: PlanetaryEphemeris.Body = .sun
    @State private var showActualComparison = true
    @State private var bodySnapshot: PlanetaryEphemeris.BodySnapshot?
    @State private var displayPair: ARCelestialMath.DisplayPair?
    @State private var guidance: FinderGuidance = .searching
    @State private var isLocked = false
    @State private var lockFlash = false
    @State private var showAR = false
    @State private var lastHapticBucket: Int = -1
    @State private var hapticTick = 0

    private var hasLocation: Bool { location.hasLiveCoordinates }

    private var bottomClearance: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .compact ? 88 : 48
        #else
        return 48
        #endif
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                header
                targetSelector
                if target == .sun {
                    sunSafetyBanner
                }
                locationOrInstrument
                if hasLocation {
                    instrumentPanel
                    readingsPanel
                    visibilityPanel
                    if target == .sun {
                        sunriseModePanel
                    }
                    comparisonPanel
                    honestyPanel
                    arButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .onAppear {
            location.resumeIfAuthorized()
            motion.start()
            recompute()
        }
        .onDisappear {
            motion.stop()
        }
        .onReceive(clock.$now) { _ in
            recompute()
            updateGuidance()
            driveHaptics()
        }
        .onChange(of: location.latitude) { _, _ in recompute() }
        .onChange(of: location.longitude) { _, _ in recompute() }
        .onChange(of: location.source) { _, _ in recompute() }
        .onChange(of: target) { _, _ in
            isLocked = false
            lockFlash = false
            lastHapticBucket = -1
            recompute()
        }
        .onChange(of: motion.filteredHeadingDegrees) { _, _ in updateGuidance() }
        .onChange(of: motion.elevationDegrees) { _, _ in updateGuidance() }
        .sheet(isPresented: $showAR) {
            #if os(iOS)
            ARSunRocketView(selectedDate: clock.now)
                .environmentObject(location)
                .environmentObject(persistence)
            #else
            ARSunRocketView(selectedDate: clock.now)
                .environmentObject(location)
                .environmentObject(persistence)
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                motion.updateInterfaceOrientation(scene.interfaceOrientation)
            }
        }
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finder")
                .font(TimelyUNATheme.titleFont)
                .foregroundStyle(TimelyUNATheme.acid)
                .accessibilityAddTraits(.isHeader)
            Text("Point me toward it — live heading, elevation, and light-time sky.")
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TARGET")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            // Scrollable chips so vertical page scroll is never blocked by a rigid control.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlanetaryEphemeris.Body.allCases) { body in
                        Button {
                            AppHaptics.selection()
                            target = body
                        } label: {
                            Label(body.rawValue, systemImage: body.symbol)
                                .font(TimelyUNATheme.captionFont)
                                .foregroundStyle(target == body ? TimelyUNATheme.ink : TimelyUNATheme.papyrus)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(
                                    target == body ? TimelyUNATheme.acid : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(body.rawValue)
                        .accessibilityAddTraits(target == body ? .isSelected : [])
                    }
                }
            }
        }
        .padding(14)
        .finderCard()
    }

    private var sunSafetyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TimelyUNATheme.orange)
            Text("Never look directly at the Sun or point magnifying optics at it. Finder guides with screen, heading, and motion — not by eye.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TimelyUNATheme.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TimelyUNATheme.orange.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel("Sun safety. Never look directly at the Sun or point magnifying optics at it.")
    }

    @ViewBuilder
    private var locationOrInstrument: some View {
        if !hasLocation {
            locationGate
        } else {
            EmptyView()
        }
    }

    private var locationGate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location required")
                .font(TimelyUNATheme.subheadingFont)
                .foregroundStyle(TimelyUNATheme.gold)
            Text(location.guidanceMessage ?? "Finder needs your location to compute altitude, azimuth, and rise times for your sky. Location data stays on this device.")
                .font(TimelyUNATheme.bodyFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AppHaptics.selection()
                location.requestLocation()
            } label: {
                Label(location.actionButtonTitle, systemImage: location.needsSettings ? "gear" : "location.fill")
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(TimelyUNATheme.acid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .finderCard()
    }

    private var instrumentPanel: some View {
        VStack(spacing: 14) {
            // Status
            Text(guidance.title)
                .font(TimelyUNATheme.subheadingFont)
                .foregroundStyle(guidance.color)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel("Target state: \(guidance.title)")

            // Reticle + directional arrow (driven by real heading deltas)
            ZStack {
                FinderSkyBackdrop(reduceMotion: reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                FinderReticle(
                    guidance: guidance,
                    horizontalDelta: horizontalDelta,
                    verticalDelta: verticalDelta,
                    targetAltitude: bodySnapshot?.visible.altitude,
                    targetAzimuth: bodySnapshot?.visible.azimuth,
                    deviceHeading: motion.filteredHeadingDegrees ?? motion.headingDegrees,
                    viewingElevation: motion.elevationDegrees,
                    isLocked: isLocked,
                    lockFlash: lockFlash,
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: 320, maxHeight: 320)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 280)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(TimelyUNATheme.line, lineWidth: 1)
            )

            // Turn / raise numbers — replaced when the target is under the ideal horizon
            if guidance == .belowHorizon {
                deltaChip(
                    title: "Below horizon",
                    value: bodySnapshot.map { SolarFormat.degrees($0.visible.altitude) } ?? "—",
                    symbol: "arrow.down.to.line"
                )
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        deltaChip(
                            title: horizontalDelta >= 0 ? "Turn right" : "Turn left",
                            value: SolarFormat.degrees(abs(horizontalDelta)),
                            symbol: horizontalDelta >= 0 ? "arrow.right" : "arrow.left"
                        )
                        deltaChip(
                            title: verticalDelta >= 0 ? "Raise phone" : "Lower phone",
                            value: SolarFormat.degrees(abs(verticalDelta)),
                            symbol: verticalDelta >= 0 ? "arrow.up" : "arrow.down"
                        )
                    }
                    VStack(spacing: 10) {
                        deltaChip(
                            title: horizontalDelta >= 0 ? "Turn right" : "Turn left",
                            value: SolarFormat.degrees(abs(horizontalDelta)),
                            symbol: horizontalDelta >= 0 ? "arrow.right" : "arrow.left"
                        )
                        deltaChip(
                            title: verticalDelta >= 0 ? "Raise phone" : "Lower phone",
                            value: SolarFormat.degrees(abs(verticalDelta)),
                            symbol: verticalDelta >= 0 ? "arrow.up" : "arrow.down"
                        )
                    }
                }
            }

            if motion.needsCalibration {
                Text(motion.statusMessage)
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(motion.statusMessage)
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .finderCard()
    }

    private var readingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIVE READINGS")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                readingCell("Target altitude", bodySnapshot.map { SolarFormat.degrees($0.visible.altitude) } ?? "—")
                readingCell("Target azimuth", bodySnapshot.map { SolarFormat.degrees($0.visible.azimuth) } ?? "—")
                readingCell("Device heading", motion.filteredHeadingDegrees.map { SolarFormat.degrees($0) } ?? "—")
                readingCell("Viewing elevation", motion.elevationDegrees.map { SolarFormat.degrees($0) } ?? (motion.motionAvailable ? "…" : "N/A"))
                readingCell("Light delay", bodySnapshot.map { PlanetaryEphemeris.lightDelayDescription($0.lightTimeSeconds) } ?? "—")
                readingCell("Distance", bodySnapshot.map { String(format: "%.4f AU", $0.distanceAU) } ?? "—")
            }
        }
        .padding(14)
        .finderCard()
        .accessibilityElement(children: .combine)
    }

    private var visibilityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VISIBILITY")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            Text(visibilityExplanation)
                .font(TimelyUNATheme.bodyFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)

            if let snap = bodySnapshot, !snap.isAboveHorizon, let rise = snap.nextRise {
                Text("Next estimated rise: \(rise.formatted(date: .omitted, time: .shortened)) (ideal astronomical horizon).")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .finderCard()
    }

    private var sunriseModePanel: some View {
        let snap = hasLocation ? SolarEngine.snapshot(
            date: clock.now,
            latitude: location.latitude ?? 0,
            longitude: location.longitude ?? 0
        ) : nil

        return VStack(alignment: .leading, spacing: 12) {
            Text("TRUE HORIZON SUNRISE")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            if let snap {
                sunriseRows(snap: snap)
                sunriseStory(snap: snap)
            } else {
                Text("Location required for sunrise mode.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
            }
        }
        .padding(14)
        .finderCard()
    }

    @ViewBuilder
    private func sunriseRows(snap: SolarEngine.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledTime("VISIBLE SUNRISE", snap.sunrise)
            labeledTime("ACTUAL-NOW HORIZON (model)", snap.trueSunrise)
            HStack {
                Text("PHOTON DELAY")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                Spacer()
                Text(SolarFormat.lightDelayWords(snap.lightTimeSeconds))
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.gold)
            }
            if let visible = snap.sunrise {
                let remaining = visible.timeIntervalSince(clock.now)
                if remaining > 0 {
                    Text("Countdown to visible sunrise: \(countdownString(remaining))")
                        .font(TimelyUNATheme.calloutFont)
                        .foregroundStyle(TimelyUNATheme.acid)
                        .accessibilityLabel("Countdown to visible sunrise \(countdownString(remaining))")
                } else if remaining > -3600 {
                    Text("Visible sunrise has occurred for this modeled horizon.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                }
            }
        }
    }

    @ViewBuilder
    private func sunriseStory(snap: SolarEngine.Snapshot) -> some View {
        let approaching = isTrueSunriseApproaching(snap: snap)
        if approaching {
            VStack(alignment: .leading, spacing: 8) {
                Text("True Sunrise Approaching")
                    .font(TimelyUNATheme.subheadingFont)
                    .foregroundStyle(TimelyUNATheme.acid)

                SunriseMarkerStrip(
                    apparentAltitude: snap.apparent.altitude,
                    actualAltitude: snap.truePosition.altitude,
                    reduceMotion: reduceMotion
                )
                .frame(height: 72)

                Text("The Sun’s modeled Actual Now position has crossed the True Horizon. Its updated light has not reached you yet.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Visible sunrise occurs when arriving sunlight reaches your apparent horizon.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Text("Actual Now is a light-time model, not early visible sunlight.")
            .font(TimelyUNATheme.captionFont)
            .foregroundStyle(TimelyUNATheme.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var comparisonPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $showActualComparison) {
                Text("Visible Now vs Actual Now")
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
            }
            .tint(TimelyUNATheme.acid)

            if showActualComparison, let pair = displayPair, let snap = bodySnapshot {
                HStack(spacing: 12) {
                    legendDot(TimelyUNATheme.apparentSun, "Visible Now / Arriving Light")
                    legendDot(TimelyUNATheme.acid, "Actual Now / Light-Time Model")
                }

                Text("True angular separation: \(SolarFormat.degrees(pair.trueSeparationDegrees, places: 3))")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)

                if pair.isMagnified {
                    Text("Educational inset ×\(String(format: "%.0f", pair.magnificationFactor)) — the real gap is too small to show at full scale. Not a literal sky separation.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if snap.body == .moon {
                    Text("Moon light time is \(PlanetaryEphemeris.lightDelayDescription(snap.lightTimeSeconds)) — independent of the Sun’s photon delay.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .finderCard()
    }

    private var honestyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT THESE ESTIMATES")
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.goldDeep)

            Text("Sunrise and sky positions use an ideal astronomical horizon. Atmospheric refraction, observer elevation, terrain, buildings, and weather also matter. Finder indicates calculated direction and does not guarantee visibility through clouds, daylight glare, or local obstacles. Educational estimates — not navigation- or safety-grade.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .finderCard()
    }

    @ViewBuilder
    private var arButton: some View {
        let arSupported: Bool = {
            #if os(iOS)
            return ARCalibrationService.worldTrackingSupported
            #else
            return false
            #endif
        }()

        VStack(spacing: 10) {
            Button {
                AppHaptics.selection()
                showAR = true
            } label: {
                Label(
                    isLocked ? "Open in AR" : "Open educational AR sky",
                    systemImage: "camera.viewfinder"
                )
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    (isLocked || target == .sun) ? TimelyUNATheme.acid : TimelyUNATheme.gold,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasLocation)
            .opacity(hasLocation ? 1 : 0.5)
            .accessibilityHint(isLocked
                ? "Opens AR after target alignment"
                : "Opens educational AR sky mode")

            if !arSupported {
                Text("World-tracking AR is unavailable on this device. Finder remains fully useful with heading and altitude guidance.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if target != .sun {
                Text("AR currently places the educational Sun light-time model. Planet and Moon aiming stay on this Finder screen.")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Guidance math

    private var horizontalDelta: Double {
        guard let heading = motion.filteredHeadingDegrees ?? motion.headingDegrees,
              let snap = bodySnapshot else { return 0 }
        return ARCelestialMath.shortestAzimuthDelta(from: heading, to: snap.visible.azimuth)
    }

    private var verticalDelta: Double {
        guard let snap = bodySnapshot else { return 0 }
        // relativeElevation = targetAltitude − viewingElevation
        if let elev = motion.elevationDegrees {
            return ARCelestialMath.relativeElevation(
                targetAltitude: snap.visible.altitude,
                viewingElevation: elev
            )
        }
        // No pitch sensor: altitude itself is the offset from the instrument horizon (center).
        return snap.visible.altitude
    }

    private func recompute() {
        guard let lat = location.latitude, let lon = location.longitude, location.hasLiveCoordinates else {
            bodySnapshot = nil
            displayPair = nil
            return
        }
        let snap = PlanetaryEphemeris.snapshot(
            body: target,
            date: clock.now,
            latitude: lat,
            longitude: lon
        )
        bodySnapshot = snap
        displayPair = ARCelestialMath.educationalDisplayPair(
            visible: snap.visible,
            actual: snap.actual
        )
        updateGuidance()
    }

    private func updateGuidance() {
        guard hasLocation, let snap = bodySnapshot else {
            guidance = .searching
            isLocked = false
            return
        }

        if motion.headingSource == .none && motion.availability != .ready {
            // Compass-only fallback: still show altitude-based vertical cue.
            if !snap.isAboveHorizon {
                guidance = .belowHorizon
                isLocked = false
                return
            }
            guidance = .searching
            return
        }

        if !snap.isAboveHorizon {
            guidance = .belowHorizon
            isLocked = false
            return
        }

        let h = abs(horizontalDelta)
        let hasElevation = motion.elevationDegrees != nil
        let v = abs(verticalDelta)
        let lockThreshold: Double = 4.0
        let almost: Double = 12.0

        // Compass-only devices can lock on heading; with elevation both axes must agree.
        let aligned = hasElevation
            ? (h <= lockThreshold && v <= lockThreshold)
            : (h <= lockThreshold)

        if aligned {
            if !isLocked {
                isLocked = true
                fireLockHaptic()
                if reduceMotion {
                    lockFlash = true
                } else {
                    withAnimation(.easeOut(duration: 0.45)) { lockFlash = true }
                }
            }
            guidance = .locked
            return
        }

        isLocked = false
        lockFlash = false

        let nearly = hasElevation ? (h <= almost && v <= almost) : (h <= almost)
        if nearly {
            guidance = .almost
            return
        }

        // Prefer the larger error axis for primary instruction.
        if !hasElevation || h >= v {
            guidance = horizontalDelta >= 0 ? .turnRight : .turnLeft
        } else {
            guidance = verticalDelta >= 0 ? .raise : .lower
        }
    }

    private var visibilityExplanation: String {
        guard let snap = bodySnapshot else {
            return "Waiting for location to assess visibility."
        }
        if !snap.isAboveHorizon {
            return "\(snap.body.rawValue) is below the ideal astronomical horizon right now (altitude \(SolarFormat.degrees(snap.visible.altitude))). Finder shows the calculated direction for when it rises — not a guarantee through terrain or weather."
        }
        switch snap.body {
        case .sun:
            if snap.visible.altitude > 0 {
                return "The Sun is above the ideal horizon. Daylight, glare, and clouds can still hide features; never look at the Sun. Finder indicates calculated direction only."
            }
            return "The Sun is near the horizon in the model. Atmospheric refraction, elevation, and weather affect the real moment of visibility."
        case .moon:
            return "The Moon is above the ideal horizon in this model. Bright twilight, clouds, or buildings may still obscure it. Light delay is only about \(PlanetaryEphemeris.lightDelayDescription(snap.lightTimeSeconds))."
        default:
            if snap.visible.altitude < 15 {
                return "\(snap.body.rawValue) is low in the sky (altitude \(SolarFormat.degrees(snap.visible.altitude))). Atmosphere, trees, and buildings often block low objects. Finder shows calculated direction, not guaranteed visibility."
            }
            return "\(snap.body.rawValue) is positionally above the ideal horizon. Daylight, haze, or light pollution may prevent a visual sighting — Finder indicates calculated direction only."
        }
    }

    private func isTrueSunriseApproaching(snap: SolarEngine.Snapshot) -> Bool {
        guard let visible = snap.sunrise else { return false }
        let delay = snap.lightTimeSeconds
        let windowStart = visible.addingTimeInterval(-delay)
        // Active from one photon delay before visible sunrise until visible sunrise.
        return clock.now >= windowStart && clock.now <= visible.addingTimeInterval(120)
            && snap.truePosition.altitude > -1
    }

    // MARK: - Haptics

    private func driveHaptics() {
        #if os(iOS)
        guard hasLocation, bodySnapshot?.isAboveHorizon == true else { return }
        guard motion.headingSource != .none else { return }
        if isLocked { return }

        let sep = hypot(horizontalDelta, verticalDelta)
        // Buckets: 0 far (>45), 1 mid (20-45), 2 near (8-20), 3 almost (<8)
        let bucket: Int
        if sep > 45 { bucket = 0 }
        else if sep > 20 { bucket = 1 }
        else if sep > 8 { bucket = 2 }
        else { bucket = 3 }

        hapticTick += 1
        let period: Int
        switch bucket {
        case 0: period = 8   // ~every 8s at 1Hz clock
        case 1: period = 4
        case 2: period = 2
        default: period = 1
        }
        if hapticTick % period == 0 {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = bucket >= 2 ? .medium : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: bucket >= 2 ? 0.85 : 0.55)
        }
        lastHapticBucket = bucket
        #endif
    }

    private func fireLockHaptic() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - Small UI bits

    private func deltaChip(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(TimelyUNATheme.acid)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                Text(value)
                    .font(TimelyUNATheme.subheadingFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func readingCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted)
            Text(value)
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func labeledTime(_ title: String, _ date: Date?) -> some View {
        HStack {
            Text(title)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
            Spacer()
            Text(date?.formatted(date: .omitted, time: .shortened) ?? "—")
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .monospacedDigit()
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func countdownString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Guidance state

private enum FinderGuidance: Equatable {
    case searching
    case turnLeft
    case turnRight
    case raise
    case lower
    case almost
    case locked
    case belowHorizon

    var title: String {
        switch self {
        case .searching: return "Searching…"
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .raise: return "Raise phone"
        case .lower: return "Lower phone"
        case .almost: return "Almost aligned"
        case .locked: return "Target found"
        case .belowHorizon: return "Below horizon"
        }
    }

    var color: Color {
        switch self {
        case .locked: return TimelyUNATheme.acid
        case .almost: return TimelyUNATheme.gold
        case .belowHorizon: return TimelyUNATheme.orange
        default: return TimelyUNATheme.papyrus
        }
    }
}

// MARK: - Reticle

private struct FinderReticle: View {
    let guidance: FinderGuidance
    let horizontalDelta: Double
    let verticalDelta: Double
    let targetAltitude: Double?
    let targetAzimuth: Double?
    let deviceHeading: Double?
    let viewingElevation: Double?
    let isLocked: Bool
    let lockFlash: Bool
    let reduceMotion: Bool

    /// Instrument half-FOV (degrees) → ±1 normalized offset at the usable edge.
    private let halfHorizontalFOV: Double = 35
    private let halfVerticalFOV: Double = 30

    private var isBelowHorizon: Bool {
        guidance == .belowHorizon
            || targetAltitude.map { ARCelestialMath.isBelowHorizon(targetAltitude: $0) } == true
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let inset = max(14, side * 0.08)

            // relativeElevation → normalized → screenY → edge clamp
            // Below horizon: force bottom clamp (fixture: alt −15.38°, elev +29.69° → bottom).
            let placement: ARCelestialMath.ScreenPlacement = {
                if let alt = targetAltitude, let az = targetAzimuth {
                    return ARCelestialMath.finderScreenPlacement(
                        targetAltitude: alt,
                        targetAzimuth: az,
                        deviceHeading: deviceHeading,
                        viewingElevation: viewingElevation,
                        viewSize: geo.size,
                        halfHorizontalFOVDegrees: halfHorizontalFOV,
                        halfVerticalFOVDegrees: halfVerticalFOV,
                        edgeInset: inset
                    )
                }
                return ARCelestialMath.screenPlacement(
                    relativeAzimuthDegrees: horizontalDelta,
                    relativeElevationDegrees: verticalDelta,
                    viewSize: geo.size,
                    halfHorizontalFOVDegrees: halfHorizontalFOV,
                    halfVerticalFOVDegrees: halfVerticalFOV,
                    edgeInset: inset,
                    forceBottomClamp: isBelowHorizon
                )
            }()
            let pip = placement.screenPoint
            let arrowAngle = Angle(degrees: horizontalDelta)
            let pipColor = isBelowHorizon ? TimelyUNATheme.orange : TimelyUNATheme.acid
            let guideColor = isBelowHorizon ? TimelyUNATheme.orange : TimelyUNATheme.acid

            ZStack {
                // Outer ring
                Circle()
                    .stroke(TimelyUNATheme.line, lineWidth: 1.5)
                    .frame(width: side * 0.88, height: side * 0.88)

                // Crosshair
                Path { p in
                    p.move(to: CGPoint(x: center.x, y: center.y - side * 0.38))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + side * 0.38))
                    p.move(to: CGPoint(x: center.x - side * 0.38, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + side * 0.38, y: center.y))
                }
                .stroke(TimelyUNATheme.goldDeep.opacity(0.35), lineWidth: 1)

                // Ideal horizon tick (instrument center line is aim; light mark for sky horizon cue)
                if isBelowHorizon {
                    Path { p in
                        p.move(to: CGPoint(x: center.x - side * 0.32, y: center.y))
                        p.addLine(to: CGPoint(x: center.x + side * 0.32, y: center.y))
                    }
                    .stroke(TimelyUNATheme.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                // Center reticle (aim point)
                Circle()
                    .stroke(isLocked ? TimelyUNATheme.acid : TimelyUNATheme.papyrus.opacity(0.7), lineWidth: isLocked ? 3 : 1.5)
                    .frame(width: side * 0.16, height: side * 0.16)
                    .position(center)
                    .scaleEffect(lockFlash && !reduceMotion ? 1.15 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatCount(2, autoreverses: true), value: lockFlash)

                if isLocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: side * 0.12))
                        .foregroundStyle(TimelyUNATheme.acid)
                        .position(center)
                        .transition(.opacity)
                } else {
                    // Continuous target pip — bottom-clamped when below horizon
                    Circle()
                        .fill(pipColor.opacity(placement.isClampedToEdge ? 0.6 : 0.92))
                        .frame(width: side * 0.055, height: side * 0.055)
                        .overlay(
                            Circle()
                                .stroke(
                                    isBelowHorizon ? TimelyUNATheme.orange : TimelyUNATheme.gold,
                                    lineWidth: placement.clampedBottom || placement.isClampedToEdge ? 2 : 1
                                )
                        )
                        .position(pip)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.86), value: pip.x)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.86), value: pip.y)
                        .accessibilityHidden(true)

                    Path { p in
                        p.move(to: center)
                        p.addLine(to: pip)
                    }
                    .stroke(guideColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if placement.clampedBottom || isBelowHorizon {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isBelowHorizon ? TimelyUNATheme.orange : TimelyUNATheme.gold)
                            .position(x: pip.x, y: min(geo.size.height - 10, pip.y + side * 0.06))
                    }
                    if placement.clampedTop && !isBelowHorizon {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TimelyUNATheme.gold)
                            .position(x: pip.x, y: max(10, pip.y - side * 0.06))
                    }
                    if placement.clampedLeft && !isBelowHorizon {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TimelyUNATheme.gold)
                            .position(x: max(10, pip.x - side * 0.06), y: pip.y)
                    }
                    if placement.clampedRight && !isBelowHorizon {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TimelyUNATheme.gold)
                            .position(x: min(geo.size.width - 10, pip.x + side * 0.06), y: pip.y)
                    }

                    if isBelowHorizon {
                        Text("Below horizon")
                            .font(TimelyUNATheme.smallCaptionFont)
                            .foregroundStyle(TimelyUNATheme.orange)
                            .position(x: center.x, y: min(geo.size.height - 8, pip.y + side * 0.12))
                    } else if abs(horizontalDelta) > halfHorizontalFOV * 0.85 {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: side * 0.1, weight: .semibold))
                            .foregroundStyle(TimelyUNATheme.acid.opacity(0.85))
                            .rotationEffect(arrowAngle)
                            .position(x: center.x, y: center.y - side * 0.36)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guidance.title)
        .accessibilityValue(
            isBelowHorizon
                ? "Target below ideal horizon. Altitude \(targetAltitude.map { String(format: "%.1f", $0) } ?? "—") degrees."
                : "Horizontal \(String(format: "%.0f", abs(horizontalDelta))) degrees. Vertical \(String(format: "%.0f", abs(verticalDelta))) degrees."
        )
    }
}

private struct FinderSkyBackdrop: View {
    let reduceMotion: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.14),
                    Color.black,
                    Color(red: 0.08, green: 0.05, blue: 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Horizon glow
            RadialGradient(
                colors: [TimelyUNATheme.orange.opacity(0.22), .clear],
                center: .bottom,
                startRadius: 4,
                endRadius: 160
            )
            .offset(y: 80)

            Canvas { context, size in
                for i in 0..<40 {
                    let x = pseudo(i * 17) * size.width
                    let y = pseudo(i * 41 + 3) * size.height * 0.72
                    let r = 0.6 + pseudo(i * 9) * 1.4
                    let twinkle = reduceMotion ? 0.55 : 0.35 + 0.45 * abs(sin(Double(phase) + Double(i)))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(.white.opacity(twinkle))
                    )
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func pseudo(_ n: Int) -> CGFloat {
        let x = sin(Double(n) * 12.9898) * 43758.5453
        return CGFloat(x - floor(x))
    }
}

private struct SunriseMarkerStrip: View {
    let apparentAltitude: Double
    let actualAltitude: Double
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let horizonY = h * 0.62
            let apparentY = altitudeY(apparentAltitude, height: h)
            let actualY = altitudeY(actualAltitude, height: h)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                // Horizon line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: horizonY))
                    p.addLine(to: CGPoint(x: w, y: horizonY))
                }
                .stroke(TimelyUNATheme.goldDeep.opacity(0.7), lineWidth: 1)

                Text("Horizon")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .position(x: 36, y: horizonY - 10)

                Circle()
                    .fill(TimelyUNATheme.apparentSun)
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.35, y: apparentY)
                    .accessibilityLabel("Visible Now Sun marker")

                Circle()
                    .stroke(TimelyUNATheme.acid, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .position(x: w * 0.65, y: actualY)
                    .accessibilityLabel("Actual Now Sun marker")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Map altitude −10…+15° into strip height.
    private func altitudeY(_ alt: Double, height: CGFloat) -> CGFloat {
        let t = (alt + 10) / 25
        return height * (1 - CGFloat(min(1, max(0, t))))
    }
}

// MARK: - Card chrome

private extension View {
    func finderCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TimelyUNATheme.line, lineWidth: 1)
            )
    }
}

#Preview {
    PlanetFinderView()
        .environmentObject(ObserverLocationService())
        .environmentObject(HorizonClock())
        .preferredColorScheme(.dark)
}
