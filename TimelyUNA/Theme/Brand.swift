import SwiftUI

enum Brand {
    /// Canonical app and product name.
    static let appName = "TimelyUNA"

    /// Official singular product-facing name.
    static let productDisplayName = "TimelyUNA"

    /// Compact chrome / headers when space is limited.
    static let productShortName = "TimelyUNA"

    /// Navigation tab label (may stay shorter than full product name).
    static let productNavLabel = "Horizon"

    /// Opening studio credit (exact capitalization).
    static let studioCredit = "A QuantumRootz Studio"

    /// Studio mark for the first opening frame (exact spelling: Rootz ends in z).
    static let studioMark = "QuantumRootz"

    /// Supporting technology descriptor shown beneath the product name.
    static let technologyCredit = "Light-Time Engine"

    /// Closing dedication (exact capitalization).
    static let cosmicDedication = "Congruent with the Ancestors of the Cosmos"

    static let productDescriptor =
        "Light-Spacetime Sextant"

    static let tagline =
        "Because the Sun is always late to its own Dawn—from our perspective."

    static let thesis =
        "We do not see the universe as it is. We see it as its light arrives."

    static let expandedThesis =
        "Seeing is receiving. Every photon arrives carrying an earlier chapter of the universe."

    static let dawnLie =
        "Every Dawn tells the same beautiful lie: the Sun is not where you think it is."

    static let arrivalLine =
        "The Dawn is not lying. It is arriving."

    static let blackHoleLine =
        "A black hole is a star so bright it forgot to let go of its light."

    static let gold = Color(red: 0.83, green: 0.68, blue: 0.42)
    static let parchment = Color(red: 0.96, green: 0.91, blue: 0.76)
    static let paper = parchment
    static let background = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let panel = Color(red: 0.09, green: 0.075, blue: 0.065)
}

/// Full Dynamic Type–aware Papyrus scale for TimelyUNA UI.
enum TimelyUNAFont {
    static let extraLargeTitle = Font.custom(
        "Papyrus",
        size: 42,
        relativeTo: .largeTitle
    )

    static let largeTitle = Font.custom(
        "Papyrus",
        size: 34,
        relativeTo: .largeTitle
    )

    static let title = Font.custom(
        "Papyrus",
        size: 28,
        relativeTo: .title
    )

    static let title2 = Font.custom(
        "Papyrus",
        size: 22,
        relativeTo: .title2
    )

    static let title3 = Font.custom(
        "Papyrus",
        size: 20,
        relativeTo: .title3
    )

    static let headline = Font.custom(
        "Papyrus",
        size: 17,
        relativeTo: .headline
    )

    static let body = Font.custom(
        "Papyrus",
        size: 17,
        relativeTo: .body
    )

    static let callout = Font.custom(
        "Papyrus",
        size: 16,
        relativeTo: .callout
    )

    static let subheadline = Font.custom(
        "Papyrus",
        size: 15,
        relativeTo: .subheadline
    )

    static let footnote = Font.custom(
        "Papyrus",
        size: 13,
        relativeTo: .footnote
    )

    static let caption = Font.custom(
        "Papyrus",
        size: 12,
        relativeTo: .caption
    )

    static let caption2 = Font.custom(
        "Papyrus",
        size: 11,
        relativeTo: .caption2
    )

    /// Fixed Papyrus sizes (do not scale with Dynamic Type).
    static let fixedBody = Font.custom("Papyrus", fixedSize: 18)
    static let fixedHeadline = Font.custom("Papyrus", fixedSize: 17)
    static let fixedCaption = Font.custom("Papyrus", fixedSize: 12)
}

/// Size-based Papyrus helpers (legacy call sites).
enum PapyrusFont {
    static func regular(_ size: CGFloat) -> Font {
        .custom("Papyrus", size: size, relativeTo: .body)
    }

    static func condensed(_ size: CGFloat) -> Font {
        .custom("Papyrus-Condensed", size: size, relativeTo: .body)
    }

    /// Prefer semantic roles from `TimelyUNAFont`.
    static var title: Font { TimelyUNAFont.largeTitle }
    static var heading: Font { TimelyUNAFont.title2 }
    static var body: Font { TimelyUNAFont.body }
    static var caption: Font { TimelyUNAFont.caption }
}
