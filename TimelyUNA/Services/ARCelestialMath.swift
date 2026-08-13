import Foundation
import CoreGraphics
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

    // MARK: Angular → screen (Finder HUD)

    /// Result of mapping relative sky angles into a 2D instrument face.
    /// Pipeline: relative angle → normalize by half-FOV → screen coords → edge clamp.
    struct ScreenPlacement: Equatable {
        /// Pre-clamp normalized offsets. ±1 ≈ half FOV at the instrument edge.
        var normalizedX: Double
        var normalizedY: Double
        /// Final pixel position after edge clamp (origin top-left, Y down).
        var screenPoint: CGPoint
        /// True when either axis was pulled back onto the usable rectangle.
        var isClampedToEdge: Bool
        /// Which edges were hit (for chevrons / edge arrows).
        var clampedLeft: Bool
        var clampedRight: Bool
        var clampedTop: Bool
        var clampedBottom: Bool
    }

    /// relativeElevation = targetAltitude − viewingElevation
    static func relativeElevation(targetAltitude: Double, viewingElevation: Double) -> Double {
        targetAltitude - viewingElevation
    }

    /// Ideal-horizon gate used by Finder (`PlanetaryEphemeris.BodySnapshot.isAboveHorizon`).
    static func isBelowHorizon(targetAltitude: Double, thresholdDegrees: Double = -0.5) -> Bool {
        targetAltitude <= thresholdDegrees
    }

    /// Map relative azimuth/elevation (degrees) onto a view.
    ///
    /// - `relativeAzimuth`: shortestAngle(targetAz − heading); + = target to the right
    /// - `relativeElevation`: targetAltitude − viewingElevation; + = target above aim
    /// - `forceBottomClamp`: pin to the bottom edge (below-horizon / under-FOV targets)
    /// - `halfHorizontalFOVDegrees` / `halfVerticalFOVDegrees`: angles that map to ±1
    ///   (instrument “half FOV”, not necessarily the camera FOV)
    /// - Elevation-up maps to smaller `screenY` (UIKit/SwiftUI Y grows downward).
    ///
    /// Fixture: targetAltitude −15.38°, viewingElevation +29.69°
    /// → relativeElevation −45.07° → normalizedY ≲ −1.5 → `clampedBottom` (with 30° half-FOV).
    static func screenPlacement(
        relativeAzimuthDegrees: Double,
        relativeElevationDegrees: Double,
        viewSize: CGSize,
        halfHorizontalFOVDegrees: Double = 35,
        halfVerticalFOVDegrees: Double = 30,
        edgeInset: CGFloat = 18,
        forceBottomClamp: Bool = false,
        forceTopClamp: Bool = false
    ) -> ScreenPlacement {
        let halfH = max(halfHorizontalFOVDegrees, 1e-3)
        let halfV = max(halfVerticalFOVDegrees, 1e-3)

        // 1) relative → normalized vertical/horizontal offset
        let normalizedX = relativeAzimuthDegrees / halfH
        // Below-horizon / forced edge: drive past ±1 so clamp flags stay honest.
        let normalizedY: Double
        if forceBottomClamp {
            normalizedY = min(relativeElevationDegrees / halfV, -1.05)
        } else if forceTopClamp {
            normalizedY = max(relativeElevationDegrees / halfV, 1.05)
        } else {
            normalizedY = relativeElevationDegrees / halfV
        }

        // 2) normalized → raw screen coords (center-based; +elev → up → lower Y)
        let midX = viewSize.width * 0.5
        let midY = viewSize.height * 0.5
        let usableHalfW = max(viewSize.width * 0.5 - edgeInset, 1)
        let usableHalfH = max(viewSize.height * 0.5 - edgeInset, 1)
        let rawX = midX + CGFloat(normalizedX) * usableHalfW
        let rawY = midY - CGFloat(normalizedY) * usableHalfH

        // 3) edge clamp
        let minX = edgeInset
        let maxX = max(viewSize.width - edgeInset, edgeInset)
        let minY = edgeInset
        let maxY = max(viewSize.height - edgeInset, edgeInset)
        let clampedX = min(max(rawX, minX), maxX)
        let clampedY = min(max(rawY, minY), maxY)

        let left = rawX < minX
        let right = rawX > maxX
        let top = rawY < minY || forceTopClamp
        let bottom = rawY > maxY || forceBottomClamp

        return ScreenPlacement(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            screenPoint: CGPoint(x: clampedX, y: clampedY),
            isClampedToEdge: left || right || top || bottom,
            clampedLeft: left,
            clampedRight: right,
            clampedTop: top,
            clampedBottom: bottom
        )
    }

    /// Finder instrument placement from sky + device readings.
    /// Below-horizon targets always bottom-clamp the marker (even if the user aims downward).
    static func finderScreenPlacement(
        targetAltitude: Double,
        targetAzimuth: Double,
        deviceHeading: Double?,
        viewingElevation: Double?,
        viewSize: CGSize,
        halfHorizontalFOVDegrees: Double = 35,
        halfVerticalFOVDegrees: Double = 30,
        edgeInset: CGFloat = 18
    ) -> ScreenPlacement {
        let relativeAz: Double
        if let heading = deviceHeading {
            relativeAz = shortestAzimuthDelta(from: heading, to: targetAzimuth)
        } else {
            relativeAz = 0
        }

        let relativeEl: Double
        if let elev = viewingElevation {
            relativeEl = relativeElevation(targetAltitude: targetAltitude, viewingElevation: elev)
        } else {
            // No pitch: treat altitude as offset from the instrument horizon (center).
            relativeEl = targetAltitude
        }

        let below = isBelowHorizon(targetAltitude: targetAltitude)
        return screenPlacement(
            relativeAzimuthDegrees: relativeAz,
            relativeElevationDegrees: relativeEl,
            viewSize: viewSize,
            halfHorizontalFOVDegrees: halfHorizontalFOVDegrees,
            halfVerticalFOVDegrees: halfVerticalFOVDegrees,
            edgeInset: edgeInset,
            forceBottomClamp: below
        )
    }

    /// Elevation-only half of the pipeline (useful when heading is unavailable).
    static func screenY(
        relativeElevationDegrees: Double,
        viewHeight: CGFloat,
        halfVerticalFOVDegrees: Double = 30,
        edgeInset: CGFloat = 18
    ) -> (normalized: Double, screenY: CGFloat, clampedTop: Bool, clampedBottom: Bool) {
        let placement = screenPlacement(
            relativeAzimuthDegrees: 0,
            relativeElevationDegrees: relativeElevationDegrees,
            viewSize: CGSize(width: max(viewHeight, 1), height: viewHeight),
            halfVerticalFOVDegrees: halfVerticalFOVDegrees,
            edgeInset: edgeInset
        )
        return (
            placement.normalizedY,
            placement.screenPoint.y,
            placement.clampedTop,
            placement.clampedBottom
        )
    }
}

