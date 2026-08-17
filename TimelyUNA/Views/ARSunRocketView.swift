import SwiftUI

#if os(iOS)
import UIKit
import RealityKit
import ARKit
import AVFoundation
import Combine

// MARK: - Public entry

/// Physical-device AR experience with celestial Visible Now / Actual Now placement.
/// Simulator and unsupported devices use non-camera 2D sky mode (expected fallback).
struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var location: ObserverLocationService
    /// Optional — when provided, successful launches complete the daily ritual once.
    @EnvironmentObject private var persistence: HorizonPersistence

    @StateObject private var calibration = ARCalibrationService()
    @StateObject private var launch = BabyXLaunchController()
    @State private var forceTwoD = false
    @State private var cameraDenied = false
    @State private var showActualPosition = true
    @State private var showLightline = true
    @State private var educationalMagnification = true
    @State private var showCalibrationDetail = false
    @State private var statusBannerVisible = true
    @State private var howThisWorksExpanded = false
    @State private var calibrationDetailsExpanded = false

    // Bottom sheet (custom detents — keeps AR interactive, no modal dimming)
    // Only user gestures change detent — live AR ticks must not resize/jump the sheet.
    @State private var sheetDetent: ARSheetDetent = .collapsed
    @State private var sheetDragTranslation: CGFloat = 0

    // Live solar + AR scene bindings
    @State private var snapshot: SolarEngine.Snapshot?
    @State private var displayPair: ARCelestialMath.DisplayPair?
    @State private var edgeGuides: [EdgeGuide] = []
    /// Screen-space labels (presentation only — not driven by SwiftUI implicit animation).
    @State private var screenLabels: [ARScreenLabel] = []
    @State private var overlayUncertaintyText: String?
    /// One-shot signal: AR coordinator ignites rocket along locked Actual Now vector.
    @State private var triggerRocket = false
    /// Last AR query: whether Actual Now is in front of camera (nil = unknown / 2D).
    @State private var actualTargetInFront: Bool? = nil
    /// Idempotent dismissal / teardown gate (Close, swipe, dismantle, parent dismiss).
    @State private var isShuttingDown = false
    /// Brief nonblocking Close acknowledgement.
    @State private var isClosing = false
    /// Pushed into UIViewRepresentable so teardown wins over updateUIView restarts.
    @State private var arForceShutdown = false
    /// Ensures SwiftUI `dismiss()` runs at most once per presentation.
    @State private var didRequestSwiftUIDismiss = false
    /// Same-turn access to the AR coordinator so Close stops display-link publishes before dismiss.
    @StateObject private var arTeardown = ARTeardownBridge()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var worldTrackingSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    private var useTwoD: Bool {
        forceTwoD || !worldTrackingSupported || cameraDenied
    }

    private var isLandscape: Bool {
        #if os(iOS)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return scene.interfaceOrientation.isLandscape
        }
        #endif
        return false
    }

    private var isCompactPhone: Bool {
        horizontalSizeClass == .compact
    }

    private var prefersIconToolbar: Bool {
        isCompactPhone || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let topChromeHeight: CGFloat = prefersIconToolbar ? 96 : 108
            let safeBottom = geo.safeAreaInsets.bottom
            let topReserved = topChromeHeight + geo.safeAreaInsets.top
            // Stable height from detent only (+ transient drag). AR ticks never change this.
            let sheetH = sheetHeight(
                fullHeight: geo.size.height,
                safeBottom: safeBottom,
                topReserve: topReserved + 8,
                drag: sheetDragTranslation
            )
            // Banner / bottom-sheet exclusion: markers must not sit under chrome.
            let bannerExtra: CGFloat = (statusBannerVisible && !useTwoD) ? 48 : 0
            let trailingReserve: CGFloat = (landscape && geo.size.width >= 700)
                ? min(260, geo.size.width * 0.32) + 16
                : 28
            let chrome = ARScreenGuide.ExclusionInsets.arChrome(
                topReserved: topReserved,
                bottomSheetHeight: sheetH,
                leading: 28,
                trailing: trailingReserve,
                bannerExtra: bannerExtra,
                pad: 8
            )

            ZStack(alignment: .top) {
                // Camera / 2D sky fills the full area
                Group {
                    if useTwoD {
                        twoDLayer(chrome: chrome)
                    } else {
                        arLayer(chrome: chrome)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

                // Screen-space celestial labels + leaders (never inside protected chrome)
                ARScreenLabelOverlay(labels: screenLabels)
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
                    .zIndex(1)

                // Edge / behind-you guidance (resolved against live chrome)
                EdgeArrowOverlay(
                    guides: edgeGuides,
                    chrome: chrome
                )
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
                .zIndex(1)

                // Baby X launch HUD (countdown, confirmations) — does not steal sheet hits
                BabyXLaunchHUD(launch: launch, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .zIndex(2)

                if let uncertainty = overlayUncertaintyText, !useTwoD {
                    Text(uncertainty)
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(TimelyUNATheme.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.top, topReserved + bannerExtra + 6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                        .transaction { $0.animation = nil }
                        .zIndex(2)
                }

                // Top safe chrome (toolbar + heading + status) — never under bottom sheet
                // APPROVED — do not redesign this toolbar block.
                VStack(spacing: 6) {
                    compactToolbar
                    headingStatusLine
                    if statusBannerVisible && !useTwoD {
                        compactStatusBanner
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .top)
                .zIndex(3)

                // Landscape: optional narrow trailing secondary strip (non-phone width)
                if landscape && geo.size.width >= 700 {
                    HStack {
                        Spacer()
                        landscapeSidePanel
                            .frame(width: min(260, geo.size.width * 0.32))
                            .padding(.trailing, 10)
                            .padding(.vertical, topChromeHeight + 8)
                    }
                    .zIndex(1)
                }

                // Bottom sheet — sits flush to bottom of geo; content pads above Home indicator
                VStack {
                    Spacer(minLength: 0)
                    arBottomSheet(
                        height: sheetH,
                        fullHeight: geo.size.height,
                        safeBottom: safeBottom,
                        topReserve: topReserved + 8
                    )
                }
                .zIndex(4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: calibration.quality) { _, quality in
                guard !isShuttingDown else { return }
                // Never change sheetDetent from calibration updates — preserve user position.
                if quality == .calibrated {
                    calibrationDetailsExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        guard !isShuttingDown, calibration.quality == .calibrated else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            statusBannerVisible = false
                        }
                    }
                } else {
                    statusBannerVisible = true
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        // Require Close (or parent removal) so interactive sheet swipe cannot bypass teardown.
        .interactiveDismissDisabled(true)
        .onAppear {
            guard !isShuttingDown else { return }
            arLifecycleLog("AR presented")
            isShuttingDown = false
            isClosing = false
            arForceShutdown = false
            didRequestSwiftUIDismiss = false
            arTeardown.presentationAlive = true
            calibration.start()
            syncLocationIntoCalibration()
            recomputeSolar()
            sheetDetent = .collapsed
            sheetDragTranslation = 0
            howThisWorksExpanded = false
            calibrationDetailsExpanded = false
            statusBannerVisible = true
            edgeGuides = []
            screenLabels = []
            overlayUncertaintyText = nil
            if worldTrackingSupported {
                checkCamera()
            } else {
                forceTwoD = false // show gate then 2D
            }
        }
        .onDisappear {
            // Defensive path for parent dismissal / tab change / system sheet teardown.
            shutdownARDismissal(requestSwiftUIDismiss: false, reason: "onDisappear")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard !isShuttingDown else { return }
            // Resume paused AR session (background uses pause, not permanent shutdown).
            arTeardown.resumeFromForeground()
            syncLocationIntoCalibration()
            recomputeSolar()
            calibration.start()
            arLifecycleLog("App foreground — AR resume requested")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            guard !isShuttingDown else { return }
            // Pause camera/session only — do not permanently kill the coordinator.
            edgeGuides = []
            screenLabels = []
            launch.cancel()
            triggerRocket = false
            arTeardown.pauseForBackground(reason: "app background")
            arLifecycleLog("App background — AR session paused")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            guard !isShuttingDown else { return }
            launch.cancel()
            triggerRocket = false
            arTeardown.pauseForBackground(reason: "memory warning")
            arLifecycleLog("Memory warning — AR session paused")
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            guard !isShuttingDown else { return }
            // Live AR data only — do not touch sheetDetent / sheetDragTranslation.
            recomputeSolar()
            syncLocationIntoCalibration()
        }
        .onChange(of: location.latitude) { _, _ in
            guard !isShuttingDown else { return }
            syncLocationIntoCalibration()
            recomputeSolar()
        }
        .onChange(of: location.longitude) { _, _ in
            guard !isShuttingDown else { return }
            syncLocationIntoCalibration()
            recomputeSolar()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            guard !isShuttingDown else { return }
            updateHeadingOrientation()
        }
        .sheet(isPresented: $showCalibrationDetail) {
            calibrationDetailSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sheet height (stable detents)

    private enum ARSheetDetent: Equatable {
        case collapsed
        case medium
        case expanded
    }

    /// Collapsed height fits: handle + title + target + status + Launch button + full bottom safe inset.
    private func collapsedSheetHeight(safeBottom: CGFloat) -> CGFloat {
        // handle 19 + header ~52 + status ~18 + gaps 18 + launch 48 + bottom pad (safe + 12)
        let content: CGFloat = 19 + 52 + 18 + 18 + 48
        let bottomPad = max(safeBottom, 8) + 12
        return content + bottomPad
    }

    private func mediumSheetHeight(fullHeight: CGFloat) -> CGFloat {
        fullHeight * 0.42
    }

    private func expandedSheetHeight(fullHeight: CGFloat, topReserve: CGFloat) -> CGFloat {
        // Never under Dynamic Island / top toolbar: leave topReserve free.
        let byFraction = fullHeight * 0.82
        let byReserve = fullHeight - topReserve
        return min(byFraction, byReserve)
    }

    private func sheetHeight(
        fullHeight: CGFloat,
        safeBottom: CGFloat,
        topReserve: CGFloat,
        drag: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        switch sheetDetent {
        case .collapsed:
            base = collapsedSheetHeight(safeBottom: safeBottom)
        case .medium:
            base = mediumSheetHeight(fullHeight: fullHeight)
        case .expanded:
            base = expandedSheetHeight(fullHeight: fullHeight, topReserve: topReserve)
        }
        // Drag up (negative translation) expands. Clamp between collapsed min and expanded max.
        let minH = collapsedSheetHeight(safeBottom: safeBottom)
        let maxH = expandedSheetHeight(fullHeight: fullHeight, topReserve: topReserve)
        let adjusted = base - drag
        return min(maxH, max(minH, adjusted))
    }

    private func snapSheet(
        from height: CGFloat,
        fullHeight: CGFloat,
        safeBottom: CGFloat,
        topReserve: CGFloat
    ) {
        let c = collapsedSheetHeight(safeBottom: safeBottom)
        let m = mediumSheetHeight(fullHeight: fullHeight)
        let e = expandedSheetHeight(fullHeight: fullHeight, topReserve: topReserve)
        let dC = abs(height - c)
        let dM = abs(height - m)
        let dE = abs(height - e)
        let next: ARSheetDetent
        if dC <= dM && dC <= dE {
            next = .collapsed
        } else if dM <= dE {
            next = .medium
        } else {
            next = .expanded
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            sheetDetent = next
            sheetDragTranslation = 0
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private func arLayer(chrome: ARScreenGuide.ExclusionInsets) -> some View {
        if !worldTrackingSupported {
            ARUnavailableGate(
                reason: .worldTrackingUnsupported,
                onContinue: { forceTwoD = true },
                onClose: { shutdownARDismissal(requestSwiftUIDismiss: true, reason: "unsupported gate Close") }
            )
        } else if cameraDenied {
            ARUnavailableGate(
                reason: .cameraDenied,
                onContinue: { forceTwoD = true },
                onClose: { shutdownARDismissal(requestSwiftUIDismiss: true, reason: "camera denied gate Close") }
            )
        } else {
            CelestialARContainer(
                selectedDate: selectedDate,
                displayPair: displayPair,
                showActual: showActualPosition,
                showLightline: showLightline,
                educationalMagnification: educationalMagnification,
                calibration: calibration,
                reduceMotion: reduceMotion,
                chrome: chrome,
                triggerRocket: $triggerRocket,
                edgeGuides: $edgeGuides,
                screenLabels: $screenLabels,
                overlayUncertaintyText: $overlayUncertaintyText,
                launchFlightProgress: launch.flightProgress,
                isLaunchActive: launch.isLaunchingVisual && !isShuttingDown,
                forceShutdown: arForceShutdown || isShuttingDown,
                teardownBridge: arTeardown,
                onActualInFrontChange: { [arTeardown] inFront in
                    // Bridge isShuttingDown is checked on coordinator; also skip if parent is leaving.
                    guard arTeardown.presentationAlive else { return }
                    actualTargetInFront = inFront
                },
                onCameraUnauthorized: { [arTeardown] in
                    guard arTeardown.presentationAlive else { return }
                    cameraDenied = true
                },
                onARIgnitionResult: { [arTeardown] ok, message in
                    guard arTeardown.presentationAlive else { return }
                    if ok {
                        launch.noteARIgnitionSucceeded()
                    } else {
                        launch.abortFailedLaunch(message: message ?? "Could not lock launch direction.")
                    }
                }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Orderly AR dismissal (idempotent)

    /// Safe teardown for Close, parent dismissal, tab change, and dismantle races.
    /// - Parameter requestSwiftUIDismiss: true only from Close / explicit UI; false from onDisappear.
    private func shutdownARDismissal(requestSwiftUIDismiss: Bool, reason: String) {
        if isShuttingDown {
            arLifecycleLog("Shutdown ignored (already shutting down) — \(reason)")
            // Still honor a late Close that needs dismiss if owner is stuck presented.
            if requestSwiftUIDismiss, !didRequestSwiftUIDismiss {
                didRequestSwiftUIDismiss = true
                dismiss()
            }
            return
        }
        isShuttingDown = true
        isClosing = true
        arForceShutdown = true
        arTeardown.presentationAlive = false
        arLifecycleLog("Shutdown requested — \(reason)")

        // 1. Immediate coordinator teardown (same turn): kills display link + clears delegates
        //    BEFORE SwiftUI dismiss, so late CADisplayLink ticks cannot publish into dying state.
        arTeardown.shutdownCoordinator(reason: reason)
        arLifecycleLog("Tasks cancelled / delegates cleared (bridge)")

        // 2. Disable further launch/calibration actions
        triggerRocket = false
        launch.cancel()
        arLifecycleLog("Baby X tasks cancelled")

        // 3. Clear presentation state (no continuous sensor logging)
        edgeGuides = []
        screenLabels = []
        overlayUncertaintyText = nil
        actualTargetInFront = nil

        // 4. Stop AR-presentation-owned calibration (Finder location/heading services remain)
        calibration.stop()
        arLifecycleLog("Calibration stopped")

        // 5. Exactly one SwiftUI dismiss when Close (or gate) initiated it
        if requestSwiftUIDismiss, !didRequestSwiftUIDismiss {
            didRequestSwiftUIDismiss = true
            arLifecycleLog("Dismissal completed (SwiftUI dismiss)")
            dismiss()
        } else if !requestSwiftUIDismiss {
            arLifecycleLog("Dismissal completed (owner already leaving)")
        }
    }

    private func arLifecycleLog(_ message: String) {
        #if DEBUG
        print("[TrueHorizon AR] \(message)")
        #endif
    }

    private func twoDLayer(chrome: ARScreenGuide.ExclusionInsets) -> some View {
        ZStack {
            if !worldTrackingSupported && !forceTwoD && !cameraDenied {
                // Will be replaced once forceTwoD true; show gate first
                Color.black
            }
            EducationalTwoDSkyView(
                selectedDate: selectedDate,
                displayPair: displayPair,
                showActualPosition: showActualPosition,
                showLightline: showLightline,
                educationalMagnification: educationalMagnification,
                rocketProgress: launch.flightProgress,
                showRocket: launch.isLaunchingVisual || launch.flightProgress > 0,
                showHit: launch.phase == .arrival,
                showPhotonSlip: launch.showPhotonSlip,
                chrome: chrome,
                onTapLaunch: { beginBabyXLaunch() },
                onEdgeGuides: { edgeGuides = $0 }
            )
            .ignoresSafeArea()

            if !worldTrackingSupported && !forceTwoD {
                ARUnavailableGate(
                    reason: .worldTrackingUnsupported,
                    onContinue: { forceTwoD = true },
                    onClose: { shutdownARDismissal(requestSwiftUIDismiss: true, reason: "2D unsupported gate Close") }
                )
            } else if cameraDenied && !forceTwoD {
                ARUnavailableGate(
                    reason: .cameraDenied,
                    onContinue: { forceTwoD = true },
                    onClose: { shutdownARDismissal(requestSwiftUIDismiss: true, reason: "2D camera gate Close") }
                )
            }
        }
    }

    // MARK: - Compact top toolbar

    /// Single horizontal toolbar in the top safe area: Calibrate · Reset · 2D · Close
    private var compactToolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(
                title: "Calibrate",
                systemImage: "scope",
                emphasis: calibration.quality == .calibrated ? .neutral : .accent
            ) {
                statusBannerVisible = true
                showCalibrationDetail = true
                if !location.hasLiveCoordinates {
                    location.requestLocation()
                }
            }

            toolbarButton(
                title: "Reset",
                systemImage: "arrow.counterclockwise",
                emphasis: .neutral
            ) {
                calibration.reset()
                statusBannerVisible = true
                sheetDetent = .collapsed
                if location.hasLiveCoordinates {
                    location.requestLocation()
                }
            }

            if worldTrackingSupported {
                toolbarButton(
                    title: forceTwoD ? "AR" : "2D",
                    systemImage: forceTwoD ? "camera.viewfinder" : "rectangle.on.rectangle",
                    emphasis: .gold
                ) {
                    forceTwoD.toggle()
                    if !forceTwoD { cameraDenied = false }
                }
            }

            Spacer(minLength: 4)

            Button {
                // Immediate visual acknowledgement, then orderly teardown + single dismiss.
                guard !isClosing, !isShuttingDown else { return }
                isClosing = true
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
                #endif
                shutdownARDismissal(requestSwiftUIDismiss: true, reason: "Close button")
            } label: {
                Image(systemName: isClosing ? "hourglass.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isClosing ? TimelyUNATheme.muted : TimelyUNATheme.gold)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isClosing || isShuttingDown)
            .accessibilityLabel(isClosing ? "Closing AR" : "Close")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TimelyUNATheme.line.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private enum ToolbarEmphasis {
        case neutral, accent, gold
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        emphasis: ToolbarEmphasis,
        action: @escaping () -> Void
    ) -> some View {
        let bg: Color = {
            switch emphasis {
            case .neutral: return Color.white.opacity(0.10)
            case .accent: return TimelyUNATheme.acid.opacity(0.22)
            case .gold: return TimelyUNATheme.gold.opacity(0.85)
            }
        }()
        let fg: Color = {
            switch emphasis {
            case .gold: return TimelyUNATheme.ink
            default: return TimelyUNATheme.papyrus
            }
        }()

        return Button {
            AppHaptics.selection()
            action()
        } label: {
            Group {
                if prefersIconToolbar {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                } else {
                    Label(title, systemImage: systemImage)
                        .font(TimelyUNATheme.captionFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    /// One compact line under the toolbar — never behind buttons.
    private var headingStatusLine: some View {
        let heading = calibration.filteredHeadingDegrees ?? calibration.headingDegrees
        let accuracy = calibration.headingAccuracyDegrees
        let source = calibration.headingSource.rawValue
        let headingText: String = {
            if let heading {
                if let accuracy, accuracy >= 0 {
                    return "\(source) \(Int(heading.rounded()))° · accuracy ±\(Int(accuracy.rounded()))°"
                }
                return "\(source) \(Int(heading.rounded()))°"
            }
            return "\(source) · acquiring…"
        }()

        return Text(headingText)
            .font(TimelyUNATheme.smallCaptionFont)
            .foregroundStyle(TimelyUNATheme.papyrus)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.45), in: Capsule())
            .accessibilityLabel(headingText)
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Compact status banner (replaces large permanent calibration card).
    private var compactStatusBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusBannerColor)
                .frame(width: 8, height: 8)
            Text(statusBannerTitle)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Button {
                AppHaptics.selection()
                showCalibrationDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calibration details")

            if calibration.quality == .calibrated || calibration.quality == .limited {
                Button {
                    AppHaptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        statusBannerVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TimelyUNATheme.muted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss status banner")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusBannerColor.opacity(0.45), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusBannerTitle)
    }

    private var statusBannerTitle: String {
        if !location.hasLiveCoordinates && !calibration.hasLiveLocation {
            return "Location needed"
        }
        switch calibration.quality {
        case .calibrated:
            return "Calibrated"
        case .acquiring:
            return "Calibrating…"
        case .limited:
            if let acc = calibration.headingAccuracyDegrees, acc > 25 {
                return "Compass accuracy low"
            }
            return "Tracking limited"
        case .unavailable:
            return "Tracking unavailable"
        }
    }

    private var statusBannerColor: Color {
        switch calibration.quality {
        case .calibrated: return TimelyUNATheme.acid
        case .limited: return TimelyUNATheme.orange
        case .acquiring: return TimelyUNATheme.gold
        case .unavailable: return Color.red.opacity(0.85)
        }
    }

    private var calibrationDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(calibration.statusMessage)
                        .font(TimelyUNATheme.bodyFont)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Need: live location · compass heading · stable AR tracking. Stand still, then slowly point toward the horizon. Wave figure-eights if compass accuracy is low.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(calibration.trackingStateLabel)
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                    if !location.hasLiveCoordinates {
                        Button {
                            AppHaptics.selection()
                            location.requestLocation()
                        } label: {
                            Text(location.actionButtonTitle)
                                .font(TimelyUNATheme.calloutFont)
                                .foregroundStyle(TimelyUNATheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(TimelyUNATheme.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("AR Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        AppHaptics.selection()
                        showCalibrationDetail = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom sheet

    private func arBottomSheet(
        height: CGFloat,
        fullHeight: CGFloat,
        safeBottom: CGFloat,
        topReserve: CGFloat
    ) -> some View {
        let bottomContentPad = max(safeBottom, 8) + 12
        let isCollapsed = sheetDetent == .collapsed && abs(sheetDragTranslation) < 24

        return VStack(spacing: 0) {
            // Distinct drag handle — only gesture that may change detent
            sheetDragHandle(fullHeight: fullHeight, safeBottom: safeBottom, topReserve: topReserve)

            if isCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    collapsedSheetHeader
                    compactStatusRow
                    launchButton
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                // Full Home-indicator clearance inside sheet bounds (no negative offsets).
                .padding(.bottom, bottomContentPad)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        collapsedSheetHeader
                        compactStatusRow

                        Text(calibration.trackingStateLabel)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)

                        displayOptionsBlock

                        launchButton

                        sunSafetyInSheet

                        disclosureSection(
                            title: "How this view works",
                            isExpanded: $howThisWorksExpanded
                        ) {
                            howThisWorksBody
                        }

                        disclosureSection(
                            title: "Calibration details",
                            isExpanded: $calibrationDetailsExpanded
                        ) {
                            calibrationDetailsBody
                        }

                        if sheetDetent == .expanded || abs(sheetDragTranslation) > 40 {
                            expandedMetricsBlock
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, bottomContentPad)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
            // Opaque enough for Papyrus on camera, still cosmic.
            .fill(Color(red: 0.05, green: 0.05, blue: 0.08).opacity(0.94))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .stroke(TimelyUNATheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 12, y: -3)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
    }

    private func sheetDragHandle(
        fullHeight: CGFloat,
        safeBottom: CGFloat,
        topReserve: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(TimelyUNATheme.gold.opacity(0.9))
                .frame(width: 44, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    sheetDragTranslation = value.translation.height
                }
                .onEnded { value in
                    let current = sheetHeight(
                        fullHeight: fullHeight,
                        safeBottom: safeBottom,
                        topReserve: topReserve,
                        drag: value.translation.height
                    )
                    var projected = current
                    if value.translation.height < -36 {
                        projected = mediumSheetHeight(fullHeight: fullHeight)
                        if value.translation.height < -120 {
                            projected = expandedSheetHeight(fullHeight: fullHeight, topReserve: topReserve)
                        }
                    } else if value.translation.height > 36 {
                        projected = collapsedSheetHeight(safeBottom: safeBottom)
                    } else {
                        projected = current - value.predictedEndTranslation.height * 0.12
                    }
                    snapSheet(
                        from: projected,
                        fullHeight: fullHeight,
                        safeBottom: safeBottom,
                        topReserve: topReserve
                    )
                }
        )
        .accessibilityLabel("Sheet drag handle")
        .accessibilityHint("Drag up to expand details, down to collapse")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            // Tap cycles collapsed → medium → expanded → collapsed for accessibility.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                switch sheetDetent {
                case .collapsed: sheetDetent = .medium
                case .medium: sheetDetent = .expanded
                case .expanded: sheetDetent = .collapsed
                }
                sheetDragTranslation = 0
            }
        }
    }

    private var collapsedSheetHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(useTwoD ? "2D educational sky" : "Live celestial AR")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("Target: Sun")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var compactStatusRow: some View {
        HStack(spacing: 6) {
            statusChip("Visible Now", on: true, color: TimelyUNATheme.apparentSun)
            statusChip("Actual Now", on: showActualPosition, color: TimelyUNATheme.acid)
            statusChip("Lightline", on: showLightline, color: TimelyUNATheme.gold)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Visible Now on. Actual Now \(showActualPosition ? "on" : "off"). Lightline \(showLightline ? "on" : "off")."
        )
    }

    private func statusChip(_ title: String, on: Bool, color: Color) -> some View {
        Text(title)
            .font(TimelyUNATheme.smallCaptionFont)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(on ? TimelyUNATheme.ink : TimelyUNATheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                on ? color.opacity(0.9) : Color.white.opacity(0.08),
                in: Capsule()
            )
    }

    /// Full-width standard switch rows — no circular text controls.
    private var displayOptionsBlock: some View {
        VStack(spacing: 0) {
            standardToggleRow(
                title: "Show Actual Position",
                isOn: $showActualPosition
            )
            Divider().overlay(TimelyUNATheme.line.opacity(0.5))
            standardToggleRow(
                title: "Show Lightline",
                isOn: $showLightline
            )
            Divider().overlay(TimelyUNATheme.line.opacity(0.5))
            educationalMagnificationRow
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func standardToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .tint(TimelyUNATheme.acid)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }

    private var educationalMagnificationRow: some View {
        let factor = displayPair?.magnificationFactor ?? 1
        let trueSep = displayPair?.trueSeparationDegrees ?? 0
        let title: String = {
            if educationalMagnification && factor > 1.05 {
                return "Educational magnification ×\(String(format: "%.0f", factor))"
            }
            return "Educational magnification"
        }()

        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $educationalMagnification) {
                Text(title)
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .tint(TimelyUNATheme.orange)
            .onChange(of: educationalMagnification) { _, _ in
                recomputeSolar()
            }

            Text("Visual separation is enlarged for teaching. True offset: approximately \(String(format: "%.2f", trueSep))°.")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func disclosureSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                AppHaptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(TimelyUNATheme.calloutFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TimelyUNATheme.muted)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded.wrappedValue ? "Collapse" : "Expand")
            .accessibilityAddTraits(.isButton)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var howThisWorksBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visible Now is the direction of photons arriving now — arriving light.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
            Text("Actual Now is a light-time model of where the Sun is after correcting for travel delay — not early visible sunlight.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap the sky or Launch to send Baby X toward Actual Now. Edge arrows guide when a marker is offscreen.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var calibrationDetailsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(calibration.statusMessage)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
            Text(calibration.trackingStateLabel)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Need: live location · compass heading · stable AR tracking. Stand still, then slowly point toward the horizon.")
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !location.hasLiveCoordinates {
                Button {
                    AppHaptics.selection()
                    location.requestLocation()
                } label: {
                    Text(location.actionButtonTitle)
                        .font(TimelyUNATheme.calloutFont)
                        .lineLimit(1)
                        .foregroundStyle(TimelyUNATheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(TimelyUNATheme.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                AppHaptics.selection()
                showCalibrationDetail = true
            } label: {
                Text("Open full calibration tips")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.acid)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var expandedMetricsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snap = snapshot {
                Text("Apparent \(SolarFormat.degrees(snap.apparent.altitude)) alt · \(SolarFormat.degrees(snap.apparent.azimuth)) az")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("True \(SolarFormat.degrees(snap.truePosition.altitude)) alt · \(SolarFormat.degrees(snap.truePosition.azimuth)) az")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.acid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Photon delay \(SolarFormat.lightDelayCompact(snap.lightTimeSeconds)) · \(SolarFormat.au(snap.distanceAU)) AU")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sunSafetyInSheet: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TimelyUNATheme.orange)
            Text("Never look directly at the Sun or point magnifying optics at it.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TimelyUNATheme.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Sun safety. Never look directly at the Sun or point magnifying optics at it.")
    }

    private var launchButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                beginBabyXLaunch()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: launch.isBusy ? "hourglass" : "airplane.departure")
                    Text(launch.isBusy ? launchBusyTitle : "Launch Baby X")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(TimelyUNATheme.calloutFont)
                .foregroundStyle(TimelyUNATheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    launchButtonBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .scaleEffect(launch.phase == .charging ? 0.97 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: launch.phase)
            }
            .buttonStyle(.plain)
            .disabled(launch.isBusy || !showActualPosition)
            .accessibilityLabel(launch.isBusy ? launchBusyTitle : "Launch Baby X")
            .accessibilityHint("Launches Baby X toward Actual Now")
            .accessibilityValue(launch.blockMessage ?? "")

            if let msg = launch.blockMessage, !msg.isEmpty {
                Text(msg)
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(msg)
            }

            if useTwoD {
                Text("2D educational sky — same launch ritual without world tracking.")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var launchBusyTitle: String {
        switch launch.phase {
        case .charging: return "Charging…"
        case .ignition: return "Ignition…"
        case .launching: return "Launching…"
        case .arrival: return "Aligned…"
        case .cooldown: return "Cooling down…"
        case .idle: return "Launch Baby X"
        }
    }

    private var launchButtonBackground: Color {
        if launch.isBusy { return TimelyUNATheme.gold.opacity(0.85) }
        if !showActualPosition { return TimelyUNATheme.muted }
        return TimelyUNATheme.acid
    }

    /// Charge → ignition → flight toward Actual Now (AR or 2D). Never silent-fail.
    private func beginBabyXLaunch() {
        guard !isShuttingDown, !isClosing, arTeardown.presentationAlive else { return }

        // Block only when we have no usable direction yet (not merely limited heading).
        let noDirectionYet = !useTwoD && displayPair == nil
        let hardTrackingBlock = !useTwoD && calibration.quality == .unavailable

        if noDirectionYet {
            launch.blockMessage = "Calibrating direction… Wait for sky placement."
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            return
        }

        let inFront: Bool? = useTwoD ? true : actualTargetInFront
        let bridge = arTeardown
        let needsAR = !useTwoD

        let started = launch.requestLaunch(
            showActualNow: showActualPosition,
            hasDisplayPair: displayPair != nil,
            targetInFront: inFront,
            trackingLimited: hardTrackingBlock,
            reduceMotion: reduceMotion,
            requiresARIgnition: needsAR,
            onARIgnition: {
                guard bridge.presentationAlive else { return }
                if needsAR {
                    triggerRocket = true
                } else {
                    // 2D path: no AR coordinator — acknowledge immediately.
                    launch.noteARIgnitionSucceeded()
                }
            },
            onSuccess: {
                guard bridge.presentationAlive else { return }
                // Ritual/streak only after a successful full sequence.
                if !persistence.ritualCompleteToday {
                    persistence.completeRitual()
                }
            }
        )
        if started {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
            #endif
        } else {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
        }
    }

    /// Wider landscape inspector for secondary controls (iPad / large landscape).
    private var landscapeSidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Controls")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.goldDeep)
                displayOptionsBlock
                launchButton
                sunSafetyInSheet
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.08).opacity(0.94))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TimelyUNATheme.line, lineWidth: 1)
        )
    }

    // MARK: - Logic

    private func syncLocationIntoCalibration() {
        calibration.applyExternalLocation(
            latitude: location.latitude,
            longitude: location.longitude,
            isLive: location.hasLiveCoordinates
        )
        if !location.hasLiveCoordinates {
            // Calibration service also acquires its own location; still prompt user via UI.
        }
    }

    private func recomputeSolar() {
        guard let lat = location.latitude ?? calibration.latitude,
              let lon = location.longitude ?? calibration.longitude,
              (location.hasLiveCoordinates || calibration.hasLiveLocation) else {
            snapshot = nil
            displayPair = nil
            return
        }
        let snap = SolarEngine.snapshot(date: Date(), latitude: lat, longitude: lon)
        snapshot = snap
        let pair = ARCelestialMath.educationalDisplayPair(
            visible: snap.apparent,
            actual: snap.truePosition
        )
        if educationalMagnification {
            displayPair = pair
        } else {
            displayPair = ARCelestialMath.DisplayPair(
                visibleAltitude: snap.apparent.altitude,
                visibleAzimuth: snap.apparent.azimuth,
                actualAltitude: snap.truePosition.altitude,
                actualAzimuth: snap.truePosition.azimuth,
                trueSeparationDegrees: pair.trueSeparationDegrees,
                displaySeparationDegrees: pair.trueSeparationDegrees,
                magnificationFactor: 1,
                isMagnified: false
            )
        }
    }

    private func checkCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraDenied = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraDenied = !granted }
            }
        case .denied, .restricted:
            cameraDenied = true
        @unknown default:
            cameraDenied = true
        }
    }

    private func updateHeadingOrientation() {
        let orient = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        calibration.updateInterfaceOrientation(orient)
    }

}

// MARK: - Screen-space presentation (labels + edge guides)

/// Celestial label drawn in SwiftUI screen space (not RealityKit text).
struct ARScreenLabel: Identifiable, Equatable {
    let id: String
    var markerPoint: CGPoint
    var labelPoint: CGPoint
    var title: String
    var color: Color
    var showLeader: Bool
    var opacity: Double
}

struct EdgeGuide: Identifiable, Equatable {
    let id: String
    var direction: CGPoint
    var color: Color
    var label: String
    /// Resolved screen position after exclusion + collision (optional; overlay re-resolves if nil).
    var screenPoint: CGPoint? = nil
    var priority: Int = 0
    /// True when target is behind the observer (turn-around cue).
    var isBehind: Bool = false
}

private struct ARScreenLabelOverlay: View {
    let labels: [ARScreenLabel]

    var body: some View {
        GeometryReader { _ in
            ForEach(labels) { item in
                ZStack {
                    if item.showLeader {
                        Path { p in
                            p.move(to: item.markerPoint)
                            p.addLine(to: item.labelPoint)
                        }
                        .stroke(item.color.opacity(0.55 * item.opacity), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    Text(item.title)
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(item.color.opacity(item.opacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62 * item.opacity), in: Capsule())
                        .overlay(
                            Capsule().stroke(item.color.opacity(0.45 * item.opacity), lineWidth: 1)
                        )
                        .position(item.labelPoint)
                        .accessibilityLabel(item.title)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EdgeArrowOverlay: View {
    let guides: [EdgeGuide]
    /// Live banner / bottom-sheet exclusion insets.
    var chrome: ARScreenGuide.ExclusionInsets = .defaultChrome

    var body: some View {
        GeometryReader { geo in
            let directions = guides.map { (id: $0.id, direction: $0.direction, priority: $0.priority) }
            let resolved = ARScreenGuide.resolveEdgeGuides(
                directions: directions,
                viewSize: geo.size,
                insets: chrome,
                markerSize: CGSize(width: 108, height: 62)
            )
            let byId = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })

            ForEach(guides) { guide in
                let pos = guide.screenPoint
                    ?? byId[guide.id]?.point
                    ?? ARScreenGuide.freeCenter(viewSize: geo.size, insets: chrome)
                VStack(spacing: 4) {
                    Image(systemName: guide.isBehind ? "arrow.uturn.backward" : "location.north.fill")
                        .rotationEffect(guide.isBehind ? .zero : .radians(atan2(guide.direction.x, -guide.direction.y)))
                        .foregroundStyle(guide.color)
                        .font(.title2)
                        .shadow(radius: 4)
                    Text(guide.label)
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(guide.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
                .position(pos)
                .accessibilityLabel(
                    guide.isBehind
                        ? "\(guide.label) is behind you. Turn \(directionPhrase(guide.direction))."
                        : "\(guide.label) is off screen. Turn \(directionPhrase(guide.direction))."
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func directionPhrase(_ d: CGPoint) -> String {
        if abs(d.x) > abs(d.y) {
            return d.x > 0 ? "right" : "left"
        }
        return d.y > 0 ? "down" : "up"
    }
}

// MARK: - Gate

private enum ARGateReason {
    case worldTrackingUnsupported
    case cameraDenied
}

private struct ARUnavailableGate: View {
    let reason: ARGateReason
    let onContinue: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: reason == .cameraDenied ? "camera.fill" : "arkit")
                    .font(.system(size: 42))
                    .foregroundStyle(TimelyUNATheme.gold)
                Text(reason == .cameraDenied ? "Camera Access Needed" : "AR Unavailable")
                    .font(TimelyUNATheme.sectionFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .multilineTextAlignment(.center)
                Text(explanation)
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    AppHaptics.selection()
                    onContinue()
                } label: {
                    Text("Continue without AR")
                        .font(TimelyUNATheme.buttonFont)
                        .foregroundStyle(TimelyUNATheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(TimelyUNATheme.acid, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                if reason == .cameraDenied {
                    Button("Open Settings") {
                        AppHaptics.selection()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .frame(minHeight: 44)
                }
                Button("Close") {
                    AppHaptics.selection()
                    onClose()
                }
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .frame(minHeight: 44)
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(TimelyUNATheme.line))
            )
            .padding(20)
        }
    }

    private var explanation: String {
        switch reason {
        case .worldTrackingUnsupported:
            return "World-tracking AR requires a compatible physical iPhone or iPad. The Simulator cannot run an AR camera session. Continue in 2D sky mode for Visible Now and Actual Now without a camera."
        case .cameraDenied:
            return "Camera permission is off, so AR cannot start. Enable the camera in Settings, or continue in 2D sky mode."
        }
    }
}

// MARK: - Same-turn teardown bridge (Close → coordinator before dismiss)

/// Owns a weak link to the live AR coordinator so SwiftUI Close can stop CADisplayLink /
/// clear ARSession.delegate on the same call stack — not one frame later via updateUIView.
@MainActor
private final class ARTeardownBridge: ObservableObject {
    /// False after dismissal starts; late Baby X / callback closures must no-op.
    var presentationAlive = true
    fileprivate weak var coordinator: CelestialARContainer.Coordinator?

    fileprivate func register(_ coordinator: CelestialARContainer.Coordinator) {
        // Do not revive presentationAlive here — Close may race with updateUIView.
        self.coordinator = coordinator
    }

    fileprivate func unregister(_ coordinator: CelestialARContainer.Coordinator) {
        if self.coordinator === coordinator {
            self.coordinator = nil
        }
    }

    func shutdownCoordinator(reason: String) {
        presentationAlive = false
        coordinator?.shutdownARDismissal(reason: reason)
    }

    func pauseForBackground(reason: String) {
        coordinator?.pauseSession(reason: reason)
    }

    func resumeFromForeground() {
        guard presentationAlive else { return }
        coordinator?.resumeSessionIfNeeded()
    }
}

// MARK: - Celestial AR container

private struct CelestialARContainer: UIViewRepresentable {
    let selectedDate: Date
    let displayPair: ARCelestialMath.DisplayPair?
    let showActual: Bool
    let showLightline: Bool
    let educationalMagnification: Bool
    @ObservedObject var calibration: ARCalibrationService
    let reduceMotion: Bool
    /// Banner / bottom-sheet exclusion for projection + edge guides.
    var chrome: ARScreenGuide.ExclusionInsets = .defaultChrome
    @Binding var triggerRocket: Bool
    @Binding var edgeGuides: [EdgeGuide]
    @Binding var screenLabels: [ARScreenLabel]
    @Binding var overlayUncertaintyText: String?
    var launchFlightProgress: Double = 0
    var isLaunchActive: Bool = false
    /// When true, coordinator shuts down and ignores further apply/tick work.
    var forceShutdown: Bool = false
    /// Shared bridge for same-turn Close teardown.
    var teardownBridge: ARTeardownBridge
    var onActualInFrontChange: ((Bool?) -> Void)?
    var onCameraUnauthorized: (() -> Void)?
    /// Ignition path lock result (success → continue flight; failure → abort without ritual).
    var onARIgnitionResult: ((Bool, String?) -> Void)?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(calibration: calibration, onCameraUnauthorized: onCameraUnauthorized)
        teardownBridge.register(coordinator)
        return coordinator
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.renderOptions.insert(.disableMotionBlur)
        context.coordinator.arView = arView
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.chrome = chrome
        context.coordinator.onActualInFrontChange = onActualInFrontChange
        context.coordinator.onARIgnitionResult = onARIgnitionResult
        teardownBridge.register(context.coordinator)
        context.coordinator.wirePresentation(
            onGuides: { [weak bridge = teardownBridge] guides, labels, uncertainty in
                guard let bridge, bridge.presentationAlive else { return }
                edgeGuides = guides
                screenLabels = labels
                overlayUncertaintyText = uncertainty
            }
        )
        Self.arLifecycleStaticLog("AR view created")

        guard ARWorldTrackingConfiguration.isSupported else {
            onCameraUnauthorized?()
            return arView
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        guard !context.coordinator.isShuttingDown else { return }
                        if granted {
                            context.coordinator.start(on: arView)
                        } else {
                            onCameraUnauthorized?()
                        }
                    }
                }
            } else {
                onCameraUnauthorized?()
            }
            return arView
        }

        context.coordinator.start(on: arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        if forceShutdown {
            context.coordinator.shutdownARDismissal(reason: "forceShutdown flag")
            return
        }
        guard !context.coordinator.isShuttingDown else { return }

        // Keep bridge registered for Close path (SwiftUI may recreate container values).
        teardownBridge.register(context.coordinator)
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.chrome = chrome
        context.coordinator.headingAccuracyDegrees = calibration.headingAccuracyDegrees
        context.coordinator.headingSource = calibration.headingSource
        context.coordinator.calibrationQuality = calibration.quality
        context.coordinator.onActualInFrontChange = onActualInFrontChange
        context.coordinator.onARIgnitionResult = onARIgnitionResult
        context.coordinator.wirePresentation(
            onGuides: { [weak bridge = teardownBridge] guides, labels, uncertainty in
                guard let bridge, bridge.presentationAlive else { return }
                edgeGuides = guides
                screenLabels = labels
                overlayUncertaintyText = uncertainty
            }
        )
        // Celestial pair + flags only — never re-run placement or reset tracking from sheet/chrome updates.
        context.coordinator.apply(
            pair: displayPair,
            showActual: showActual,
            showLightline: showLightline,
            magnified: educationalMagnification
        )
        // Drive rocket along locked path using SwiftUI flight progress (state machine owns pacing).
        context.coordinator.syncLaunchProgress(launchFlightProgress, active: isLaunchActive)
        if triggerRocket {
            // Resolve ignition on this update pass; report on next main turn (never mutate
            // ObservedObject / bindings synchronously inside updateUIView).
            let ok = context.coordinator.beginIgnitionFlight()
            let failReason = context.coordinator.lastIgnitionFailureReason
            DispatchQueue.main.async {
                guard !context.coordinator.isShuttingDown else { return }
                triggerRocket = false
                context.coordinator.onARIgnitionResult?(ok, ok ? nil : failReason)
            }
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        // Defensive path — Close/onDisappear should already have shut down.
        coordinator.shutdownARDismissal(reason: "dismantleUIView")
        Self.arLifecycleStaticLog("AR view dismantled")
    }

    private static func arLifecycleStaticLog(_ message: String) {
        #if DEBUG
        print("[TrueHorizon AR] \(message)")
        #endif
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        let calibration: ARCalibrationService
        var onCameraUnauthorized: (() -> Void)?
        weak var arView: ARView?
        var reduceMotion = false
        /// Live top banner + bottom sheet exclusion from SwiftUI chrome (screen-space only).
        var chrome: ARScreenGuide.ExclusionInsets = .defaultChrome
        var headingAccuracyDegrees: Double?
        var headingSource: ARCalibrationService.HeadingSource = .none
        var calibrationQuality: ARCalibrationService.Quality = .acquiring
        /// Pushes throttled screen presentation (guides + labels). Never animates via SwiftUI.
        private var onPresentation: (([EdgeGuide], [ARScreenLabel], String?) -> Void)?
        var onActualInFrontChange: ((Bool?) -> Void)?
        var onARIgnitionResult: ((Bool, String?) -> Void)?
        /// Last failure reason from `beginIgnitionFlight` (for UI messaging).
        private(set) var lastIgnitionFailureReason: String?
        /// Set once for full dismissal; all ticks/delegates/publishes become no-ops.
        private(set) var isShuttingDown = false
        /// Temporary background/memory pause — session can resume without recreating the view.
        private var isPausedForBackground = false

        private var sessionStarted = false
        private var rootAnchor: AnchorEntity?
        private var visibleSun: ModelEntity?
        private var actualSun: ModelEntity?
        private var lightline: ModelEntity?
        private var rocket: ModelEntity?
        private var exhaustPlume: ModelEntity?
        private var trailPoints: [SIMD3<Float>] = []
        private var trailEntities: [ModelEntity] = []
        private var currentPair: ARCelestialMath.DisplayPair?
        private var showActualFlag = true
        private var showLightlineFlag = true
        private var showMagnifiedFlag = true

        /// World-space unit directions (ENU / gravityAndHeading). Never mix with camera-local vectors.
        private var smoothedWorldVisible: SIMD3<Float>?
        private var smoothedWorldActual: SIMD3<Float>?
        /// Last valid camera-local Actual Now position (even when marker is off free-rect).
        private var lastActualLocal: SIMD3<Float>?
        private var lastActualInFront: Bool?
        /// Locked at ignition so compass updates do not redirect the rocket mid-flight.
        private var launchOriginLocal: SIMD3<Float>?
        private var launchTargetLocal: SIMD3<Float>?
        private var launchActive = false
        private var lastFlightProgress: Double = 0
        /// Screen-space smoothed marker centers (presentation only).
        private var smoothedScreenVisible: CGPoint?
        private var smoothedScreenActual: CGPoint?
        private var lastPublishedGuides: [EdgeGuide] = []
        private var lastPublishedLabels: [ARScreenLabel] = []
        private var lastPublishedUncertainty: String?
        private var lastPresentationPublishTime: CFTimeInterval = 0
        private var displayLink: CADisplayLink?
        /// Weak proxy so CADisplayLink does not create teardown races via target retain semantics.
        private var displayLinkProxy: ARDisplayLinkProxy?

        /// Placement distance keeps angular size readable without giant near-field spheres.
        private let skyDistance: Float = 80
        /// Shorter flight path so Baby X stays large enough to read during liftoff.
        private let rocketFlightDistance: Float = 28
        private let visibleRadius: Float = 0.55
        private let actualRadius: Float = 0.62
        /// Display-link presentation publish floor (~12 Hz) to avoid SwiftUI thrash/flicker.
        private let presentationMinInterval: CFTimeInterval = 1.0 / 12.0

        init(calibration: ARCalibrationService, onCameraUnauthorized: (() -> Void)?) {
            self.calibration = calibration
            self.onCameraUnauthorized = onCameraUnauthorized
        }

        func wirePresentation(onGuides: @escaping ([EdgeGuide], [ARScreenLabel], String?) -> Void) {
            guard !isShuttingDown else { return }
            onPresentation = { guides, labels, uncertainty in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    onGuides(guides, labels, uncertainty)
                }
            }
        }

        /// Idempotent full teardown — safe from Close, dismantleUIView, and forceShutdown.
        /// Not used for temporary background pause (see `pauseSession`).
        func shutdownARDismissal(reason: String) {
            if isShuttingDown {
                arLog("Late shutdown ignored — \(reason)")
                return
            }
            isShuttingDown = true
            isPausedForBackground = false
            arLog("Shutdown requested — \(reason)")

            // Cancel launch path
            launchActive = false
            launchOriginLocal = nil
            launchTargetLocal = nil
            lastFlightProgress = 0

            // Invalidate display link first so no further ticks publish into SwiftUI.
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy?.owner = nil
            displayLinkProxy = nil
            arLog("Tasks cancelled / display link invalidated")

            // Drop callbacks so late ARKit/RealityKit work cannot mutate dismissed UI.
            onPresentation = nil
            onActualInFrontChange = nil
            onCameraUnauthorized = nil
            onARIgnitionResult = nil
            arLog("Delegates/callbacks cleared")

            // Clear session delegate BEFORE pause so no callback lands on a dying coordinator.
            if let arView {
                arView.session.delegate = nil
                arView.session.pause()
                arLog("Session paused")
            }

            // Disable entities first (safe if scene is mid-frame), then detach.
            visibleSun?.isEnabled = false
            actualSun?.isEnabled = false
            lightline?.isEnabled = false
            rocket?.isEnabled = false
            exhaustPlume?.isEnabled = false
            clearTrail()
            if let anchor = rootAnchor {
                let children = Array(anchor.children)
                for child in children {
                    child.removeFromParent()
                }
                if let arView, arView.scene.anchors.contains(where: { $0 === anchor }) {
                    anchor.removeFromParent()
                } else {
                    anchor.removeFromParent()
                }
            }
            rootAnchor = nil
            visibleSun = nil
            actualSun = nil
            lightline = nil
            rocket = nil
            exhaustPlume = nil
            currentPair = nil
            smoothedWorldVisible = nil
            smoothedWorldActual = nil
            lastActualLocal = nil
            lastActualInFront = nil
            smoothedScreenVisible = nil
            smoothedScreenActual = nil
            lastPublishedGuides = []
            lastPublishedLabels = []
            lastPublishedUncertainty = nil
            lastIgnitionFailureReason = nil
            launchActive = false
            launchOriginLocal = nil
            launchTargetLocal = nil

            calibration.markSessionRunning(false)
            arView = nil
            sessionStarted = false
            arLog("Coordinator teardown complete")
        }

        /// Temporary pause for app background / memory pressure. Idempotent; does not set isShuttingDown.
        func pauseSession(reason: String) {
            guard !isShuttingDown else { return }
            arLog("Session pause — \(reason)")
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy?.owner = nil
            displayLinkProxy = nil
            if let arView {
                arView.session.delegate = nil
                arView.session.pause()
            }
            calibration.markSessionRunning(false)
            isPausedForBackground = true
            // Drop in-flight launch geometry; sequence is cancelled by the SwiftUI owner.
            launchActive = false
            launchOriginLocal = nil
            launchTargetLocal = nil
            exhaustPlume?.isEnabled = false
        }

        /// Resume after `pauseSession` while the AR presentation is still alive.
        func resumeSessionIfNeeded() {
            guard !isShuttingDown else {
                arLog("Resume ignored — shutting down")
                return
            }
            guard isPausedForBackground, let arView else { return }
            isPausedForBackground = false
            arLog("Session resume from background")
            start(on: arView)
        }

        func start(on arView: ARView) {
            guard !isShuttingDown else {
                arLog("Start ignored — shutting down")
                return
            }
            guard ARWorldTrackingConfiguration.isSupported else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                onCameraUnauthorized?()
                return
            }

            isPausedForBackground = false
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravityAndHeading
            config.environmentTexturing = .automatic
            arView.session.delegate = self
            // Cold start: full reset + remove anchors. Resume / re-run: reset tracking only.
            // Never call run() from chrome-only updateUIView paths (those skip start()).
            let runOptions: ARSession.RunOptions = sessionStarted
                ? [.resetTracking]
                : [.resetTracking, .removeExistingAnchors]
            arView.session.run(config, options: runOptions)
            sessionStarted = true
            calibration.markSessionRunning(true)
            self.arView = arView
            if rootAnchor == nil {
                buildScene(in: arView)
            }

            displayLink?.invalidate()
            let proxy = ARDisplayLinkProxy()
            proxy.owner = self
            displayLinkProxy = proxy
            let link = CADisplayLink(target: proxy, selector: #selector(ARDisplayLinkProxy.tick))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            }
            link.add(to: .main, forMode: .common)
            displayLink = link
            arLog("AR session started")
        }

        /// Update celestial data only. Does not reset AR session or world coordinates.
        func apply(
            pair: ARCelestialMath.DisplayPair?,
            showActual: Bool,
            showLightline: Bool,
            magnified: Bool
        ) {
            guard !isShuttingDown else { return }
            currentPair = pair
            showActualFlag = showActual
            showLightlineFlag = showLightline
            showMagnifiedFlag = magnified
            // Soft snap when pair identity changes significantly (new day/body), not every sensor tick.
            if pair == nil {
                smoothedWorldVisible = nil
                smoothedWorldActual = nil
                smoothedScreenVisible = nil
                smoothedScreenActual = nil
            }
        }

        func handleDisplayTick() {
            guard !isShuttingDown else {
                arLog("Late callback ignored — displayTick")
                return
            }
            guard !isPausedForBackground else { return }
            updateWorldAndCameraPlacements()
            updateScreenPresentation(forcePublish: false)
        }

        private func arLog(_ message: String) {
            #if DEBUG
            print("[TrueHorizon AR] \(message)")
            #endif
        }

        /// Called at ignition: lock Actual Now vector and prepare rocket (flight driven by `syncLaunchProgress`).
        /// Returns false when the rocket cannot be placed — caller must abort without ritual.
        @discardableResult
        func beginIgnitionFlight() -> Bool {
            lastIgnitionFailureReason = nil
            guard !isShuttingDown else {
                arLog("Late callback ignored — beginIgnitionFlight")
                lastIgnitionFailureReason = "AR is closing."
                return false
            }
            // Idempotent if already locked this launch (duplicate updateUIView before trigger clears).
            if launchActive, launchOriginLocal != nil, launchTargetLocal != nil {
                return true
            }
            guard let rocket else {
                lastIgnitionFailureReason = "Rocket not ready. Reopen AR and try again."
                arLog("Ignition failed — no rocket entity")
                return false
            }
            guard rootAnchor != nil else {
                lastIgnitionFailureReason = "AR scene not ready."
                return false
            }

            // Prefer live Actual Now local vector; fall back to last good sample.
            // CRITICAL: do not require actualSun.isEnabled — that was false when the target was
            // merely off the free viewport / behind chrome, causing silent launch failures.
            guard let target = resolveActualLocalTarget() else {
                lastIgnitionFailureReason = "Could not lock Actual Now direction. Aim toward the target."
                arLog("Ignition failed — no valid Actual Now vector")
                return false
            }
            let origin = SIMD3<Float>(0, -0.42, -0.95)

            // Validate finite, non-zero direction.
            let delta = target - origin
            let len = simd_length(delta)
            guard len.isFinite, len > 0.5,
                  target.x.isFinite, target.y.isFinite, target.z.isFinite else {
                lastIgnitionFailureReason = "Invalid launch direction. Try again."
                return false
            }
            // Behind camera: refuse (caller should have blocked).
            guard target.z < -0.5 else {
                lastIgnitionFailureReason = "Turn toward Actual Now to launch."
                return false
            }

            launchOriginLocal = origin
            launchTargetLocal = target
            launchActive = true
            lastFlightProgress = 0
            trailPoints = [origin]
            clearTrail()

            rocket.isEnabled = true
            rocket.position = origin
            // Visible scale near camera (~0.35–0.5 m visual).
            rocket.scale = SIMD3<Float>(repeating: 3.2)
            exhaustPlume?.isEnabled = !reduceMotion
            exhaustPlume?.position = origin + SIMD3<Float>(0, -0.12, 0.08)

            if reduceMotion {
                rocket.position = target
                rocket.scale = SIMD3<Float>(repeating: 0.4)
                exhaustPlume?.isEnabled = false
            }
            arLog("Ignition path locked")
            return true
        }

        /// Drive rocket along locked path using SwiftUI flight progress (0…1).
        func syncLaunchProgress(_ progress: Double, active: Bool) {
            guard !isShuttingDown else { return }
            guard let rocket else { return }
            if !active {
                if launchActive {
                    launchActive = false
                    launchOriginLocal = nil
                    launchTargetLocal = nil
                    exhaustPlume?.isEnabled = false
                    // Park rocket near lower FOV for next launch.
                    rocket.position = SIMD3<Float>(0, -0.42, -0.95)
                    rocket.scale = SIMD3<Float>(repeating: 2.4)
                    rocket.isEnabled = true
                    clearTrail()
                }
                return
            }
            // Charging / pre-ignition: keep rocket visible near camera as acknowledgement.
            if !launchActive {
                rocket.isEnabled = true
                rocket.position = SIMD3<Float>(0, -0.42, -0.95)
                let pulse = 2.4 + 0.35 * Float(sin(CACurrentMediaTime() * 6.0))
                rocket.scale = SIMD3<Float>(repeating: pulse)
                return
            }
            guard let origin = launchOriginLocal,
                  let target = launchTargetLocal else { return }

            let p = Float(min(max(progress, 0), 1))
            // Smoothstep acceleration
            let ease = p * p * (3 - 2 * p)
            let arc = SIMD3<Float>(0, 0.55 * sin(Float.pi * ease), 0)
            let bank = SIMD3<Float>(0.12 * sin(ease * Float.pi * 2), 0, 0)
            let pos = origin + (target - origin) * ease + arc + bank
            guard pos.x.isFinite, pos.y.isFinite, pos.z.isFinite else { return }
            rocket.position = pos
            // Shrink slightly as it recedes
            let scale = 3.2 * (1.0 - 0.55 * ease)
            rocket.scale = SIMD3<Float>(repeating: max(0.35, scale))
            // Face along velocity — only when look target is finite and separated.
            let ahead = origin + (target - origin) * min(1, ease + 0.05) + arc
            let lookDelta = ahead - pos
            if simd_length(lookDelta) > 0.02,
               ahead.x.isFinite, ahead.y.isFinite, ahead.z.isFinite {
                rocket.look(at: ahead, from: pos, relativeTo: rootAnchor)
            }

            exhaustPlume?.isEnabled = ease < 0.92 && !reduceMotion
            exhaustPlume?.position = pos + SIMD3<Float>(0, -0.08, 0.12)
            exhaustPlume?.scale = SIMD3<Float>(repeating: 1.2 + ease)

            if p - Float(lastFlightProgress) > 0.03 || p >= 1 {
                appendTrailDot(at: pos, progress: Double(p))
                lastFlightProgress = Double(p)
            }
        }

        private func resolveActualLocalTarget() -> SIMD3<Float>? {
            // 1) Last camera-local Actual Now sample (even if marker hidden for chrome).
            if let last = lastActualLocal {
                let len = simd_length(last)
                if len.isFinite, len > 0.01, last.z < -0.02 {
                    let dir = last / len
                    if dir.x.isFinite, dir.y.isFinite, dir.z.isFinite {
                        return dir * rocketFlightDistance
                    }
                }
            }
            // 2) Fresh world→camera transform from current pair + frame.
            guard let pair = currentPair, let arView, let frame = arView.session.currentFrame else {
                return nil
            }
            let worldA = ARCelestialMath.worldDirection(
                altitudeDegrees: pair.actualAltitude,
                azimuthDegrees: pair.actualAzimuth
            )
            guard worldA.x.isFinite, worldA.y.isFinite, worldA.z.isFinite else { return nil }
            let cam = frame.camera.transform
            let r = simd_float3x3(
                SIMD3<Float>(cam.columns.0.x, cam.columns.0.y, cam.columns.0.z),
                SIMD3<Float>(cam.columns.1.x, cam.columns.1.y, cam.columns.1.z),
                SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
            )
            let local = r.transpose * worldA
            guard local.z < -0.02 else { return nil }
            let n = simd_normalize(local)
            guard n.x.isFinite, n.y.isFinite, n.z.isFinite else { return nil }
            return n * rocketFlightDistance
        }

        private func clearTrail() {
            trailEntities.forEach { $0.removeFromParent() }
            trailEntities.removeAll()
        }

        private func appendTrailDot(at p: SIMD3<Float>, progress: Double) {
            guard let rootAnchor else { return }
            // Split trail near target: orange Visible strand + lime Actual strand.
            let split = progress > 0.72
            let color: UIColor
            if split {
                color = progress.truncatingRemainder(dividingBy: 0.08) < 0.04
                    ? UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.7)
                    : UIColor(red: 0.85, green: 1.0, blue: 0.26, alpha: 0.75)
            } else {
                color = UIColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 0.65)
            }
            let r: Float = split ? 0.07 : 0.09
            let dot = ModelEntity(
                mesh: .generateSphere(radius: r),
                materials: [UnlitMaterial(color: color)]
            )
            dot.position = p
            rootAnchor.addChild(dot)
            trailEntities.append(dot)
            if trailEntities.count > 48 {
                let old = trailEntities.removeFirst()
                old.removeFromParent()
            }
        }

        private func buildScene(in arView: ARView) {
            arView.scene.anchors.removeAll()
            // Camera-anchored root: positions are camera-local (−Z forward).
            // World ENU directions are converted each frame — never stored as camera-local in the smoother.
            let anchor = AnchorEntity(.camera)
            rootAnchor = anchor

            let vSun = makeSun(radius: visibleRadius, color: UIColor(red: 1.0, green: 0.67, blue: 0.2, alpha: 0.92))
            vSun.name = "VisibleNow"
            visibleSun = vSun
            anchor.addChild(vSun)

            let aSun = makeSun(radius: actualRadius, color: UIColor(red: 0.85, green: 1.0, blue: 0.26, alpha: 1.0))
            aSun.name = "ActualNow"
            actualSun = aSun
            anchor.addChild(aSun)

            // Labels are SwiftUI screen-space (readable, collision-safe). Only markers + lightline live in 3D.
            let line = ModelEntity(
                mesh: .generateBox(size: [0.03, 0.03, 1], cornerRadius: 0.01),
                materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 0.75))]
            )
            lightline = line
            anchor.addChild(line)

            let rock = makeRocket()
            rock.position = SIMD3<Float>(0, -0.42, -0.95)
            rock.scale = SIMD3<Float>(repeating: 2.4)
            rocket = rock
            anchor.addChild(rock)

            // Exhaust plume (unlit) — enabled only during flight.
            let plume = ModelEntity(
                mesh: .generateSphere(radius: 0.08),
                materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.75))]
            )
            plume.isEnabled = false
            exhaustPlume = plume
            anchor.addChild(plume)

            arView.scene.addAnchor(anchor)
        }

        // MARK: Frame tick — world smooth → camera place → screen project → publish

        /// Single pipeline: celestial dirs stay in world space; camera placement is a pure transform each frame.
        private func updateWorldAndCameraPlacements() {
            guard !isShuttingDown else { return }
            guard let pair = currentPair, let arView, let frame = arView.session.currentFrame else {
                visibleSun?.isEnabled = false
                actualSun?.isEnabled = false
                lightline?.isEnabled = false
                return
            }

            let targetV = ARCelestialMath.worldDirection(
                altitudeDegrees: pair.visibleAltitude,
                azimuthDegrees: pair.visibleAzimuth
            )
            let targetA = ARCelestialMath.worldDirection(
                altitudeDegrees: pair.actualAltitude,
                azimuthDegrees: pair.actualAzimuth
            )

            // World-space smoothing only. Alpha restrained; slower when heading is uncertain.
            let baseAlpha: Float = reduceMotion ? 1.0 : 0.18
            let accuracy = headingAccuracyDegrees ?? 90
            let uncertaintyScale = Float(min(1.0, max(0.35, 25.0 / max(accuracy, 8.0))))
            let alpha = reduceMotion ? 1.0 : baseAlpha * uncertaintyScale

            smoothedWorldVisible = ARCelestialMath.smoothVector(
                previous: smoothedWorldVisible,
                sample: targetV,
                alpha: alpha
            )
            smoothedWorldActual = ARCelestialMath.smoothVector(
                previous: smoothedWorldActual,
                sample: targetA,
                alpha: alpha
            )

            let worldV = smoothedWorldVisible ?? targetV
            let worldA = smoothedWorldActual ?? targetA

            // World → camera-local (camera anchor children).
            let cam = frame.camera.transform
            let r = simd_float3x3(
                SIMD3<Float>(cam.columns.0.x, cam.columns.0.y, cam.columns.0.z),
                SIMD3<Float>(cam.columns.1.x, cam.columns.1.y, cam.columns.1.z),
                SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
            )
            let rInv = r.transpose
            let localV = rInv * worldV
            let localA = rInv * worldA

            // Behind camera when local Z ≥ 0 (ARKit −Z is forward).
            let vInFront = localV.z < -0.02
            let aInFront = localA.z < -0.02

            let vPos = localV * skyDistance
            let aPos = localA * skyDistance

            if let visibleSun {
                visibleSun.isEnabled = vInFront
                if vInFront { visibleSun.position = vPos }
            }
            // Always keep last known Actual Now local vector for launch targeting
            // (even when the marker is hidden for free-rect / chrome reasons).
            if showActualFlag {
                lastActualLocal = aPos
                if lastActualInFront != aInFront {
                    lastActualInFront = aInFront
                    if !isShuttingDown {
                        onActualInFrontChange?(aInFront)
                    }
                }
            } else {
                if lastActualInFront != nil {
                    lastActualInFront = nil
                    if !isShuttingDown {
                        onActualInFrontChange?(nil)
                    }
                }
            }

            if let actualSun {
                let show = showActualFlag && aInFront
                actualSun.isEnabled = show
                if aInFront { actualSun.position = aPos }
            }

            // Lightline endpoints always match the same camera-local marker positions.
            // During launch, keep lightline stable (do not hide).
            if let lightline {
                let both = showLightlineFlag && showActualFlag && vInFront && aInFront
                lightline.isEnabled = both || (launchActive && showActualFlag)
                if vInFront && aInFront {
                    let mid = (vPos + aPos) * 0.5
                    let delta = aPos - vPos
                    let length = simd_length(delta)
                    lightline.position = mid
                    if length > 0.05 {
                        lightline.scale = SIMD3<Float>(1, 1, length)
                        lightline.look(at: aPos, from: mid, relativeTo: rootAnchor)
                    }
                }
            }

            // Do not move rocket while a launch flight is active (path is locked).
            if !launchActive, let rocket, !rocket.isEnabled {
                rocket.isEnabled = true
            }
        }

        private func updateScreenPresentation(forcePublish: Bool) {
            guard !isShuttingDown else { return }
            guard let arView, let pair = currentPair, let frame = arView.session.currentFrame else {
                // Do not publish empty overlays while tearing down — that mutated dismissed SwiftUI state.
                return
            }
            let size = arView.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            let viewM = frame.camera.viewMatrix(for: orientation)
            let projM = frame.camera.projectionMatrix(for: orientation, viewportSize: size, zNear: 0.01, zFar: 200)
            let camPos = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )

            let worldV = (smoothedWorldVisible ?? ARCelestialMath.worldDirection(
                altitudeDegrees: pair.visibleAltitude,
                azimuthDegrees: pair.visibleAzimuth
            ))
            let worldA = (smoothedWorldActual ?? ARCelestialMath.worldDirection(
                altitudeDegrees: pair.actualAltitude,
                azimuthDegrees: pair.actualAzimuth
            ))

            let vWorldPoint = camPos + worldV * skyDistance
            let aWorldPoint = camPos + worldA * skyDistance
            let insets = chrome
            let free = ARScreenGuide.freeRect(viewSize: size, insets: insets)

            let vp = ARScreenGuide.project(
                worldPoint: vWorldPoint,
                viewMatrix: viewM,
                projectionMatrix: projM,
                viewSize: size,
                chrome: insets
            )
            let ap = ARScreenGuide.project(
                worldPoint: aWorldPoint,
                viewMatrix: viewM,
                projectionMatrix: projM,
                viewSize: size,
                chrome: insets
            )

            // Screen-space marker smoothing (presentation only).
            let screenAlpha: CGFloat = reduceMotion ? 1.0 : 0.28
            if !vp.isBehind {
                smoothedScreenVisible = ARScreenGuide.smoothScreenPoint(
                    previous: smoothedScreenVisible,
                    sample: vp.screenPoint,
                    alpha: screenAlpha
                )
            } else {
                smoothedScreenVisible = nil
            }
            if showActualFlag && !ap.isBehind {
                smoothedScreenActual = ARScreenGuide.smoothScreenPoint(
                    previous: smoothedScreenActual,
                    sample: ap.screenPoint,
                    alpha: screenAlpha
                )
            } else {
                smoothedScreenActual = nil
            }

            // Labels only for targets in the free viewport (in front + not under chrome).
            let vMarkerForLabel: CGPoint? = (vp.isOnScreen ? smoothedScreenVisible : nil)
            let aMarkerForLabel: CGPoint? = (showActualFlag && ap.isOnScreen ? smoothedScreenActual : nil)
            let layout = ARScreenGuide.layoutCelestialLabels(
                visibleMarker: vMarkerForLabel,
                actualMarker: aMarkerForLabel,
                free: free
            )

            let uncertaintyDim: Double = {
                guard let acc = headingAccuracyDegrees, acc >= 0 else { return 0.55 }
                if acc > 35 { return 0.5 }
                if acc > 25 { return 0.72 }
                return 1.0
            }()

            var labels: [ARScreenLabel] = []
            if let mp = vMarkerForLabel, let lp = layout.visibleLabel {
                labels.append(ARScreenLabel(
                    id: "visible",
                    markerPoint: mp,
                    labelPoint: lp,
                    title: "VISIBLE NOW",
                    color: TimelyUNATheme.apparentSun,
                    showLeader: layout.visibleLeader,
                    opacity: uncertaintyDim
                ))
            }
            if let mp = aMarkerForLabel, let lp = layout.actualLabel {
                labels.append(ARScreenLabel(
                    id: "actual",
                    markerPoint: mp,
                    labelPoint: lp,
                    title: "ACTUAL NOW",
                    color: TimelyUNATheme.acid,
                    showLeader: layout.actualLeader,
                    opacity: uncertaintyDim
                ))
            }
            if showMagnifiedFlag, pair.isMagnified, vMarkerForLabel != nil || aMarkerForLabel != nil {
                let badge = ARScreenGuide.clampCenter(
                    CGPoint(x: free.midX, y: free.minY + 18),
                    size: CGSize(width: 200, height: 22),
                    free: free
                ).point
                labels.append(ARScreenLabel(
                    id: "edu",
                    markerPoint: badge,
                    labelPoint: badge,
                    title: "EDU MAG · NOT LITERAL",
                    color: TimelyUNATheme.orange,
                    showLeader: false,
                    opacity: 0.9
                ))
            }

            // Edge / behind guides — not false on-image markers.
            var pending: [(id: String, direction: CGPoint, color: Color, label: String, priority: Int, behind: Bool)] = []
            if vp.isBehind {
                pending.append((
                    id: "visible",
                    direction: vp.edgeDirection,
                    color: TimelyUNATheme.apparentSun,
                    label: "Visible · behind you",
                    priority: 10,
                    behind: true
                ))
            } else if vp.isOffFreeEdge {
                pending.append((
                    id: "visible",
                    direction: vp.edgeDirection,
                    color: TimelyUNATheme.apparentSun,
                    label: "Visible Now",
                    priority: 10,
                    behind: false
                ))
            }
            if showActualFlag {
                if ap.isBehind {
                    pending.append((
                        id: "actual",
                        direction: ap.edgeDirection,
                        color: TimelyUNATheme.acid,
                        label: "Actual · behind you",
                        priority: 8,
                        behind: true
                    ))
                } else if ap.isOffFreeEdge {
                    pending.append((
                        id: "actual",
                        direction: ap.edgeDirection,
                        color: TimelyUNATheme.acid,
                        label: "Actual Now",
                        priority: 8,
                        behind: false
                    ))
                }
            }

            let resolved = ARScreenGuide.resolveEdgeGuides(
                directions: pending.map { (id: $0.id, direction: $0.direction, priority: $0.priority) },
                viewSize: size,
                insets: insets
            )
            let byId = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
            let guides: [EdgeGuide] = pending.map { item in
                EdgeGuide(
                    id: item.id,
                    direction: item.direction,
                    color: item.color,
                    label: item.label,
                    screenPoint: byId[item.id]?.point,
                    priority: item.priority,
                    isBehind: item.behind
                )
            }

            let uncertainty: String? = {
                if headingSource == .none {
                    return "No compass heading · overlay approximate"
                }
                if let acc = headingAccuracyDegrees, acc >= 0, acc > 25 {
                    return "Heading ±\(Int(acc.rounded()))° · placement uncertain"
                }
                if calibrationQuality == .limited {
                    return "Tracking limited · move slowly"
                }
                return nil
            }()

            publishPresentation(guides: guides, labels: labels, uncertainty: uncertainty, force: forcePublish)
        }

        private func publishPresentation(
            guides: [EdgeGuide],
            labels: [ARScreenLabel],
            uncertainty: String?,
            force: Bool
        ) {
            guard !isShuttingDown else {
                arLog("Late callback ignored — publishPresentation")
                return
            }
            guard onPresentation != nil else { return }
            let now = CACurrentMediaTime()
            if !force, now - lastPresentationPublishTime < presentationMinInterval {
                // Still publish if structure changed significantly (appear/disappear).
                let sameGuides = guides.map(\.id) == lastPublishedGuides.map(\.id)
                    && guides.map(\.isBehind) == lastPublishedGuides.map(\.isBehind)
                let sameLabels = labels.map(\.id) == lastPublishedLabels.map(\.id)
                if sameGuides && sameLabels && uncertainty == lastPublishedUncertainty {
                    return
                }
            }
            // Skip no-op equality on full content when throttled.
            if !force,
               guides == lastPublishedGuides,
               labels == lastPublishedLabels,
               uncertainty == lastPublishedUncertainty {
                return
            }
            lastPresentationPublishTime = now
            lastPublishedGuides = guides
            lastPublishedLabels = labels
            lastPublishedUncertainty = uncertainty
            onPresentation?(guides, labels, uncertainty)
        }

        private func makeSun(radius: Float, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateSphere(radius: radius)
            var mat = UnlitMaterial(color: color)
            mat.blending = .transparent(opacity: .init(floatLiteral: Float(color.cgColor.alpha)))
            let sun = ModelEntity(mesh: mesh, materials: [mat])
            let glow = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.45),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.2))]
            )
            sun.addChild(glow)
            return sun
        }

        private func makeRocket() -> ModelEntity {
            // Unlit + contrast halo so Baby X stays visible in daylight and dark rooms.
            let body = ModelEntity(
                mesh: .generateBox(size: [0.10, 0.28, 0.10], cornerRadius: 0.04),
                materials: [UnlitMaterial(color: UIColor(white: 0.96, alpha: 1))]
            )
            let halo = ModelEntity(
                mesh: .generateSphere(radius: 0.22),
                materials: [UnlitMaterial(color: UIColor(red: 0.85, green: 1.0, blue: 0.35, alpha: 0.22))]
            )
            body.addChild(halo)
            let nose = ModelEntity(
                mesh: .generateSphere(radius: 0.06),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.42, blue: 0.2, alpha: 1))]
            )
            nose.position = [0, 0.18, 0]
            body.addChild(nose)
            let fin = ModelEntity(
                mesh: .generateBox(size: [0.16, 0.05, 0.025]),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.42, blue: 0.2, alpha: 1))]
            )
            fin.position = [0, -0.10, 0]
            body.addChild(fin)
            return body
        }

        // MARK: ARSessionDelegate

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let state = camera.trackingState
            Task { @MainActor in
                guard !self.isShuttingDown else {
                    self.arLog("Late callback ignored — trackingState")
                    return
                }
                self.calibration.updateARTracking(state)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in
                guard !self.isShuttingDown else {
                    self.arLog("Late callback ignored — sessionFail")
                    return
                }
                self.calibration.markSessionRunning(false)
                self.publishPresentation(guides: [], labels: [], uncertainty: "AR session failed", force: true)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                guard !self.isShuttingDown else {
                    self.arLog("Late callback ignored — interrupted")
                    return
                }
                self.calibration.markSessionRunning(false)
                // Do not publish empty overlays during interruption races with dismissal.
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                guard !self.isShuttingDown else {
                    self.arLog("Late callback ignored — interruptionEnded")
                    return
                }
                // If we intentionally paused for background, wait for foreground resume.
                guard !self.isPausedForBackground else { return }
                // Resume session without wiping celestial pair; clear stale screen smoothers only.
                self.smoothedScreenVisible = nil
                self.smoothedScreenActual = nil
                if let arView = self.arView {
                    if self.sessionStarted {
                        let config = ARWorldTrackingConfiguration()
                        config.worldAlignment = .gravityAndHeading
                        config.environmentTexturing = .automatic
                        arView.session.delegate = self
                        arView.session.run(config, options: [.resetTracking])
                        self.calibration.markSessionRunning(true)
                        // Ensure display link is alive after interruption.
                        if self.displayLink == nil {
                            self.start(on: arView)
                        }
                    } else {
                        self.start(on: arView)
                    }
                }
            }
        }
    }
}

// MARK: - Display-link proxy (breaks CADisplayLink → coordinator retain teardown races)

/// Nonisolated NSObject target for CADisplayLink; weakly holds the coordinator.
/// CADisplayLink runs on the main *thread* run loop but is **not** guaranteed to be on the
/// Swift MainActor executor — `MainActor.assumeIsolated` can trap and kill the process.
/// Always hop with `Task { @MainActor }` and drop work when the owner is gone or shutting down.
private final class ARDisplayLinkProxy: NSObject {
    weak var owner: CelestialARContainer.Coordinator?

    @objc func tick() {
        guard let owner else { return }
        Task { @MainActor [weak owner] in
            guard let owner, !owner.isShuttingDown else { return }
            owner.handleDisplayTick()
        }
    }
}

// MARK: - Baby X launch HUD (SwiftUI overlay)

private struct BabyXLaunchHUD: View {
    @ObservedObject var launch: BabyXLaunchController
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            if let mark = launch.countdownMark {
                Text("\(mark)")
                    .font(TimelyUNATheme.heroMetricFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .shadow(color: .black.opacity(0.8), radius: 6)
                    .transition(.opacity)
            }

            if launch.phase == .ignition && !reduceMotion {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                TimelyUNATheme.orange.opacity(0.55),
                                TimelyUNATheme.acid.opacity(0.15),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 90
                        )
                    )
                    .frame(width: 160, height: 160)
                    .offset(y: 40)
                    .allowsHitTesting(false)
            }

            if launch.showPhotonSlip {
                // Restrained dual-strand ring near completion
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [TimelyUNATheme.orange, TimelyUNATheme.acid, TimelyUNATheme.orange],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 72, height: 72)
                    .opacity(0.85)
                    .allowsHitTesting(false)
            }

            if let title = launch.confirmTitle {
                VStack(spacing: 6) {
                    Text(title)
                        .font(TimelyUNATheme.subheadingFont)
                        .foregroundStyle(TimelyUNATheme.acid)
                    if let sub = launch.confirmSubtitle {
                        Text(sub)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.papyrus)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 120)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.08) : .easeInOut(duration: 0.2), value: launch.phase)
        .animation(reduceMotion ? .linear(duration: 0.08) : .easeInOut(duration: 0.15), value: launch.countdownMark)
    }
}

