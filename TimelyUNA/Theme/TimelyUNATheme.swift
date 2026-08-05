import SwiftUI

/// TimelyUNA's shared palette and semantic Papyrus typography.
enum TimelyUNATheme {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let papyrus = Color(red: 0.961, green: 0.910, blue: 0.780)
    static let gold = Color(red: 0.957, green: 0.851, blue: 0.627)
    static let accent = Color(red: 0.788, green: 0.643, blue: 0.431)
    static let accentMuted = Color(red: 0.545, green: 0.435, blue: 0.278)
    static let panel = Color(red: 0.118, green: 0.098, blue: 0.078).opacity(0.92)
    static let apparentSun = Color(red: 1.0, green: 0.667, blue: 0.2)
    static let actualSun = Color(red: 1.0, green: 0.8, blue: 0.4)
    static let earthBlue = Color(red: 0.227, green: 0.482, blue: 0.835)
    static let earthGreen = Color(red: 0.165, green: 0.353, blue: 0.165)

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
}
