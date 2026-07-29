import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var simulation: SimulationState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("This is only the beginning.")
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .multilineTextAlignment(.center)

                Text("TimelyUNA is a living concept — a light-time sextant that reveals the true positions of stars and planets by correcting for the finite speed of light, with playful extensions into deep-time observation and guided rocket navigation.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    aboutRow(title: "Sun light delay", value: LightTimeConstants.sunLightTravelDescription)
                    aboutRow(title: "Demo angular offset", value: "~\(Int(LightTimeConstants.demoAngularOffsetDegrees))° (educational)")
                    aboutRow(title: "Chronos distance", value: LightTimeConstants.chronosDistanceLabel)
                    aboutRow(title: "Version", value: LightTimeConstants.appVersionLabel)
                    aboutRow(title: "Creator", value: LightTimeConstants.creatorCredit)
                    aboutRow(title: "Domain", value: LightTimeConstants.domain)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TimelyUNATheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(TimelyUNATheme.accent, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                ShareLink(item: LightTimeConstants.shareText) {
                    Label(
                        simulation.showShareCopied ? "READY TO SHARE" : "SHARE TIMELYUNA",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(AncientButtonStyle(filled: true))
                .simultaneousGesture(TapGesture().onEnded {
                    simulation.markShareCopied()
                })

                Text("If you are a developer who dreams in photons and code, a designer who sees beauty in time itself, or someone who simply believes the invisible should be made visible — the door is open. The universe doesn’t wait. Neither should we.")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.accent.opacity(0.75))
                    .multilineTextAlignment(.center)

                Text("Educational simulation • Not scientific instrumentation\nMade with curiosity for the Apple ecosystem")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(TimelyUNATheme.accent.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(TimelyUNATheme.background.ignoresSafeArea())
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.accent)
            Spacer()
            Text(value)
                .font(TimelyUNATheme.bodyFont.weight(.semibold))
                .foregroundStyle(TimelyUNATheme.gold)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .environmentObject(SimulationState())
}