// MARK: - Screen guidance (projection, exclusion zones, marker collision)

enum ARScreenGuide {
    // MARK: Exclusion chrome

    /// Platform-neutral chrome insets (top banner / toolbar, bottom sheet, sides).
    struct ExclusionInsets: Equatable, Sendable {
        var top: CGFloat
        var left: CGFloat
        var bottom: CGFloat
        var right: CGFloat

        static let zero = ExclusionInsets(top: 0, left: 0, bottom: 0, right: 0)
        static let defaultChrome = ExclusionInsets(top: 110, left: 28, bottom: 130, right: 28)

        /// Live AR layout: toolbar+banner top, bottom sheet height, optional trailing panel.
        static func arChrome(
            topReserved: CGFloat,
            bottomSheetHeight: CGFloat,
            leading: CGFloat = 28,
            trailing: CGFloat = 28,
            bannerExtra: CGFloat = 0,
            pad: CGFloat = 8
        ) -> ExclusionInsets {
            ExclusionInsets(
                top: max(0, topReserved + bannerExtra + pad),
                left: max(0, leading),
                bottom: max(0, bottomSheetHeight + pad),
                right: max(0, trailing)
            )
        }

        #if canImport(UIKit)
        var uiEdgeInsets: UIEdgeInsets {
            UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        }

