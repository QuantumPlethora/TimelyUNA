import Foundation
import simd

#if canImport(UIKit)
import UIKit
#endif

/// Offline celestial direction helpers for educational AR placement.
/// Azimuth is degrees from true north, clockwise; altitude is degrees above horizon.
enum ARCelestialMath {
    /// ARKit gravityAndHeading: +x east, +y up, +z south (so −z is north).
    static func worldDirection(altitudeDegrees: Double, azimuthDegrees: Double) -> SIMD3<Float> {
        let alt = altitudeDegrees * .pi / 180
        let az = azimuthDegrees * .pi / 180
        let cosAlt = cos(alt)
        let east = Float(cosAlt * sin(az))
        let up = Float(sin(alt))
        let south = Float(-cosAlt * cos(az))
        let v = SIMD3<Float>(east, up, south)
        let len = simd_length(v)
        guard len > 1e-6 else { return SIMD3<Float>(0, 1, 0) }
        return v / len
    }

    /// Place a point at `distanceMeters` along the celestial ray from the camera/world origin.
    static func worldPoint(
        altitudeDegrees: Double,
        azimuthDegrees: Double,
        distanceMeters: Float
    ) -> SIMD3<Float> {
        worldDirection(altitudeDegrees: altitudeDegrees, azimuthDegrees: azimuthDegrees) * distanceMeters
    }

    /// Angular separation in degrees between two alt/az pairs (great-circle style on the sky).
    static func angularSeparationDegrees(
        alt1: Double, az1: Double,
        alt2: Double, az2: Double
    ) -> Double {
        let a1 = alt1 * .pi / 180
        let a2 = alt2 * .pi / 180
        let dAz = (az2 - az1) * .pi / 180
        let cosC = sin(a1) * sin(a2) + cos(a1) * cos(a2) * cos(dAz)
        return acos(min(1, max(-1, cosC))) * 180 / .pi
    }

    /// Educational display coords: keep true science separation in metadata,
    /// but optionally amplify the visual offset for perception.
    struct DisplayPair: Equatable {
        var visibleAltitude: Double
        var visibleAzimuth: Double
        var actualAltitude: Double
        var actualAzimuth: Double
        /// Literal angular separation (degrees).
        var trueSeparationDegrees: Double
        /// Separation used for placement (may be magnified).
        var displaySeparationDegrees: Double
        var magnificationFactor: Double
        var isMagnified: Bool
    }

    /// When true separation is tiny, amplify azimuth offset for teaching (capped).
    static func educationalDisplayPair(
        visible: SolarEngine.HorizontalCoordinates,
        actual: SolarEngine.HorizontalCoordinates,
        minPerceptibleDegrees: Double = 2.5,
        maxDisplaySeparationDegrees: Double = 10.0,
        preferredFactor: Double = 18.0
    ) -> DisplayPair {
        let trueSep = angularSeparationDegrees(
            alt1: visible.altitude, az1: visible.azimuth,
            alt2: actual.altitude, az2: actual.azimuth
        )

        var displayActualAlt = actual.altitude
        var displayActualAz = actual.azimuth
        var factor = 1.0
        var magnified = false

        if trueSep > 0.0001 && trueSep < minPerceptibleDegrees {
            factor = min(preferredFactor, maxDisplaySeparationDegrees / trueSep)
            // Amplify differences in alt and az relative to visible.
            var dAlt = (actual.altitude - visible.altitude) * factor
            var dAz = shortestAzimuthDelta(from: visible.azimuth, to: actual.azimuth) * factor
            // Cap total display separation approximately.
            let sepAfter = hypot(dAlt, dAz)
            if sepAfter > maxDisplaySeparationDegrees {
                let s = maxDisplaySeparationDegrees / sepAfter
                dAlt *= s
                dAz *= s
                factor *= s
            }
            displayActualAlt = visible.altitude + dAlt
            displayActualAz = normalizeAzimuth(visible.azimuth + dAz)
            magnified = true
        }

        let displaySep = angularSeparationDegrees(
            alt1: visible.altitude, az1: visible.azimuth,
            alt2: displayActualAlt, az2: displayActualAz
        )

        return DisplayPair(
            visibleAltitude: visible.altitude,
            visibleAzimuth: visible.azimuth,
            actualAltitude: displayActualAlt,
            actualAzimuth: displayActualAz,
            trueSeparationDegrees: trueSep,
            displaySeparationDegrees: displaySep,
            magnificationFactor: factor,
            isMagnified: magnified
        )
    }

