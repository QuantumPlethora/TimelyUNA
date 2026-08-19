import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Protected planet viewport. No chrome may overlap this region.
/// Participates in normal SwiftUI layout (not a background behind scroll content).
///
/// Gestures are intentional:
/// - Vertical pans are *not* claimed by the planet stage so the parent `ScrollView` scrolls.
/// - Horizontal-dominant pans orbit the camera.
/// - Pinch continues to zoom.
struct XSkyPlanetStage: View {
    @ObservedObject var state: XSkyJumpState
    /// When true, draws a bright debug outline and logs frame geometry.
    var debugOutline: Bool = false
    var onStageFrame: ((CGRect) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            // GeometryReader sizes the stage; camera distance keeps disc ≤76% of min side
            // with ≥8% diameter empty margin around the atmospheric rim.
            ZStack {
                if state.isOnSurface {
                    XSkySurfaceSkyView(state: state)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity)
                } else {
                    // Starfield is clipped to the stage; the planet renderer is not.
                    XSkyStarfieldView(
                        parallax: CGSize(
                            width: state.orbitYaw * 12,
                            height: state.orbitPitch * 10
                        ),
                        intensity: state.phase == .corridor ? 1.15 : 1.0
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                    XSkyPlanetSceneView(state: state, stageSize: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Never clip the planet / atmospheric rim.
                        .compositingGroup()
                        // SceneKit view does not own touches; gesture overlay + ScrollView do.
                        .allowsHitTesting(false)

                    // Transparent interaction layer: directional orbit + pinch.
                    XSkyPlanetInteractionOverlay(state: state)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // No journey labels inside PlanetStage — text lives in chrome below/beside.

                if debugOutline {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.green, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityPlanetLabel)
            .accessibilityHint(accessibilityStageHint)
            .animation(.easeInOut(duration: 0.3), value: state.isOnSurface)
            .onAppear {
                reportFrame(geo.frame(in: .global))
            }
            .onChange(of: geo.size) { _, _ in
                reportFrame(geo.frame(in: .global))
            }
            .background(
                GeometryReader { g in
                    Color.clear
                        .preference(
                            key: XSkyPlanetStageFrameKey.self,
                            value: g.frame(in: .global)
                        )
                }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        )
        // Do not clip the stage container — clipping would risk the atmospheric rim.
        // Starfield alone is clipped above.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TimelyUNATheme.line.opacity(0.55), lineWidth: 1)
        )
        .onPreferenceChange(XSkyPlanetStageFrameKey.self) { frame in
            onStageFrame?(frame)
            if debugOutline {
                #if DEBUG
                #if DEBUG
                print("[xSky PlanetStage] frame=\(frame.integral)")
                #endif
                #endif
            }
        }
    }

    private var accessibilityPlanetLabel: String {
        switch state.phase {
        case .mars: return "Standing on the Martian surface, viewing Earth, Venus, Mercury, and the Sun"
        case .earth: return "Standing on Earth's surface, viewing Mars, Venus, Mercury, and the Sun"
        default: return "Planet stage during xSky Jump"
        }
    }

    private var accessibilityStageHint: String {
        state.isOnSurface
            ? "Use the Look toward selector below to inspect a celestial body. Swipe vertically to scroll the page."
            : "Drag horizontally to orbit. Pinch or scroll to zoom. Swipe vertically to scroll the page."
    }

    private func reportFrame(_ frame: CGRect) {
        onStageFrame?(frame)
    }
}

// MARK: - Destination surface skies

/// Ground-level educational view shown after arrival. All principal inner-sky targets
/// remain visible together; the Look toward picker selects which body demonstrates the
/// TimelyUNA Visible Now / Actual Now separation.
private struct XSkySurfaceSkyView: View {
    @ObservedObject var state: XSkyJumpState

    private var isMars: Bool { state.observer == .mars }

    private var visibleTargets: [XSkyJumpState.LookTarget] {
        isMars
            ? [.earth, .venus, .mercury, .sun]
            : [.mars, .venus, .mercury, .sun]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: skyColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                surfaceStars

                RadialGradient(
                    colors: [hazeColor.opacity(0.38), .clear],
                    center: isMars ? .trailing : .topTrailing,
                    startRadius: 4,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )

                ForEach(visibleTargets, id: \.rawValue) { target in
                    celestialMarker(for: target)
                        .position(position(for: target, in: geo.size))
                }

                XSkySurfaceTerrain(isMars: isMars)
                    .fill(
                        LinearGradient(
                            colors: terrainColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .bottom) {
                        terrainDetails(in: geo.size)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isMars ? "MARTIAN SURFACE SKY" : "EARTH SURFACE SKY")
                        .font(TimelyUNATheme.captionFont)
                        .tracking(1.1)
                        .foregroundStyle(isMars ? Color(red: 0.35, green: 0.12, blue: 0.07) : TimelyUNATheme.papyrus)
                    Text(isMars ? "Earth · Venus · Mercury" : "Mars · Venus · Mercury")
                        .font(TimelyUNATheme.smallCaptionFont)
                        .foregroundStyle(isMars ? Color.black.opacity(0.62) : TimelyUNATheme.gold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.black.opacity(isMars ? 0.12 : 0.34), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

                Text("Illustrative surface view · positions not to scale")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.papyrus.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.46), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
            .accessibilityHidden(true)
        }
    }

    private var skyColors: [Color] {
        if isMars {
            return [
                Color(red: 0.22, green: 0.13, blue: 0.22),
                Color(red: 0.58, green: 0.31, blue: 0.23),
                Color(red: 0.84, green: 0.55, blue: 0.36),
                Color(red: 0.95, green: 0.70, blue: 0.46)
            ]
        }
        return [
            Color(red: 0.015, green: 0.025, blue: 0.10),
            Color(red: 0.08, green: 0.12, blue: 0.28),
            Color(red: 0.34, green: 0.20, blue: 0.32),
            Color(red: 0.72, green: 0.42, blue: 0.28)
        ]
    }

    private var terrainColors: [Color] {
        isMars
            ? [Color(red: 0.48, green: 0.21, blue: 0.12), Color(red: 0.16, green: 0.07, blue: 0.05)]
            : [Color(red: 0.09, green: 0.16, blue: 0.16), Color(red: 0.015, green: 0.035, blue: 0.04)]
    }

    private var hazeColor: Color {
        isMars ? Color.orange : Color(red: 0.35, green: 0.55, blue: 1)
    }

    private var surfaceStars: some View {
        Canvas { context, size in
            for index in 0..<(isMars ? 34 : 70) {
                let x = deterministicFraction(index * 37 + (isMars ? 7 : 19)) * size.width
                let y = deterministicFraction(index * 71 + 5) * size.height * 0.64
                let diameter = 0.7 + deterministicFraction(index * 13) * 1.5
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(Color.white.opacity(isMars ? 0.34 : 0.72))
                )
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func celestialMarker(for target: XSkyJumpState.LookTarget) -> some View {
        let selected = state.lookTarget == target
        let offset = state.lookAngularOffsetDegrees()
        let separation = selected ? min(34, max(9, CGFloat(offset.displaySep) * 3.2)) : 0
        let diameter = markerDiameter(for: target)

        VStack(spacing: 3) {
            ZStack {
                if selected && state.showLightline {
                    Path { path in
                        path.move(to: CGPoint(x: 40 - separation / 2, y: 24))
                        path.addLine(to: CGPoint(x: 40 + separation / 2, y: 24))
                    }
                    .stroke(
                        TimelyUNATheme.gold,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
                    )
                }

                if !selected || state.showVisibleNow {
                    bodyDisc(for: target, diameter: diameter)
                        .overlay(Circle().stroke(selected ? TimelyUNATheme.apparentSun : .white.opacity(0.55), lineWidth: selected ? 2 : 1))
                        .offset(x: selected ? -separation / 2 : 0)
                }

                if selected && state.showActualNow {
                    bodyDisc(for: target, diameter: diameter)
                        .overlay(Circle().stroke(TimelyUNATheme.acid, lineWidth: 2))
                        .offset(x: separation / 2)
                }
            }
            .frame(width: 80, height: 48)

            Text(target.rawValue)
                .font(TimelyUNATheme.smallCaptionFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(selected ? 0.62 : 0.34), in: Capsule())
        }
        .scaleEffect(selected ? 1.08 : 1)
    }

    private func bodyDisc(for target: XSkyJumpState.LookTarget, diameter: CGFloat) -> some View {
        Circle()
            .fill(markerColor(for: target))
            .frame(width: diameter, height: diameter)
            .shadow(color: markerColor(for: target).opacity(0.9), radius: target == .sun ? 10 : 4)
    }

    private func position(for target: XSkyJumpState.LookTarget, in size: CGSize) -> CGPoint {
        let coordinates: (CGFloat, CGFloat)
        if isMars {
            switch target {
            case .venus: coordinates = (0.22, 0.31)
            case .mercury: coordinates = (0.43, 0.46)
            case .earth: coordinates = (0.66, 0.28)
            case .sun: coordinates = (0.84, 0.42)
            case .mars: coordinates = (0.50, 0.32)
            }
        } else {
            switch target {
            case .venus: coordinates = (0.22, 0.35)
            case .mercury: coordinates = (0.43, 0.49)
            case .mars: coordinates = (0.66, 0.27)
            case .sun: coordinates = (0.84, 0.43)
            case .earth: coordinates = (0.50, 0.32)
            }
        }
        return CGPoint(x: size.width * coordinates.0, y: size.height * coordinates.1)
    }

    private func markerDiameter(for target: XSkyJumpState.LookTarget) -> CGFloat {
        switch target {
        case .sun: return 22
        case .earth: return 15
        case .venus: return 13
        case .mars: return 12
        case .mercury: return 9
        }
    }

    private func markerColor(for target: XSkyJumpState.LookTarget) -> Color {
        switch target {
        case .earth: return Color(red: 0.32, green: 0.74, blue: 1)
        case .venus: return Color(red: 0.96, green: 0.80, blue: 0.52)
        case .mercury: return Color(red: 0.69, green: 0.67, blue: 0.62)
        case .sun: return Color(red: 1, green: 0.88, blue: 0.42)
        case .mars: return Color(red: 0.89, green: 0.33, blue: 0.18)
        }
    }

    private func terrainDetails(in size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: size.width * 0.22, height: 14)
                .offset(x: -size.width * 0.24, y: -18)
            Ellipse()
                .fill(Color.black.opacity(0.13))
                .frame(width: size.width * 0.14, height: 10)
                .offset(x: size.width * 0.27, y: -35)
        }
        .allowsHitTesting(false)
    }

    private func deterministicFraction(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private struct XSkySurfaceTerrain: Shape {
    let isMars: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizon = rect.height * (isMars ? 0.70 : 0.74)
        path.move(to: CGPoint(x: 0, y: horizon))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.34, y: horizon - rect.height * 0.08),
            control1: CGPoint(x: rect.width * 0.12, y: horizon - rect.height * 0.01),
            control2: CGPoint(x: rect.width * 0.22, y: horizon - rect.height * 0.07)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.68, y: horizon + rect.height * 0.01),
            control1: CGPoint(x: rect.width * 0.46, y: horizon - rect.height * 0.11),
            control2: CGPoint(x: rect.width * 0.56, y: horizon + rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.width, y: horizon - rect.height * 0.045),
            control1: CGPoint(x: rect.width * 0.80, y: horizon + rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.90, y: horizon - rect.height * 0.05)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Interaction overlay (directional drag + pinch)

#if os(iOS)
/// UIKit pan that only begins for horizontal-dominant motion, so vertical pans
/// fall through to the parent SwiftUI `ScrollView`. Pinch zooms the planet.
private struct XSkyPlanetInteractionOverlay: UIViewRepresentable {
    @ObservedObject var state: XSkyJumpState

    func makeCoordinator() -> XSkyPlanetGestureCoordinator {
        XSkyPlanetGestureCoordinator(state: state)
    }

    func makeUIView(context: Context) -> XSkyPlanetGestureView {
        let view = XSkyPlanetGestureView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.isOpaque = false
        view.installGestures(coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: XSkyPlanetGestureView, context: Context) {
        context.coordinator.state = state
        uiView.ensureGestures(coordinator: context.coordinator)
    }
}

/// Gesture logic shared by the clear interaction view (file-level for access control).
final class XSkyPlanetGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var state: XSkyJumpState
    private var lastTranslation: CGPoint = .zero
    private var lastMagnification: CGFloat = 1

    init(state: XSkyJumpState) {
        self.state = state
    }

    @objc func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            lastTranslation = .zero
            state.beginOrbitDrag()
        case .changed:
            let t = pan.translation(in: pan.view)
            let dx = t.x - lastTranslation.x
            let dy = t.y - lastTranslation.y
            lastTranslation = t
            state.applyOrbitDrag(dx: Double(dx), dy: Double(dy))
        case .ended, .cancelled, .failed:
            lastTranslation = .zero
            state.endOrbitDrag()
        default:
            break
        }
    }

    @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            lastMagnification = pinch.scale
        case .changed:
            // Convert scale growth into orbit distance delta (pinch out → zoom in).
            let deltaScale = pinch.scale - lastMagnification
            lastMagnification = pinch.scale
            // Negative delta when pinching out (scale increases) → closer camera.
            state.applyZoom(delta: Double(-deltaScale) * 1.6)
        case .ended, .cancelled, .failed:
            lastMagnification = 1
        default:
            break
        }
    }

    /// Only claim the pan when the motion is clearly horizontal so vertical
    /// scrolling of the parent `ScrollView` is never stolen.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: pan.view)
        let t = pan.translation(in: pan.view)
        // Prefer velocity when available; fall back to early translation.
        let dx = abs(v.x) > 8 ? abs(v.x) : abs(t.x)
        let dy = abs(v.y) > 8 ? abs(v.y) : abs(t.y)
        return dx > dy * 1.15
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch + pan together; never block the scroll view's pan when we fail to begin.
        true
    }
}

