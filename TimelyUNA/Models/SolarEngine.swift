import Foundation

/// Educational NOAA/Meeus-style solar engine (offline).
/// Ported from the True Horizon web engine. Not navigation-grade.
enum SolarEngine {
    /// Mean light-seconds per astronomical unit (~AU / c).
    static let lightSecondsPerAU: Double = 499.0047838

    /// Mean solar orbital speed used for “distance traveled while light flew” teaching estimate (km/s).
    static let meanSolarOrbitalSpeedKMS: Double = 29.78

    struct HorizontalCoordinates: Equatable, Sendable {
        var altitude: Double
        var azimuth: Double
    }

    struct Position: Equatable, Sendable {
        var horizontal: HorizontalCoordinates
        var distanceAU: Double
    }

    struct Snapshot: Equatable, Sendable {
        var date: Date
        /// Observer latitude used for this calculation — **internal only**; never format for UI/share/logs outside True Horizon’s approved coordinate display.
        var latitude: Double
        /// Observer longitude used for this calculation — **internal only**; never format for UI/share/logs outside True Horizon’s approved coordinate display.
        var longitude: Double
        var apparent: HorizontalCoordinates
        var truePosition: HorizontalCoordinates
        var distanceAU: Double
        var lightTimeSeconds: Double
        /// Local visible (apparent) sunrise for the modeled civil day, or nil if none.
        var sunrise: Date?
        /// Light-time-corrected “true” sunrise (visible sunrise minus photon delay).
        var trueSunrise: Date?

        var lightMinutes: Int { Int(lightTimeSeconds) / 60 }
        var lightSecondsRemainder: Int { Int(lightTimeSeconds) % 60 }

        var sunTravelWhileLightFlewKilometers: Double {
            meanSolarOrbitalSpeedKMS * lightTimeSeconds
        }
    }

    // MARK: - Public API

    static func snapshot(date: Date, latitude: Double, longitude: Double) -> Snapshot {
        let current = position(date: date, latitude: latitude, longitude: longitude)
        let lightTime = current.distanceAU * lightSecondsPerAU
        let trueDate = date.addingTimeInterval(lightTime)
        let trueSun = position(date: trueDate, latitude: latitude, longitude: longitude)
        let rise = sunrise(on: date, latitude: latitude, longitude: longitude)
        let trueRise = rise.map { $0.addingTimeInterval(-lightTime) }

        return Snapshot(
            date: date,
            latitude: latitude,
            longitude: longitude,
            apparent: current.horizontal,
            truePosition: trueSun.horizontal,
            distanceAU: current.distanceAU,
            lightTimeSeconds: lightTime,
            sunrise: rise,
            trueSunrise: trueRise
        )
    }

    /// Next useful true-sunrise pair (rolls to tomorrow if today’s true sunrise has passed).
    static func nextSunrisePair(from date: Date, latitude: Double, longitude: Double) -> (visible: Date?, trueSun: Date?) {
        var snap = snapshot(date: date, latitude: latitude, longitude: longitude)
        if let trueRise = snap.trueSunrise, trueRise < date {
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
                snap = snapshot(date: tomorrow, latitude: latitude, longitude: longitude)
            }
        }
        return (snap.sunrise, snap.trueSunrise)
    }

    // MARK: - Core position

    static func position(date: Date, latitude: Double, longitude: Double) -> Position {
        let jd = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        let t = (jd - 2_451_545.0) / 36_525.0

        let l0 = norm(280.46646 + t * (36_000.76983 + 0.0003032 * t))
        let m = norm(357.52911 + t * (35_999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sinD(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sinD(2 * m) * (0.019993 - 0.000101 * t)
            + sinD(3 * m) * 0.000289
        let trueLong = l0 + c
        let trueAnomaly = m + c
        let radius = (1.000001018 * (1 - e * e)) / (1 + e * cosD(trueAnomaly))
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sinD(omega)
        let epsilon0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let epsilon = epsilon0 + 0.00256 * cosD(omega)
        let dec = asinD(sinD(epsilon) * sinD(lambda))
        let ra = atan2D(cosD(epsilon) * sinD(lambda), cosD(lambda))
        let gmst = norm(
            280.46061837
                + 360.98564736629 * (jd - 2_451_545.0)
                + 0.000387933 * t * t
                - t * t * t / 38_710_000
        )
        let ha = signed(gmst + longitude - ra)
        var alt = asinD(
            sinD(latitude) * sinD(dec)
                + cosD(latitude) * cosD(dec) * cosD(ha)
        )
        let az = norm(
            atan2D(
                sinD(ha),
                cosD(ha) * sinD(latitude) - tanD(dec) * cosD(latitude)
            ) + 180
        )
        alt += refraction(alt)
        return Position(
            horizontal: HorizontalCoordinates(altitude: alt, azimuth: az),
            distanceAU: radius
        )
    }

    static func sunrise(on date: Date, latitude: Double, longitude: Double) -> Date? {
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) else {
            return nil
        }
        var prevDate = start
        var prevAlt = position(date: start, latitude: latitude, longitude: longitude).horizontal.altitude
        let target = -0.833

        for minute in stride(from: 2, through: 24 * 60, by: 2) {
            let cand = start.addingTimeInterval(Double(minute) * 60)
            let alt = position(date: cand, latitude: latitude, longitude: longitude).horizontal.altitude
            if prevAlt < target && alt >= target {
                let f = (target - prevAlt) / (alt - prevAlt)
                return prevDate.addingTimeInterval(120 * f)
            }
            prevDate = cand
            prevAlt = alt
        }
        return nil
    }

    // MARK: - Helpers

    private static func refraction(_ alt: Double) -> Double {
        if alt <= -1 { return 0 }
        return 1.02 / tanD(alt + 10.3 / (alt + 5.11)) / 60
    }

    private static func norm(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x
    }

    private static func signed(_ v: Double) -> Double {
        let x = norm(v)
        return x > 180 ? x - 360 : x
    }

    private static func sinD(_ x: Double) -> Double { sin(x * .pi / 180) }
    private static func cosD(_ x: Double) -> Double { cos(x * .pi / 180) }
    private static func tanD(_ x: Double) -> Double { tan(x * .pi / 180) }
    private static func asinD(_ x: Double) -> Double {
        asin(min(1, max(-1, x))) * 180 / .pi
    }
    private static func atan2D(_ y: Double, _ x: Double) -> Double {
        atan2(y, x) * 180 / .pi
    }
}

// MARK: - Formatting

enum SolarFormat {
    static func degrees(_ value: Double, places: Int = 2) -> String {
        String(format: "%.\(places)f°", value)
    }

    static func au(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    static func lightDelayWords(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m) minutes, \(s) seconds"
    }

    static func lightDelayCompact(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%dm %02ds", m, s)
    }

    static func pad2(_ n: Int) -> String {
        String(format: "%02d", n)
    }

    static func localTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func countdown(to date: Date, from now: Date = .now) -> String {
        let diff = max(0, date.timeIntervalSince(now))
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        let s = Int(diff) % 60
        return "\(pad2(h)):\(pad2(m)):\(pad2(s))"
    }

    static func travelKilometers(_ km: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " km"
    }
}
