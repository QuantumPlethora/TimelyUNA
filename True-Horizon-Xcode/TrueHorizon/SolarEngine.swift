import Foundation
import CoreLocation

/// Offline solar ephemeris based on standard NOAA/Meeus low-precision equations.
/// Accuracy is suitable for an educational horizon display (typically within a few arcminutes).
enum SolarEngine {
    static func snapshot(at date: Date, location: CLLocationCoordinate2D, timeZone: TimeZone = .current) -> SolarSnapshot {
        let current = position(at: date, location: location)
        let lightTime = current.distanceAU * 499.0047838
        let trueDate = date.addingTimeInterval(lightTime)
        let true = position(at: trueDate, location: location)
        let rise = sunrise(on: date, location: location, timeZone: timeZone)
        return SolarSnapshot(
            date: date,
            location: location,
            apparent: current.horizontal,
            truePosition: true.horizontal,
            distanceAU: current.distanceAU,
            lightTimeSeconds: lightTime,
            sunrise: rise,
            trueSunrise: rise?.addingTimeInterval(-lightTime)
        )
    }

    private static func position(at date: Date, location: CLLocationCoordinate2D) -> (horizontal: HorizontalPosition, distanceAU: Double) {
        let jd = julianDate(date)
        let t = (jd - 2451545.0) / 36525.0
        let l0 = normalized(280.46646 + t * (36000.76983 + 0.0003032 * t))
        let m = normalized(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sinD(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
              + sinD(2 * m) * (0.019993 - 0.000101 * t)
              + sinD(3 * m) * 0.000289
        let trueLongitude = l0 + c
        let trueAnomaly = m + c
        let radius = (1.000001018 * (1 - e * e)) / (1 + e * cosD(trueAnomaly))
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLongitude - 0.00569 - 0.00478 * sinD(omega)
        let epsilon0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let epsilon = epsilon0 + 0.00256 * cosD(omega)
        let declination = asinD(sinD(epsilon) * sinD(lambda))
        let rightAscension = atan2D(cosD(epsilon) * sinD(lambda), cosD(lambda))

        let gmst = normalized(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000)
        let hourAngle = signed(gmst + location.longitude - rightAscension)
        let lat = location.latitude
        let altitude = asinD(sinD(lat) * sinD(declination) + cosD(lat) * cosD(declination) * cosD(hourAngle))
        let azimuth = normalized(atan2D(sinD(hourAngle), cosD(hourAngle) * sinD(lat) - tanD(declination) * cosD(lat)) + 180)
        let refracted = altitude + atmosphericRefraction(altitude)
        return (HorizontalPosition(altitude: refracted, azimuth: azimuth), radius)
    }

    static func sunrise(on date: Date, location: CLLocationCoordinate2D, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        var previousDate = start
        var previousAltitude = position(at: start, location: location).horizontal.altitude
        let target = -0.833
        for minute in stride(from: 2, through: 24 * 60, by: 2) {
            let candidate = start.addingTimeInterval(Double(minute * 60))
            let altitude = position(at: candidate, location: location).horizontal.altitude
            if previousAltitude < target && altitude >= target {
                let fraction = (target - previousAltitude) / (altitude - previousAltitude)
                return previousDate.addingTimeInterval(120 * fraction)
            }
            previousDate = candidate
            previousAltitude = altitude
        }
        return nil
    }

    private static func atmosphericRefraction(_ altitude: Double) -> Double {
        guard altitude > -1 else { return 0 }
        return 1.02 / tanD(altitude + 10.3 / (altitude + 5.11)) / 60
    }
    private static func julianDate(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }
    private static func normalized(_ value: Double) -> Double { (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    private static func signed(_ value: Double) -> Double { let x = normalized(value); return x > 180 ? x - 360 : x }
    private static func sinD(_ x: Double) -> Double { sin(x * .pi / 180) }
    private static func cosD(_ x: Double) -> Double { cos(x * .pi / 180) }
    private static func tanD(_ x: Double) -> Double { tan(x * .pi / 180) }
    private static func asinD(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func atan2D(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
}

