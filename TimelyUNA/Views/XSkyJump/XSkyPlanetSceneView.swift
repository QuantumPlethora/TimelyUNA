import SwiftUI
import SceneKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// SceneKit vector components are Float on iOS and CGFloat on macOS.
#if os(macOS)
private typealias SCNScalar = CGFloat
#else
private typealias SCNScalar = Float
#endif

@inline(__always)
private func scnV3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
    SCNVector3(SCNScalar(x), SCNScalar(y), SCNScalar(z))
}

@inline(__always)
private func scnV3f(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 {
    SCNVector3(SCNScalar(x), SCNScalar(y), SCNScalar(z))
}

/// Shared SceneKit stage: Earth / Mars, sun light, orbit camera, jump path.
/// Orbit / zoom gestures live on the parent `XSkyPlanetStage`.
struct XSkyPlanetSceneView: View {
    @ObservedObject var state: XSkyJumpState
    /// Stage pixel size — used to keep the full disc + atmosphere inside the viewport.
    var stageSize: CGSize = CGSize(width: 400, height: 400)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Keep gentle planet spin even under Reduce Motion; starfield handles motion reduction.
        XSkySCNRepresentable(state: state, isActive: scenePhase == .active, stageSize: stageSize)
    }
}

// MARK: - Representable

#if os(iOS)
private struct XSkySCNRepresentable: UIViewRepresentable {
    @ObservedObject var state: XSkyJumpState
    var isActive: Bool
    var stageSize: CGSize

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.stageSize = stageSize
        context.coordinator.sync(from: state)
    }

    func makeCoordinator() -> XSkySceneCoordinator {
        XSkySceneCoordinator(state: state)
    }

    private func configure(_ view: SCNView, coordinator: XSkySceneCoordinator) {
        view.scene = coordinator.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        // Touches must reach SwiftUI (parent ScrollView + directional orbit / pinch).
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.isPlaying = true
        view.rendersContinuously = true
        coordinator.stageSize = stageSize
        coordinator.attach(to: view)
        coordinator.sync(from: state)
    }
}
#else
private struct XSkySCNRepresentable: NSViewRepresentable {
    @ObservedObject var state: XSkyJumpState
    var isActive: Bool
    var stageSize: CGSize

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.stageSize = stageSize
        context.coordinator.sync(from: state)
        // Orbit / zoom handled via SwiftUI gestures.
    }

    func makeCoordinator() -> XSkySceneCoordinator {
        XSkySceneCoordinator(state: state)
    }

    private func configure(_ view: SCNView, coordinator: XSkySceneCoordinator) {
        view.scene = coordinator.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        // Orbit / zoom owned by SwiftUI on PlanetStage; scroll-wheel via NSEvent monitor.
        // NSView has no isUserInteractionEnabled — hit testing is left to AppKit + SwiftUI.
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.isPlaying = true
        view.rendersContinuously = true
        coordinator.stageSize = stageSize
        coordinator.attach(to: view)
        coordinator.sync(from: state)
        // Scroll-wheel zoom on Mac
        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coordinator] event in
            guard let coordinator, event.window == view.window else { return event }
            // Prefer precise deltas when available; invert so scroll-up zooms in.
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
            if abs(dy) > 0.01 {
                Task { @MainActor in
                    coordinator.state?.applyZoom(delta: Double(-dy) * 0.012)
                }
            }
            return event
        }
        coordinator.scrollMonitor = scroll
    }
}
#endif

// MARK: - Scene coordinator

@MainActor
final class XSkySceneCoordinator: NSObject {
    let scene = SCNScene()
    private weak var scnView: SCNView?
    weak var state: XSkyJumpState?

    private let cameraNode = SCNNode()
    private let sunLight = SCNNode()
    private let ambient = SCNNode()

    private let earthRoot = SCNNode()
    private let earthBody = SCNNode()
    private let earthClouds = SCNNode()
    private let earthAtmosphere = SCNNode()
    private let earthNight = SCNNode()

    private let marsRoot = SCNNode()
    private let marsBody = SCNNode()
    private let marsAtmosphere = SCNNode()

    private let corridorNode = SCNNode()
    private var lookMarkers: [SCNNode] = []

    var isActive = true
    /// PlanetStage size in points — drives FOV-aware camera framing.
    var stageSize: CGSize = CGSize(width: 400, height: 400)
    private var displayLink: Timer?
    private var lastTick = Date()
    #if os(macOS)
    var scrollMonitor: Any?
    #endif