    static func normalizeAzimuth(_ az: Double) -> Double {
        var a = az.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }

    static func shortestAzimuthDelta(from: Double, to: Double) -> Double {
        var d = to - from
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// Exponential smoothing for headings (degrees, unwrap-aware).
    static func smoothHeading(previous: Double?, sample: Double, alpha: Double) -> Double {
        guard let previous else { return sample }
        let delta = shortestAzimuthDelta(from: previous, to: sample)
        return normalizeAzimuth(previous + alpha * delta)
    }

    static func smoothAngle(previous: Double?, sample: Double, alpha: Double) -> Double {
        guard let previous else { return sample }
        return previous + alpha * (sample - previous)
    }

    static func smoothVector(previous: SIMD3<Float>?, sample: SIMD3<Float>, alpha: Float) -> SIMD3<Float> {
        guard let previous else { return sample }
        let mixed = previous * (1 - alpha) + sample * alpha
        let len = simd_length(mixed)
        guard len > 1e-6 else { return sample }
        return mixed / len
    }
}

// MARK: - Screen guidance

enum ARScreenGuide {
    /// Result of projecting a world point into view.
    struct Projection: Equatable {
        var isOnScreen: Bool
        var screenPoint: CGPoint
        /// Unit vector in screen space pointing toward the target when offscreen.
        var edgeDirection: CGPoint
    }

    #if canImport(UIKit)
    /// Convert NDC-ish projection helpers when a view size and 3D camera transform are known.
    /// `viewMatrix` is world-to-camera; `projectionMatrix` is camera-to-clip.
    /// `chromeInsets` reserves toolbar / banner / bottom-sheet regions so labels edge-anchor
    /// instead of reporting “on screen” behind UI chrome.
    static func project(
        worldPoint: SIMD3<Float>,
        viewMatrix: float4x4,
        projectionMatrix: float4x4,
        viewSize: CGSize,
        chromeInsets: UIEdgeInsets = UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
    ) -> Projection {
        let world4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let camera = viewMatrix * world4
        let clip = projectionMatrix * camera
        guard abs(clip.w) > 1e-5 else {
            return Projection(isOnScreen: false, screenPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), edgeDirection: CGPoint(x: 0, y: -1))
        }
        let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
        let behind = camera.z > 0 // in ARKit camera space, −Z is forward; behind if z > 0 roughly
        // ARKit camera looks down −Z, so points in front have negative z in camera space.
        let inFront = camera.z < 0
        let sx = (CGFloat(ndc.x) * 0.5 + 0.5) * viewSize.width
        let sy = (1.0 - (CGFloat(ndc.y) * 0.5 + 0.5)) * viewSize.height
        let point = CGPoint(x: sx, y: sy)
        let onScreen = inFront
            && sx >= chromeInsets.left && sx <= viewSize.width - chromeInsets.right
            && sy >= chromeInsets.top && sy <= viewSize.height - chromeInsets.bottom
            && !behind

        // Center of the free viewport (between chrome), not full screen.
        let freeMidY = (chromeInsets.top + (viewSize.height - chromeInsets.bottom)) * 0.5
        let center = CGPoint(x: viewSize.width / 2, y: freeMidY)
        var dir = CGPoint(x: point.x - center.x, y: point.y - center.y)
        if !inFront {
            // Target behind camera: reverse projected xy so arrows point to turn around.
            dir = CGPoint(x: -dir.x, y: -dir.y)
        }
        let len = hypot(dir.x, dir.y)
        if len < 1 {
            dir = CGPoint(x: 0, y: -1)
        } else {
            dir = CGPoint(x: dir.x / len, y: dir.y / len)
        }

        return Projection(isOnScreen: onScreen, screenPoint: point, edgeDirection: dir)
    }
    #endif
}
