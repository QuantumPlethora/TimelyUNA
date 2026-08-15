import SwiftUI

private struct HorizonInterfaceRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the cold-launch opening still covers the live interface.
    var horizonInterfaceRevealed: Bool {
        get { self[HorizonInterfaceRevealedKey.self] }
        set { self[HorizonInterfaceRevealedKey.self] = newValue }
    }
}

/// True Horizon daily screen — cinematic native composition.
/// Visible Now / Actual Now is the central story; the daily ritual lives below.
struct TrueHorizonView: View {
    @EnvironmentObject private var simulation: SimulationState
    @EnvironmentObject private var location: ObserverLocationService
    @EnvironmentObject private var persistence: HorizonPersistence
    @EnvironmentObject private var clock: HorizonClock
    @EnvironmentObject private var sunriseReminder: SunriseReminderService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.horizonInterfaceRevealed) private var horizonInterfaceRevealed

    @State private var snapshot: SolarEngine.Snapshot?
    @State private var toastMessage: String?
    @State private var launchAnimating = false
    @State private var skyPulse = false

    private static let rocketClass = "BABY SPCX"
    private static let rocketName = "BEAUTEOUS MAXIMUS"

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(0, geo.size.width)
            let wide = contentWidth >= 820 && horizontalSizeClass != .compact
            let narrow = contentWidth < 520 || horizontalSizeClass == .compact
            let pad: CGFloat = {
                if contentWidth > 1000 { return 32 }
                if contentWidth > 700 { return 22 }
                if contentWidth > 400 { return 16 }
                return 12
            }()
            // Stage scales with width; never wider than available content, avoid clipping labels.
            let stageHeight: CGFloat = {
                if wide { return min(360, contentWidth * 0.38) }
                if narrow {
                    let h = contentWidth * 0.72
                    return min(300, max(200, h))
                }
                return min(320, max(240, contentWidth * 0.48))
            }()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    topChrome(wide: wide, narrow: narrow)
                        .padding(.horizontal, pad)
                        .padding(.top, 6)

                    observerStrip(narrow: narrow)
                        .padding(.horizontal, pad)
                        .padding(.top, 14)

                    // Central story — full width
                    solarStage(height: stageHeight)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, pad)
                        .padding(.top, 18)

                    replayLightLineButton
                        .padding(.horizontal, pad)
                        .padding(.top, 10)

                    nowLegend
                        .padding(.horizontal, pad)
                        .padding(.top, 14)

                    // Daily ritual lives below the visualization (scroll to complete)
                    ritualSection(wide: wide)
                        .padding(.horizontal, pad)
                        .padding(.top, 22)
                        .id("daily-ritual")

                    sunriseSection
                        .padding(.horizontal, pad)
                        .padding(.top, 18)

                    footerActions
                        .padding(.horizontal, pad)
                        .padding(.top, 18)
                        // Extra bottom inset so last ritual/share controls clear the compact tab bar
                        // and home indicator when scrolling to end.
                        .padding(.bottom, narrow ? 96 : 56)
                }
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .frame(width: contentWidth)
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            persistence.reload()
            location.resumeIfAuthorized()
            recomputeSolar()
            startMotion()
            if horizonInterfaceRevealed {
                simulation.beginLightLineIfNeeded()
            }
            Task { await sunriseReminder.refreshStatus() }
        }
        .onChange(of: horizonInterfaceRevealed) { _, revealed in
            if revealed {
                simulation.beginLightLineIfNeeded()
            }
        }
        .onReceive(clock.solarTick) { _ in
            recomputeSolar()
            rescheduleReminderIfNeeded()
        }
        .onChange(of: location.latitude) { _, _ in
            recomputeSolar()
            rescheduleReminderIfNeeded()
        }
        .onChange(of: location.longitude) { _, _ in
            recomputeSolar()
            rescheduleReminderIfNeeded()
        }
        .onChange(of: location.source) { _, _ in
            recomputeSolar()
            rescheduleReminderIfNeeded()
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(TimelyUNATheme.acid, in: Capsule())
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.28), value: toastMessage)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Top

    private func topChrome(wide: Bool, narrow: Bool) -> some View {
        let titleBlock = VStack(alignment: .leading, spacing: 8) {
            Text("01 · DAILY RITUAL · TRUE HORIZON")
                .font(TimelyUNATheme.captionFont)
                .tracking(narrow ? 1.4 : 2.4)
                .foregroundStyle(TimelyUNATheme.goldDeep)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text("See the Sun where it truly is.")
                .font(wide ? TimelyUNATheme.displayFont : (narrow ? TimelyUNATheme.sectionFont : TimelyUNATheme.titleFont))
                .foregroundStyle(TimelyUNATheme.gold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Light takes a calculated delay—driven by today’s Earth–Sun distance—to reach your eyes.")
                .font(TimelyUNATheme.bodyFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640, alignment: .leading)
        }

        return Group {
            if narrow {
                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    streakBadge
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    titleBlock
                    Spacer(minLength: 8)
                    streakBadge
                }
            }
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 8) {
            Text("\(persistence.streak)")
                .font(TimelyUNATheme.headlineFont)
                .foregroundStyle(TimelyUNATheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(TimelyUNATheme.acid, in: Capsule())

            VStack(alignment: .leading, spacing: 0) {
                Text("STREAK")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.4)
                    .foregroundStyle(TimelyUNATheme.goldDeep)
                Text(persistence.streak == 1 ? "1 day" : "\(persistence.streak) days")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay(Capsule().stroke(TimelyUNATheme.line, lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(persistence.streak) days")
    }

    // MARK: - Observer (thin strip — not a gray card)

    private func observerStrip(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Narrow / compact: always stack so date, time, coords, source never overflow.
            if narrow {
                VStack(alignment: .leading, spacing: 10) {
                    stripCell("DATE", clock.now.formatted(date: .complete, time: .omitted))
                    stripCell("TIME", clock.now.formatted(date: .omitted, time: .standard))
                    stripCell("COORDS", location.coordinateLabel)
                    stripCell("SOURCE", location.sourceBadge)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        stripCell("DATE", clock.now.formatted(date: .complete, time: .omitted))
                        stripDivider
                        stripCell("TIME", clock.now.formatted(date: .omitted, time: .standard))
                        stripDivider
                        stripCell("COORDS", location.coordinateLabel)
                        stripDivider
                        stripCell("SOURCE", location.sourceBadge)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        stripCell("DATE", clock.now.formatted(date: .complete, time: .omitted))
                        stripCell("TIME", clock.now.formatted(date: .omitted, time: .standard))
                        stripCell("COORDS", location.coordinateLabel)
                        stripCell("SOURCE", location.sourceBadge)
                    }
                }
            }

            if !location.hasLiveCoordinates {
                locationPrompt
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(location.statusMessage)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.acid)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        locationButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(location.statusMessage)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.acid)
                            .fixedSize(horizontal: false, vertical: true)
                        locationButton
                    }
                }
            }

            Text("Educational visualization · not for navigation, surveying, or safety-critical astronomy.")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(TimelyUNATheme.line).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(TimelyUNATheme.line).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var locationPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(location.statusMessage)
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.gold)

            if let guidance = location.guidanceMessage {
                Text(guidance)
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    locationButton
                    if location.needsSettings { howToEnableButton }
                }
                VStack(alignment: .leading, spacing: 10) {
                    locationButton
                    if location.needsSettings { howToEnableButton }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TimelyUNATheme.acid.opacity(0.35), lineWidth: 1)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .accessibilityElement(children: .contain)
    }

    private var howToEnableButton: some View {
        Button {
            location.openSystemLocationSettings()
        } label: {
            Text("How to enable")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.acid)
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .overlay(Capsule().stroke(TimelyUNATheme.acid.opacity(0.6), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Settings for Location Services")
    }

    private var locationButton: some View {
        Button {
            let before = location.source
            location.requestLocation()
            if before == .notRequested || before == .fixFailed {
                showToast("Requesting location…")
            } else if location.needsSettings {
                showToast("Opening Location Settings…")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: location.hasLiveCoordinates ? "location.fill" : "location")
                Text(location.actionButtonTitle)
                    .font(TimelyUNATheme.calloutFont)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(TimelyUNATheme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                location.source == .requesting ? TimelyUNATheme.muted : TimelyUNATheme.gold,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(location.source == .requesting)
        .accessibilityLabel(location.actionButtonTitle)
        .accessibilityHint("Requests Core Location for live educational solar calculations. Exact latitude and longitude appear only in this screen’s observer strip after a live fix.")
    }

    private func stripCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(TimelyUNATheme.smallCaptionFont)
                .tracking(1.5)
                .foregroundStyle(TimelyUNATheme.goldDeep)
            Text(value)
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(TimelyUNATheme.line.opacity(0.7))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 10)
    }

    // MARK: - Central solar stage (the story)

    private func solarStage(height: CGFloat) -> some View {
        ZStack {
            // Deep stage
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            TimelyUNATheme.acid.opacity(0.10),
                            Color(red: 0.05, green: 0.05, blue: 0.04),
                            Color.black
                        ],
                        center: UnitPoint(x: 0.72, y: 0.28),
                        startRadius: 10,
                        endRadius: 420
                    )
                )

            // Orbits + scene
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: simulation.lightLineFinished)) { timeline in
                Canvas { context, size in
                    drawSolarStage(context: context, size: size, time: timeline.date)
                }
            }
            .id(simulation.lightLineGeneration)

            // Corner labels (editorial, not cards)
            VStack {
                HStack(alignment: .top, spacing: 8) {
                    Text("ARRIVING LIGHT")
                        .font(TimelyUNATheme.smallCaptionFont)
                        .tracking(1.4)
                        .foregroundStyle(TimelyUNATheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if let snapshot {
                        Text("☉ \(SolarFormat.lightDelayCompact(snapshot.lightTimeSeconds)) DELAY")
                            .font(TimelyUNATheme.captionFont)
                            .tracking(1.0)
                            .foregroundStyle(TimelyUNATheme.acid)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("LOCATION REQUIRED")
                            .font(TimelyUNATheme.captionFont)
                            .tracking(1.0)
                            .foregroundStyle(TimelyUNATheme.orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(12)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
        .shadow(color: TimelyUNATheme.acid.opacity(0.08), radius: 30, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stageAccessibilityLabel)
    }

    private var stageAccessibilityLabel: String {
        guard let snapshot else {
            return "Solar stage showing Visible Now and Actual Now. Live altitude and delay require your location."
        }
        return """
        Visible Now: altitude \(SolarFormat.degrees(snapshot.apparent.altitude)), \
        azimuth \(SolarFormat.degrees(snapshot.apparent.azimuth)). \
        Actual Now: altitude \(SolarFormat.degrees(snapshot.truePosition.altitude)), \
        azimuth \(SolarFormat.degrees(snapshot.truePosition.azimuth)). \
        Photon delay \(SolarFormat.lightDelayWords(snapshot.lightTimeSeconds)). \
        A photon leaves the emission Sun toward you. A full-sized ghost Sun continues along the Sun’s path for the same light-delay interval. VISIBLE NOW and ACTUAL NOW appear together when the photon arrives. \
        Distance \(SolarFormat.au(snapshot.distanceAU)) astronomical units. Computed from live location. \
        Baby SPCX rocket Beauteous Maximus travels across the TimelyUNA gap from Apparent Now to Actual Now. Educational visualization, not for navigation.
        """
    }

    private func drawSolarStage(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height
        let cx = w * 0.52
        let cy = h * 0.48

        // Star field
        for i in 0..<110 {
            let x = frac(i * 19 + 3) * w
            let y = frac(i * 41 + 7) * h
            let d = 0.5 + frac(i * 13) * 1.8
            var star = context
            star.opacity = 0.15 + frac(i * 29) * 0.55
            star.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white))
        }

        // Orbital rings (solar-stage style)
        for (idx, radius) in [0.18, 0.28, 0.38].enumerated() {
            let r = min(w, h) * radius
            var orbit = Path()
            orbit.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            context.stroke(orbit, with: .color(.white.opacity(0.07 + Double(idx) * 0.02)), lineWidth: 1)
        }

        // Horizon ground wash
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.82))
        ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.80), control: CGPoint(x: w * 0.5, y: h * 0.76))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        context.fill(
            ground,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.14, green: 0.12, blue: 0.08).opacity(0.85),
                    Color.black
                ]),
                startPoint: CGPoint(x: 0, y: h * 0.78),
                endPoint: CGPoint(x: 0, y: h)
            )
        )
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: h * 0.82))
        horizon.addQuadCurve(to: CGPoint(x: w, y: h * 0.80), control: CGPoint(x: w * 0.5, y: h * 0.76))
        context.stroke(horizon, with: .color(TimelyUNATheme.gold.opacity(0.35)), lineWidth: 1.2)

        // Positions — story geometry
        let you = CGPoint(x: w * 0.42, y: h * 0.86)
        let emission = CGPoint(x: w * 0.22, y: h * 0.48)
        let actual = CGPoint(x: w * 0.78, y: h * 0.30)
        let sunRadius = min(w, h) * 0.088
        let ghostPathLength = hypot(actual.x - emission.x, actual.y - emission.y)
        let lightTime = snapshot?.lightTimeSeconds ?? SolarEngine.lightSecondsPerAU
        let lesson = HorizonLightLesson.resolve(
            lightTimeSeconds: lightTime,
            visualPathLength: ghostPathLength,
            elapsed: simulation.lightLineElapsed(now: time),
            reduceMotion: reduceMotion,
            lockedComplete: simulation.lightLineFinished
        )
        if lesson.phase == .labelsRevealed, lesson.labelReveal >= 1, !simulation.lightLineFinished {
            DispatchQueue.main.async {
                simulation.markLightLineFinished()
            }
        }
        let progress = lesson.progress
        let photonPos = HorizonLightLesson.position(from: emission, to: you, at: progress)
        let ghostPos = HorizonLightLesson.position(from: emission, to: actual, at: progress)
        let photonDash = lightLineDashPhase(at: time)

        // Photon geodesic is always the light path. Sun-trajectory and gap
        // lines wait for arrival so the result is not pre-drawn.
        drawDashedLine(
            context: context,
            from: emission,
            to: you,
            color: TimelyUNATheme.gold.opacity(0.75),
            phase: photonDash,
            width: 1.8
        )
        if lesson.phase == .labelsRevealed {
            drawDashedLine(
                context: context,
                from: emission,
                to: actual,
                color: TimelyUNATheme.gold.opacity(0.55),
                phase: photonDash + 12,
                width: 1.8
            )
            drawDashedLine(
                context: context,
                from: you,
                to: actual,
                color: TimelyUNATheme.acid.opacity(0.28),
                phase: photonDash + 24,
                width: 1.1
            )
            label(
                context,
                "TIMELYUNA GAP",
                at: CGPoint(x: (emission.x + actual.x) * 0.5, y: (emission.y + actual.y) * 0.5 - 14),
                color: TimelyUNATheme.gold,
                size: 10,
                bold: true
            )
        }

        // Starting Sun (emission / what will become Visible Now).
        drawSun(
            context: context,
            center: emission,
            radius: sunRadius,
            coreTop: Color(red: 1.0, green: 0.96, blue: 0.67),
            coreMid: Color(red: 0.89, green: 0.89, blue: 0.38),
            coreEdge: Color(red: 0.36, green: 0.38, blue: 0.16),
            glow: TimelyUNATheme.gold.opacity(0.40),
            opacity: 0.92
        )

        drawHorizonLightLesson(
            context: context,
            lesson: lesson,
            emission: emission,
            photonPos: photonPos,
            ghostPos: ghostPos,
            sunRadius: sunRadius
        )

        // YOU
        context.fill(
            Path(ellipseIn: CGRect(x: you.x - 14, y: you.y - 14, width: 28, height: 28)),
            with: .radialGradient(
                Gradient(colors: [TimelyUNATheme.cosmicPurple, Color(red: 0.24, green: 0.54, blue: 0.54)]),
                center: CGPoint(x: you.x - 4, y: you.y - 2),
                startRadius: 0,
                endRadius: 16
            )
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: you.x - 14, y: you.y - 14, width: 28, height: 28)),
            with: .color(TimelyUNATheme.cosmicPurple.opacity(0.8)),
            lineWidth: 1
        )
        label(context, "YOU", at: CGPoint(x: you.x, y: you.y + 24), color: TimelyUNATheme.papyrus, size: 10, bold: true)

        // Beauteous Maximus crosses TimelyUNA's signature Apparent Now → Actual Now gap.
        let rocketProgress = simulation.rocketProgress
        if (simulation.isRocketFlying || launchAnimating || simulation.showRocketHit) && rocketProgress > 0.01 {
            let t = min(1, max(0.02, rocketProgress))
            let rx = emission.x + (actual.x - emission.x) * t
            let ry = emission.y + (actual.y - emission.y) * t
            drawRocket(
                context: context,
                at: CGPoint(x: rx, y: ry),
                angle: atan2(actual.y - emission.y, actual.x - emission.x),
                time: time,
                flame: t < 0.96 && !simulation.showRocketHit
            )
            if !simulation.showRocketHit {
                label(
                    context,
                    Self.rocketName,
                    at: CGPoint(x: rx, y: ry + 28),
                    color: TimelyUNATheme.papyrus,
                    size: 9,
                    bold: true
                )
            }
        }

        if simulation.showRocketHit {
            label(context, "BEAUTEOUS MAXIMUS · REALITY CORRECTED", at: CGPoint(x: w * 0.5, y: h * 0.14), color: TimelyUNATheme.acid, size: 15, bold: true)
            label(context, "Apparent Now → Actual Now complete", at: CGPoint(x: w * 0.5, y: h * 0.14 + 18), color: TimelyUNATheme.gold, size: 11)
        }
    }

    /// Shared emission clock. Photon and ghost Sun both sample `lesson.progress`.
    private func drawHorizonLightLesson(
        context: GraphicsContext,
        lesson: HorizonLightLesson,
        emission: CGPoint,
        photonPos: CGPoint,
        ghostPos: CGPoint,
        sunRadius: CGFloat
    ) {
        if lesson.phase == .ready {
            context.fill(
                Path(ellipseIn: CGRect(x: emission.x - sunRadius, y: emission.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.35), .clear]),
                    center: emission,
                    startRadius: 0,
                    endRadius: sunRadius * 1.6
                )
            )
        }

        // Photon — a compact mote, never confused with the Sun.
        let pr: CGFloat = 3.4
        context.fill(
            Path(ellipseIn: CGRect(x: photonPos.x - pr, y: photonPos.y - pr, width: pr * 2, height: pr * 2)),
            with: .color(TimelyUNATheme.gold)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: photonPos.x - 10, y: photonPos.y - 10, width: 20, height: 20)),
            with: .radialGradient(
                Gradient(colors: [TimelyUNATheme.gold.opacity(0.40), .clear]),
                center: photonPos,
                startRadius: 0,
                endRadius: 12
            )
        )

        // Ghost Sun — full solar disc, same radius as the emission Sun.
        if lesson.progress > 0.002 || lesson.phase != .ready {
            drawGhostSun(
                context: context,
                center: ghostPos,
                radius: sunRadius,
                trailFrom: emission,
                progress: lesson.progress,
                reduceMotion: reduceMotion
            )
        }

        if lesson.phase == .labelsRevealed {
            let fade = lesson.labelReveal
            var labeled = context
            labeled.opacity = fade
            label(
                labeled,
                "VISIBLE NOW",
                at: CGPoint(x: emission.x, y: emission.y + sunRadius + 16),
                color: TimelyUNATheme.papyrus,
                size: 12,
                bold: true
            )
            label(
                labeled,
                "ACTUAL NOW",
                at: CGPoint(x: ghostPos.x, y: ghostPos.y + sunRadius + 16),
                color: TimelyUNATheme.gold,
                size: 12,
                bold: true
            )
        }
    }

    /// Full-sized ethereal Sun: disc + glow + corona. Never a waypoint dot.
    private func drawGhostSun(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        trailFrom: CGPoint,
        progress: CGFloat,
        reduceMotion: Bool
    ) {
        if !reduceMotion, progress > 0.04 {
            for echo in [0.18, 0.34] as [CGFloat] {
                let t = max(0, progress - echo)
                let ex = trailFrom.x + (center.x - trailFrom.x) * (t / max(progress, 0.001))
                let ey = trailFrom.y + (center.y - trailFrom.y) * (t / max(progress, 0.001))
                drawSun(
                    context: context,
                    center: CGPoint(x: ex, y: ey),
                    radius: radius,
                    coreTop: Color(red: 1.0, green: 0.97, blue: 0.78),
                    coreMid: Color(red: 0.92, green: 0.82, blue: 0.42),
                    coreEdge: Color(red: 0.45, green: 0.38, blue: 0.16),
                    glow: TimelyUNATheme.gold.opacity(0.16),
                    opacity: 0.10
                )
            }
        }

        drawSun(
            context: context,
            center: center,
            radius: radius,
            coreTop: Color(red: 1.0, green: 0.98, blue: 0.82),
            coreMid: Color(red: 0.94, green: 0.86, blue: 0.48),
            coreEdge: Color(red: 0.50, green: 0.42, blue: 0.18),
            glow: TimelyUNATheme.gold.opacity(0.38),
            opacity: 0.55
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius * 1.18, y: center.y - radius * 1.18, width: radius * 2.36, height: radius * 2.36)),
            with: .color(Color.white.opacity(0.22)),
            style: StrokeStyle(lineWidth: 1.1, dash: [4, 5])
        )
    }

    private func drawDashedLine(
        context: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color,
        phase: CGFloat,
        width: CGFloat
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: width,
                lineCap: .round,
                dash: [9, 7],
                dashPhase: reduceMotion ? 0 : phase
            )
        )
    }

    private func drawSun(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        coreTop: Color,
        coreMid: Color,
        coreEdge: Color,
        glow: Color,
        opacity: Double
    ) {
        var ctx = context
        ctx.opacity = opacity
        let glowR = radius * 2.1
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2)),
            with: .radialGradient(
                Gradient(colors: [glow, .clear]),
                center: center,
                startRadius: radius * 0.2,
                endRadius: glowR
            )
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [coreTop, coreMid, coreEdge]),
                center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3),
                startRadius: 0,
                endRadius: radius * 1.15
            )
        )
    }

    private func drawRocket(context: GraphicsContext, at point: CGPoint, angle: CGFloat, time: Date, flame: Bool) {
        var ctx = context
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: .radians(angle + .pi / 2))

        var body = Path()
        body.addRoundedRect(in: CGRect(x: -7, y: -16, width: 14, height: 32), cornerSize: CGSize(width: 6, height: 6))
        ctx.fill(body, with: .color(Color(red: 0.93, green: 0.93, blue: 0.90)))

        var nose = Path()
        nose.move(to: CGPoint(x: 0, y: -26))
        nose.addLine(to: CGPoint(x: -7, y: -14))
        nose.addLine(to: CGPoint(x: 7, y: -14))
        nose.closeSubpath()
        ctx.fill(nose, with: .color(TimelyUNATheme.orange))

        ctx.fill(Path(ellipseIn: CGRect(x: -3.5, y: -4, width: 7, height: 7)), with: .color(TimelyUNATheme.blue))

        // Fins
        var finL = Path()
        finL.move(to: CGPoint(x: -7, y: 8))
        finL.addLine(to: CGPoint(x: -14, y: 16))
        finL.addLine(to: CGPoint(x: -7, y: 16))
        finL.closeSubpath()
        ctx.fill(finL, with: .color(TimelyUNATheme.orange))
        var finR = Path()
        finR.move(to: CGPoint(x: 7, y: 8))
        finR.addLine(to: CGPoint(x: 14, y: 16))
        finR.addLine(to: CGPoint(x: 7, y: 16))
        finR.closeSubpath()
        ctx.fill(finR, with: .color(TimelyUNATheme.orange))

        if flame {
            let flicker = 1.0 + 0.28 * sin(time.timeIntervalSinceReferenceDate * 30)
            var flamePath = Path()
            flamePath.move(to: CGPoint(x: -5, y: 16))
            flamePath.addLine(to: CGPoint(x: 0, y: 16 + 16 * flicker))
            flamePath.addLine(to: CGPoint(x: 5, y: 16))
            flamePath.closeSubpath()
            ctx.fill(flamePath, with: .color(TimelyUNATheme.acid))
        }
    }

    private func label(
        _ context: GraphicsContext,
        _ text: String,
        at point: CGPoint,
        color: Color,
        size: CGFloat,
        bold: Bool = false
    ) {
        let font = Font.system(size: size, weight: bold ? .semibold : .medium, design: .serif)
        let resolved = context.resolve(Text(text).font(font).foregroundColor(color))
        let width = resolved.measure(in: CGSize(width: 600, height: 40)).width
        context.draw(resolved, at: CGPoint(x: point.x - width / 2, y: point.y), anchor: .leading)
    }

    private func frac(_ seed: Int) -> CGFloat {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }

    // MARK: - Now legend (inline story, not sidebar cards)

    private var replayLightLineButton: some View {
        Group {
            if simulation.lightLineFinished {
                Button("Replay LightLine") {
                    simulation.replayLightLine()
                }
                .buttonStyle(.plain)
                .font(TimelyUNATheme.captionFont)
                .tracking(1.2)
                .foregroundStyle(TimelyUNATheme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(TimelyUNATheme.gold, in: Capsule())
                .disabled(!simulation.lightLineFinished)
                .accessibilityLabel("Replay LightLine")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nowLegend: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: simulation.lightLineFinished)) { timeline in
            let lesson = HorizonLightLesson.resolve(
                lightTimeSeconds: snapshot?.lightTimeSeconds ?? SolarEngine.lightSecondsPerAU,
                visualPathLength: 1,
                elapsed: simulation.lightLineElapsed(now: timeline.date),
                reduceMotion: reduceMotion,
                lockedComplete: simulation.lightLineFinished
            )
            Group {
                if lesson.phase == .labelsRevealed {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            legendItem(title: "VISIBLE NOW", accent: TimelyUNATheme.papyrus, body: "Where arriving light tells you to look.")
                            legendItem(title: "ACTUAL NOW", accent: TimelyUNATheme.gold, body: "Where the Sun has progressed during the photon’s flight.")
                            legendItem(title: "TIMELYUNA GAP", accent: TimelyUNATheme.cosmicPurple, body: "The separation between those two positions—Beauteous Maximus’s flight corridor.")
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            legendItem(title: "VISIBLE NOW", accent: TimelyUNATheme.papyrus, body: "Where arriving light tells you to look.")
                            legendItem(title: "ACTUAL NOW", accent: TimelyUNATheme.gold, body: "Where the Sun has progressed during the photon’s flight.")
                            legendItem(title: "TIMELYUNA GAP", accent: TimelyUNATheme.cosmicPurple, body: "The separation between those two positions—Beauteous Maximus’s flight corridor.")
                        }
                    }
                } else {
                    Text("A photon is traveling to the observer. The Sun continues on its own path.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func legendItem(title: String, accent: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title)
                    .font(TimelyUNATheme.captionFont)
                    .tracking(1.6)
                    .foregroundStyle(accent)
            }
            Text(body)
                .font(TimelyUNATheme.bodyFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Ritual section

    private func ritualSection(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .top, spacing: 0) {
                    ritualSky
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 420)
                    ritualPanel
                        .frame(width: min(400, 380))
                }
            } else {
                VStack(spacing: 0) {
                    ritualSky
                        .frame(height: 280)
                    ritualPanel
                }
            }
        }
        .background(Color(red: 0.071, green: 0.071, blue: 0.059))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily correction ritual")
    }

    private var ritualSky: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.12),
                    Color(red: 0.09, green: 0.09, blue: 0.07),
                    Color(red: 0.05, green: 0.05, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Warm dust glow near actual sun
            RadialGradient(
                colors: [Color(red: 0.46, green: 0.44, blue: 0.30).opacity(0.45), .clear],
                center: UnitPoint(x: 0.78, y: 0.28),
                startRadius: 4,
                endRadius: 160
            )
            .allowsHitTesting(false)

            Canvas { context, size in
                for i in 0..<50 {
                    let x = frac(i * 23 + 2) * size.width
                    let y = frac(i * 47 + 5) * size.height * 0.62
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                        with: .color(.white.opacity(0.35))
                    )
                }
            }
            .allowsHitTesting(false)

            // Horizon band
            VStack {
                Spacer()
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.18, blue: 0.12).opacity(0.0),
                            Color(red: 0.12, green: 0.11, blue: 0.08),
                            Color.black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    Rectangle()
                        .fill(TimelyUNATheme.gold.opacity(0.35))
                        .frame(height: 1)
                        .padding(.top, 28)
                        .rotationEffect(.degrees(-2))
                        .shadow(color: TimelyUNATheme.gold.opacity(0.35), radius: 18, y: -4)
                }
            }

            // Suns on sky
            GeometryReader { g in
                // Apparent — soft
                sunDisc(size: 68, acid: false)
                    .position(x: g.size.width * 0.58, y: g.size.height * 0.58)
                    .opacity(0.45)

                // Actual — acid
                sunDisc(size: 118, acid: true)
                    .position(x: g.size.width * 0.78, y: g.size.height * 0.40)
                    .scaleEffect(reduceMotion ? 1 : (skyPulse ? 1.04 : 1))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: skyPulse)

                // Labels
                Text("APPARENT")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.5)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .position(x: g.size.width * 0.58, y: g.size.height * 0.58 + 48)

                Text("TRUE POSITION")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.5)
                    .foregroundStyle(TimelyUNATheme.acid)
                    .position(x: g.size.width * 0.78, y: g.size.height * 0.40 + 72)

                // Beauteous Maximus launches at Apparent Now and crosses the TimelyUNA gap.
                let gapStart = CGPoint(x: g.size.width * 0.58, y: g.size.height * 0.58)
                let gapEnd = CGPoint(x: g.size.width * 0.78, y: g.size.height * 0.40)
                let gapProgress = ritualRocketProgress
                let rocketPoint = CGPoint(
                    x: gapStart.x + (gapEnd.x - gapStart.x) * gapProgress,
                    y: gapStart.y + (gapEnd.y - gapStart.y) * gapProgress
                )
                let rocketAngle = atan2(gapEnd.y - gapStart.y, gapEnd.x - gapStart.x)

                Path { path in
                    path.move(to: gapStart)
                    path.addLine(to: gapEnd)
                }
                .stroke(
                    TimelyUNATheme.cosmicPurple.opacity(0.9),
                    style: StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        dash: [7, 6],
                        dashPhase: reduceMotion ? 0 : -CGFloat(simulation.rocketProgress) * 48
                    )
                )

                VStack(spacing: 2) {
                    RitualRocketMark(lit: simulation.isRocketFlying || launchAnimating || simulation.showRocketHit)
                        .scaleEffect(0.72)
                        .rotationEffect(.radians(Double(rocketAngle + .pi / 2)))
                        .opacity(simulation.showRocketHit ? 0.45 : 1)
                    Text(Self.rocketName)
                        .font(TimelyUNATheme.smallCaptionFont)
                        .tracking(0.8)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .position(rocketPoint)
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.08),
                    value: simulation.rocketProgress
                )

                Text(ritualRocketStatus)
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.1)
                    .foregroundStyle(simulation.showRocketHit ? TimelyUNATheme.acid : TimelyUNATheme.gold)
                    .position(x: g.size.width * 0.50, y: g.size.height * 0.18)
            }
        }
        .accessibilityHidden(true)
    }

    private var ritualRocketProgress: CGFloat {
        if simulation.showRocketHit { return 1 }
        if simulation.isRocketFlying || launchAnimating {
            return CGFloat(simulation.rocketProgress)
        }
        return 0
    }

    private var ritualRocketStatus: String {
        if simulation.showRocketHit { return "ACTUAL NOW ACQUIRED" }
        if simulation.isRocketFlying || launchAnimating { return "CROSSING TIMELYUNA GAP" }
        return "READY AT APPARENT NOW"
    }

    private func sunDisc(size: CGFloat, acid: Bool) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: acid
                        ? [Color.white, TimelyUNATheme.acid, Color(red: 0.45, green: 0.5, blue: 0.1)]
                        : [Color(red: 1, green: 0.96, blue: 0.75), Color(red: 0.85, green: 0.82, blue: 0.45), Color(red: 0.35, green: 0.36, blue: 0.18)],
                    center: UnitPoint(x: 0.35, y: 0.32),
                    startRadius: 0,
                    endRadius: size / 1.6
                )
            )
            .frame(width: size, height: size)
            .shadow(color: (acid ? TimelyUNATheme.acid : TimelyUNATheme.gold).opacity(0.55), radius: acid ? 36 : 18)
    }

    private var ritualPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Self.rocketClass) · \(Self.rocketName)")
                .font(TimelyUNATheme.smallCaptionFont)
                .tracking(1.4)
                .foregroundStyle(TimelyUNATheme.orange)
                .padding(.bottom, 8)

            Text("PHOTON DELAY TODAY")
                .font(TimelyUNATheme.captionFont)
                .tracking(2)
                .foregroundStyle(Color(red: 0.54, green: 0.54, blue: 0.50))

            if let snapshot {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(SolarFormat.pad2(snapshot.lightMinutes))
                        .font(TimelyUNATheme.heroMetricFont)
                        .foregroundStyle(.white)
                    Text("MIN")
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(Color(red: 0.54, green: 0.54, blue: 0.50))
                        .padding(.bottom, 8)
                    Text(SolarFormat.pad2(snapshot.lightSecondsRemainder))
                        .font(TimelyUNATheme.heroMetricFont)
                        .foregroundStyle(.white)
                    Text("SEC")
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(Color(red: 0.54, green: 0.54, blue: 0.50))
                        .padding(.bottom, 8)
                }
                .monospacedDigit()
                .padding(.top, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Photon delay \(snapshot.lightMinutes) minutes \(snapshot.lightSecondsRemainder) seconds")

                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Color(red: 0.22, green: 0.22, blue: 0.20)).frame(height: 1)
                    Text("Earth–Sun distance \(SolarFormat.au(snapshot.distanceAU)) AU · Sun has traveled roughly \(SolarFormat.travelKilometers(snapshot.sunTravelWhileLightFlewKilometers)) while this light flew.")
                        .font(TimelyUNATheme.calloutFont)
                        .foregroundStyle(Color(red: 0.66, green: 0.65, blue: 0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 14)
                    Rectangle().fill(Color(red: 0.22, green: 0.22, blue: 0.20)).frame(height: 1)
                }
                .padding(.top, 10)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    metricLine("Apparent altitude", SolarFormat.degrees(snapshot.apparent.altitude))
                    metricLine("Apparent azimuth", SolarFormat.degrees(snapshot.apparent.azimuth))
                    metricLine("True altitude", SolarFormat.degrees(snapshot.truePosition.altitude))
                    metricLine("True azimuth", SolarFormat.degrees(snapshot.truePosition.azimuth))
                }
                .padding(.top, 16)

                // Approved same-screen coordinate display (True Horizon only).
                Text("Live calculation · \(location.coordinateLabel)")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.acid.opacity(0.85))
                    .padding(.top, 10)
                    .accessibilityLabel("Live calculation · \(location.coordinateLabel)")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("— MIN  — SEC")
                        .font(TimelyUNATheme.metricFont)
                        .foregroundStyle(Color(red: 0.54, green: 0.54, blue: 0.50))
                        .padding(.top, 8)

                    Text("Photon delay, Earth–Sun distance, altitude, and azimuth appear after a live location fix.")
                        .font(TimelyUNATheme.calloutFont)
                        .foregroundStyle(Color(red: 0.66, green: 0.65, blue: 0.62))
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricLine("Apparent altitude", "—")
                        metricLine("Apparent azimuth", "—")
                        metricLine("True altitude", "—")
                        metricLine("True azimuth", "—")
                    }
                }
            }

            Text(persistence.ritualCompleteToday
                 ? "Reality corrected. Streak preserved on this device."
                 : "One Beauteous Maximus launch across the TimelyUNA gap keeps your streak alive.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(Color(red: 0.66, green: 0.65, blue: 0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 16)

            Button {
                performRitual()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(TimelyUNATheme.ink, lineWidth: 1.5)
                            .frame(width: 26, height: 26)
                        Image(systemName: persistence.ritualCompleteToday ? "checkmark" : "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TimelyUNATheme.ink)
                    }
                    Text(persistence.ritualCompleteToday ? "BEAUTEOUS MAXIMUS · MISSION COMPLETE" : "LAUNCH BEAUTEOUS MAXIMUS")
                        .font(TimelyUNATheme.captionFont)
                        .tracking(1.2)
                        .foregroundStyle(TimelyUNATheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(
                    persistence.ritualCompleteToday ? Color.white : TimelyUNATheme.acid,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(persistence.ritualCompleteToday || simulation.isRocketFlying)
            .accessibilityHint(
                persistence.ritualCompleteToday
                ? "Already completed today"
                : "Launches Baby SPCX rocket Beauteous Maximus from Apparent Now across the TimelyUNA gap to Actual Now"
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.098, green: 0.098, blue: 0.082))
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(Color(red: 0.66, green: 0.65, blue: 0.62))
            Text(value)
                .font(TimelyUNATheme.headlineFont)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.22, green: 0.22, blue: 0.20))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Sunrise

    private var nextSunrisePair: (visible: Date?, trueSun: Date?) {
        guard let lat = location.latitude, let lon = location.longitude, location.hasLiveCoordinates else {
            return (nil, nil)
        }
        return SolarEngine.nextSunrisePair(from: clock.now, latitude: lat, longitude: lon)
    }

    private var sunriseSection: some View {
        let pair = nextSunrisePair
        let dayLabel: String = {
            guard let visible = pair.visible else { return "" }
            if Calendar.current.isDateInToday(visible) { return "Local calendar · today" }
            if Calendar.current.isDateInTomorrow(visible) { return "Local calendar · tomorrow" }
            return "Local calendar · \(visible.formatted(date: .abbreviated, time: .omitted))"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOCAL SUNRISE")
                    .font(TimelyUNATheme.captionFont)
                    .tracking(2)
                    .foregroundStyle(TimelyUNATheme.goldDeep)
                Spacer(minLength: 8)
                if !dayLabel.isEmpty {
                    Text(dayLabel)
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(TimelyUNATheme.muted)
                }
            }

            if location.hasLiveCoordinates {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        sunriseColumn("VISIBLE SUNRISE", SolarFormat.localTime(pair.visible), "Apparent horizon crossing")
                        sunriseColumn("TRUE SUNRISE", SolarFormat.localTime(pair.trueSun), "Light-time corrected")
                        if let trueSun = pair.trueSun {
                            sunriseColumn("COUNTDOWN", SolarFormat.countdown(to: trueSun, from: clock.now), "Until true sunrise")
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        sunriseColumn("VISIBLE SUNRISE", SolarFormat.localTime(pair.visible), "Apparent horizon crossing")
                        sunriseColumn("TRUE SUNRISE", SolarFormat.localTime(pair.trueSun), "Light-time corrected")
                        if let trueSun = pair.trueSun {
                            sunriseColumn("COUNTDOWN", SolarFormat.countdown(to: trueSun, from: clock.now), "Until true sunrise")
                        }
                    }
                }

                // Quiet reminder — authorization + scheduling
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        reminderButton(trueSunrise: pair.trueSun)
                        Text(sunriseReminder.statusMessage)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.muted)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        reminderButton(trueSunrise: pair.trueSun)
                        Text(sunriseReminder.statusMessage)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Visible and true sunrise require a live location fix for your horizon.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(TimelyUNATheme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(TimelyUNATheme.line).frame(height: 1) }
    }

    private func sunriseColumn(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TimelyUNATheme.smallCaptionFont)
                .tracking(1.4)
                .foregroundStyle(TimelyUNATheme.goldDeep)
            Text(value)
                .font(TimelyUNATheme.metricFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(detail)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }

    private func reminderButton(trueSunrise: Date?) -> some View {
        Button {
            Task {
                if sunriseReminder.isScheduled || persistence.sunriseReminderArmed {
                    await sunriseReminder.disarm(persistence: persistence)
                    showToast("Sunrise reminder off")
                } else {
                    await sunriseReminder.armQuietReminder(
                        trueSunrise: trueSunrise,
                        persistence: persistence
                    )
                    showToast(sunriseReminder.statusMessage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sunriseReminder.isScheduled ? "bell.fill" : "bell")
                Text(sunriseReminder.isScheduled ? "Reminder armed" : "Set a quiet reminder")
                    .font(TimelyUNATheme.calloutFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(TimelyUNATheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                sunriseReminder.isScheduled ? TimelyUNATheme.acid : TimelyUNATheme.gold,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(trueSunrise == nil)
        .accessibilityHint("Requests notification permission and schedules a quiet alert near true sunrise")
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 16) {
            ShareLink(item: shareText(for: snapshot)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share this moment")
                        .font(TimelyUNATheme.buttonFont)
                }
                .foregroundStyle(TimelyUNATheme.gold)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TimelyUNATheme.line, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the system share sheet")

            Text("We do not see the universe as it is.\nWe see it as its light arrives.")
                .font(TimelyUNATheme.subheadingFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(Brand.productDisplayName) · \(Brand.technologyCredit) · Educational estimate")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Logic

    private func recomputeSolar() {
        guard let lat = location.latitude,
              let lon = location.longitude,
              location.hasLiveCoordinates else {
            snapshot = nil
            return
        }
        snapshot = SolarEngine.snapshot(date: clock.now, latitude: lat, longitude: lon)
    }

    private func rescheduleReminderIfNeeded() {
        let pair = nextSunrisePair
        Task {
            await sunriseReminder.rescheduleIfArmed(
                trueSunrise: pair.trueSun,
                persistence: persistence
            )
        }
    }

    private func startMotion() {
        guard !reduceMotion else {
            skyPulse = false
            return
        }
        skyPulse = true
    }

    /// Dash crawl is derived from the one-shot LightLine clock so it cannot loop
    /// independently or restart on redraw / tab reappearance.
    private func lightLineDashPhase(at time: Date) -> CGFloat {
        if simulation.lightLineFinished { return 48 }
        return CGFloat(simulation.lightLineElapsed(now: time) * 22)
    }

    private func performRitual() {
        guard !persistence.ritualCompleteToday else { return }
        launchAnimating = true
        simulation.launchRocket()
        persistence.completeRitual()
        showToast("Beauteous Maximus crossed the TimelyUNA gap. Reality corrected.")
        if reduceMotion {
            launchAnimating = false
            return
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run { launchAnimating = false }
        }
    }

    private func shareText(for snapshot: SolarEngine.Snapshot?) -> String {
        let ritual = persistence.ritualCompleteToday ? "Beauteous Maximus launched" : "Beauteous Maximus ready to launch"
        if let snapshot {
            let delay = SolarFormat.lightDelayCompact(snapshot.lightTimeSeconds)
            let alt = SolarFormat.degrees(snapshot.truePosition.altitude)
            let au = SolarFormat.au(snapshot.distanceAU)
            return "I saw the Sun where it actually is on True Horizon. Light delay \(delay) · Earth–Sun \(au) AU · true altitude \(alt). \(ritual). Educational estimate. https://macsafedevelopersapple.io/"
        }
        return "True Horizon — Apparent Now vs Actual Now, with Beauteous Maximus crossing the TimelyUNA gap. Powered by the TimelyUNA light-time engine. \(ritual). Educational estimate. https://macsafedevelopersapple.io/"
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            await MainActor.run {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }
}

// MARK: - Ritual rocket glyph

private struct RitualRocketMark: View {
    var lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.93, green: 0.93, blue: 0.90))
                .frame(width: 20, height: 40)
            // Nose
            RitualTriangle()
                .fill(TimelyUNATheme.orange)
                .frame(width: 20, height: 16)
                .offset(y: -26)
            Circle()
                .fill(TimelyUNATheme.blue)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .frame(width: 8, height: 8)
                .offset(y: -4)
            // Fins
            HStack(spacing: 16) {
                RitualTriangle()
                    .fill(TimelyUNATheme.orange)
                    .frame(width: 10, height: 14)
                    .rotationEffect(.degrees(-90))
                RitualTriangle()
                    .fill(TimelyUNATheme.orange)
                    .frame(width: 10, height: 14)
                    .rotationEffect(.degrees(90))
            }
            .offset(y: 14)
            if lit {
                RitualTriangle()
                    .fill(TimelyUNATheme.acid)
                    .frame(width: 12, height: 16)
                    .rotationEffect(.degrees(180))
                    .offset(y: 30)
            }
        }
        .frame(width: 40, height: 70)
    }
}

/// Shared emission clock for the Horizon light-time lesson.
/// Physical travel uses SolarEngine light delay; screen travel uses an isolated scale factor.
enum HorizonLightPhase: Equatable {
    case ready
    case photonInFlight
    case photonArrived
    case labelsRevealed
}

struct HorizonLightLesson {
    /// Physical photon flight time (s) from SolarEngine / mean AU.
    let lightTimeSeconds: Double
    /// How far the Sun travels on its orbit during that photon flight (km).
    let physicalSunTravelKilometers: Double
    /// Isolated visual exaggeration: screen points shown per physical km.
    let visualPointsPerKilometer: Double
    /// Shared 0…1 sample for photon path and sun trajectory.
    let progress: CGFloat
    let phase: HorizonLightPhase
    /// 0…1 fade for the paired arrival labels (only after progress == 1).
    let labelReveal: CGFloat

    /// Compress ~499 s of light time into a watchable shared flight.
    static let educationalTimeCompression: Double = 80

    static func position(from: CGPoint, to: CGPoint, at t: CGFloat) -> CGPoint {
        let u = min(1, max(0, t))
        return CGPoint(x: from.x + (to.x - from.x) * u, y: from.y + (to.y - from.y) * u)
    }

    static func resolve(
        lightTimeSeconds: Double,
        visualPathLength: CGFloat,
        elapsed: TimeInterval,
        reduceMotion: Bool,
        lockedComplete: Bool
    ) -> HorizonLightLesson {
        let lt = lightTimeSeconds > 1 ? lightTimeSeconds : SolarEngine.lightSecondsPerAU
        let physicalKm = SolarEngine.meanSolarOrbitalSpeedKMS * lt
        let visualLen = max(1, Double(visualPathLength))
        let pointsPerKm = visualLen / max(physicalKm, 1)
        let flightSeconds = max(3.6, lt / educationalTimeCompression)
        let holdSeconds = flightSeconds * 0.12
        let revealSeconds = flightSeconds * 0.16

        let progress: CGFloat
        let phase: HorizonLightPhase
        let labelReveal: CGFloat
        if lockedComplete {
            progress = 1
            phase = .labelsRevealed
            labelReveal = 1
        } else if elapsed < holdSeconds {
            progress = 0
            phase = .ready
            labelReveal = 0
        } else if elapsed < holdSeconds + flightSeconds {
            let u = (elapsed - holdSeconds) / flightSeconds
            let shaped = reduceMotion ? u : u * u * (3 - 2 * u)
            progress = CGFloat(shaped)
            phase = .photonInFlight
            labelReveal = 0
        } else {
            progress = 1
            let u = min(1, (elapsed - holdSeconds - flightSeconds) / revealSeconds)
            labelReveal = CGFloat(u)
            phase = labelReveal < 0.02 ? .photonArrived : .labelsRevealed
        }

        return HorizonLightLesson(
            lightTimeSeconds: lt,
            physicalSunTravelKilometers: physicalKm,
            visualPointsPerKilometer: pointsPerKm,
            progress: progress,
            phase: phase,
            labelReveal: labelReveal
        )
    }
}

private struct RitualTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        TimelyUNATheme.background.ignoresSafeArea()
        TrueHorizonView()
    }
    .environmentObject(SimulationState())
    .environmentObject(ObserverLocationService())
    .environmentObject(HorizonPersistence())
    .environmentObject(HorizonClock())
    .environmentObject(SunriseReminderService())
    .preferredColorScheme(.dark)
}