        init(uiEdgeInsets insets: UIEdgeInsets) {
            top = insets.top
            left = insets.left
            bottom = insets.bottom
            right = insets.right
        }
        #endif

        init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
    }

    enum ExclusionKind: String, Equatable, Sendable {
        case banner
        case bottomSheet
        case sidePanel
        case custom
    }

    /// Axis-aligned region markers must not occupy.
    struct ExclusionZone: Equatable, Identifiable, Sendable {
        var id: String
        var rect: CGRect
        var kind: ExclusionKind
    }

    /// Build standard banner + bottom-sheet (+ optional trailing) exclusion rects for a view.
    static func exclusionZones(viewSize: CGSize, insets: ExclusionInsets) -> [ExclusionZone] {
        var zones: [ExclusionZone] = []
        if insets.top > 0.5 {
            zones.append(ExclusionZone(
                id: "banner",
                rect: CGRect(x: 0, y: 0, width: viewSize.width, height: insets.top),
                kind: .banner
            ))
        }
        if insets.bottom > 0.5 {
            zones.append(ExclusionZone(
                id: "bottomSheet",
                rect: CGRect(
                    x: 0,
                    y: max(0, viewSize.height - insets.bottom),
                    width: viewSize.width,
                    height: insets.bottom
                ),
                kind: .bottomSheet
            ))
        }
        if insets.left > 0.5 {
            zones.append(ExclusionZone(
                id: "leading",
                rect: CGRect(x: 0, y: 0, width: insets.left, height: viewSize.height),
                kind: .sidePanel
            ))
        }
        if insets.right > 0.5 {
            zones.append(ExclusionZone(
                id: "trailing",
                rect: CGRect(
                    x: max(0, viewSize.width - insets.right),
                    y: 0,
                    width: insets.right,
                    height: viewSize.height
                ),
                kind: .sidePanel
            ))
        }
        return zones
    }

