import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// TimelyUNA shared palette and Papyrus typography.
/// Palette mirrors macsafedevelopersapple.io: black, warm cream, electric yellow-green, orange, cosmic purple.
enum TimelyUNATheme {
    // MARK: Surfaces
    static let background = Color(red: 0.027, green: 0.035, blue: 0.071) // #070912
    static let backgroundDeep = Color.black
    static let panel = Color(red: 0.067, green: 0.078, blue: 0.125).opacity(0.92) // #111420
    static let panelWarm = Color(red: 0.098, green: 0.098, blue: 0.082) // ritual #191915
    static let ritualSky = Color(red: 0.071, green: 0.071, blue: 0.059) // #12120f

    // MARK: Type colors
    static let papyrus = Color(red: 0.973, green: 0.929, blue: 0.812) // #f8edcf
    static let cream = Color(red: 0.949, green: 0.937, blue: 0.902) // #f2efe6
    static let muted = Color(red: 0.788, green: 0.745, blue: 0.639) // #c9bea3
    static let ink = Color(red: 0.090, green: 0.090, blue: 0.075)

    // MARK: Accents
    static let gold = Color(red: 0.957, green: 0.851, blue: 0.624) // #f4d99f
    static let goldDeep = Color(red: 0.835, green: 0.682, blue: 0.412) // #d5ae69
    static let accent = goldDeep
    static let accentMuted = Color(red: 0.545, green: 0.435, blue: 0.278)
    static let acid = Color(red: 0.851, green: 1.0, blue: 0.263) // #d9ff43 electric yellow-green
    static let orange = Color(red: 1.0, green: 0.420, blue: 0.208) // #ff6b35
    static let cosmicPurple = Color(red: 0.514, green: 0.404, blue: 0.910) // #8367e8
    static let blue = Color(red: 0.471, green: 0.741, blue: 0.910) // #78bde8
    static let mars = Color(red: 0.867, green: 0.459, blue: 0.290) // #dd754a

    // MARK: Sun markers
    static let apparentSun = Color(red: 1.0, green: 0.667, blue: 0.2)
    static let actualSun = acid
    static let earthBlue = Color(red: 0.227, green: 0.482, blue: 0.835)
    static let earthGreen = Color(red: 0.165, green: 0.353, blue: 0.165)

    // MARK: Lines
    static let line = goldDeep.opacity(0.42)

    // MARK: Papyrus type scale
    static let displayFont = Font.custom("Papyrus", size: 40, relativeTo: .largeTitle)
    static let titleFont = Font.custom("Papyrus", size: 32, relativeTo: .largeTitle)
    static let sectionFont = Font.custom("Papyrus", size: 24, relativeTo: .title2)
    static let subheadingFont = Font.custom("Papyrus", size: 20, relativeTo: .title3)
    static let headlineFont = Font.custom("Papyrus", size: 17, relativeTo: .headline)
    static let bodyFont = Font.custom("Papyrus", size: 17, relativeTo: .body)
    static let calloutFont = Font.custom("Papyrus", size: 16, relativeTo: .callout)
    static let captionFont = Font.custom("Papyrus", size: 13, relativeTo: .caption)
    static let smallCaptionFont = Font.custom("Papyrus", size: 11, relativeTo: .caption2)
    static let buttonFont = Font.custom("Papyrus", size: 18, relativeTo: .headline)
    static let metricFont = Font.custom("Papyrus", size: 28, relativeTo: .title)
    static let heroMetricFont = Font.custom("Papyrus", size: 42, relativeTo: .largeTitle)
}

enum TimelyUNAGlass {
    static let tabCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 13
}

extension View {
    func timelyUNAGlassGroup(spacing: CGFloat = 8) -> some View {
        modifier(TimelyUNAGlassGroupModifier(spacing: spacing))
    }

    func timelyUNAGlassSurface(
        cornerRadius: CGFloat = TimelyUNAGlass.controlCornerRadius,
        tint: Color = TimelyUNATheme.gold,
        backing: Color = .black,
        backingOpacity: Double = 0.34,
        stroke: Color = TimelyUNATheme.line,
        strokeOpacity: Double = 1,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            TimelyUNAGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                backing: backing,
                backingOpacity: backingOpacity,
                stroke: stroke,
                strokeOpacity: strokeOpacity,
                isInteractive: isInteractive
            )
        )
    }
}

private struct TimelyUNAGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct TimelyUNAGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    let backing: Color
    let backingOpacity: Double
    let stroke: Color
    let strokeOpacity: Double
    let isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesSolidFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    private var effectiveBackingOpacity: Double {
        if usesSolidFallback {
            min(1, max(backingOpacity, 0.82))
        } else {
            backingOpacity
        }
    }

    private var effectiveStrokeOpacity: Double {
        if colorSchemeContrast == .increased {
            return min(1, max(strokeOpacity, 0.92))
        }
        return strokeOpacity
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if usesSolidFallback {
            content
                .background(backing.opacity(effectiveBackingOpacity), in: shape)
                .overlay(shape.stroke(stroke.opacity(effectiveStrokeOpacity), lineWidth: 1.25))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background(backing.opacity(effectiveBackingOpacity), in: shape)
                .glassEffect(
                    .regular
                        .tint(tint.opacity(0.42))
                        .interactive(isInteractive),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay(shape.stroke(stroke.opacity(effectiveStrokeOpacity), lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(backing.opacity(effectiveBackingOpacity), in: shape)
                .overlay(shape.stroke(stroke.opacity(effectiveStrokeOpacity), lineWidth: 1))
        }
    }
}

/// One medium impact for deliberate button and tab activations.
/// UIKit honors the device's system haptic settings; macOS is a silent no-op.
@MainActor
enum AppHaptics {
    static func selection() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
