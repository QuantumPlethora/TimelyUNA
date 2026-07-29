import SwiftUI

/// Papyrus-inspired palette matching the HTML proof of concept.
enum TimelyUNATheme {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059) // #0a0a0f
    static let papyrus = Color(red: 0.961, green: 0.910, blue: 0.780) // #f5e8c7
    static let gold = Color(red: 0.957, green: 0.851, blue: 0.627) // #f4d9a0
    static let accent = Color(red: 0.788, green: 0.643, blue: 0.431) // #c9a46e
    static let accentMuted = Color(red: 0.545, green: 0.435, blue: 0.278) // #8b6f47
    static let panel = Color(red: 0.118, green: 0.098, blue: 0.078).opacity(0.92)
    static let apparentSun = Color(red: 1.0, green: 0.667, blue: 0.2) // #ffaa33
    static let actualSun = Color(red: 1.0, green: 0.8, blue: 0.4) // #ffcc66
    static let earthBlue = Color(red: 0.227, green: 0.482, blue: 0.835) // #3a7bd5
    static let earthGreen = Color(red: 0.165, green: 0.353, blue: 0.165)

    static var titleFont: Font {
        .system(.largeTitle, design: .serif).weight(.bold)
    }

    static var sectionFont: Font {
        .system(.title2, design: .serif).weight(.semibold)
    }

    static var bodyFont: Font {
        .system(.body, design: .serif)
    }

    static var captionFont: Font {
        .system(.caption, design: .serif)
    }

    static var buttonFont: Font {
        .system(.headline, design: .serif).weight(.bold)
    }
}
