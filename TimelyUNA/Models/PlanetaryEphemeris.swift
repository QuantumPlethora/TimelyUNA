import Foundation
import simd

/// Educational low-precision Solar System body positions for Finder.
/// Reuses SolarEngine for the Sun. Not navigation-grade.
enum PlanetaryEphemeris {
    static let cKmS = 299_792.458
    static let auKm = 149_597_870.7

    enum Body: String, CaseIterable, Identifiable, Hashable {
        case sun = "Sun"
        case moon = "Moon"
        case venus = "Venus"
        case mars = "Mars"
        case jupiter = "Jupiter"
        case saturn = "Saturn"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .sun: return "sun.max.fill"
            case .moon: return "moon.fill"
            case .venus: return "circle.fill"
            case .mars: return "circle.circle.fill"
            case .jupiter: return "circle.grid.cross.fill"
            case .saturn: return "circle.dotted.circle.fill"
            }
        }
    }

    struct BodySnapshot: Equatable, Sendable {
        var body: Body
        var date: Date
        /// Observer latitude for this snapshot — **internal only** (never show outside TimelyUNA’s approved strip).
        var latitude: Double
        /// Observer longitude for this snapshot — **internal only** (never show outside TimelyUNA’s approved strip).
        var longitude: Double
        /// Apparent direction of photons arriving now (observer frame).
        var visible: SolarEngine.HorizontalCoordinates
        /// Light-time–corrected modeled “Actual Now” direction.
        var actual: SolarEngine.HorizontalCoordinates
        var distanceAU: Double
        var lightTimeSeconds: Double
        /// Next estimated rise across the ideal −0.833° horizon (or 0° for stars/planets without refraction offset when not Sun).
        var nextRise: Date?
        var isAboveHorizon: Bool { visible.altitude > -0.5 }
    }

    // MARK: - Public

    static func snapshot(
        body: Body,
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> BodySnapshot {
        switch body {
        case .sun:
            let snap = SolarEngine.snapshot(date: date, latitude: latitude, longitude: longitude)
            return BodySnapshot(
                body: .sun,
                date: date,
                latitude: latitude,
                longitude: longitude,
                visible: snap.apparent,
                actual: snap.truePosition,
                distanceAU: snap.distanceAU,
                lightTimeSeconds: snap.lightTimeSeconds,
                nextRise: nextRise(body: .sun, from: date, latitude: latitude, longitude: longitude)
            )
        default:
            let apparent = geocentricHorizontal(body: body, date: date, latitude: latitude, longitude: longitude)
            let light = apparent.distanceAU * SolarEngine.lightSecondsPerAU
            // Actual Now: evaluate at emission epoch (now − light time for outer bodies is
            // forward correction: object has moved during photon flight → model at date + light).
            // For consistency with SolarEngine: true position uses date + lightTime.
            let actualPos = geocentricHorizontal(
                body: body,
                date: date.addingTimeInterval(light),
                latitude: latitude,
                longitude: longitude
            )
            return BodySnapshot(
                body: body,
                date: date,
                latitude: latitude,
                longitude: longitude,
                visible: apparent.horizontal,
                actual: actualPos.horizontal,
                distanceAU: apparent.distanceAU,
                lightTimeSeconds: light,
                nextRise: nextRise(body: body, from: date, latitude: latitude, longitude: longitude)
            )
        }
    }

    static func lightDelayDescription(_ seconds: Double) -> String {
        if seconds < 90 {
            return String(format: "%.1f s", seconds)
        }
        return SolarFormat.lightDelayCompact(seconds)
    }

    // MARK: - Rise search (ideal astronomical horizon)

    static func nextRise(
        body: Body,
        from date: Date,
        latitude: Double,
        longitude: Double
    ) -> Date? {
        let targetAlt: Double = body == .sun ? -0.833 : -0.5
        // Search up to ~36 hours in 2-minute steps.
        var prevDate = date
        var prevAlt = altitude(body: body, date: date, latitude: latitude, longitude: longitude)
        for minute in stride(from: 2, through: 36 * 60, by: 2) {
            let cand = date.addingTimeInterval(Double(minute) * 60)
            let alt = altitude(body: body, date: cand, latitude: latitude, longitude: longitude)
            if prevAlt < targetAlt && alt >= targetAlt {
                let f = (targetAlt - prevAlt) / max(alt - prevAlt, 1e-6)
                return prevDate.addingTimeInterval(120 * f)
            }
            prevDate = cand
            prevAlt = alt
        }
        return nil
    }

    private static func altitude(
        body: Body,
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> Double {
        if body == .sun {
            return SolarEngine.position(date: date, latitude: latitude, longitude: longitude).horizontal.altitude
        }
        return geocentricHorizontal(body: body, date: date, latitude: latitude, longitude: longitude).horizontal.altitude
    }

    // MARK: - Geocentric model

    private struct Helio {
        var x: Double
        var y: Double
        var z: Double
        var r: Double
    }

    private struct Equatorial {
        var ra: Double  // degrees
        var dec: Double // degrees
        var distanceAU: Double
    }

    private struct GeoPos {
        var horizontal: SolarEngine.HorizontalCoordinates
        var distanceAU: Double
    }

    private static func geocentricHorizontal(
        body: Body,
        date: Date,
        latitude: Double,
        longitude: Double
    ) -> GeoPos {
        let eq: Equatorial
        switch body {
        case .moon:
            eq = moonEquatorial(date: date)
        case .venus, .mars, .jupiter, .saturn:
            eq = planetEquatorial(body: body, date: date)
        case .sun:
            // Handled by SolarEngine path.
            let p = SolarEngine.position(date: date, latitude: latitude, longitude: longitude)
            return GeoPos(horizontal: p.horizontal, distanceAU: p.distanceAU)
        }
        let horiz = equatorialToHorizontal(
            ra: eq.ra,
            dec: eq.dec,
            date: date,
            latitude: latitude,
            longitude: longitude,
            applyRefraction: body != .moon
        )
        return GeoPos(horizontal: horiz, distanceAU: eq.distanceAU)
    }

    // MARK: - Planet Kepler (J2000-ish educational elements)

    private struct Elements {
        let a: Double
        let e: Double
        let i: Double
        let L: Double
        let peri: Double
        let node: Double
        let aRate: Double
        let eRate: Double
        let iRate: Double
        let LRate: Double
        let periRate: Double
        let nodeRate: Double

        static let earth = Elements(
            a: 1.00000261, e: 0.01671123, i: -0.00001531,
            L: 100.46457166, peri: 102.93768193, node: 0,
            aRate: 0.00000562, eRate: -0.00004392, iRate: -0.01294668,
            LRate: 35_999.37244981, periRate: 0.32327364, nodeRate: 0
        )
        static let venus = Elements(
            a: 0.72333566, e: 0.00677672, i: 3.39467605,
            L: 181.97970850, peri: 131.60246718, node: 76.67984255,
            aRate: 0.00000390, eRate: -0.00004107, iRate: -0.00078890,
            LRate: 58_517.81560260, periRate: 0.00268329, nodeRate: -0.27769418
        )
        static let mars = Elements(
            a: 1.52371034, e: 0.09339410, i: 1.84969142,
            L: -4.55343205, peri: -23.94362959, node: 49.55953891,
            aRate: 0.00001847, eRate: 0.00007882, iRate: -0.00813131,
            LRate: 19_140.30268499, periRate: 0.44441088, nodeRate: -0.29257343
        )
        static let jupiter = Elements(
            a: 5.20288700, e: 0.04838624, i: 1.30439695,
            L: 34.39644051, peri: 14.72847983, node: 100.47390909,
            aRate: -0.00011607, eRate: -0.00013253, iRate: -0.00183714,
            LRate: 3_034.74612775, periRate: 0.21252668, nodeRate: 0.20469106
        )
        static let saturn = Elements(
            a: 9.53667594, e: 0.05386179, i: 2.48599187,
            L: 49.95424423, peri: 92.59887831, node: 113.66242448,
            aRate: -0.00125060, eRate: -0.00050991, iRate: 0.00193609,
            LRate: 1_222.49362201, periRate: -0.41897216, nodeRate: -0.28867794
        )
    }

    private static func elements(for body: Body) -> Elements? {
        switch body {
        case .venus: return .venus
        case .mars: return .mars
        case .jupiter: return .jupiter
        case .saturn: return .saturn
        default: return nil
        }
    }

    private static func planetEquatorial(body: Body, date: Date) -> Equatorial {
        let days = julianDay(date) - 2_451_545.0
        let earth = heliocentric(elements: .earth, daysSinceJ2000: days)
        guard let el = elements(for: body) else {
            return Equatorial(ra: 0, dec: 0, distanceAU: 1)
        }
        let planet = heliocentric(elements: el, daysSinceJ2000: days)
        // Geocentric vector (AU)
        let gx = planet.x - earth.x
        let gy = planet.y - earth.y
        let gz = planet.z - earth.z
        let dist = sqrt(gx * gx + gy * gy + gz * gz)
        // Ecliptic → equatorial (mean obliquity ~J2000)
        let eps = 23.43929111 * .pi / 180
        let xe = gx
        let ye = gy * cos(eps) - gz * sin(eps)
        let ze = gy * sin(eps) + gz * cos(eps)
        let ra = atan2(ye, xe) * 180 / .pi
        let dec = asin(max(-1, min(1, ze / max(dist, 1e-9)))) * 180 / .pi
        return Equatorial(ra: norm360(ra), dec: dec, distanceAU: dist)
    }

    private static func heliocentric(elements base: Elements, daysSinceJ2000: Double) -> Helio {
        let centuries = daysSinceJ2000 / 36_525.0
        let a = base.a + base.aRate * centuries
        let e = base.e + base.eRate * centuries
        let i = rad(base.i + base.iRate * centuries)
        let L = rad(norm360(base.L + base.LRate * centuries))
        let peri = rad(norm360(base.peri + base.periRate * centuries))
        let node = rad(norm360(base.node + base.nodeRate * centuries))
        let argument = peri - node
        let meanAnomaly = normalizeAngle(L - peri)
        let ecc = solveKepler(meanAnomaly, e: e)
        let xOrbit = a * (cos(ecc) - e)
        let yOrbit = a * sqrt(max(0, 1 - e * e)) * sin(ecc)

        let cosNode = cos(node)
        let sinNode = sin(node)
        let cosI = cos(i)
        let sinI = sin(i)
        let cosArg = cos(argument)
        let sinArg = sin(argument)

        let x = (cosNode * cosArg - sinNode * sinArg * cosI) * xOrbit
            + (-cosNode * sinArg - sinNode * cosArg * cosI) * yOrbit
        let y = (sinNode * cosArg + cosNode * sinArg * cosI) * xOrbit
            + (-sinNode * sinArg + cosNode * cosArg * cosI) * yOrbit
        let z = sinArg * sinI * xOrbit + cosArg * sinI * yOrbit
        let r = sqrt(x * x + y * y + z * z)
        return Helio(x: x, y: y, z: z, r: r)
    }

    // MARK: - Moon (low-precision educational)

    /// Simplified lunar geocentric equatorial position (Meeus-inspired truncation).
    private static func moonEquatorial(date: Date) -> Equatorial {
        let jd = julianDay(date)
        let t = (jd - 2_451_545.0) / 36_525.0
        // Mean elements (degrees)
        let Lp = norm360(218.3164477 + 481_267.88123421 * t) // mean longitude
        let D = norm360(297.8501921 + 445_267.1114034 * t)   // mean elongation
        let M = norm360(357.5291092 + 35_999.0502909 * t)    // sun mean anomaly
        let Mp = norm360(134.9633964 + 477_198.8675055 * t)  // moon mean anomaly
        let F = norm360(93.2720950 + 483_202.0175233 * t)    // arg of latitude

        // Longitude / latitude perturbations (arc-degrees, truncated)
        let lon = Lp
            + 6.289 * sinD(Mp)
            + 1.274 * sinD(2 * D - Mp)
            + 0.658 * sinD(2 * D)
            + 0.214 * sinD(2 * Mp)
            - 0.186 * sinD(M)
            - 0.114 * sinD(2 * F)
        let lat = 5.128 * sinD(F)
            + 0.281 * sinD(Mp + F)
            + 0.278 * sinD(Mp - F)
            + 0.173 * sinD(2 * D - F)

        // Geocentric distance (km), educational truncation of the lunar distance series.
        let distKm = 385_000.56
            - 20_905.56 * cosD(Mp)
            - 3_699.11 * cosD(2 * D - Mp)
            - 2_956.21 * cosD(2 * D)
        let distanceAU = max(distKm / auKm, 0.002)

        // Ecliptic → equatorial
        let eps = (23.43929111 - 0.0130042 * t) * .pi / 180
        let beta = lat * .pi / 180
        let lambda = lon * .pi / 180
        let sinDec = sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lambda)
        let dec = asin(max(-1, min(1, sinDec))) * 180 / .pi
        let y = sin(lambda) * cos(eps) - tan(beta) * sin(eps)
        let x = cos(lambda)
        let ra = atan2(y, x) * 180 / .pi
        return Equatorial(ra: norm360(ra), dec: dec, distanceAU: distanceAU)
    }

    // MARK: - Equatorial → horizontal (shared with SolarEngine approach)

    private static func equatorialToHorizontal(
        ra: Double,
        dec: Double,
        date: Date,
        latitude: Double,
        longitude: Double,
        applyRefraction: Bool
    ) -> SolarEngine.HorizontalCoordinates {
        let jd = julianDay(date)
        let t = (jd - 2_451_545.0) / 36_525.0
        let gmst = norm360(
            280.46061837
                + 360.98564736629 * (jd - 2_451_545.0)
                + 0.000387933 * t * t
                - t * t * t / 38_710_000
        )
        let ha = signedAngle(gmst + longitude - ra)
        var alt = asinD(
            sinD(latitude) * sinD(dec)
                + cosD(latitude) * cosD(dec) * cosD(ha)
        )
        let az = norm360(
            atan2D(
                sinD(ha),
                cosD(ha) * sinD(latitude) - tanD(dec) * cosD(latitude)
            ) + 180
        )
        if applyRefraction {
            alt += refraction(alt)
        }
        return SolarEngine.HorizontalCoordinates(altitude: alt, azimuth: az)
    }

    private static func refraction(_ alt: Double) -> Double {
        if alt <= -1 { return 0 }
        return 1.02 / tanD(alt + 10.3 / (alt + 5.11)) / 60
    }

    // MARK: - Math

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    private static func solveKepler(_ m: Double, e: Double) -> Double {
        var v = m
        for _ in 0..<12 {
            v -= (v - e * sin(v) - m) / (1 - e * cos(v))
        }
        return v
    }

    private static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    private static func normalizeAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x < 0 { x += 2 * .pi }
        return x
    }
    private static func norm360(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x
    }
    private static func signedAngle(_ v: Double) -> Double {
        let x = norm360(v)
        return x > 180 ? x - 360 : x
    }
    private static func sinD(_ x: Double) -> Double { sin(x * .pi / 180) }
    private static func cosD(_ x: Double) -> Double { cos(x * .pi / 180) }
    private static func tanD(_ x: Double) -> Double { tan(x * .pi / 180) }
    private static func asinD(_ x: Double) -> Double { asin(min(1, max(-1, x))) * 180 / .pi }
    private static func atan2D(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
}