/// Clear UIView that hosts the directional pan / pinch recognizers.
final class XSkyPlanetGestureView: UIView {
    private weak var installedCoordinator: XSkyPlanetGestureCoordinator?

    func installGestures(coordinator: XSkyPlanetGestureCoordinator) {
        installedCoordinator = coordinator
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(XSkyPlanetGestureCoordinator.handlePan(_:)))
        pan.delegate = coordinator
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(XSkyPlanetGestureCoordinator.handlePinch(_:)))
        pinch.delegate = coordinator
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
    }

    func ensureGestures(coordinator: XSkyPlanetGestureCoordinator) {
        if installedCoordinator !== coordinator || (gestureRecognizers?.isEmpty ?? true) {
            installGestures(coordinator: coordinator)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Participate in hit testing so our recognizers can evaluate;
        // vertical pans still fail `gestureRecognizerShouldBegin` and leave
        // the scroll view free to scroll.
        bounds.contains(point) ? self : nil
    }
}

#else
/// macOS: SwiftUI drag (horizontal-biased) + magnify; scroll-wheel zoom is on the SCNView monitor.
private struct XSkyPlanetInteractionOverlay: View {
    @ObservedObject var state: XSkyJumpState
    @State private var lastDrag: CGSize = .zero
    @State private var dragAxis: DragAxis = .undecided