    // Axial tilts (degrees)
    private let earthTilt: SCNScalar = 23.4
    private let marsTilt: SCNScalar = 25.2
    private let earthRadius: SCNScalar = 1.06 // body + atmosphere rim
    private let marsRadius: SCNScalar = 0.76
    private let cameraVFOV: Double = 42

    init(state: XSkyJumpState) {
        self.state = state
        super.init()
        buildScene()
    }

    func attach(to view: SCNView) {
        scnView = view
        startTicker()
    }

    func sync(from state: XSkyJumpState) {
        self.state = state
        updateCamera(for: state, animated: false)
        updateWorldVisibility(for: state)
        updateCorridor(for: state)
        updateLookMarkers(for: state)
        scnView?.isPlaying = isActive
        scnView?.rendersContinuously = isActive
        if isActive {
            startTicker()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func startTicker() {
        guard displayLink == nil else { return }
        lastTick = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayLink = timer
    }

    private func tick() {
        guard isActive else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        // Earth sidereal day ~86164s; visual spin slowed for beauty (~120s per rev educational).
        let earthSpin = SCNScalar(dt) * (SCNScalar.pi * 2 / 120)
        let marsSpin = SCNScalar(dt) * (SCNScalar.pi * 2 / 148) // slightly slower
        earthBody.eulerAngles.y += earthSpin
        earthNight.eulerAngles.y += earthSpin
        earthClouds.eulerAngles.y += earthSpin * SCNScalar(1.08)
        marsBody.eulerAngles.y += marsSpin
        if let state {
            state.tickOrbitMomentum(dt: dt)
            updateCamera(for: state, animated: true)
            updateCorridor(for: state)
        }
    }

    // MARK: - Build

    private func buildScene() {
        scene.background.contents = nil

        // Camera
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 200
        // Vertical FOV: keep disc ≤ ~70% of stage height at default orbit distance.
        cam.fieldOfView = 42
        cam.wantsHDR = true
        cameraNode.camera = cam
        cameraNode.position = scnV3(0, 0.2, 5.8)
        scene.rootNode.addChildNode(cameraNode)

        // Sun light (directional)
        let light = SCNLight()
        light.type = .directional
        light.intensity = 900
        light.temperature = 5600
        light.castsShadow = true
        sunLight.light = light
        sunLight.eulerAngles = scnV3(-0.4, 0.9, 0)
        scene.rootNode.addChildNode(sunLight)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 120
        amb.color = platformColor(r: 0.15, g: 0.16, b: 0.25)
        ambient.light = amb
        scene.rootNode.addChildNode(ambient)

        // Earth system
        earthRoot.position = scnV3(0, 0, 0)
        earthRoot.eulerAngles = scnV3f(Float(earthTilt) * .pi / 180, 0, 0)
        scene.rootNode.addChildNode(earthRoot)

        earthBody.geometry = makeSphere(radius: 1.0, segment: 64)
        applyEarthMaterials(earthBody)
        earthRoot.addChildNode(earthBody)

        earthClouds.geometry = makeSphere(radius: 1.02, segment: 48)
        if let mat = earthClouds.geometry?.firstMaterial {
            mat.diffuse.contents = XSkyPlanetTextures.earthClouds()
            mat.transparent.contents = XSkyPlanetTextures.earthClouds()
            mat.transparencyMode = .rgbZero
            mat.writesToDepthBuffer = false
            mat.blendMode = .alpha
            mat.lightingModel = .constant
            mat.transparency = 0.55
        }
        earthRoot.addChildNode(earthClouds)

        earthAtmosphere.geometry = makeSphere(radius: 1.06, segment: 48)
        if let mat = earthAtmosphere.geometry?.firstMaterial {
            mat.diffuse.contents = platformColor(r: 0.35, g: 0.55, b: 1.0, a: 0.12)
            mat.emission.contents = platformColor(r: 0.25, g: 0.45, b: 1.0, a: 0.18)
            mat.transparency = 0.85
            mat.writesToDepthBuffer = false
            mat.blendMode = .add
            mat.lightingModel = .constant
        }
        earthRoot.addChildNode(earthAtmosphere)

        earthNight.geometry = makeSphere(radius: 1.001, segment: 48)
        if let mat = earthNight.geometry?.firstMaterial {
            mat.emission.contents = XSkyPlanetTextures.earthNightLights()
            mat.diffuse.contents = platformColor(r: 0, g: 0, b: 0, a: 0)
            mat.lightingModel = .constant
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.transparency = 0.65
        }
        earthRoot.addChildNode(earthNight)

        // Mars system (parked along +X for jump path)
        marsRoot.position = scnV3(18, 0.3, -2)
        marsRoot.eulerAngles = scnV3f(Float(marsTilt) * .pi / 180, 0, 0)
        marsRoot.isHidden = true
        scene.rootNode.addChildNode(marsRoot)

        marsBody.geometry = makeSphere(radius: 0.72, segment: 56)
        applyMarsMaterials(marsBody)
        marsRoot.addChildNode(marsBody)

        marsAtmosphere.geometry = makeSphere(radius: 0.75, segment: 40)
        if let mat = marsAtmosphere.geometry?.firstMaterial {
            mat.diffuse.contents = platformColor(r: 0.85, g: 0.45, b: 0.25, a: 0.08)
            mat.emission.contents = platformColor(r: 0.9, g: 0.4, b: 0.2, a: 0.1)
            mat.transparency = 0.9
            mat.writesToDepthBuffer = false
            mat.blendMode = .add
            mat.lightingModel = .constant
        }
        marsRoot.addChildNode(marsAtmosphere)

        // Corridor (SpaceTime tunnel visual)
        corridorNode.isHidden = true
        scene.rootNode.addChildNode(corridorNode)
        buildCorridor()
    }

    private func makeSphere(radius: CGFloat, segment: Int) -> SCNSphere {
        let s = SCNSphere(radius: radius)
        s.segmentCount = segment
        return s
    }

    private func applyEarthMaterials(_ node: SCNNode) {
        guard let mat = node.geometry?.firstMaterial else { return }
        mat.diffuse.contents = XSkyPlanetTextures.earthDiffuse()
        mat.specular.contents = platformColor(r: 0.15, g: 0.2, b: 0.3)
        mat.shininess = 0.15
        mat.lightingModel = .blinn
        mat.locksAmbientWithDiffuse = true
    }

    private func applyMarsMaterials(_ node: SCNNode) {
        guard let mat = node.geometry?.firstMaterial else { return }
        mat.diffuse.contents = XSkyPlanetTextures.marsDiffuse()
        mat.specular.contents = platformColor(r: 0.08, g: 0.05, b: 0.04)
        mat.shininess = 0.05
        mat.lightingModel = .blinn
        mat.locksAmbientWithDiffuse = true
        // Restrained relief via normal-ish darkening: use multiply ambient
        mat.ambient.contents = platformColor(r: 0.35, g: 0.2, b: 0.12)
    }

    private func buildCorridor() {
        corridorNode.childNodes.forEach { $0.removeFromParentNode() }
        // Series of rings + dashed core line from Earth to Mars parking spot
        let start = scnV3(1.4, 0, 0)
        let end = scnV3(16.5, 0.25, -1.8)
        for i in 0..<14 {
            let t = SCNScalar(i) / 13.0
            let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(0.35 + Double(t) * 0.15), pipeRadius: 0.012))
            ring.geometry?.firstMaterial?.emission.contents = platformColor(r: 0.85, g: 1.0, b: 0.35, a: 0.55)
            ring.geometry?.firstMaterial?.lightingModel = .constant
            ring.position = lerp(start, end, t)
            ring.eulerAngles = scnV3(0, 0, Double.pi / 2)
            corridorNode.addChildNode(ring)
        }
        let tube = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 15.2))
        tube.geometry?.firstMaterial?.emission.contents = platformColor(r: 0.55, g: 0.45, b: 1.0, a: 0.35)
        tube.geometry?.firstMaterial?.lightingModel = .constant
        tube.position = lerp(start, end, 0.5)
        tube.eulerAngles = scnV3(0, 0, Double.pi / 2)
        corridorNode.addChildNode(tube)
    }

    // MARK: - Camera

    private func updateCamera(for state: XSkyJumpState, animated: Bool) {
        let earthPos = scnV3(0, 0, 0)
        let marsPos = marsRoot.position

        var focus = earthPos
        var activeRadius = earthRadius
        var yaw = SCNScalar(state.orbitYaw)
        var pitch = SCNScalar(state.orbitPitch)
        // User zoom is relative; fitDistance guarantees full disc + rim in PlanetStage.
        let fitEarth = fitDistance(for: earthRadius)
        let fitMars = fitDistance(for: marsRadius)
        var dist = max(SCNScalar(state.orbitDistance), fitEarth)

        let p = SCNScalar(state.jumpProgress)
        switch state.phase {
        case .earth:
            focus = earthPos
            activeRadius = earthRadius
            dist = max(SCNScalar(state.orbitDistance), fitEarth)
            marsRoot.isHidden = true
            earthRoot.isHidden = false
            earthRoot.opacity = 1
        case .launching:
            focus = earthPos
            activeRadius = earthRadius
            dist = max(SCNScalar(state.orbitDistance), fitEarth) + p * 2.5
            earthRoot.isHidden = false
            marsRoot.isHidden = false
            marsRoot.opacity = 0.15
            earthRoot.opacity = 1
        case .corridor:
            // Pull away through corridor toward Mars
            let t = (p - 0.18) / 0.54
            let clamped = max(0, min(1, t))
            focus = lerp(earthPos, marsPos, clamped)
            activeRadius = earthRadius + (marsRadius - earthRadius) * clamped
            dist = max(fitDistance(for: activeRadius), 4.5) + clamped * 1.2
            yaw = SCNScalar(state.orbitYaw) + clamped * 0.4
            earthRoot.isHidden = false
            marsRoot.isHidden = false
            earthRoot.opacity = CGFloat(1.0 - Double(clamped) * 0.7)
            marsRoot.opacity = CGFloat(0.2 + Double(clamped) * 0.8)
        case .approachingMars:
            focus = marsPos
            activeRadius = marsRadius
            dist = max(fitMars + 1.2 - ((p - 0.72) / 0.2) * 1.0, fitMars)
            earthRoot.opacity = 0.2
            marsRoot.isHidden = false
            marsRoot.opacity = 1
        case .mars:
            focus = marsPos
            activeRadius = marsRadius
            dist = max(SCNScalar(state.orbitDistance) * SCNScalar(0.92), fitMars)
            earthRoot.isHidden = true
            marsRoot.isHidden = false
            marsRoot.opacity = 1
            earthRoot.opacity = 1
        }

        // Keep pitch gentle so poles are not pushed off-frame.
        pitch = min(max(pitch, SCNScalar(-0.2)), SCNScalar(0.22))

        let cp = cos(pitch)
        let x = focus.x + dist * cp * sin(yaw)
        let y = focus.y + dist * sin(pitch)
        let z = focus.z + dist * cp * cos(yaw)
        let targetPos = SCNVector3(x, y, z)

        if animated && state.isJumping {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.05
            cameraNode.position = targetPos
            cameraNode.look(at: focus)
            SCNTransaction.commit()
        } else {
            cameraNode.position = targetPos
            cameraNode.look(at: focus)
        }
    }

    /// Minimum camera distance so the sphere diameter is ≤ ~68% of the limiting stage axis
    /// (keeps ≥8% diameter empty margin and full atmospheric rim visible on tall/narrow stages).
    private func fitDistance(for radius: SCNScalar) -> SCNScalar {
        let w = max(Double(stageSize.width), 40)
        let h = max(Double(stageSize.height), 40)
        let aspect = w / h
        let vHalf = cameraVFOV * .pi / 360.0
        let hHalf = atan(tan(vHalf) * aspect)
        let limitingHalf = min(hHalf, vHalf)
        // Angular radius of disc ≈ half of diameter fraction of limiting FOV.
        let maxAngularRadius = limitingHalf * 0.68
        let d = Double(radius) / max(tan(maxAngularRadius), 0.001)
        // Extra 12% safety for axial tilt silhouette + soft atmosphere glow.
        return SCNScalar(max(d * 1.12, 4.0))
    }

    private func updateWorldVisibility(for state: XSkyJumpState) {
        switch state.phase {
        case .earth:
            earthRoot.isHidden = false
            marsRoot.isHidden = true
            earthRoot.opacity = 1
        case .mars:
            earthRoot.isHidden = true
            marsRoot.isHidden = false
            marsRoot.opacity = 1
        default:
            break
        }
    }

    private func updateCorridor(for state: XSkyJumpState) {
        let show = state.phase == .corridor || state.phase == .launching || state.phase == .approachingMars
        corridorNode.isHidden = !show
        if show {
            corridorNode.opacity = state.phase == .corridor ? 1.0 : 0.45
        }
    }

    private func updateLookMarkers(for state: XSkyJumpState) {
        lookMarkers.forEach { $0.removeFromParentNode() }
        lookMarkers.removeAll()
        guard state.phase == .mars || state.phase == .earth else { return }

        let offset = state.lookAngularOffsetDegrees()
        let host = state.observer == .earth ? earthRoot : marsRoot
        let radius: SCNScalar = state.observer == .earth ? 1.35 : 1.05

        // Place educational sky markers relative to host planet
        if state.showVisibleNow {
            let vis = markerNode(
                title: "VISIBLE NOW",
                color: platformColor(r: 1, g: 0.67, b: 0.2),
                position: SCNVector3(radius * 0.2, radius * 0.55, radius * 0.85)
            )
            host.addChildNode(vis)
            lookMarkers.append(vis)
        }
        if state.showActualNow {
            let az = SCNScalar(offset.displaySep) * .pi / 180
            let actX = radius * 0.2 + sin(az) * radius * 0.35
            let actY = radius * 0.55
            let actZ = radius * 0.85 - (1 - cos(az)) * radius * 0.2
            let act = markerNode(
                title: "ACTUAL NOW",
                color: platformColor(r: 0.85, g: 1.0, b: 0.26),
                position: SCNVector3(actX, actY, actZ)
            )
            host.addChildNode(act)
            lookMarkers.append(act)
            if state.showLightline, state.showVisibleNow, let first = lookMarkers.first {
                let line = lineNode(from: first.position, to: act.position, color: platformColor(r: 1, g: 0.9, b: 0.4, a: 0.8))
                host.addChildNode(line)
                lookMarkers.append(line)
            }
        }
    }

    private func markerNode(title: String, color: Any, position: SCNVector3) -> SCNNode {
        let ball = SCNNode(geometry: SCNSphere(radius: 0.06))
        ball.geometry?.firstMaterial?.emission.contents = color
        ball.geometry?.firstMaterial?.lightingModel = .constant
        ball.position = position
        let text = SCNText(string: title, extrusionDepth: 0.01)
        text.font = platformFont(size: 0.12)
        text.flatness = 0.2
        let textNode = SCNNode(geometry: text)
        textNode.scale = scnV3(0.012, 0.012, 0.012)
        textNode.position = scnV3(-0.12, -0.12, 0)
        textNode.geometry?.firstMaterial?.emission.contents = color
        textNode.geometry?.firstMaterial?.lightingModel = .constant
        ball.addChildNode(textNode)
        // Billboard constraint
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]
        return ball
    }

    private func lineNode(from: SCNVector3, to: SCNVector3, color: Any) -> SCNNode {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        let lengthScalar = sqrt(dx * dx + dy * dy + dz * dz)
        let length = CGFloat(lengthScalar)
        let cyl = SCNNode(geometry: SCNCylinder(radius: 0.008, height: length))
        cyl.geometry?.firstMaterial?.emission.contents = color
        cyl.geometry?.firstMaterial?.lightingModel = .constant
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let midZ = (from.z + to.z) / 2
        cyl.position = SCNVector3(midX, midY, midZ)
        cyl.look(at: to, up: scnV3(0, 1, 0), localFront: scnV3(0, 1, 0))
        return cyl
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: SCNScalar) -> SCNVector3 {
        let x = a.x + (b.x - a.x) * t
        let y = a.y + (b.y - a.y) * t
        let z = a.z + (b.z - a.z) * t
        return SCNVector3(x, y, z)
    }

    private func platformColor(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) -> Any {
        #if canImport(UIKit)
        return UIColor(red: r, green: g, blue: b, alpha: a)
        #else
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
        #endif
    }

    private func platformFont(size: CGFloat) -> XSkyFont {
        #if canImport(UIKit)
        return UIFont(name: "Papyrus", size: size) ?? .systemFont(ofSize: size)
        #else
        return NSFont(name: "Papyrus", size: size) ?? .systemFont(ofSize: size)
        #endif
    }

    deinit {
        displayLink?.invalidate()
        #if os(macOS)
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        #endif
    }
}

#if canImport(UIKit)
private typealias XSkyFont = UIFont
#else
private typealias XSkyFont = NSFont
#endif
