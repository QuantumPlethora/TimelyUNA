import Foundation

/// Educational constants for the light-time sextant demo.
/// Dynamic distance/delay live in `SolarEngine`; these remain as mean-value labels for static UI copy.
enum LightTimeConstants {
    /// Mean light travel time from the Sun to Earth (~AU / c).
    static let sunLightTravelSeconds: Double = SolarEngine.lightSecondsPerAU // ~8 min 19 s

    static var sunLightTravelDescription: String {
        let minutes = Int(sunLightTravelSeconds) / 60
        let seconds = Int(sunLightTravelSeconds) % 60
        return "\(minutes) minutes \(seconds) seconds"
    }

    /// Approximate angular offset used in the visual demo (degrees).
    /// Real light-time aberration is more subtle; this exaggerates for teaching.
    static let demoAngularOffsetDegrees: Double = 2.0

    /// Thought-experiment distance for Chronos Mode.
    static let chronosLightYears: Double = 65_000_000

    static var chronosDistanceLabel: String {
        "65,000,000 light years"
    }

    static var chronosEraLabel: String {
        "65 million years ago"
    }

    static let appVersionLabel = "1.0.0"
    static let creatorCredit = "Craig (QuantumCentz)"
    static let domain = "macsafedevelopersapple.io"

    static let shareText = """
    Just explored TimelyUNA — a light-time sextant that shows the Sun where it *actually* is vs where its \(sunLightTravelDescription)-old light says it is. Then Chronos Mode jumps 65 million light-years to hang with dinosaurs. Mind-bending.

    #TimelyUNA #LightTime #SpaceTech #SwiftUI
    """
}
