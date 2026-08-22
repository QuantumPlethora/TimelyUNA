import SwiftUI

struct InfoCard: View {
    let indicator: Color
    let title: String
    let bodyText: AttributedString

    init(indicator: Color, title: String, body: String, emphasis: String? = nil) {
        self.indicator = indicator
        self.title = title
        var attr = AttributedString(body)
        if let emphasis, let range = attr.range(of: emphasis) {
            attr[range].font = .system(.body, design: .serif).weight(.semibold)
        }
        self.bodyText = attr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(indicator)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(TimelyUNATheme.captionFont.weight(.semibold))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .tracking(1.2)
            }
            Text(bodyText)
                .font(TimelyUNATheme.bodyFont)
                .foregroundStyle(TimelyUNATheme.papyrus)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TimelyUNATheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(TimelyUNATheme.accent, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct AncientButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TimelyUNATheme.buttonFont)
            .foregroundStyle(filled ? TimelyUNATheme.background : TimelyUNATheme.gold)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .timelyUNAGlassSurface(
                cornerRadius: 14,
                tint: filled ? TimelyUNATheme.acid : TimelyUNATheme.gold,
                backing: filled ? TimelyUNATheme.accent : TimelyUNATheme.background,
                backingOpacity: filled ? 0.78 : 0.46,
                stroke: TimelyUNATheme.accent,
                strokeOpacity: filled ? 0.86 : 0.72,
                isInteractive: true
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
