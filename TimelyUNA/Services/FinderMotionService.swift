import Foundation
import Combine
import CoreLocation

#if os(iOS)
import UIKit
import CoreMotion
#endif

/// Device heading + viewing elevation for Finder guidance.
/// Location coordinates come from `ObserverLocationService` — this service does not invent a second fix.
@MainActor
final class FinderMotionService: NSObject, ObservableObject {
    enum HeadingSource: String, Equatable {
        case trueNorth = "True heading"
        case magnetic = "Magnetic heading"
        case none = "No heading"
    }

    enum MotionAvailability: Equatable {
        case ready
        case headingOnly
        case unavailable
        case calibrating
    }

    @Published private(set) var headingDegrees: Double?
    @Published private(set) var filteredHeadingDegrees: Double?
    @Published private(set) var headingAccuracyDegrees: Double?
    @Published private(set) var headingSource: HeadingSource = .none
    /// Device viewing elevation (degrees above horizon). Positive = aimed above horizon.
    @Published private(set) var elevationDegrees: Double?
    @Published private(set) var motionAvailable = false
    @Published private(set) var headingAvailable = false
    @Published private(set) var availability: MotionAvailability = .unavailable
    @Published private(set) var statusMessage: String = "Point the top of the device toward the sky."
    @Published private(set) var needsCalibration = false

    #if os(iOS)
    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()
    private var smoothedHeading: Double?
    private var smoothedElevation: Double?
    private let headingAlpha = 0.20
    private let elevationAlpha = 0.22
    #endif

    override init() {
        super.init()
        #if os(iOS)
        locationManager.delegate = self
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
        headingAvailable = CLLocationManager.headingAvailable()
        motionAvailable = motion.isDeviceMotionAvailable
        #else
        headingAvailable = false
        motionAvailable = false
        availability = .unavailable
        statusMessage = "Live heading and elevation require iPhone or iPad. Finder still shows calculated altitude and azimuth."
        #endif
    }

    func start() {
        #if os(iOS)
        refreshHeadingStart()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 20.0
            // Attitude relative to magnetic north, Z vertical — pitch ≈ elevation when phone is upright.
            motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    self.ingestMotion(data)
                }
            }
            motionAvailable = true
        } else {
            motionAvailable = false
            elevationDegrees = nil
        }
        recomputeAvailability()
        #endif
    }

    func stop() {
        #if os(iOS)
        locationManager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        #endif
    }

    #if os(iOS)
    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .landscapeLeft: locationManager.headingOrientation = .landscapeLeft
        case .landscapeRight: locationManager.headingOrientation = .landscapeRight
        case .portraitUpsideDown: locationManager.headingOrientation = .portraitUpsideDown
        default: locationManager.headingOrientation = .portrait
        }
    }

    private func refreshHeadingStart() {
        headingAvailable = CLLocationManager.headingAvailable()
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Location permission is requested by ObserverLocationService; still try heading if allowed later.
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if headingAvailable {
                locationManager.startUpdatingHeading()
            }
        case .denied, .restricted:
            headingSource = .none
            headingDegrees = nil
            filteredHeadingDegrees = nil
            statusMessage = "Location permission is required for compass heading. Enable it in Settings."
        @unknown default:
            break
        }
        recomputeAvailability()
    }

    private func ingestHeading(_ heading: CLHeading) {
        let trueH = heading.trueHeading
        let magH = heading.magneticHeading
        let accuracy = heading.headingAccuracy

        if trueH >= 0, accuracy >= 0 {
            headingSource = .trueNorth
            headingDegrees = trueH
            headingAccuracyDegrees = accuracy
            smoothedHeading = ARCelestialMath.smoothHeading(
                previous: smoothedHeading,
                sample: trueH,
                alpha: headingAlpha
            )
            needsCalibration = accuracy > 25
        } else if magH >= 0, accuracy >= 0 {
            headingSource = .magnetic
            headingDegrees = magH
            headingAccuracyDegrees = accuracy
            smoothedHeading = ARCelestialMath.smoothHeading(
                previous: smoothedHeading,
                sample: magH,
                alpha: headingAlpha
            )
            needsCalibration = accuracy > 25
        } else {
            headingSource = .none
            headingAccuracyDegrees = nil
            needsCalibration = true
        }
        filteredHeadingDegrees = smoothedHeading
        recomputeAvailability()
    }

    private func ingestMotion(_ data: CMDeviceMotion) {
        // Pitch: radians; when holding phone in portrait (screen toward user, top toward sky),
        // attitude.pitch is roughly the elevation of the device’s forward axis after mapping.
        // Using gravity vector for a more stable “where is the top of the phone pointing” elevation:
        let g = data.gravity
        // Elevation of the device long axis: asin(-g.z) when z is out of screen in device coords…
        // With xMagneticNorthZVertical, pitch is rotation about X (right). Holding phone upright
        // pointed at horizon → pitch ≈ 0; pointed up → positive pitch.
        let pitchDeg = data.attitude.pitch * 180 / .pi
        // Clamp to sensible sky range for UI.
        let sample = max(-90, min(90, pitchDeg))
        smoothedElevation = ARCelestialMath.smoothAngle(
            previous: smoothedElevation,
            sample: sample,
            alpha: elevationAlpha
        )
        elevationDegrees = smoothedElevation
        _ = g
        recomputeAvailability()
    }

    private func recomputeAvailability() {
        if !headingAvailable && !motionAvailable {
            availability = .unavailable
            statusMessage = "Motion sensors unavailable. Showing calculated altitude and azimuth only."
            return
        }
        if headingSource == .none {
            availability = .calibrating
            statusMessage = "Acquiring compass… Hold still, then slowly pan, or wave a figure-eight to calibrate."
            return
        }
        if needsCalibration {
            availability = .calibrating
            let acc = headingAccuracyDegrees.map { "±\(Int($0))°" } ?? ""
            statusMessage = "Compass accuracy limited \(acc). Wave figure-eights slowly; avoid metal cases."
            return
        }
        if motionAvailable, elevationDegrees != nil {
            availability = .ready
            let src = headingSource.rawValue
            statusMessage = "Live \(src.lowercased()) and elevation. Point the top of the device toward the target."
        } else {
            availability = .headingOnly
            statusMessage = "Heading live. Elevation unavailable — use altitude readout and raise/lower by eye."
        }
    }
    #endif
}

#if os(iOS)
extension FinderMotionService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshHeadingStart()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.ingestHeading(newHeading)
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.headingSource == .none {
                self.statusMessage = "Heading update failed. \(error.localizedDescription)"
            }
        }
    }
}
#endif
