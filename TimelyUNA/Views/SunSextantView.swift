import SwiftUI

struct SunSextantView: View {
    @EnvironmentObject private var simulation: SimulationState
    @State private var showingARSunrise = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Text("We do not see the universe as it is — we see it as its light arrives. Correct for Light-SpaceTime. Reveal Apparent Now, Actual Position, and the Lightline between them.")
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
                        Text("Light-SpaceTime")
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
        .sheet(isPresented: $showingARSunrise) {
            ARSunRocketView(selectedDate: Date())
        }
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
                Text("LIGHT-SPACETIME SEXTANT")
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
        .accessibilityLabel("TimelyUNA Light-SpaceTime Sextant, version \(LightTimeConstants.appVersionLabel)")
    }

    private var demoLabel: some View {
        Text("DAWN-FIRST DEMONSTRATION")
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
            .accessibilityLabel("Sun Light-SpaceTime simulation showing Earth, Apparent Now, Actual Position, and the SpaceTime Offset")

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
                title: "APPARENT NOW",
                body: "Where arriving light makes the Sun appear. This Photon Stamp left the Sun \(LightTimeConstants.sunLightTravelDescription) ago.",
                emphasis: "appear"
            )
            InfoCard(
                indicator: TimelyUNATheme.actualSun,
                title: "ACTUAL POSITION",
                body: "A calculated later position after accounting for Light-SpaceTime. TimelyUNA reveals what direct sight cannot deliver live.",
                emphasis: "calculated"
            )
            InfoCard(
                indicator: TimelyUNATheme.accent,
                title: "SPACETIME OFFSET",
                body: "The difference between Apparent Now and Actual Position. The AR demonstration exaggerates the visual separation so learners can clearly see the concept."
            )

            Button {
                showingARSunrise = true
            } label: {
                Label("OPEN AR SUNRISE", systemImage: "arkit")
            }
            .buttonStyle(AncientButtonStyle())
            .accessibilityHint("Opens the camera experience showing Apparent Now, Actual Position, and the Lightline")

            Button {
                simulation.launchRocket()
            } label: {
                Label("LAUNCH BABY SPCX ROCKET", systemImage: "airplane.departure")
            }
            .buttonStyle(AncientButtonStyle())
            .disabled(simulation.isRocketFlying)
            .accessibilityHint("Launches a rocket toward Actual Position, correcting for Light-SpaceTime")

            Text("In AR, point toward the horizon and tap the scene to launch Baby X along the Lightline toward Actual Position.")
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