    /// Usable camera/instrument band between chrome (may be empty if chrome is oversized).
    static func freeRect(viewSize: CGSize, insets: ExclusionInsets) -> CGRect {
        let x = insets.left
        let y = insets.top
        let w = max(0, viewSize.width - insets.left - insets.right)
        let h = max(0, viewSize.height - insets.top - insets.bottom)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func freeCenter(viewSize: CGSize, insets: ExclusionInsets) -> CGPoint {
        let r = freeRect(viewSize: viewSize, insets: insets)
        return CGPoint(x: r.midX, y: r.midY)
    }

    // MARK: Markers

    /// Preferred screen marker before collision resolution.
    struct Marker: Equatable, Identifiable, Sendable {
        var id: String
        /// Desired center in view coordinates.
        var preferred: CGPoint
        /// Full width/height of the marker (label + glyph hit box).
        var size: CGSize
        /// Higher priority moves less when resolving overlaps (0 = default).
        var priority: Int

        init(id: String, preferred: CGPoint, size: CGSize = CGSize(width: 44, height: 44), priority: Int = 0) {
            self.id = id
            self.preferred = preferred
            self.size = size
            self.priority = priority
        }

        func bounds(at center: CGPoint) -> CGRect {
            CGRect(
                x: center.x - size.width * 0.5,
                y: center.y - size.height * 0.5,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Marker after exclusion clamp + peer separation.
    struct ResolvedMarker: Equatable, Identifiable, Sendable {
        var id: String
        var point: CGPoint
        var preferred: CGPoint
        var size: CGSize
        var priority: Int
        /// Preferred center lay inside a banner / sheet / side exclusion zone.
        var preferredInExclusion: Bool
        /// Final point was pushed to stay inside the free rect.
        var clampedToFreeRect: Bool
        /// Final point differs from preferred due to peer collision separation.
        var separatedFromPeers: Bool
        var wasMoved: Bool { clampedToFreeRect || separatedFromPeers || preferredInExclusion }
    }

    /// True if two axis-aligned marker bounds overlap (with optional padding).
    static func markersCollide(_ a: CGRect, _ b: CGRect, padding: CGFloat = 0) -> Bool {
        let ra = a.insetBy(dx: -padding, dy: -padding)
        return ra.intersects(b)
    }

    /// True if center (with half-size) intersects any exclusion zone.
    static func intersectsExclusion(center: CGPoint, size: CGSize, zones: [ExclusionZone]) -> Bool {
        let bounds = CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        return zones.contains { $0.rect.intersects(bounds) }
    }

    /// Clamp a marker center so its full AABB stays inside `free`.
    static func clampCenter(
        _ center: CGPoint,
        size: CGSize,
        free: CGRect
    ) -> (point: CGPoint, clamped: Bool) {
        guard free.width > 1, free.height > 1 else {
            return (CGPoint(x: free.midX, y: free.midY), true)
        }
        let halfW = size.width * 0.5
        let halfH = size.height * 0.5
        let minX = free.minX + halfW
        let maxX = free.maxX - halfW
        let minY = free.minY + halfH
        let maxY = free.maxY - halfH
        // If marker is larger than free rect, pin to free center on that axis.
        let x: CGFloat
        if minX > maxX {
            x = free.midX
        } else {
            x = min(max(center.x, minX), maxX)
        }
        let y: CGFloat
        if minY > maxY {
            y = free.midY
        } else {
            y = min(max(center.y, minY), maxY)
        }
        let p = CGPoint(x: x, y: y)
        let clamped = abs(p.x - center.x) > 0.25 || abs(p.y - center.y) > 0.25
        return (p, clamped)
    }

    /// Push `center` out of exclusion zones (shortest axis exit), then into free rect.
    static func resolveAgainstExclusions(
        center: CGPoint,
        size: CGSize,
        free: CGRect,
        zones: [ExclusionZone]
    ) -> (point: CGPoint, hitExclusion: Bool, clamped: Bool) {
        var p = center
        var hit = false
        let halfW = size.width * 0.5
        let halfH = size.height * 0.5

        for zone in zones {
            let bounds = CGRect(x: p.x - halfW, y: p.y - halfH, width: size.width, height: size.height)
            guard bounds.intersects(zone.rect) else { continue }
            hit = true
            // Distance to each free-side of the zone (positive = how far to move out).
            let outLeft = (zone.rect.minX - halfW) - p.x   // move left: more negative x
            let outRight = (zone.rect.maxX + halfW) - p.x
            let outTop = (zone.rect.minY - halfH) - p.y
            let outBottom = (zone.rect.maxY + halfH) - p.y
            // Prefer the shortest escape that lands nearer the free rect center.
            let candidates: [(CGFloat, CGPoint)] = [
                (abs(outLeft), CGPoint(x: p.x + outLeft, y: p.y)),
                (abs(outRight), CGPoint(x: p.x + outRight, y: p.y)),
                (abs(outTop), CGPoint(x: p.x, y: p.y + outTop)),
                (abs(outBottom), CGPoint(x: p.x, y: p.y + outBottom))
            ]
            // Only consider escapes that reduce intersection; pick minimum |delta|.
            if let best = candidates.min(by: { $0.0 < $1.0 }) {
                p = best.1
            }
        }

        let clamped = clampCenter(p, size: size, free: free)
        return (clamped.point, hit || intersectsExclusion(center: center, size: size, zones: zones), clamped.clamped || hit)
    }

    /// Full pipeline: exclusion eviction → free-rect clamp → iterative peer separation.
    ///
    /// - Higher `priority` markers stay put; lower priority yields.
    /// - Equal priority: both move half the separation.
    /// - After each push, re-clamp into free rect so chrome is never re-entered.
    static func resolveMarkers(
        _ markers: [Marker],
        viewSize: CGSize,
        insets: ExclusionInsets,
        padding: CGFloat = 6,
        maxIterations: Int = 12
    ) -> [ResolvedMarker] {
        let free = freeRect(viewSize: viewSize, insets: insets)
        let zones = exclusionZones(viewSize: viewSize, insets: insets)
        guard !markers.isEmpty else { return [] }

        var points: [CGPoint] = []
        var preferredHits: [Bool] = []
        var clampedFlags: [Bool] = []
        var separatedFlags = Array(repeating: false, count: markers.count)

        for m in markers {
            let excl = resolveAgainstExclusions(center: m.preferred, size: m.size, free: free, zones: zones)
            points.append(excl.point)
            preferredHits.append(excl.hitExclusion)
            clampedFlags.append(excl.clamped)
        }

        // Index order: high priority first for asymmetric yields.
        let order = markers.indices.sorted {
            if markers[$0].priority != markers[$1].priority {
                return markers[$0].priority > markers[$1].priority
            }
            return markers[$0].id < markers[$1].id
        }

        if markers.count > 1 {
            for _ in 0..<maxIterations {
                var moved = false
                for a in 0..<order.count {
                    for b in (a + 1)..<order.count {
                        let i = order[a]
                        let j = order[b]
                        let bi = markers[i].bounds(at: points[i])
                        let bj = markers[j].bounds(at: points[j])
                        guard markersCollide(bi, bj, padding: padding) else { continue }

                        var dx = points[j].x - points[i].x
                        var dy = points[j].y - points[i].y
                        var dist = hypot(dx, dy)
                        let nx: CGFloat
                        let ny: CGFloat
                        if dist < 0.5 {
                            // Coincident: deterministic unit axis from ids.
                            var hasher = Hasher()
                            hasher.combine(markers[i].id)
                            hasher.combine(markers[j].id)
                            let angle = CGFloat(abs(hasher.finalize() % 360)) * .pi / 180
                            nx = cos(angle)
                            ny = sin(angle)
                            dist = 0.5
                            dx = nx
                            dy = ny
                        } else {
                            nx = dx / dist
                            ny = dy / dist
                        }

                        let req =
                            (markers[i].size.width + markers[j].size.width) * 0.5 * abs(nx)
                            + (markers[i].size.height + markers[j].size.height) * 0.5 * abs(ny)
                            + padding
                        let overlap = req - dist
                        guard overlap > 0.5 else { continue }

                        let pi = markers[i].priority
                        let pj = markers[j].priority
                        let moveI: CGFloat
                        let moveJ: CGFloat
                        if pi > pj {
                            moveI = 0
                            moveJ = overlap
                        } else if pj > pi {
                            moveI = overlap
                            moveJ = 0
                        } else {
                            moveI = overlap * 0.5
                            moveJ = overlap * 0.5
                        }

                        if moveI > 0 {
                            let raw = CGPoint(x: points[i].x - nx * moveI, y: points[i].y - ny * moveI)
                            let clamped = clampCenter(raw, size: markers[i].size, free: free)
                            points[i] = clamped.point
                            if clamped.clamped { clampedFlags[i] = true }
                            separatedFlags[i] = true
                            moved = true
                        }
                        if moveJ > 0 {
                            let raw = CGPoint(x: points[j].x + nx * moveJ, y: points[j].y + ny * moveJ)
                            let clamped = clampCenter(raw, size: markers[j].size, free: free)
                            points[j] = clamped.point
                            if clamped.clamped { clampedFlags[j] = true }
                            separatedFlags[j] = true
                            moved = true
                        }
                    }
                }
                if !moved { break }
            }
        }

        return markers.indices.map { idx in
            ResolvedMarker(
                id: markers[idx].id,
                point: points[idx],
                preferred: markers[idx].preferred,
                size: markers[idx].size,
                priority: markers[idx].priority,
                preferredInExclusion: preferredHits[idx],
                clampedToFreeRect: clampedFlags[idx],
                separatedFromPeers: separatedFlags[idx]
            )
        }
    }

    /// Result of projecting a world point into view.
    struct Projection: Equatable {
        /// In front of camera and inside the free (non-chrome) rect.
        var isOnScreen: Bool
        /// True when the target is behind the observer (do not draw a false on-image marker).
        var isBehind: Bool
        /// In front but outside free rect (edge indicator appropriate).
        var isOffFreeEdge: Bool
        var screenPoint: CGPoint
        /// Unit vector in screen space pointing toward the target when offscreen / under chrome / behind.
        var edgeDirection: CGPoint
        /// Preferred point lay outside free viewport (edge, chrome, or behind).
        var outsideFreeRect: Bool
    }

    /// Restrained exponential smoothing for screen points (presentation only — not world math).
    static func smoothScreenPoint(previous: CGPoint?, sample: CGPoint, alpha: CGFloat) -> CGPoint {
        guard let previous else { return sample }
        let a = min(1, max(0, alpha))
        return CGPoint(
            x: previous.x + (sample.x - previous.x) * a,
            y: previous.y + (sample.y - previous.y) * a
        )
    }

    /// Layout two celestial labels with opposite offsets + optional leader lines.
    /// Labels are never placed outside `free`. Prefer vertical split (Visible below, Actual above).
    static func layoutCelestialLabels(
        visibleMarker: CGPoint?,
        actualMarker: CGPoint?,
        free: CGRect,
        labelSize: CGSize = CGSize(width: 118, height: 28),
        defaultOffsetY: CGFloat = 36,
        minSeparation: CGFloat = 34
    ) -> (
        visibleLabel: CGPoint?,
        actualLabel: CGPoint?,
        visibleLeader: Bool,
        actualLeader: Bool
    ) {
        func base(for marker: CGPoint, preferBelow: Bool) -> CGPoint {
            let dy = preferBelow ? defaultOffsetY : -defaultOffsetY
            return CGPoint(x: marker.x, y: marker.y + dy)
        }

        var vLabel: CGPoint? = nil
        var aLabel: CGPoint? = nil
        var vLeader = false
        var aLeader = false

        if let vm = visibleMarker {
            let raw = base(for: vm, preferBelow: true)
            let clamped = clampCenter(raw, size: labelSize, free: free)
            vLabel = clamped.point
            vLeader = clamped.clamped || hypot(clamped.point.x - vm.x, clamped.point.y - vm.y) > defaultOffsetY * 0.6
        }
        if let am = actualMarker {
            let raw = base(for: am, preferBelow: false)
            let clamped = clampCenter(raw, size: labelSize, free: free)
            aLabel = clamped.point
            aLeader = clamped.clamped || hypot(clamped.point.x - am.x, clamped.point.y - am.y) > defaultOffsetY * 0.6
        }

        // Collision: opposite push, then re-clamp into free.
        if var vl = vLabel, var al = aLabel {
            let dx = al.x - vl.x
            let dy = al.y - vl.y
            let dist = hypot(dx, dy)
            if dist < minSeparation {
                // Force opposite vertical offsets relative to midpoint.
                let mid = CGPoint(x: (vl.x + al.x) * 0.5, y: (vl.y + al.y) * 0.5)
                let half = minSeparation * 0.55
                vl = clampCenter(CGPoint(x: mid.x, y: mid.y + half), size: labelSize, free: free).point
                al = clampCenter(CGPoint(x: mid.x, y: mid.y - half), size: labelSize, free: free).point
                // If still overlapping (tight free rect), separate horizontally.
                if markersCollide(
                    CGRect(x: vl.x - labelSize.width * 0.5, y: vl.y - labelSize.height * 0.5, width: labelSize.width, height: labelSize.height),
                    CGRect(x: al.x - labelSize.width * 0.5, y: al.y - labelSize.height * 0.5, width: labelSize.width, height: labelSize.height),
                    padding: 4
                ) {
                    vl = clampCenter(CGPoint(x: mid.x - half, y: mid.y + half * 0.35), size: labelSize, free: free).point
                    al = clampCenter(CGPoint(x: mid.x + half, y: mid.y - half * 0.35), size: labelSize, free: free).point
                }
                vLeader = true
                aLeader = true
                vLabel = vl
                aLabel = al
            }
        }

        return (vLabel, aLabel, vLeader, aLeader)
    }

    /// Convert NDC-ish projection helpers when a view size and 3D camera transform are known.
    /// `viewMatrix` is world-to-camera; `projectionMatrix` is camera-to-clip.
    /// `chrome` reserves toolbar / banner / bottom-sheet regions so labels edge-anchor
    /// instead of reporting “on screen” behind UI chrome.
    static func project(
        worldPoint: SIMD3<Float>,
        viewMatrix: float4x4,
        projectionMatrix: float4x4,
        viewSize: CGSize,
        chrome: ExclusionInsets = .defaultChrome
    ) -> Projection {
        let world4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let camera = viewMatrix * world4
        let clip = projectionMatrix * camera
        let free = freeRect(viewSize: viewSize, insets: chrome)
        let center = freeCenter(viewSize: viewSize, insets: chrome)

        guard abs(clip.w) > 1e-5 else {
            return Projection(
                isOnScreen: false,
                isBehind: true,
                isOffFreeEdge: false,
                screenPoint: center,
                edgeDirection: CGPoint(x: 0, y: -1),
                outsideFreeRect: true
            )
        }
        let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
        // ARKit camera looks down −Z; behind when z ≥ 0.
        let isBehind = camera.z >= 0
        let inFront = !isBehind
        let sx = (CGFloat(ndc.x) * 0.5 + 0.5) * viewSize.width
        let sy = (1.0 - (CGFloat(ndc.y) * 0.5 + 0.5)) * viewSize.height
        let point = CGPoint(x: sx, y: sy)

        let inFree = free.contains(point)
        let onScreen = inFront && inFree
        let offEdge = inFront && !inFree

        var dir = CGPoint(x: point.x - center.x, y: point.y - center.y)
        if isBehind {
            // Point the way to turn so the target comes into view.
            dir = CGPoint(x: -dir.x, y: -dir.y)
        }
        let len = hypot(dir.x, dir.y)
        if len < 1 {
            dir = CGPoint(x: 0, y: isBehind ? 1 : -1)
        } else {
            dir = CGPoint(x: dir.x / len, y: dir.y / len)
        }

        return Projection(
            isOnScreen: onScreen,
            isBehind: isBehind,
            isOffFreeEdge: offEdge,
            screenPoint: point,
            edgeDirection: dir,
            outsideFreeRect: !inFree || isBehind
        )
    }

    #if canImport(UIKit)
    /// UIKit convenience — forwards to `ExclusionInsets`.
    static func project(
        worldPoint: SIMD3<Float>,
        viewMatrix: float4x4,
        projectionMatrix: float4x4,
        viewSize: CGSize,
        chromeInsets: UIEdgeInsets
    ) -> Projection {
        project(
            worldPoint: worldPoint,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewSize: viewSize,
            chrome: ExclusionInsets(uiEdgeInsets: chromeInsets)
        )
    }
    #endif

    /// Place off-screen edge guides: preferred rim points → exclusion + collision resolve.
    static func resolveEdgeGuides(
        directions: [(id: String, direction: CGPoint, priority: Int)],
        viewSize: CGSize,
        insets: ExclusionInsets,
        markerSize: CGSize = CGSize(width: 96, height: 56)
    ) -> [ResolvedMarker] {
        let free = freeRect(viewSize: viewSize, insets: insets)
        let center = freeCenter(viewSize: viewSize, insets: insets)
        let radius = min(free.width, free.height) * 0.40
        let markers: [Marker] = directions.map { item in
            let len = hypot(item.direction.x, item.direction.y)
            let dx = len > 1e-4 ? item.direction.x / len : 0
            let dy = len > 1e-4 ? item.direction.y / len : -1
            let preferred = CGPoint(x: center.x + dx * radius, y: center.y + dy * radius)
            return Marker(id: item.id, preferred: preferred, size: markerSize, priority: item.priority)
        }
        return resolveMarkers(markers, viewSize: viewSize, insets: insets, padding: 10)
    }
}
