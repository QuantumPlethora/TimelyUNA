import Foundation
import CoreLocation
import Combine

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Observer coordinates for educational solar calculations.
///
/// ## Location privacy (True Horizon policy)
/// - Raw `latitude` / `longitude` exist only after a live Core Location fix (never a silent fallback).
/// - Exact values may be **visibly displayed only on True Horizon’s observer strip / same-screen metrics**.
/// - Use `coordinateLabel` solely for that approved UI. Prefer `locationAvailabilityLabel` for
///   diagnostics, AR, Finder gates, and any non-approved surface.
/// - Do not put coordinates in share text, notifications, URLs, UserDefaults keys, analytics, or logs.
@MainActor
final class ObserverLocationService: NSObject, ObservableObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
        case unavailable
    }

    enum Source: Equatable {
        /// Live Core Location fix — only state that supplies coordinates.
        case liveGPS
        /// User has not requested location yet.
        case notRequested
        /// System permission dialog in flight or first fix pending.
        case requesting
        /// Permission denied or restricted; no coordinates.
        case denied
        /// Location services off or hardware unavailable; no coordinates.
        case unavailable
        /// Authorized but a fix failed; no coordinates until retry succeeds.
        case fixFailed
    }

    /// Precise device latitude — **internal astronomy only**. Do not format for UI outside True Horizon.
    @Published private(set) var latitude: Double?
    /// Precise device longitude — **internal astronomy only**. Do not format for UI outside True Horizon.
    @Published private(set) var longitude: Double?
    @Published private(set) var source: Source = .notRequested
    @Published private(set) var authorization: AuthorizationState = .notDetermined
    @Published private(set) var statusMessage: String = "Location needed for your horizon"
    @Published private(set) var lastUpdate: Date?
    /// User-facing errors must never embed numeric latitude/longitude.
    @Published var lastErrorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 500
        syncAuthorizationFromSystem()
        // If permission was already granted (e.g. prior launch or simctl privacy grant),
        // start a live fix without requiring another button press.
        resumeIfAuthorized()
    }

    /// Begin updates when the system already authorized location.
    func resumeIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        default:
            break
        }
    }

    /// True only when we hold a live GPS fix.
    var hasLiveCoordinates: Bool {
        source == .liveGPS && latitude != nil && longitude != nil
    }

    var isLive: Bool { hasLiveCoordinates }

    /// **APPROVED DISPLAY ONLY** — True Horizon observer strip / same-screen metrics.
    /// Never use this in Finder, AR, xSky, share, notifications, accessibility outside True Horizon, or logs.
    var coordinateLabel: String {
        guard let latitude, let longitude, hasLiveCoordinates else {
            return "—"
        }
        return String(format: "%.4f°, %.4f°", latitude, longitude)
    }

    /// Redacted location state for diagnostics, gates, and non-approved UI.
    /// Values: `available`, `acquiring`, `denied`, `unavailable`, `not set`, `fix failed`.
    var locationAvailabilityLabel: String {
        switch source {
        case .liveGPS where hasLiveCoordinates:
            return "available"
        case .liveGPS:
            return "acquiring"
        case .requesting:
            return "acquiring"
        case .denied:
            return "denied"
        case .unavailable:
            return "unavailable"
        case .fixFailed:
            return "fix failed"
        case .notRequested:
            return "not set"
        }
    }

    /// Short badge without numeric coordinates (safe for Finder / AR chrome).
    var sourceBadge: String {
        switch source {
        case .liveGPS: return "Live location"
        case .notRequested: return "Not set"
        case .requesting: return "Requesting…"
        case .denied: return "Permission denied"
        case .unavailable: return "Unavailable"
        case .fixFailed: return "Fix failed"
        }
    }

    /// Primary call-to-action label for the location button.
    var actionButtonTitle: String {
        switch source {
        case .liveGPS:
            return "Refresh location"
        case .denied, .unavailable:
            return "Open Location Settings"
        case .requesting:
            return "Requesting…"
        case .notRequested, .fixFailed:
            return "Use my location"
        }
    }

    var needsSettings: Bool {
        switch source {
        case .denied, .unavailable:
            return true
        default:
            return authorization == .denied || authorization == .restricted
        }
    }

    /// Guidance when the user cannot get a live fix yet.
    /// Never embeds numeric latitude/longitude.
    var guidanceMessage: String? {
        switch source {
        case .notRequested:
            return "True Horizon needs your location to compute altitude, azimuth, and sunrise for your sky. Location data stays on this device."
        case .requesting:
            return "Waiting for permission or the first location fix…"
        case .denied:
            #if os(iOS)
            return "Location access is off for True Horizon. Open Settings → Privacy & Security → Location Services, enable True Horizon, then return and tap Refresh."
            #else
            return "Location access is off for True Horizon. Open System Settings → Privacy & Security → Location Services, enable True Horizon, then return and refresh."
            #endif
        case .unavailable:
            #if os(iOS)
            return "Location Services appear to be off. Enable them in the Settings app, then try again."
            #else
            return "Location Services appear to be off. Enable them in System Settings, then try again."
            #endif
        case .fixFailed:
            return "Could not get a location fix. Check that Location Services are on, then try again."
        case .liveGPS:
            return nil
        }
    }

    // MARK: - Public actions

    func requestLocation() {
        lastErrorMessage = nil

        switch manager.authorizationStatus {
        case .denied, .restricted:
            authorization = manager.authorizationStatus == .denied ? .denied : .restricted
            clearCoordinates(source: .denied, message: "Location permission denied")
            openSystemLocationSettings()
            return
        default:
            break
        }

        guard CLLocationManager.locationServicesEnabled() else {
            authorization = .unavailable
            clearCoordinates(source: .unavailable, message: "Location Services are turned off")
            lastErrorMessage = "Location Services are turned off on this device."
            openSystemLocationSettings()
            return
        }

        syncAuthorizationFromSystem()

        switch manager.authorizationStatus {
        case .notDetermined:
            source = .requesting
            statusMessage = "Requesting location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .denied:
            authorization = .denied
            clearCoordinates(source: .denied, message: "Location permission denied")
            openSystemLocationSettings()
        case .restricted:
            authorization = .restricted
            clearCoordinates(source: .denied, message: "Location is restricted on this device")
            openSystemLocationSettings()
        @unknown default:
            clearCoordinates(source: .unavailable, message: "Location status unknown")
        }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    func openSystemLocationSettings() {
        #if os(macOS)
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.Location-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for string in candidates {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Private

    private func beginUpdates() {
        authorization = .authorized
        if !hasLiveCoordinates {
            source = .requesting
            statusMessage = "Acquiring horizon fix…"
        }
        manager.requestLocation()
        manager.startUpdatingLocation()
    }

    private func clearCoordinates(source: Source, message: String) {
        latitude = nil
        longitude = nil
        lastUpdate = nil
        self.source = source
        statusMessage = message
    }

    private func syncAuthorizationFromSystem() {
        switch manager.authorizationStatus {
        case .notDetermined:
            authorization = .notDetermined
            if source != .requesting && source != .liveGPS {
                source = .notRequested
                statusMessage = "Location needed for your horizon"
            }
        case .authorizedAlways, .authorizedWhenInUse:
            authorization = .authorized
        case .denied:
            authorization = .denied
            if source != .liveGPS {
                clearCoordinates(source: .denied, message: "Location permission denied")
            }
        case .restricted:
            authorization = .restricted
            if source != .liveGPS {
                clearCoordinates(source: .denied, message: "Location is restricted on this device")
            }
        @unknown default:
            authorization = .unavailable
        }
    }
}

extension ObserverLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.syncAuthorizationFromSystem()
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.beginUpdates()
            case .denied:
                self.clearCoordinates(source: .denied, message: "Location permission denied")
            case .restricted:
                self.clearCoordinates(source: .denied, message: "Location is restricted on this device")
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return }
        Task { @MainActor in
            self.latitude = coord.latitude
            self.longitude = coord.longitude
            self.source = .liveGPS
            self.statusMessage = "Live location horizon locked"
            self.lastUpdate = location.timestamp
            self.lastErrorMessage = nil
            self.manager.stopUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Keep a previous live fix if we already have one (transient error).
            if self.source == .liveGPS, self.latitude != nil {
                // Never embed coordinates; keep prior fix for astronomy, surface redacted status only.
                self.lastErrorMessage = "Location update failed; using last known fix"
                self.statusMessage = "Live location · last fix kept (update failed)"
                return
            }
            self.clearCoordinates(source: .fixFailed, message: "Could not get a location fix")
            self.lastErrorMessage = "Location fix failed"
        }
    }
}
