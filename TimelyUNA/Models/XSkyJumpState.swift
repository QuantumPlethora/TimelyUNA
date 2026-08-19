import Foundation
import Combine
import simd

/// Simulation state for the xSky Jump experience (separate from rendering).
@MainActor
final class XSkyJumpState: ObservableObject {
    enum Phase: Equatable {
        case earth
        case launching
        case corridor
        case approachingMars
        case mars
    }

    enum ObserverWorld: String, CaseIterable, Identifiable {
        case earth = "Earth"
        case mars = "Mars"
        var id: String { rawValue }
    }

    enum LookTarget: String, CaseIterable, Identifiable {
        case earth = "Earth"
        case venus = "Venus"
        case mercury = "Mercury"
        case sun = "Sun"
        case mars = "Mars"
        var id: String { rawValue }
    }

    @Published var phase: Phase = .earth
    @Published var jumpProgress: Double = 0
    @Published var isJumping = false
    /// Chrome beside/below PlanetStage; faded during flight so planets stay unobstructed.
    @Published var showChrome = true
    @Published var observer: ObserverWorld = .earth
    @Published var lookTarget: LookTarget = .earth
    @Published var showVisibleNow = true
    @Published var showActualNow = true
    @Published var showLightline = true
    @Published var educationalMagnification = true

    /// Orbit camera (radians / distance).
    /// Distance is clamped so the disc stays fully inside PlanetStage (≤ ~76% of stage).
    @Published var orbitYaw: Double = 0.35
    @Published var orbitPitch: Double = 0.08
    @Published var orbitDistance: Double = 5.8
    @Published var userOrbitActive = false

    /// Zoom range; SceneKit also enforces a stage-aspect fit distance so the disc never crops.
    private let minOrbitDistance: Double = 5.0
    private let maxOrbitDistance: Double = 14.0
    private let defaultOrbitDistance: Double = 6.5

    /// Gentle post-drag momentum (rad/s), clamped and friction-damped.
    private var yawVelocity: Double = 0
    private var pitchVelocity: Double = 0
    private var isDraggingOrbit = false

    @Published private(set) var earthMarsDistanceAU: Double = 1.52
    @Published private(set) var oneWayLightSeconds: Double = 760
    @Published private(set) var lastUpdated: Date = Date()

    private var jumpTask: Task<Void, Never>?
    private var ephemerisTimer: Timer?

    // Mean / illustrative defaults; refined by lightweight offline ephemeris tick.
    private let auKm = 149_597_870.7
    private let cKmS = 299_792.458

    var lightDelayDescription: String {
        let m = Int(oneWayLightSeconds) / 60
        let s = Int(oneWayLightSeconds) % 60
        return "\(m)m \(String(format: "%02d", s))s"
    }

    var distanceDescription: String {
        String(format: "%.3f AU", earthMarsDistanceAU)
    }

    var departureName: String { observer == .earth ? "Earth" : "Mars" }
    var destinationName: String { observer == .earth ? "Mars" : "Earth" }

    var isOnSurface: Bool {
        phase == .earth || phase == .mars
    }

    var phaseLabel: String {
        switch phase {
        case .earth: return "Standing on Earth"
        case .launching: return "xSky Jump launching…"
        case .corridor: return "Light-time corridor"
        case .approachingMars: return "Approaching Mars"
        case .mars: return "Standing on Mars"
        }
    }

    /// Caption shown under PlanetStage (not over the planet).
    var standingCaption: String {
        switch phase {
        case .earth: return "Standing on Earth"
        case .mars: return "Standing on Mars"
        case .launching: return "Departing…"
        case .corridor: return "In the light-time corridor"
        case .approachingMars: return "Approaching destination…"
        }
    }

