import SwiftUI

#if os(iOS)
import UIKit
import RealityKit
import ARKit
import AVFoundation

/// Full-screen TimelyUNA AR experience (physical devices with world tracking).
///
/// On Simulator and devices without ARKit world tracking, presents a non-camera
/// 2D sky mode with the same Visible Now / Actual Now educational overlay.
/// AR sessions are never started when world tracking is unsupported.
struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showActualPosition = true
    @State private var showLightline = true
    /// User chose the non-camera educational sky (or device has no world tracking).
    @State private var useTwoDSky = false
    @State private var cameraDenied = false
    @State private var rocketProgress: Double = 0
    @State private var isRocketFlying = false
    @State private var showRocketHit = false

    private var worldTrackingSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if worldTrackingSupported && !useTwoDSky && !cameraDenied {
                    ARSunriseContainer(
                        selectedDate: selectedDate,
                        showActualPosition: showActualPosition,
                        showLightline: showLightline,
                        onCameraUnauthorized: {
                            cameraDenied = true
                        }
                    )
                    .ignoresSafeArea()
                } else if useTwoDSky || !worldTrackingSupported || cameraDenied {
                    EducationalTwoDSkyView(
                        selectedDate: selectedDate,
                        showActualPosition: showActualPosition,
                        showLightline: showLightline,
                        rocketProgress: rocketProgress,
                        showRocket: isRocketFlying || rocketProgress > 0,
                        showHit: showRocketHit,
                        onTapLaunch: { launchTwoDRocket() }
                    )
                    .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            // Intro gate when AR is unavailable until user continues.
            if !worldTrackingSupported && !useTwoDSky {
                ARUnavailableGate(
                    reason: .worldTrackingUnsupported,
                    onContinue: { useTwoDSky = true },
                    onClose: { dismiss() }
                )
            } else if cameraDenied && !useTwoDSky {
                ARUnavailableGate(
                    reason: .cameraDenied,
                    onContinue: { useTwoDSky = true },
                    onClose: { dismiss() }
                )
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding()
            }
            .accessibilityLabel("Close True Horizon AR")
        }
        .safeAreaInset(edge: .bottom) {
            if useTwoDSky || (worldTrackingSupported && !cameraDenied) {
                bottomControls
            }
        }
        .onAppear {
            // Never auto-start AR on unsupported devices; gate stays until Continue.
            if worldTrackingSupported {
                checkCameraAuthorization()
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            Text("We do not see the universe as it is. We see it as its light arrives.")
                .font(TimelyUNATheme.headlineFont)
                .multilineTextAlignment(.center)

            if !worldTrackingSupported || useTwoDSky {
                Text(useTwoDSky && !worldTrackingSupported
                     ? "2D sky mode · Visible Now / Actual Now (no camera)"
                     : "Educational overlay")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.acid)
            }

            HStack(spacing: 12) {
                Toggle("Actual Position", isOn: $showActualPosition)
                Toggle("Lightline", isOn: $showLightline)
            }
            .font(TimelyUNATheme.calloutFont)
            .toggleStyle(.button)

            Text(
                worldTrackingSupported && !useTwoDSky
                ? "Point toward the horizon. Tap the scene to launch Baby X toward Actual Position."
                : "Tap the sky to launch Baby X toward Actual Now along the Lightline."
            )
            .font(TimelyUNATheme.footnoteFontCompatible)
            .multilineTextAlignment(.center)

            Text("Educational overlay • \(selectedDate.formatted(date: .abbreviated, time: .shortened))")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.goldDeep)
        }
        .foregroundStyle(TimelyUNATheme.papyrus)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraDenied = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraDenied = !granted
                }
            }
        case .denied, .restricted:
            cameraDenied = true
        @unknown default:
            cameraDenied = true
        }
    }

    private func launchTwoDRocket() {
        guard !isRocketFlying else { return }
        isRocketFlying = true
        showRocketHit = false
        rocketProgress = 0
        let duration: Double = reduceMotion ? 0.15 : 1.45
        let start = Date()
        Task { @MainActor in
            while true {
                let p = min(Date().timeIntervalSince(start) / duration, 1.0)
                rocketProgress = p
                if p >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            showRocketHit = true
            isRocketFlying = false
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            showRocketHit = false
            rocketProgress = 0
        }
    }
}