    private enum DragAxis {
        case undecided
        case horizontal
        case vertical
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .simultaneousGesture(orbitDrag)
            .simultaneousGesture(zoomGesture)
    }

    private var orbitDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == .undecided {
                    let ax = abs(value.translation.width)
                    let ay = abs(value.translation.height)
                    guard ax > 6 || ay > 6 else { return }
                    if ax > ay * 1.2 {
                        dragAxis = .horizontal
                        lastDrag = .zero
                        state.beginOrbitDrag()
                    } else if ay >= ax * 0.95 {
                        dragAxis = .vertical
                    }
                }
                guard dragAxis == .horizontal else { return }
                let dx = value.translation.width - lastDrag.width
                let dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                state.applyOrbitDrag(dx: Double(dx), dy: Double(dy))
            }
            .onEnded { _ in
                if dragAxis == .horizontal {
                    state.endOrbitDrag()
                }
                lastDrag = .zero
                dragAxis = .undecided
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = (1.0 - Double(value.magnification)) * 0.08
                state.applyZoom(delta: delta)
            }
    }
}
#endif

// MARK: - Layout geometry keys (debug + non-overlap verification)

struct XSkyPlanetStageFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}

struct XSkyChromeFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tag a chrome panel so we can assert it does not intersect PlanetStage.
    func xSkyChromeFrame(_ id: String) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(
                    key: XSkyChromeFrameKey.self,
                    value: [id: g.frame(in: .global)]
                )
            }
        )
    }
}

/// Logs when PlanetStage intersects known chrome frames (DEBUG geometry verification).
enum XSkyLayoutVerifier {
    static func verify(planet: CGRect, chrome: [String: CGRect], inset: CGFloat = 2) {
        guard !planet.isNull, planet.width > 1, planet.height > 1 else { return }
        // Slight inset avoids false positives from shared borders.
        let core = planet.insetBy(dx: inset, dy: inset)
        for (id, frame) in chrome {
            guard frame.width > 1, frame.height > 1 else { continue }
            if core.intersects(frame) {
                #if DEBUG
                #if DEBUG
                print("[xSky LAYOUT ASSERT] PlanetStage intersects chrome '\(id)': planet=\(core.integral) chrome=\(frame.integral)")
                #endif
                #endif
            }
        }
    }
}