    func startEphemerisUpdates() {
        refreshEphemeris()
        ephemerisTimer?.invalidate()
        ephemerisTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEphemeris() }
        }
        if let ephemerisTimer {
            RunLoop.main.add(ephemerisTimer, forMode: .common)
        }
    }

    func stopEphemerisUpdates() {
        ephemerisTimer?.invalidate()
        ephemerisTimer = nil
    }

    func refreshEphemeris() {
        let now = Date()
        lastUpdated = now
        // Lightweight educational Earth–Mars separation (low-precision circular model).
        let day = now.timeIntervalSince1970 / 86_400.0
        // Relative orbital angle (illustrative).
        let theta = day * 0.009 + 1.2
        // Distances in AU from Sun (approx).
        let rE = 1.0
        let rM = 1.524
        let d = sqrt(rE * rE + rM * rM - 2 * rE * rM * cos(theta))
        earthMarsDistanceAU = max(0.37, min(2.7, d))
        oneWayLightSeconds = earthMarsDistanceAU * auKm / cKmS
    }

    /// Angular educational offset for Visible/Actual (degrees), may be magnified.
    func lookAngularOffsetDegrees() -> (trueSep: Double, displaySep: Double, magnified: Bool, factor: Double) {
        // Educational light-time angular teaching offset by target.
        let base: Double
        switch lookTarget {
        case .sun: base = 0.15
        case .mercury: base = 0.35
        case .venus: base = 0.55
        case .earth: base = observer == .mars ? 0.4 : 0.0
        case .mars: base = observer == .earth ? 0.45 : 0.0
        }
        let trueSep = base
        if educationalMagnification && trueSep > 0 && trueSep < 2.5 {
            let factor = min(18.0, 4.0 / max(trueSep, 0.05))
            return (trueSep, min(10, trueSep * factor), true, factor)
        }
        return (trueSep, trueSep, false, 1)
    }

    func performJump(reduceMotion: Bool) {
        guard !isJumping else { return }
        jumpTask?.cancel()
        isJumping = true
        jumpProgress = 0

        let goingToMars = observer == .earth

        jumpTask = Task { [weak self] in
            guard let self else { return }

            // 1) Fade controls before camera movement so Earth stays unobstructed.
            await MainActor.run { self.showChrome = false }
            let fadeNs: UInt64 = reduceMotion ? 40_000_000 : 280_000_000
            try? await Task.sleep(nanoseconds: fadeNs)
            guard !Task.isCancelled else { return }

            await MainActor.run { self.phase = .launching }

            let total: Double = reduceMotion ? 0.45 : 4.2
            let start = Date()
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / total)
                await MainActor.run {
                    self.jumpProgress = t
                    if t < 0.18 {
                        self.phase = .launching
                    } else if t < 0.72 {
                        self.phase = .corridor
                    } else if t < 0.92 {
                        self.phase = .approachingMars
                    } else {
                        self.phase = goingToMars ? .mars : .earth
                    }
                }
                if t >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard !Task.isCancelled else { return }

            // 2) Arrive with destination unobstructed, then restore controls.
            await MainActor.run {
                self.observer = goingToMars ? .mars : .earth
                self.lookTarget = goingToMars ? .earth : .mars
                self.phase = goingToMars ? .mars : .earth
                self.jumpProgress = 0
                self.resetOrbitPreservingWorld()
            }
            let settleNs: UInt64 = reduceMotion ? 40_000_000 : 320_000_000
            try? await Task.sleep(nanoseconds: settleNs)
            await MainActor.run {
                self.isJumping = false
                self.showChrome = true
            }
        }
    }

    func returnToEarth(reduceMotion: Bool) {
        guard observer == .mars, !isJumping else { return }
        // Jump home reuses corridor reverse.
        observer = .mars
        performJump(reduceMotion: reduceMotion)
    }

    func resetView() {
        resetOrbitPreservingWorld()
    }

    private func resetOrbitPreservingWorld() {
        orbitYaw = observer == .earth ? 0.28 : -0.45
        orbitPitch = 0.06
        orbitDistance = defaultOrbitDistance
        userOrbitActive = false
        yawVelocity = 0
        pitchVelocity = 0
        isDraggingOrbit = false
    }

    func beginOrbitDrag() {
        isDraggingOrbit = true
        yawVelocity = 0
        pitchVelocity = 0
    }

    func applyOrbitDrag(dx: Double, dy: Double) {
        userOrbitActive = true
        isDraggingOrbit = true
        let yawStep = dx * 0.008
        let pitchStep = dy * 0.008
        orbitYaw += yawStep
        orbitPitch = min(1.2, max(-1.2, orbitPitch + pitchStep))
        // Track last motion for post-release coast (sensible limits).
        yawVelocity = min(1.8, max(-1.8, yawStep * 28))
        pitchVelocity = min(1.0, max(-1.0, pitchStep * 28))
    }

    func endOrbitDrag() {
        isDraggingOrbit = false
    }

    func applyZoom(delta: Double) {
        userOrbitActive = true
        // Keep full disc + atmospheric rim inside PlanetStage (no pole/side crop).
        orbitDistance = min(maxOrbitDistance, max(minOrbitDistance, orbitDistance + delta))
    }

    /// Called from the scene ticker for post-drag coasting.
    func tickOrbitMomentum(dt: TimeInterval) {
        guard !isDraggingOrbit else { return }
        guard abs(yawVelocity) > 0.0005 || abs(pitchVelocity) > 0.0005 else { return }
        orbitYaw += yawVelocity * dt
        orbitPitch = min(1.2, max(-1.2, orbitPitch + pitchVelocity * dt))
        let friction = pow(0.08, dt) // ~strong decay, gentle coast
        yawVelocity *= friction
        pitchVelocity *= friction
        if abs(yawVelocity) < 0.0005 { yawVelocity = 0 }
        if abs(pitchVelocity) < 0.0005 { pitchVelocity = 0 }
    }

    deinit {
        jumpTask?.cancel()
        ephemerisTimer?.invalidate()
    }
}