// MARK: - Unavailable / denial gate

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
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: reason == .cameraDenied ? "camera.fill" : "arkit")
                    .font(.system(size: 44))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .accessibilityHidden(true)

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
                        .background(TimelyUNATheme.acid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a non-camera 2D sky with Visible Now and Actual Now")

                if reason == .cameraDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(TimelyUNATheme.calloutFont)
                            .foregroundStyle(TimelyUNATheme.gold)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }

                Button("Close", action: onClose)
                    .font(TimelyUNATheme.calloutFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(TimelyUNATheme.line, lineWidth: 1)
                    )
            )
            .padding(20)
        }
        .accessibilityElement(children: .contain)
    }

    private var explanation: String {
        switch reason {
        case .worldTrackingUnsupported:
            return "World-tracking AR needs a compatible physical iPhone or iPad. The iOS Simulator cannot run an AR camera session. Continue in 2D sky mode to see Visible Now, Actual Now, and the Lightline without a camera."
        case .cameraDenied:
            return "Camera permission is off, so AR cannot start. You can enable the camera in Settings, or continue in 2D sky mode to explore Visible Now and Actual Now without AR."
        }
    }
}

// MARK: - Non-camera 2D sky (Visible Now / Actual Now)

private struct EducationalTwoDSkyView: View {
    let selectedDate: Date
    let showActualPosition: Bool
    let showLightline: Bool
    let rocketProgress: Double
    let showRocket: Bool
    let showHit: Bool
    let onTapLaunch: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion && !showRocket)) { timeline in
            Canvas { context, size in
                drawSky(context: context, size: size, time: timeline.date)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.12),
                    .black,
                    Color(red: 0.08, green: 0.04, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapLaunch)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                dashPhase = 48
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("2D educational sky. Visible Now and Actual Now. Double-tap to launch the rocket toward Actual Now.")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("2D SKY MODE")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.6)
                    .foregroundStyle(TimelyUNATheme.acid)
                Text("Visible Now · Actual Now")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
            }
            .padding(16)
        }
    }

    private func drawSky(context: GraphicsContext, size: CGSize, time: Date) {
        let w = size.width
        let h = size.height

        for i in 0..<90 {
            let x = frac(i * 19 + 3) * w
            let y = frac(i * 41 + 7) * h * 0.75
            let d = 0.6 + frac(i * 13) * 1.6
            var star = context
            star.opacity = 0.2 + frac(i * 29) * 0.5
            star.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white))
        }

        // Horizon ground
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h * 0.78))
        ground.addQuadCurve(to: CGPoint(x: w, y: h * 0.76), control: CGPoint(x: w * 0.5, y: h * 0.72))
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.addLine(to: CGPoint(x: 0, y: h))
        ground.closeSubpath()
        context.fill(
            ground,
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.14, green: 0.12, blue: 0.08).opacity(0.9), .black]),
                startPoint: CGPoint(x: 0, y: h * 0.78),
                endPoint: CGPoint(x: 0, y: h)
            )
        )

        let you = CGPoint(x: w * 0.22, y: h * 0.82)
        let apparent = CGPoint(x: w * 0.42, y: h * 0.48)
        let actual = CGPoint(x: w * 0.78, y: h * 0.32)

        // YOU
        context.fill(
            Path(ellipseIn: CGRect(x: you.x - 10, y: you.y - 10, width: 20, height: 20)),
            with: .color(TimelyUNATheme.cosmicPurple)
        )
        label(context, "YOU", at: CGPoint(x: you.x, y: you.y + 22), color: TimelyUNATheme.blue, size: 11)

        // Visible Now (Apparent)
        drawSun(context: context, center: apparent, radius: min(w, h) * 0.07, color: TimelyUNATheme.apparentSun, opacity: 0.85)
        label(context, "VISIBLE NOW", at: CGPoint(x: apparent.x, y: apparent.y + min(w, h) * 0.1), color: TimelyUNATheme.papyrus, size: 12)
        label(context, "APPARENT", at: CGPoint(x: apparent.x, y: apparent.y + min(w, h) * 0.1 + 14), color: TimelyUNATheme.muted, size: 10)

        if showActualPosition {
            drawSun(context: context, center: actual, radius: min(w, h) * 0.09, color: TimelyUNATheme.acid, opacity: 1)
            label(context, "ACTUAL NOW", at: CGPoint(x: actual.x, y: actual.y + min(w, h) * 0.12), color: TimelyUNATheme.acid, size: 12)
            label(context, "TRUE POSITION", at: CGPoint(x: actual.x, y: actual.y + min(w, h) * 0.12 + 14), color: TimelyUNATheme.acid.opacity(0.85), size: 10)
        }

        if showLightline && showActualPosition {
            var path = Path()
            path.move(to: apparent)
            path.addLine(to: actual)
            context.stroke(
                path,
                with: .color(TimelyUNATheme.gold),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6], dashPhase: reduceMotion ? 0 : dashPhase)
            )
            label(context, "LIGHTLINE", at: CGPoint(x: (apparent.x + actual.x) / 2, y: (apparent.y + actual.y) / 2 - 14), color: TimelyUNATheme.gold, size: 10)
        }

        // Soft path from you to apparent
        var arrive = Path()
        arrive.move(to: you)
        arrive.addLine(to: apparent)
        context.stroke(
            arrive,
            with: .color(TimelyUNATheme.gold.opacity(0.45)),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 5], dashPhase: reduceMotion ? 0 : dashPhase)
        )

        if showRocket && rocketProgress > 0.01 && showActualPosition {
            let t = min(1, max(0.02, rocketProgress))
            let rx = you.x + (actual.x - you.x) * t
            let ry = you.y + (actual.y - you.y) * t
            var body = Path()
            body.addRoundedRect(in: CGRect(x: rx - 6, y: ry - 14, width: 12, height: 28), cornerSize: CGSize(width: 5, height: 5))
            context.fill(body, with: .color(Color(white: 0.9)))
            context.fill(Path(ellipseIn: CGRect(x: rx - 3, y: ry - 4, width: 6, height: 6)), with: .color(TimelyUNATheme.blue))
            if t < 0.95 {
                let flicker = 1.0 + 0.2 * sin(time.timeIntervalSinceReferenceDate * 28)
                var flame = Path()
                flame.move(to: CGPoint(x: rx - 4, y: ry + 14))
                flame.addLine(to: CGPoint(x: rx, y: ry + 14 + 12 * flicker))
                flame.addLine(to: CGPoint(x: rx + 4, y: ry + 14))
                flame.closeSubpath()
                context.fill(flame, with: .color(TimelyUNATheme.acid))
            }
        }

        if showHit {
            label(context, "DIRECT HIT · ACTUAL NOW", at: CGPoint(x: w * 0.5, y: h * 0.16), color: TimelyUNATheme.acid, size: 15)
        }

        label(context, selectedDate.formatted(date: .abbreviated, time: .shortened), at: CGPoint(x: w * 0.5, y: h * 0.08), color: TimelyUNATheme.muted, size: 11)
    }

    private func drawSun(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        var ctx = context
        ctx.opacity = opacity
        let glow = radius * 1.9
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(Gradient(colors: [color.opacity(0.55), .clear]), center: center, startRadius: 0, endRadius: glow)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(color)
        )
    }

    private func label(_ context: GraphicsContext, _ text: String, at point: CGPoint, color: Color, size: CGFloat) {
        let font = Font.system(size: size, weight: .semibold, design: .serif)
        let resolved = context.resolve(Text(text).font(font).foregroundColor(color))
        let width = resolved.measure(in: CGSize(width: 600, height: 40)).width
        context.draw(resolved, at: CGPoint(x: point.x - width / 2, y: point.y), anchor: .leading)
    }

    private func frac(_ seed: Int) -> CGFloat {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

// MARK: - AR container (only constructed when world tracking is supported)

struct ARSunriseContainer: UIViewRepresentable {
    let selectedDate: Date
    let showActualPosition: Bool
    let showLightline: Bool
    var onCameraUnauthorized: (() -> Void)?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        // Hard gate: never run a session without world tracking support.
        guard ARWorldTrackingConfiguration.isSupported else {
            onCameraUnauthorized?()
            return arView
        }

        // Camera must be authorized before starting AR.
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraStatus == .authorized else {
            if cameraStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            context.coordinator.startSession(on: arView)
                            context.coordinator.installTap(on: arView)
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

        context.coordinator.selectedDate = selectedDate
        context.coordinator.startSession(on: arView)
        context.coordinator.installTap(on: arView)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.selectedDate = selectedDate
        context.coordinator.setActualPositionVisible(showActualPosition)
        context.coordinator.setLightlineVisible(showLightline)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCameraUnauthorized: onCameraUnauthorized)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedDate = Date()
        private let onCameraUnauthorized: (() -> Void)?

        private weak var arView: ARView?
        private var rootAnchor: AnchorEntity?
        private var apparentSun: ModelEntity?
        private var actualSun: ModelEntity?
        private var lightline: ModelEntity?
        private var rocket: ModelEntity?
        private var actualLabel: ModelEntity?
        private var lightlineLabel: ModelEntity?
        private var hasLaunched = false
        private var sessionStarted = false

        init(onCameraUnauthorized: (() -> Void)?) {
            self.onCameraUnauthorized = onCameraUnauthorized
        }

        func startSession(on arView: ARView) {
            // Never start ARKit when world tracking is unsupported (Simulator, older devices).
            guard ARWorldTrackingConfiguration.isSupported, !sessionStarted else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                onCameraUnauthorized?()
                return
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravityAndHeading
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            arView.session.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
            sessionStarted = true
            self.arView = arView

            if rootAnchor == nil {
                setupScene(in: arView)
            }
        }

        func installTap(on arView: ARView) {
            let existing = arView.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } ?? false
            guard !existing else { return }
            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(launchRocket(_:))
            )
            arView.addGestureRecognizer(tap)
        }

        func setupScene(in arView: ARView) {
            self.arView = arView

            // Camera-relative educational placement approximately 2.5 m ahead.
            // The horizontal separation exaggerates the offset for learning.
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0.15, -2.5))
            rootAnchor = anchor

            let apparentPosition = SIMD3<Float>(-0.38, 0.38, 0)
            let actualPosition = SIMD3<Float>(0.42, 0.48, -0.08)

            let apparent = makeSun(
                radius: 0.20,
                color: UIColor(red: 0.98, green: 0.72, blue: 0.16, alpha: 0.78)
            )
            apparent.position = apparentPosition
            apparent.name = "ApparentNow"
            apparentSun = apparent
            anchor.addChild(apparent)

            let actual = makeSun(
                radius: 0.22,
                color: UIColor(red: 1.0, green: 0.91, blue: 0.35, alpha: 1.0)
            )
            actual.position = actualPosition
            actual.name = "ActualPosition"
            actualSun = actual
            anchor.addChild(actual)

            let apparentText = makeLabel("VISIBLE NOW", color: .white)
            apparentText.position = apparentPosition + SIMD3<Float>(-0.18, -0.34, 0)
            anchor.addChild(apparentText)

            let actualText = makeLabel("ACTUAL NOW", color: UIColor(red: 1, green: 0.87, blue: 0.35, alpha: 1))
            actualText.position = actualPosition + SIMD3<Float>(-0.20, -0.36, 0)
            actualLabel = actualText
            anchor.addChild(actualText)

            let line = makeLine(
                from: apparentPosition,
                to: actualPosition,
                color: UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 0.88)
            )
            lightline = line
            anchor.addChild(line)

            let middle = (apparentPosition + actualPosition) / 2
            let lineText = makeLabel("LIGHTLINE", color: UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1))
            lineText.position = middle + SIMD3<Float>(-0.10, 0.12, 0)
            lightlineLabel = lineText
            anchor.addChild(lineText)

            let rocketEntity = makeRocket()
            rocketEntity.position = SIMD3<Float>(-0.05, -0.55, 0.12)
            rocketEntity.look(
                at: actualPosition,
                from: rocketEntity.position,
                relativeTo: anchor
            )
            rocket = rocketEntity
            anchor.addChild(rocketEntity)

            arView.scene.addAnchor(anchor)
            hasLaunched = false
        }

        func setActualPositionVisible(_ visible: Bool) {
            actualSun?.isEnabled = visible
            actualLabel?.isEnabled = visible
        }

        func setLightlineVisible(_ visible: Bool) {
            lightline?.isEnabled = visible
            lightlineLabel?.isEnabled = visible
        }

        @objc func launchRocket(_ recognizer: UITapGestureRecognizer) {
            guard
                let rocket,
                let actualSun,
                let anchor = rootAnchor,
                !hasLaunched
            else { return }

            hasLaunched = true
            let target = actualSun.position(relativeTo: anchor) + SIMD3<Float>(0, 0.10, -0.06)
            var transform = rocket.transform
            transform.translation = target

            rocket.move(
                to: transform,
                relativeTo: anchor,
                duration: 3.2,
                timingFunction: .easeInOut
            )

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
                guard let self, let actualSun = self.actualSun else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                var pulse = actualSun.transform
                pulse.scale = SIMD3<Float>(repeating: 1.20)
                actualSun.move(to: pulse, relativeTo: actualSun.parent, duration: 0.28)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    var normal = actualSun.transform
                    normal.scale = SIMD3<Float>(repeating: 1.0)
                    actualSun.move(to: normal, relativeTo: actualSun.parent, duration: 0.28)
                }
            }
        }

        private func makeSun(radius: Float, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateSphere(radius: radius)
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: Float(color.cgColor.alpha)))
            let sun = ModelEntity(mesh: mesh, materials: [material])

            let glow = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.35),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.18))]
            )
            sun.addChild(glow)
            return sun
        }

        private func makeRocket() -> ModelEntity {
            let body = ModelEntity(
                mesh: .generateBox(size: [0.07, 0.22, 0.07], cornerRadius: 0.018),
                materials: [SimpleMaterial(color: .systemOrange, isMetallic: true)]
            )

            let nose = ModelEntity(
                mesh: .generateSphere(radius: 0.032),
                materials: [SimpleMaterial(color: .white, isMetallic: true)]
            )
            nose.position = [0, 0.13, 0]
            body.addChild(nose)
            return body
        }

        private func makeLabel(_ text: String, color: UIColor) -> ModelEntity {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.002,
                font: UIFont(name: "Papyrus", size: 0.12) ?? .systemFont(ofSize: 0.12),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byWordWrapping
            )
            let entity = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: color)]
            )
            entity.scale = SIMD3<Float>(repeating: 0.55)
            return entity
        }

        private func makeLine(
            from start: SIMD3<Float>,
            to end: SIMD3<Float>,
            color: UIColor
        ) -> ModelEntity {
            let vector = end - start
            let length = simd_length(vector)
            let midpoint = (start + end) / 2

            let mesh: MeshResource
            if #available(iOS 18.0, *) {
                mesh = .generateCylinder(height: length, radius: 0.012)
            } else {
                mesh = .generateBox(size: [0.024, length, 0.024], cornerRadius: 0.008)
            }
            let entity = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: color)]
            )
            entity.position = midpoint
            entity.orientation = simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: simd_normalize(vector)
            )
            return entity
        }
    }
}

