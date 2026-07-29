import SwiftUI

struct SunSextantView: View {
    @EnvironmentObject private var simulation: SimulationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Text("See the cosmos as it truly is — not as its light claims it was. Correct for the speed of light. Launch rockets on true trajectories.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                demoLabel

                HStack(alignment: .firstTextBaseline) {
                    Text("The Sun We See vs. The Sun That Is")
                        .font(TimelyUNATheme.sectionFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Light travel time")
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.accent.opacity(0.8))
                        Text(LightTimeConstants.sunLightTravelDescription)
                            .font(.system(.title3, design: .serif).weight(.bold))
                            .foregroundStyle(TimelyUNATheme.gold)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        sunCanvas
                            .frame(minWidth: 320, maxWidth: .infinity)
                            .frame(height: 320)
                        infoColumn
                            .frame(width: 280)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        sunCanvas
                            .frame(height: 300)
                        infoColumn
                    }
                }
            }
            .padding(20)
        }
        .background(TimelyUNATheme.background.ignoresSafeArea())
        .navigationTitle("TimelyUNA")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TimelyUNATheme.accent, TimelyUNATheme.accentMuted],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Text("☉")
                    .font(.system(size: 28))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TIMELYUNA")
                    .font(TimelyUNATheme.titleFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .tracking(2)
                Text("LIGHT-TIME SEXTANT")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.accent)
                    .tracking(2)
            }
            Spacer()
            Text("v\(LightTimeConstants.appVersionLabel)")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.accent.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TimelyUNA light-time sextant, version \(LightTimeConstants.appVersionLabel)")
    }

    private var demoLabel: some View {
        Text("DEMONSTRATION ONE")
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .tracking(2)
            .foregroundStyle(TimelyUNATheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(TimelyUNATheme.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    private var sunCanvas: some View {
        ZStack(alignment: .topTrailing) {
            SunCanvasView(
                rocketProgress: simulation.rocketProgress,
                showRocket: simulation.isRocketFlying || simulation.rocketProgress > 0,
                showHit: simulation.showRocketHit
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(TimelyUNATheme.accent, lineWidth: 2)
            )
            .accessibilityLabel("Sun light-time simulation showing Earth, apparent Sun, and actual Sun positions")

            Text("LIVE SIMULATION")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(TimelyUNATheme.papyrus)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(TimelyUNATheme.accent.opacity(0.5), lineWidth: 1)
                )
                .padding(10)
        }
    }

    private var infoColumn: some View {
        VStack(spacing: 14) {
            InfoCard(
                indicator: TimelyUNATheme.gold,
                title: "APPARENT POSITION",
                body: "Where the Sun appears to be right now. This is the light that left the Sun \(LightTimeConstants.sunLightTravelDescription) ago.",
                emphasis: "appears"
            )
            InfoCard(
                indicator: TimelyUNATheme.actualSun,
                title: "ACTUAL POSITION",
                body: "Where the Sun actually is at this very moment. TimelyUNA reveals the truth the naked eye cannot see.",
                emphasis: "actually"
            )
            InfoCard(
                indicator: TimelyUNATheme.accent,
                title: "WHY IT MATTERS",
                body: "Because Earth is moving in its orbit, by the time the Sun’s light reaches us, the Sun has already moved forward. The difference is small (~\(Int(LightTimeConstants.demoAngularOffsetDegrees))° in this demo), but it matters for precision navigation, astronomy, and truth."
            )

            Button {
                simulation.launchRocket()
            } label: {
                Label("LAUNCH BABY SPCX ROCKET", systemImage: "airplane.departure")
            }
            .buttonStyle(AncientButtonStyle())
            .disabled(simulation.isRocketFlying)
            .accessibilityHint("Launches a rocket toward the true current position of the Sun, correcting for light delay")

            Text("The rocket flies to the actual position — correcting for light delay in real time.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.accent.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        SunSextantView()
    }
    .environmentObject(SimulationState())
}
