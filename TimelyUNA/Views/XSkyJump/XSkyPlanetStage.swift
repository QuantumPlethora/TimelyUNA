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
                // Starfield is clipped to the stage; the planet renderer is not.
                XSkyStarfieldView(
                    parallax: CGSize(
                        width: state.orbitYaw * 12,
                        height: state.orbitPitch * 10
                    ),
                    intensity: state.phase == .corridor ? 1.15 : 1.0
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
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
            .accessibilityHint("Drag horizontally to orbit. Pinch or scroll to zoom. Swipe vertically to scroll the page.")
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
                print("[xSky PlanetStage] frame=\(frame.integral)")
                #endif
            }
        }
    }

    private var accessibilityPlanetLabel: String {
        switch state.phase {
        case .mars: return "Mars, slowly rotating"
        case .earth: return "Earth, slowly rotating"
        default: return "Planet stage during xSky Jump"
        }
    }

    private func reportFrame(_ frame: CGRect) {
        onStageFrame?(frame)
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
                print("[xSky LAYOUT ASSERT] PlanetStage intersects chrome '\(id)': planet=\(core.integral) chrome=\(frame.integral)")
                #endif
            }
        }
    }
}