private extension TimelyUNATheme {
    /// Footnote-scale Papyrus used in AR chrome.
    static let footnoteFontCompatible = Font.custom("Papyrus", size: 13, relativeTo: .footnote)
}

#Preview {
    ARSunRocketView(selectedDate: Date())
}

#else

// MARK: - macOS / non-iOS: always 2D educational sky (no ARKit session)

struct ARSunRocketView: View {
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var showActual = true
    @State private var showLightline = true
    @State private var rocketProgress: Double = 0
    @State private var flying = false
    @State private var hit = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Reuse the same 2D educational language without ARKit.
            ARUnavailableMacSky(
                selectedDate: selectedDate,
                showActual: showActual,
                showLightline: showLightline,
                rocketProgress: rocketProgress,
                showRocket: flying || rocketProgress > 0,
                showHit: hit,
                onLaunch: launch
            )

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding()
            }
            .accessibilityLabel("Close")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text("AR on iPhone & iPad")
                    .font(TimelyUNATheme.headlineFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                Text("World-tracking AR requires a compatible physical iPhone or iPad. This Mac view uses the same Visible Now / Actual Now educational sky without a camera.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.muted)
                    .multilineTextAlignment(.center)
                HStack {
                    Toggle("Actual Now", isOn: $showActual)
                    Toggle("Lightline", isOn: $showLightline)
                }
                .toggleStyle(.button)
                .font(TimelyUNATheme.calloutFont)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private func launch() {
        guard !flying else { return }
        flying = true
        hit = false
        rocketProgress = 0
        Task { @MainActor in
            let start = Date()
            while Date().timeIntervalSince(start) < 1.4 {
                rocketProgress = min(1, Date().timeIntervalSince(start) / 1.4)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            rocketProgress = 1
            hit = true
            flying = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            hit = false
            rocketProgress = 0
        }
    }
}

/// macOS-only minimal 2D sky (duplicates educational layout without iOS types).
private struct ARUnavailableMacSky: View {
    let selectedDate: Date
    let showActual: Bool
    let showLightline: Bool
    let rocketProgress: Double
    let showRocket: Bool
    let showHit: Bool
    let onLaunch: () -> Void

    var body: some View {
        ZStack {
            TimelyUNATheme.background.ignoresSafeArea()
            // Lightweight shared canvas via GeometryReader
            GeometryReader { geo in
                Canvas { context, size in
                    let apparent = CGPoint(x: size.width * 0.35, y: size.height * 0.45)
                    let actual = CGPoint(x: size.width * 0.72, y: size.height * 0.32)
                    let you = CGPoint(x: size.width * 0.2, y: size.height * 0.78)
                    for i in 0..<60 {
                        let x = CGFloat((i * 47) % 1000) / 1000 * size.width
                        let y = CGFloat((i * 91) % 1000) / 1000 * size.height * 0.7
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.4)))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: apparent.x - 28, y: apparent.y - 28, width: 56, height: 56)), with: .color(TimelyUNATheme.apparentSun))
                    if showActual {
                        context.fill(Path(ellipseIn: CGRect(x: actual.x - 36, y: actual.y - 36, width: 72, height: 72)), with: .color(TimelyUNATheme.acid))
                    }
                    if showLightline && showActual {
                        var p = Path(); p.move(to: apparent); p.addLine(to: actual)
                        context.stroke(p, with: .color(TimelyUNATheme.gold), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: you.x - 8, y: you.y - 8, width: 16, height: 16)), with: .color(TimelyUNATheme.cosmicPurple))
                    if showRocket && rocketProgress > 0 {
                        let t = rocketProgress
                        let x = you.x + (actual.x - you.x) * t
                        let y = you.y + (actual.y - you.y) * t
                        context.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 10, width: 12, height: 20)), with: .color(.white))
                    }
                }
                .onTapGesture(perform: onLaunch)
            }
            VStack {
                Text("2D SKY MODE · VISIBLE NOW / ACTUAL NOW")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.acid)
                    .padding()
                Spacer()
            }
        }
    }
}

#endif
