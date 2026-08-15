import SwiftUI

/// Adaptive crop / scale for the QuantumRootz opening still.
/// Source art is a tall ~1:2 portrait (887×1774). Never stretched.
struct OpeningArtworkPresentation: Equatable {
    /// Native still aspect (width / height).
    static let sourceAspect: CGFloat = 887.0 / 1774.0

    enum CanvasClass: Equatable {
        case phonePortrait
        case phoneLandscape
        case padPortrait
        case padLandscape
        case macStandard
        case macUltrawide
    }

    /// When true, the full still is letterboxed (no crop). Used only for extreme wide canvases.
    let letterboxed: Bool
    /// Unit-space focal point inside the source still (0,0 = top-leading).
    let focal: UnitPoint
    let canvasClass: CanvasClass

    static func classify(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> CanvasClass {
        let w = max(1, size.width)
        let h = max(1, size.height)
        let aspect = w / h
        #if os(macOS)
        return aspect >= 2.15 ? .macUltrawide : .macStandard
        #else
        let compact = horizontalSizeClass == .compact
        if compact {
            return aspect >= 1.05 ? .phoneLandscape : .phonePortrait
        }
        return aspect >= 1.05 ? .padLandscape : .padPortrait
        #endif
    }

    static func resolve(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> OpeningArtworkPresentation {
        let klass = classify(size: size, horizontalSizeClass: horizontalSizeClass)
        switch klass {
        case .phonePortrait:
            return OpeningArtworkPresentation(letterboxed: false, focal: UnitPoint(x: 0.50, y: 0.42), canvasClass: klass)
        case .phoneLandscape:
            return OpeningArtworkPresentation(letterboxed: false, focal: UnitPoint(x: 0.50, y: 0.46), canvasClass: klass)
        case .padPortrait:
            return OpeningArtworkPresentation(letterboxed: false, focal: UnitPoint(x: 0.50, y: 0.44), canvasClass: klass)
        case .padLandscape:
            return OpeningArtworkPresentation(letterboxed: false, focal: UnitPoint(x: 0.50, y: 0.47), canvasClass: klass)
        case .macStandard:
            return OpeningArtworkPresentation(letterboxed: false, focal: UnitPoint(x: 0.50, y: 0.46), canvasClass: klass)
        case .macUltrawide:
            // Source has almost no horizontal overscan (~1:2). Ultrawide fill would crop the
            // S-curve to a sliver — letterbox instead of distorting or emptying the subject.
            return OpeningArtworkPresentation(letterboxed: true, focal: UnitPoint(x: 0.50, y: 0.50), canvasClass: klass)
        }
    }

    /// Destination rect for the still inside `canvas`. Aspect of the image is preserved.
    func imageFrame(in canvas: CGSize) -> CGRect {
        let cw = max(1, canvas.width)
        let ch = max(1, canvas.height)
        let src = Self.sourceAspect

        if letterboxed {
            let canvasAspect = cw / ch
            if canvasAspect > src {
                let h = ch
                let w = h * src
                return CGRect(x: (cw - w) * 0.5, y: 0, width: w, height: h)
            } else {
                let w = cw
                let h = w / src
                return CGRect(x: 0, y: (ch - h) * 0.5, width: w, height: h)
            }
        }

        let canvasAspect = cw / ch
        if canvasAspect > src {
            // Wider than the still: fill width, crop height around focal.y.
            let w = cw
            let h = w / src
            let y = (ch - h) * focal.y
            return CGRect(x: 0, y: y, width: w, height: h)
        } else {
            // Taller / narrower: fill height, crop width around focal.x.
            let h = ch
            let w = h * src
            let x = (cw - w) * focal.x
            return CGRect(x: x, y: 0, width: w, height: h)
        }
    }
}
