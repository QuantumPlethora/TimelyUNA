import Foundation
import Combine
import CoreLocation

#if os(iOS)
import UIKit
import CoreMotion
import ARKit

/// Live calibration for physical-device AR: location, heading, and tracking quality.
/// Never reports "calibrated" when heading accuracy or AR tracking is inadequate.
/// Latitude/longitude are held for solar placement only — never surface them in AR UI, labels, or logs.
@MainActor
final class ARCalibrationService: NSObject, ObservableObject {
    enum Quality: String, Equatable {
        case acquiring
        case limited
        case calibrated
        case unavailable
    }

    enum HeadingSource: String, Equatable {
        case trueNorth = "True heading"
        case magnetic = "Magnetic heading"
        case none = "No heading"
    }

    @Published private(set) var quality: Quality = .acquiring
    @Published private(set) var statusMessage: String = "Stand still and slowly point toward the horizon."
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var headingAccuracyDegrees: Double?
    @Published private(set) var headingSource: HeadingSource = .none
    @Published private(set) var hasLiveLocation: Bool = false
    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var trackingStateLabel: String = "AR tracking: acquiring"
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var filteredHeadingDegrees: Double?

    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()
    private var smoothedHeading: Double?
    private var trackingLimited = true
    private var worldTrackingOK = false
    private let goodHeadingAccuracy: Double = 25
    private let headingAlpha: Double = 0.18

    static var worldTrackingSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.headingFilter = 1
        locationManager.headingOrientation = .portrait
    }

    func start() {
        refreshAuthorizationAndStart()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30.0
            motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
        }
        recomputeQuality()
    }

    func stop() {
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
        motion.stopDeviceMotionUpdates()
        isSessionRunning = false
    }

    func reset() {
        smoothedHeading = nil
        filteredHeadingDegrees = nil
        headingDegrees = nil
        headingAccuracyDegrees = nil
        trackingLimited = true
        worldTrackingOK = false
        quality = .acquiring
        statusMessage = "Stand still and slowly point toward the horizon."
        trackingStateLabel = "AR tracking: acquiring"
        recomputeQuality()
    }

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .landscapeLeft: locationManager.headingOrientation = .landscapeLeft
        case .landscapeRight: locationManager.headingOrientation = .landscapeRight
        case .portraitUpsideDown: locationManager.headingOrientation = .portraitUpsideDown
        default: locationManager.headingOrientation = .portrait
        }
    }

    func updateARTracking(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            trackingLimited = false
            worldTrackingOK = true
            trackingStateLabel = "AR tracking: normal"
        case .limited(let reason):
            trackingLimited = true
            worldTrackingOK = true
            trackingStateLabel = "AR tracking: limited (\(String(describing: reason)))"
        case .notAvailable:
            trackingLimited = true
            worldTrackingOK = false
            trackingStateLabel = "AR tracking: unavailable"
        @unknown default:
            trackingLimited = true
            trackingStateLabel = "AR tracking: unknown"
        }
        recomputeQuality()
    }

    func markSessionRunning(_ running: Bool) {
        isSessionRunning = running
        recomputeQuality()
    }

    func applyExternalLocation(latitude: Double?, longitude: Double?, isLive: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        hasLiveLocation = isLive && latitude != nil && longitude != nil
        recomputeQuality()
    }

    private func refreshAuthorizationAndStart() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        case .denied, .restricted:
            quality = .unavailable
            statusMessage = "Location is required for celestial AR. Enable Location in Settings, or use 2D mode."
        @unknown default:
            break
        }
    }

    private func ingestHeading(_ heading: CLHeading) {
        let trueH = heading.trueHeading
        let magH = heading.magneticHeading
        let accuracy = heading.headingAccuracy

        if trueH >= 0, accuracy >= 0 {
            headingSource = .trueNorth
            headingDegrees = trueH
            headingAccuracyDegrees = accuracy
            smoothedHeading = ARCelestialMath.smoothHeading(previous: smoothedHeading, sample: trueH, alpha: headingAlpha)
        } else if magH >= 0, accuracy >= 0 {
            headingSource = .magnetic
            headingDegrees = magH
            headingAccuracyDegrees = accuracy
            smoothedHeading = ARCelestialMath.smoothHeading(previous: smoothedHeading, sample: magH, alpha: headingAlpha)
        } else {
            headingSource = .none
            headingAccuracyDegrees = nil
        }
        filteredHeadingDegrees = smoothedHeading
        recomputeQuality()
    }

    private func recomputeQuality() {
        if !ARWorldTrackingConfiguration.isSupported {
            quality = .unavailable
            statusMessage = "World-tracking AR is unavailable on this device. Use 2D mode."
            return
        }

        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            quality = .unavailable
            statusMessage = "Location permission is required for calibrated sky placement."
            return
        default:
            break
        }

        if !hasLiveLocation {
            quality = .acquiring
            statusMessage = "Acquiring live location… Stand still outdoors if possible."
            return
        }

        guard let accuracy = headingAccuracyDegrees, accuracy >= 0 else {
            quality = .acquiring
            statusMessage = "Acquiring compass heading… Hold still, then slowly pan toward the horizon."
            return
        }

        if !worldTrackingOK || !isSessionRunning {
            quality = .acquiring
            statusMessage = "Starting AR session… Move the device gently to help tracking."
            return
        }

        if trackingLimited || accuracy > goodHeadingAccuracy {
            quality = .limited
            statusMessage = accuracy > goodHeadingAccuracy
                ? "Heading accuracy limited (±\(Int(accuracy))°). Wave figure-eights slowly; avoid metal."
                : "AR tracking limited. Point toward the horizon and move slowly."
            return
        }

        quality = .calibrated
        let source = headingSource == .trueNorth ? "true" : "magnetic"
        statusMessage = "Calibrated · \(source) heading ±\(Int(accuracy))°. Slowly aim toward the horizon."
    }
}

extension ARCalibrationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshAuthorizationAndStart()
            self.recomputeQuality()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.latitude = loc.coordinate.latitude
            self.longitude = loc.coordinate.longitude
            self.hasLiveLocation = true
            self.recomputeQuality()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.ingestHeading(newHeading)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if !self.hasLiveLocation {
                self.statusMessage = "Location update failed. \(error.localizedDescription)"
            }
            self.recomputeQuality()
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}

#else

/// macOS stub — AR calibration is an iPhone/iPad concern.
@MainActor
final class ARCalibrationService: ObservableObject {
    enum Quality: String, Equatable {
        case acquiring, limited, calibrated, unavailable
    }
    enum HeadingSource: String, Equatable {
        case trueNorth = "True heading"
        case magnetic = "Magnetic heading"
        case none = "No heading"
    }

    @Published private(set) var quality: Quality = .unavailable
    @Published private(set) var statusMessage: String = "AR calibration is available on iPhone and iPad."
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var headingAccuracyDegrees: Double?
    @Published private(set) var headingSource: HeadingSource = .none
    @Published private(set) var hasLiveLocation: Bool = false
    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var trackingStateLabel: String = "AR tracking: unavailable"
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var filteredHeadingDegrees: Double?

    static var worldTrackingSupported: Bool { false }

    func start() {}
    func stop() {}
    func reset() {}
    func markSessionRunning(_ running: Bool) { isSessionRunning = running }
    func applyExternalLocation(latitude: Double?, longitude: Double?, isLive: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        hasLiveLocation = isLive
    }
}

#endif
