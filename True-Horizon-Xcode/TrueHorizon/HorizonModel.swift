import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class HorizonModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var snapshot: SolarSnapshot?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var locationName = "Finding your horizon…"
    @Published var streak = UserDefaults.standard.integer(forKey: "ritualStreak")
    @Published var ritualComplete = false
    @Published var selectedEpoch: Epoch = .present

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
        requestLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestLocation() {
        #if os(macOS)
        manager.requestAlwaysAuthorization()
        #else
        manager.requestWhenInUseAuthorization()
        #endif
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        locationName = String(format: "%.3f°, %.3f°", latest.coordinate.latitude, latest.coordinate.longitude)
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationName = "Location unavailable"
        // Cupertino is an explicit preview fallback, never silently presented as live.
        let fallback = CLLocation(latitude: 37.3349, longitude: -122.0090)
        location = fallback
        refresh()
    }

    func refresh() {
        guard let location else { return }
        snapshot = SolarEngine.snapshot(at: Date(), location: location.coordinate)
    }

    func completeRitual() {
        guard !ritualComplete else { return }
        ritualComplete = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if UserDefaults.standard.string(forKey: "lastRitualDate") != today {
            streak = max(1, streak + 1)
            UserDefaults.standard.set(streak, forKey: "ritualStreak")
            UserDefaults.standard.set(today, forKey: "lastRitualDate")
        }
    }
}

