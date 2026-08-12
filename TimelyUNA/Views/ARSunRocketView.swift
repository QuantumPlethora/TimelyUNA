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

    @StateObject private var calibration = ARCalibrationService()
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

    // 2D rocket state
    @State private var rocketProgress: Double = 0
    @State private var isRocketFlying = false
    @State private var showRocketHit = false

    // Live solar + AR scene bindings
    @State private var snapshot: SolarEngine.Snapshot?
    @State private var displayPair: ARCelestialMath.DisplayPair?
    @State private var edgeGuides: [EdgeGuide] = []
    @State private var triggerRocket = false

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
            // Stable height from detent only (+ transient drag). AR ticks never change this.
            let sheetH = sheetHeight(
                fullHeight: geo.size.height,
                safeBottom: safeBottom,
                topReserve: topChromeHeight + geo.safeAreaInsets.top + 8,
                drag: sheetDragTranslation
            )

            ZStack(alignment: .top) {
                // Camera / 2D sky fills the full area
                Group {
                    if useTwoD {
                        twoDLayer
                    } else {
                        arLayer
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

                // Edge guidance stays inside free viewport
                EdgeArrowOverlay(
                    guides: edgeGuides,
                    topReserved: topChromeHeight + geo.safeAreaInsets.top,
                    bottomReserved: sheetH
                )
                .allowsHitTesting(false)

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
                .zIndex(2)

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
                        topReserve: topChromeHeight + geo.safeAreaInsets.top + 8
                    )
                }
                .zIndex(3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: calibration.quality) { _, quality in
                // Never change sheetDetent from calibration updates — preserve user position.
                if quality == .calibrated {
                    calibrationDetailsExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        if calibration.quality == .calibrated {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                statusBannerVisible = false
                            }
                        }
                    }
                } else {
                    statusBannerVisible = true
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            calibration.start()
            syncLocationIntoCalibration()
            recomputeSolar()
            sheetDetent = .collapsed
            sheetDragTranslation = 0
            howThisWorksExpanded = false
            calibrationDetailsExpanded = false
            statusBannerVisible = true
            if worldTrackingSupported {
                checkCamera()
            } else {
                forceTwoD = false // show gate then 2D
            }
        }
        .onDisappear { calibration.stop() }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // Live AR data only — do not touch sheetDetent / sheetDragTranslation.
            recomputeSolar()
            syncLocationIntoCalibration()
        }
        .onChange(of: location.latitude) { _, _ in
            syncLocationIntoCalibration()
            recomputeSolar()
        }
        .onChange(of: location.longitude) { _, _ in
            syncLocationIntoCalibration()
            recomputeSolar()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
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
    private var arLayer: some View {
        if !worldTrackingSupported {
            ARUnavailableGate(
                reason: .worldTrackingUnsupported,
                onContinue: { forceTwoD = true },
                onClose: { dismiss() }
            )
        } else if cameraDenied {
            ARUnavailableGate(
                reason: .cameraDenied,
                onContinue: { forceTwoD = true },
                onClose: { dismiss() }
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
                triggerRocket: $triggerRocket,
                edgeGuides: $edgeGuides,
                onCameraUnauthorized: { cameraDenied = true }
            )
            .ignoresSafeArea()
        }
    }

    private var twoDLayer: some View {
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
                rocketProgress: rocketProgress,
                showRocket: isRocketFlying || rocketProgress > 0,
                showHit: showRocketHit,
                onTapLaunch: { launchTwoDRocket() },
                onEdgeGuides: { edgeGuides = $0 }
            )
            .ignoresSafeArea()

            if !worldTrackingSupported && !forceTwoD {
                ARUnavailableGate(
                    reason: .worldTrackingUnsupported,
                    onContinue: { forceTwoD = true },
                    onClose: { dismiss() }
                )
            } else if cameraDenied && !forceTwoD {
                ARUnavailableGate(
                    reason: .cameraDenied,
                    onContinue: { forceTwoD = true },
                    onClose: { dismiss() }
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

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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

        return Button(action: action) {
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
                    Button("Done") { showCalibrationDetail = false }
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
        Button {
            if useTwoD {
                launchTwoDRocket()
            } else {
                triggerRocket = true
            }
        } label: {
            Label("Launch Baby X", systemImage: "airplane.departure")
                .font(TimelyUNATheme.calloutFont)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(TimelyUNATheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    showActualPosition ? TimelyUNATheme.acid : TimelyUNATheme.muted,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!showActualPosition)
        .accessibilityHint("Launches the rocket toward Actual Now")
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

    private func launchTwoDRocket() {
        guard showActualPosition, !isRocketFlying else { return }
        if reduceMotion {
            showRocketHit = true
            rocketProgress = 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                showRocketHit = false
                rocketProgress = 0
            }
            return
        }
        isRocketFlying = true
        showRocketHit = false
        rocketProgress = 0
        Task { @MainActor in
            let start = Date()
            while true {
                let p = min(Date().timeIntervalSince(start) / 1.45, 1)
                rocketProgress = p
                if p >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            showRocketHit = true
            isRocketFlying = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showRocketHit = false
            rocketProgress = 0
        }
    }
}

// MARK: - Edge guides

struct EdgeGuide: Identifiable, Equatable {
    let id: String
    var direction: CGPoint
    var color: Color
    var label: String
}

private struct EdgeArrowOverlay: View {
    let guides: [EdgeGuide]
    /// Reserved UI chrome so arrows stay in the free camera band.
    var topReserved: CGFloat = 100
    var bottomReserved: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let freeTop = topReserved
            let freeBottom = geo.size.height - bottomReserved
            let freeHeight = max(80, freeBottom - freeTop)
            let mid = CGPoint(x: geo.size.width / 2, y: freeTop + freeHeight * 0.5)
            let radius = min(geo.size.width * 0.40, freeHeight * 0.40)
            ForEach(guides) { guide in
                let raw = CGPoint(
                    x: mid.x + guide.direction.x * radius,
                    y: mid.y + guide.direction.y * radius
                )
                // Clamp into free viewport so labels never sit under toolbar / sheet.
                let pos = CGPoint(
                    x: min(max(raw.x, 36), geo.size.width - 36),
                    y: min(max(raw.y, freeTop + 24), freeBottom - 24)
                )
                VStack(spacing: 4) {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.radians(atan2(guide.direction.x, -guide.direction.y)))
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
                .accessibilityLabel("\(guide.label) is off screen. Turn \(directionPhrase(guide.direction)).")
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
                Button(action: onContinue) {
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
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .frame(minHeight: 44)
                }
                Button("Close", action: onClose)
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

// MARK: - Celestial AR container

private struct CelestialARContainer: UIViewRepresentable {
    let selectedDate: Date
    let displayPair: ARCelestialMath.DisplayPair?
    let showActual: Bool
    let showLightline: Bool
    let educationalMagnification: Bool
    @ObservedObject var calibration: ARCalibrationService
    let reduceMotion: Bool
    @Binding var triggerRocket: Bool
    @Binding var edgeGuides: [EdgeGuide]
    var onCameraUnauthorized: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(calibration: calibration, onCameraUnauthorized: onCameraUnauthorized)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.renderOptions.insert(.disableMotionBlur)
        context.coordinator.arView = arView
        context.coordinator.reduceMotion = reduceMotion

        guard ARWorldTrackingConfiguration.isSupported else {
            onCameraUnauthorized?()
            return arView
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
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
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.apply(
            pair: displayPair,
            showActual: showActual,
            showLightline: showLightline,
            magnified: educationalMagnification
        )
        if triggerRocket {
            context.coordinator.launchRocket()
            DispatchQueue.main.async { triggerRocket = false }
        }
        context.coordinator.refreshEdgeGuides { guides in
            DispatchQueue.main.async { edgeGuides = guides }
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        coordinator.displayLink?.invalidate()
        coordinator.calibration.markSessionRunning(false)
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        let calibration: ARCalibrationService
        var onCameraUnauthorized: (() -> Void)?
        weak var arView: ARView?
        var reduceMotion = false

        private var sessionStarted = false
        private var rootAnchor: AnchorEntity?
        private var visibleSun: ModelEntity?
        private var actualSun: ModelEntity?
        private var visibleLabel: Entity?
        private var actualLabel: Entity?
        private var lightline: ModelEntity?
        private var lightlineLabel: Entity?
        private var eduBadge: Entity?
        private var rocket: ModelEntity?
        private var trailPoints: [SIMD3<Float>] = []
        private var trailEntities: [ModelEntity] = []
        private var hasLaunched = false
        private var currentPair: ARCelestialMath.DisplayPair?
        private var smoothedVisibleDir: SIMD3<Float>?
        private var smoothedActualDir: SIMD3<Float>?
        var displayLink: CADisplayLink?

        /// Placement distance keeps angular size readable without giant near-field spheres.
        private let skyDistance: Float = 80
        private let visibleRadius: Float = 0.55
        private let actualRadius: Float = 0.62

        init(calibration: ARCalibrationService, onCameraUnauthorized: (() -> Void)?) {
            self.calibration = calibration
            self.onCameraUnauthorized = onCameraUnauthorized
        }

        func start(on arView: ARView) {
            guard ARWorldTrackingConfiguration.isSupported, !sessionStarted else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                onCameraUnauthorized?()
                return
            }

            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravityAndHeading
            config.environmentTexturing = .automatic
            // No plane detection required for sky directions.
            arView.session.delegate = self
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            sessionStarted = true
            calibration.markSessionRunning(true)
            self.arView = arView
            buildScene(in: arView)

            displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func apply(
            pair: ARCelestialMath.DisplayPair?,
            showActual: Bool,
            showLightline: Bool,
            magnified: Bool
        ) {
            currentPair = pair
            actualSun?.isEnabled = showActual
            actualLabel?.isEnabled = showActual
            lightline?.isEnabled = showLightline && showActual
            lightlineLabel?.isEnabled = showLightline && showActual
            eduBadge?.isEnabled = magnified && (pair?.isMagnified ?? false)
            updatePlacements(animated: true)
        }

        func launchRocket() {
            guard let rocket, let actualSun, let rootAnchor, !hasLaunched else { return }
            guard actualSun.isEnabled else { return }

            let origin = SIMD3<Float>(0, -0.35, -0.55) // lower-center relative to camera anchor
            // Rebuild rocket at lower center of view each launch
            rocket.position = origin
            hasLaunched = true
            trailPoints = [origin]
            clearTrail()

            if reduceMotion {
                rocket.position = actualSun.position
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                hasLaunched = false
                return
            }

            let target = actualSun.position
            let duration: Float = 1.6
            let start = origin
            let startDate = CACurrentMediaTime()

            // Animate along path
            let animLink = CADisplayLink(target: self, selector: #selector(rocketTick))
            rocketAnim = RocketAnim(
                link: animLink,
                start: start,
                end: target,
                startTime: startDate,
                duration: Double(duration)
            )
            animLink.add(to: .main, forMode: .common)
        }

        private struct RocketAnim {
            let link: CADisplayLink
            let start: SIMD3<Float>
            let end: SIMD3<Float>
            let startTime: CFTimeInterval
            let duration: Double
        }
        private var rocketAnim: RocketAnim?

        @objc private func rocketTick() {
            guard let anim = rocketAnim, let rocket else { return }
            let t = min(1, (CACurrentMediaTime() - anim.startTime) / anim.duration)
            let ease = Float(t * t * (3 - 2 * t))
            let pos = anim.start + (anim.end - anim.start) * ease
            // slight arc
            let arc = SIMD3<Float>(0, 0.15 * sin(Float.pi * ease), 0)
            rocket.position = pos + arc
            trailPoints.append(rocket.position)
            if trailPoints.count % 2 == 0 {
                appendTrailDot(at: rocket.position)
            }
            if t >= 1 {
                anim.link.invalidate()
                rocketAnim = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                hasLaunched = false
            }
        }

        private func clearTrail() {
            trailEntities.forEach { $0.removeFromParent() }
            trailEntities.removeAll()
        }

        private func appendTrailDot(at p: SIMD3<Float>) {
            guard let rootAnchor else { return }
            let dot = ModelEntity(
                mesh: .generateSphere(radius: 0.04),
                materials: [UnlitMaterial(color: UIColor(red: 0.85, green: 1, blue: 0.3, alpha: 0.55))]
            )
            dot.position = p
            rootAnchor.addChild(dot)
            trailEntities.append(dot)
            if trailEntities.count > 40 {
                let old = trailEntities.removeFirst()
                old.removeFromParent()
            }
        }

        private func buildScene(in arView: ARView) {
            arView.scene.anchors.removeAll()
            // Camera-relative root so celestial directions are from observer.
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

            let vLab = makeBillboardLabel("VISIBLE NOW", color: .white)
            visibleLabel = vLab
            anchor.addChild(vLab)

            let aLab = makeBillboardLabel("ACTUAL NOW", color: UIColor(red: 0.85, green: 1.0, blue: 0.26, alpha: 1))
            actualLabel = aLab
            anchor.addChild(aLab)

            let line = ModelEntity(
                mesh: .generateBox(size: [0.03, 0.03, 1], cornerRadius: 0.01),
                materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 0.75))]
            )
            lightline = line
            anchor.addChild(line)

            let lLab = makeBillboardLabel("LIGHTLINE", color: UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1))
            lightlineLabel = lLab
            anchor.addChild(lLab)

            let edu = makeBillboardLabel("EDU MAGNIFICATION · NOT LITERAL", color: UIColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 1))
            eduBadge = edu
            edu.isEnabled = false
            anchor.addChild(edu)

            let rock = makeRocket()
            rock.position = SIMD3<Float>(0, -0.35, -0.55)
            rocket = rock
            anchor.addChild(rock)

            arView.scene.addAnchor(anchor)
            updatePlacements(animated: false)
        }

        private func updatePlacements(animated: Bool) {
            guard let pair = currentPair else { return }

            let vDir = ARCelestialMath.worldDirection(
                altitudeDegrees: pair.visibleAltitude,
                azimuthDegrees: pair.visibleAzimuth
            )
            let aDir = ARCelestialMath.worldDirection(
                altitudeDegrees: pair.actualAltitude,
                azimuthDegrees: pair.actualAzimuth
            )

            let alpha: Float = animated ? 0.2 : 1.0
            smoothedVisibleDir = ARCelestialMath.smoothVector(previous: smoothedVisibleDir, sample: vDir, alpha: alpha)
            smoothedActualDir = ARCelestialMath.smoothVector(previous: smoothedActualDir, sample: aDir, alpha: alpha)

            let vd = smoothedVisibleDir ?? vDir
            let ad = smoothedActualDir ?? aDir

            let vPos = vd * skyDistance
            let aPos = ad * skyDistance

            visibleSun?.position = vPos
            actualSun?.position = aPos

            // Labels beneath markers (slightly toward camera / down in world up sense relative to sun)
            let down = SIMD3<Float>(0, -1, 0)
            visibleLabel?.position = vPos + down * (visibleRadius * 2.2)
            actualLabel?.position = aPos + down * (actualRadius * 2.2)
            eduBadge?.position = (vPos + aPos) * 0.5 + SIMD3<Float>(0, 1.2, 0)

            // Lightline as stretched box from visible to actual
            if let lightline {
                let mid = (vPos + aPos) * 0.5
                let delta = aPos - vPos
                let length = simd_length(delta)
                lightline.position = mid
                if length > 0.01 {
                    lightline.scale = SIMD3<Float>(1, 1, length)
                    let dir = delta / length
                    // Orient box's Z axis along dir
                    lightline.look(at: mid + dir, from: mid, relativeTo: nil)
                }
                lightlineLabel?.position = mid + SIMD3<Float>(0, 0.35, 0)
            }

            billboardAll()
        }

        @objc private func tick() {
            billboardAll()
            refreshEdgeGuides { _ in }
        }

        private func billboardAll() {
            guard let arView, let cam = arView.session.currentFrame?.camera else { return }
            let camPos = SIMD3<Float>(cam.transform.columns.3.x, cam.transform.columns.3.y, cam.transform.columns.3.z)
            // Labels are children of camera anchor, so camera is near origin of parent when using .camera anchor.
            // Billboard toward local camera origin (0,0,0) in camera space... Actually camera anchor means children are in camera space already!
            // With AnchorEntity(.camera), positions are in camera coordinates: -Z forward, Y up, X right.
            // Celestial worldDirection assumes world ENU mapped with gravityAndHeading world space.
            //
            // IMPORTANT: If root is camera-anchored, celestial directions in gravityAndHeading world
            // must be transformed into camera space. Using world anchor is more correct.
            //
            // We rebuild using a world anchor at camera position for correct celestial alignment.
            for entity in [visibleLabel, actualLabel, lightlineLabel, eduBadge] {
                guard let entity else { continue }
                // Face the local camera (origin in camera-anchored space is complex).
                // Prefer facing -Z of parent if camera-anchored; use look(at:from:) with up = +Y.
                let pos = entity.position
                let toCamera = SIMD3<Float>(0, 0, 0) - pos
                if simd_length(toCamera) > 0.01 {
                    entity.look(at: pos + SIMD3<Float>(0, 0, 0.01), from: pos, relativeTo: entity.parent)
                }
                // Keep upright: constrain orientation so local +Y aligns with world up projected.
                _ = camPos
            }
            // Re-orient labels to face camera transform more carefully:
            orientBillboard(visibleLabel)
            orientBillboard(actualLabel)
            orientBillboard(lightlineLabel)
            orientBillboard(eduBadge)
        }

        private func orientBillboard(_ entity: Entity?) {
            guard let entity, let arView else { return }
            // Camera transform in world space
            guard let frame = arView.session.currentFrame else { return }
            let camT = frame.camera.transform
            // If parent is camera anchor, entity space ≈ camera space; face -Z toward camera means look at 0.
            let pos = entity.position(relativeTo: nil)
            let camPos = SIMD3<Float>(camT.columns.3.x, camT.columns.3.y, camT.columns.3.z)
            let up = SIMD3<Float>(0, 1, 0)
            entity.look(at: camPos, from: pos, upVector: up, relativeTo: nil)
        }

        func refreshEdgeGuides(completion: @escaping ([EdgeGuide]) -> Void) {
            guard let arView, let pair = currentPair, let frame = arView.session.currentFrame else {
                completion([])
                return
            }
            let size = arView.bounds.size
            guard size.width > 1, size.height > 1 else {
                completion([])
                return
            }

            // Transform celestial camera-relative points: with gravityAndHeading, place relative to camera world pose.
            let cam = frame.camera.transform
            let camPos = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)

            func worldPos(alt: Double, az: Double) -> SIMD3<Float> {
                let dir = ARCelestialMath.worldDirection(altitudeDegrees: alt, azimuthDegrees: az)
                return camPos + dir * skyDistance
            }

            let vWorld = worldPos(alt: pair.visibleAltitude, az: pair.visibleAzimuth)
            let aWorld = worldPos(alt: pair.actualAltitude, az: pair.actualAzimuth)

            let view = frame.camera.viewMatrix(for: .portrait)
            // Use interface orientation
            let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            let viewM = frame.camera.viewMatrix(for: orientation)
            let projM = frame.camera.projectionMatrix(for: orientation, viewportSize: size, zNear: 0.01, zFar: 200)

            _ = view
            // Reserve space for top toolbar/banner and collapsed bottom sheet.
            let chrome = UIEdgeInsets(top: 110, left: 28, bottom: 130, right: 28)
            var guides: [EdgeGuide] = []
            let vp = ARScreenGuide.project(
                worldPoint: vWorld,
                viewMatrix: viewM,
                projectionMatrix: projM,
                viewSize: size,
                chromeInsets: chrome
            )
            if !vp.isOnScreen {
                guides.append(EdgeGuide(id: "visible", direction: vp.edgeDirection, color: TimelyUNATheme.apparentSun, label: "Visible Now"))
            }
            if actualSun?.isEnabled == true {
                let ap = ARScreenGuide.project(
                    worldPoint: aWorld,
                    viewMatrix: viewM,
                    projectionMatrix: projM,
                    viewSize: size,
                    chromeInsets: chrome
                )
                if !ap.isOnScreen {
                    guides.append(EdgeGuide(id: "actual", direction: ap.edgeDirection, color: TimelyUNATheme.acid, label: "Actual Now"))
                }
            }
            completion(guides)

            // Also push world placements onto camera-anchored entities via converting world dir into camera space.
            placeUsingCameraSpace(frame: frame)
        }

        /// Convert world ENU celestial directions into camera-local positions for the camera anchor.
        private func placeUsingCameraSpace(frame: ARFrame) {
            guard let pair = currentPair else { return }
            let cam = frame.camera.transform
            // World-from-camera rotation
            let r = simd_float3x3(
                SIMD3<Float>(cam.columns.0.x, cam.columns.0.y, cam.columns.0.z),
                SIMD3<Float>(cam.columns.1.x, cam.columns.1.y, cam.columns.1.z),
                SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
            )
            // camera-from-world = transpose(R) for pure rotation
            let rInv = r.transpose

            func camLocal(alt: Double, az: Double) -> SIMD3<Float> {
                let worldDir = ARCelestialMath.worldDirection(altitudeDegrees: alt, azimuthDegrees: az)
                let local = rInv * worldDir
                return local * skyDistance
            }

            var v = camLocal(alt: pair.visibleAltitude, az: pair.visibleAzimuth)
            var a = camLocal(alt: pair.actualAltitude, az: pair.actualAzimuth)

            let alpha: Float = 0.22
            if let sv = smoothedVisibleDir {
                // reuse smoothed dirs as positions unit vectors in camera space
                let unitV = simd_normalize(v)
                let mixed = simd_normalize(sv * (1 - alpha) + unitV * alpha)
                smoothedVisibleDir = mixed
                v = mixed * skyDistance
            } else {
                smoothedVisibleDir = simd_normalize(v)
            }
            if let sa = smoothedActualDir {
                let unitA = simd_normalize(a)
                let mixed = simd_normalize(sa * (1 - alpha) + unitA * alpha)
                smoothedActualDir = mixed
                a = mixed * skyDistance
            } else {
                smoothedActualDir = simd_normalize(a)
            }

            visibleSun?.position = v
            actualSun?.position = a
            visibleLabel?.position = v + SIMD3<Float>(0, -visibleRadius * 2.4, 0)
            actualLabel?.position = a + SIMD3<Float>(0, -actualRadius * 2.4, 0)
            eduBadge?.position = (v + a) * 0.5 + SIMD3<Float>(0, 1.0, 0)

            if let lightline {
                let mid = (v + a) * 0.5
                let delta = a - v
                let length = simd_length(delta)
                lightline.position = mid
                if length > 0.05 {
                    lightline.scale = SIMD3<Float>(1, 1, length)
                    lightline.look(at: a, from: mid, relativeTo: rootAnchor)
                }
                lightlineLabel?.position = mid + SIMD3<Float>(0, 0.4, 0)
            }
            orientBillboardCameraSpace(visibleLabel)
            orientBillboardCameraSpace(actualLabel)
            orientBillboardCameraSpace(lightlineLabel)
            orientBillboardCameraSpace(eduBadge)
        }

        private func orientBillboardCameraSpace(_ entity: Entity?) {
            guard let entity else { return }
            // Face camera origin in camera-anchored space; keep upright with +Y.
            let pos = entity.position
            let target = SIMD3<Float>(0, 0, 0)
            entity.look(at: target, from: pos, upVector: SIMD3<Float>(0, 1, 0), relativeTo: rootAnchor)
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
            let body = ModelEntity(
                mesh: .generateBox(size: [0.08, 0.22, 0.08], cornerRadius: 0.03),
                materials: [SimpleMaterial(color: .white, isMetallic: true)]
            )
            let nose = ModelEntity(
                mesh: .generateSphere(radius: 0.045),
                materials: [SimpleMaterial(color: UIColor(red: 1, green: 0.42, blue: 0.2, alpha: 1), isMetallic: true)]
            )
            nose.position = [0, 0.14, 0]
            body.addChild(nose)
            let fin = ModelEntity(
                mesh: .generateBox(size: [0.12, 0.04, 0.02]),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.42, blue: 0.2, alpha: 1))]
            )
            fin.position = [0, -0.08, 0]
            body.addChild(fin)
            return body
        }

        private func makeBillboardLabel(_ text: String, color: UIColor) -> Entity {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.004,
                font: UIFont(name: "Papyrus", size: 0.22) ?? .systemFont(ofSize: 0.22, weight: .semibold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )
            let model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
            // Center the text mesh
            model.scale = SIMD3<Float>(repeating: 0.55)
            let parent = Entity()
            parent.addChild(model)
            // Offset so text sits centered-ish
            model.position = SIMD3<Float>(-0.35, 0, 0)
            return parent
        }

        // MARK: ARSessionDelegate

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let state = camera.trackingState
            Task { @MainActor in
                self.calibration.updateARTracking(state)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in
                self.calibration.markSessionRunning(false)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                self.calibration.markSessionRunning(false)
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                if let arView = self.arView {
                    self.sessionStarted = false
                    self.start(on: arView)
                }
            }
        }
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
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapLaunch)
        .accessibilityLabel("2D sky. Visible Now and Actual Now. Tap to launch rocket.")
    }

    private func updateEdges(size: CGSize) {
        // 2D layout keeps markers on-canvas; clear AR edge guides.
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

        // Map alt/az to screen: az→x, alt→y (educational 2D projection)
        func map(alt: Double, az: Double) -> CGPoint {
            // Center az 180 or current mid; use az 0...360 → x
            let x = CGFloat(az / 360) * w * 0.7 + w * 0.15
            let y = h * 0.72 - CGFloat((alt + 10) / 70) * h * 0.45
            return CGPoint(x: min(w - 40, max(40, x)), y: min(h * 0.75, max(80, y)))
        }

        let you = CGPoint(x: w * 0.5, y: h * 0.82)
        context.fill(Path(ellipseIn: CGRect(x: you.x - 8, y: you.y - 8, width: 16, height: 16)), with: .color(TimelyUNATheme.cosmicPurple))
        text(context, "YOU", at: CGPoint(x: you.x, y: you.y + 18), color: TimelyUNATheme.blue, size: 11)

        guard let pair = displayPair else {
            text(context, "Need live location for sky placement", at: CGPoint(x: w * 0.5, y: h * 0.4), color: TimelyUNATheme.muted, size: 14)
            return
        }

        let app = map(alt: pair.visibleAltitude, az: pair.visibleAzimuth)
        let act = map(alt: pair.actualAltitude, az: pair.actualAzimuth)

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
            text(context, "EDU MAGNIFICATION · NOT LITERAL", at: CGPoint(x: w * 0.5, y: 56), color: TimelyUNATheme.orange, size: 11)
        }
        if showRocket && showActualPosition && rocketProgress > 0 {
            let t = rocketProgress
            let x = you.x + (act.x - you.x) * t
            let y = you.y + (act.y - you.y) * t
            context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 12, width: 10, height: 22)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 4, width: 6, height: 6)), with: .color(TimelyUNATheme.blue))
        }
        if showHit {
            text(context, "DIRECT HIT · ACTUAL NOW", at: CGPoint(x: w * 0.5, y: h * 0.18), color: TimelyUNATheme.acid, size: 15)
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
            Button { dismiss() } label: {
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
                Button("Continue without AR / Launch") { launch() }
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