// MARK: - 2D educational sky

private struct EducationalTwoDSkyView: View {
    let selectedDate: Date
    let displayPair: ARCelestialMath.DisplayPair?
    let showActualPosition: Bool
    let showLightline: Bool
    let educationalMagnification: Bool
    let rocketProgress: Double
    let showRocket: Bool
    let showHit: Bool
    var showPhotonSlip: Bool = false
    var chrome: ARScreenGuide.ExclusionInsets = .defaultChrome
    let onTapLaunch: () -> Void
    var onEdgeGuides: (([EdgeGuide]) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion && !showRocket)) { timeline in
                Canvas { context, size in
                    draw(context: context, size: size, time: timeline.date)
                }
            }
            .onAppear {
                updateEdges(size: geo.size)
                if !reduceMotion {
                    withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                        dashPhase = 40
                    }
                }
            }
            .onChange(of: displayPair) { _, _ in updateEdges(size: geo.size) }
            .onChange(of: showActualPosition) { _, _ in updateEdges(size: geo.size) }
            .onChange(of: chrome) { _, _ in updateEdges(size: geo.size) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapLaunch)
        .accessibilityLabel("2D sky. Visible Now and Actual Now. Tap to launch rocket.")
    }

    private func updateEdges(size: CGSize) {
        // 2D keeps markers on-canvas via resolveMarkers; no AR edge arrows needed.
        onEdgeGuides?([])
    }

    private func draw(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height
        for i in 0..<80 {
            let x = frac(i * 17) * w
            let y = frac(i * 43) * h * 0.72
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.35)))
        }
        var ground = Path()
        ground.addRect(CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.22))
        context.fill(ground, with: .color(Color(red: 0.08, green: 0.07, blue: 0.05)))

        // Map alt/az to preferred screen point (pre-collision).
        func mapPreferred(alt: Double, az: Double) -> CGPoint {
            let x = CGFloat(az / 360) * w * 0.7 + w * 0.15
            let y = h * 0.72 - CGFloat((alt + 10) / 70) * h * 0.45
            return CGPoint(x: x, y: y)
        }

        // YOU sits above the bottom sheet exclusion band when possible.
        let free = ARScreenGuide.freeRect(viewSize: size, insets: chrome)
        let youPreferred = CGPoint(x: w * 0.5, y: min(h * 0.82, free.maxY - 28))
        let youClamped = ARScreenGuide.clampCenter(youPreferred, size: CGSize(width: 48, height: 36), free: free)
        let you = youClamped.point
        context.fill(Path(ellipseIn: CGRect(x: you.x - 8, y: you.y - 8, width: 16, height: 16)), with: .color(TimelyUNATheme.cosmicPurple))
        text(context, "YOU", at: CGPoint(x: you.x, y: you.y + 18), color: TimelyUNATheme.blue, size: 11)

        guard let pair = displayPair else {
            text(context, "Need live location for sky placement", at: CGPoint(x: free.midX, y: free.midY), color: TimelyUNATheme.muted, size: 14)
            return
        }

        // Build markers → exclusion + collision resolve (banner / sheet safe).
        var markerSpecs: [ARScreenGuide.Marker] = [
            ARScreenGuide.Marker(
                id: "visible",
                preferred: mapPreferred(alt: pair.visibleAltitude, az: pair.visibleAzimuth),
                size: CGSize(width: 96, height: 72),
                priority: 10
            )
        ]
        if showActualPosition {
            markerSpecs.append(
                ARScreenGuide.Marker(
                    id: "actual",
                    preferred: mapPreferred(alt: pair.actualAltitude, az: pair.actualAzimuth),
                    size: CGSize(width: 104, height: 76),
                    priority: 8
                )
            )
        }
        let resolved = ARScreenGuide.resolveMarkers(markerSpecs, viewSize: size, insets: chrome, padding: 8)
        let byId = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        let app = byId["visible"]?.point ?? mapPreferred(alt: pair.visibleAltitude, az: pair.visibleAzimuth)
        let act = byId["actual"]?.point ?? mapPreferred(alt: pair.actualAltitude, az: pair.actualAzimuth)

        sun(context, app, radius: 18, color: TimelyUNATheme.apparentSun)
        text(context, "VISIBLE NOW", at: CGPoint(x: app.x, y: app.y + 28), color: TimelyUNATheme.papyrus, size: 12)

        if showActualPosition {
            sun(context, act, radius: 22, color: TimelyUNATheme.acid)
            text(context, "ACTUAL NOW", at: CGPoint(x: act.x, y: act.y + 32), color: TimelyUNATheme.acid, size: 12)
        }
        if showLightline && showActualPosition {
            var p = Path(); p.move(to: app); p.addLine(to: act)
            context.stroke(p, with: .color(TimelyUNATheme.gold.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: reduceMotion ? 0 : dashPhase))
        }
        if pair.isMagnified && educationalMagnification {
            // Keep edu badge inside free rect, not under top banner.
            let badgeY = max(free.minY + 14, chrome.top + 8)
            text(context, "EDU MAGNIFICATION · NOT LITERAL", at: CGPoint(x: free.midX, y: badgeY), color: TimelyUNATheme.orange, size: 11)
        }
        // Visible for entire launch visual (charge at t=0 through arrival) — never silent.
        if showRocket && showActualPosition {
            let t = max(0, min(1, rocketProgress))
            // Slight arc so 2D flight feels alive (not a straight decorative line).
            let arc = sin(t * .pi) * 28 * (reduceMotion ? 0.15 : 1)
            let x = you.x + (act.x - you.x) * t + CGFloat(arc * 0.25)
            let y = you.y + (act.y - you.y) * t - CGFloat(arc)
            // Exhaust trail
            if t > 0.05 && !reduceMotion {
                for i in 0..<6 {
                    let u = t * Double(i) / 6.0
                    let tx = you.x + (act.x - you.x) * u
                    let ty = you.y + (act.y - you.y) * u - CGFloat(sin(u * .pi) * 28)
                    let c = showPhotonSlip && u > 0.72
                        ? (i % 2 == 0 ? TimelyUNATheme.orange : TimelyUNATheme.acid)
                        : TimelyUNATheme.gold.opacity(0.7)
                    context.fill(Path(ellipseIn: CGRect(x: tx - 2, y: ty - 2, width: 4, height: 4)), with: .color(c))
                }
            }
            context.fill(Path(ellipseIn: CGRect(x: x - 7, y: y - 14, width: 14, height: 26)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 6, width: 8, height: 8)), with: .color(TimelyUNATheme.orange))
            if showPhotonSlip {
                context.stroke(
                    Path(ellipseIn: CGRect(x: x - 18, y: y - 18, width: 36, height: 36)),
                    with: .color(TimelyUNATheme.acid.opacity(0.8)),
                    lineWidth: 1.5
                )
            }
        }
        if showHit {
            text(context, "REALITY CORRECTED", at: CGPoint(x: free.midX, y: free.minY + 24), color: TimelyUNATheme.acid, size: 15)
        }
    }

    private func sun(_ c: GraphicsContext, _ p: CGPoint, radius: CGFloat, color: Color) {
        c.fill(Path(ellipseIn: CGRect(x: p.x - radius * 1.6, y: p.y - radius * 1.6, width: radius * 3.2, height: radius * 3.2)),
               with: .radialGradient(Gradient(colors: [color.opacity(0.45), .clear]), center: p, startRadius: 0, endRadius: radius * 1.6))
        c.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    private func text(_ c: GraphicsContext, _ s: String, at p: CGPoint, color: Color, size: CGFloat) {
        let r = c.resolve(Text(s).font(.system(size: size, weight: .semibold, design: .serif)).foregroundColor(color))
        let w = r.measure(in: CGSize(width: 500, height: 40)).width
        c.draw(r, at: CGPoint(x: p.x - w / 2, y: p.y), anchor: .leading)
    }

    private func frac(_ seed: Int) -> CGFloat {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

#Preview {
    ARSunRocketView(selectedDate: Date())
        .environmentObject(ObserverLocationService())
        .environmentObject(HorizonPersistence())
}

#else

// MARK: - macOS fallback (no ARKit session)

struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: ObserverLocationService
    @State private var showActual = true
    @State private var showLightline = true
    @State private var rocket: Double = 0
    @State private var flying = false
    @State private var hit = false
    @State private var pair: ARCelestialMath.DisplayPair?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EducationalMacSky(
                pair: pair,
                showActual: showActual,
                showLightline: showLightline,
                rocket: rocket,
                hit: hit,
                onLaunch: launch
            )
            Button {
                AppHaptics.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("AR on iPhone & iPad")
                    .font(TimelyUNATheme.headlineFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                Text("World-tracking AR needs a compatible physical iPhone or iPad. This Mac view is 2D educational sky mode.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .multilineTextAlignment(.center)
                HStack {
                    Toggle("Actual Now", isOn: $showActual)
                    Toggle("Lightline", isOn: $showLightline)
                }
                .toggleStyle(.button)
                .font(TimelyUNATheme.calloutFont)
                Button("Continue without AR / Launch") {
                    AppHaptics.selection()
                    launch()
                }
                    .font(TimelyUNATheme.calloutFont)
                    .frame(minHeight: 44)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear { recompute() }
        .onChange(of: location.latitude) { _, _ in recompute() }
    }

    private func recompute() {
        guard let lat = location.latitude, let lon = location.longitude, location.hasLiveCoordinates else {
            pair = nil
            return
        }
        let snap = SolarEngine.snapshot(date: Date(), latitude: lat, longitude: lon)
        pair = ARCelestialMath.educationalDisplayPair(visible: snap.apparent, actual: snap.truePosition)
    }

    private func launch() {
        guard !flying else { return }
        flying = true
        rocket = 0
        Task { @MainActor in
            let s = Date()
            while Date().timeIntervalSince(s) < 1.4 {
                rocket = min(1, Date().timeIntervalSince(s) / 1.4)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            hit = true
            flying = false
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            hit = false
            rocket = 0
        }
    }
}

private struct EducationalMacSky: View {
    let pair: ARCelestialMath.DisplayPair?
    let showActual: Bool
    let showLightline: Bool
    let rocket: Double
    let hit: Bool
    let onLaunch: () -> Void

    var body: some View {
        Canvas { context, size in
            for i in 0..<50 {
                let x = CGFloat((i * 47) % 1000) / 1000 * size.width
                let y = CGFloat((i * 91) % 1000) / 1000 * size.height * 0.7
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.4)))
            }
            let app = CGPoint(x: size.width * 0.35, y: size.height * 0.45)
            let act = CGPoint(x: size.width * 0.7, y: size.height * 0.32)
            let you = CGPoint(x: size.width * 0.5, y: size.height * 0.8)
            context.fill(Path(ellipseIn: CGRect(x: app.x - 20, y: app.y - 20, width: 40, height: 40)), with: .color(TimelyUNATheme.apparentSun))
            if showActual {
                context.fill(Path(ellipseIn: CGRect(x: act.x - 26, y: act.y - 26, width: 52, height: 52)), with: .color(TimelyUNATheme.acid))
            }
            if showLightline && showActual {
                var p = Path(); p.move(to: app); p.addLine(to: act)
                context.stroke(p, with: .color(TimelyUNATheme.gold), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            if rocket > 0 && showActual {
                let x = you.x + (act.x - you.x) * rocket
                let y = you.y + (act.y - you.y) * rocket
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 10, width: 10, height: 20)), with: .color(.white))
            }
        }
        .background(TimelyUNATheme.background)
        .onTapGesture(perform: onLaunch)
        .overlay(alignment: .top) {
            Text("2D SKY · VISIBLE NOW / ACTUAL NOW")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.acid)
                .padding()
        }
    }
}

#endif
