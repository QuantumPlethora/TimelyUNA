import SwiftUI

struct SunSextantView: View {
    @EnvironmentObject private var simulation: SimulationState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingARSunrise = false

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Intro copy — final words ("between them.") must clear the bottom nav via
                // safeAreaInset on the shell + this explicit trailing content padding.
                Text("We do not see the universe as it is — we see it as its light arrives. Correct for Light-SpaceTime. Reveal Apparent Now, Actual Position, and the Lightline between them.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)

                demoLabel

                HStack(alignment: .firstTextBaseline) {
                    Text("The Sun We See vs. The Sun That Is")
                        .font(TimelyUNATheme.sectionFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Light-SpaceTime")
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.accent.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(LightTimeConstants.sunLightTravelDescription)
                            .font(TimelyUNATheme.subheadingFont)
                            .foregroundStyle(TimelyUNATheme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                // Simulation + info: stack on compact iPhone; side-by-side when wide enough.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        simulationPanel
                            .frame(minWidth: 300, maxWidth: .infinity)
                            .frame(minHeight: 300)
                        infoColumn
                            .frame(width: 280)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        simulationPanel
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: isCompact ? 280 : 300)
                        infoColumn
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // Clear fixed bottom navigation (shell provides safeAreaInset; this adds breathing room).
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TimelyUNATheme.background.ignoresSafeArea().allowsHitTesting(false))
        // Tab/nav chrome only — primary engine title is the Papyrus header below.
        .navigationTitle("Sextant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingARSunrise) {
            ARSunRocketView(selectedDate: Date())
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TimelyUNATheme.accent, TimelyUNATheme.accentMuted],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Text("☉")
                    .font(.system(size: 26))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("TIMELYUNA")
                    .font(TimelyUNATheme.titleFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("LIGHT-SPACETIME SEXTANT")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.accent)
                    .tracking(1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 4)
            Text("v\(LightTimeConstants.appVersionLabel)")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.accent.opacity(0.7))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TimelyUNA Light-Spacetime Sextant, version \(LightTimeConstants.appVersionLabel)")
    }

    private var demoLabel: some View {
        Text("DAWN-FIRST DEMONSTRATION")
            .font(TimelyUNATheme.smallCaptionFont)
            .tracking(2)
            .foregroundStyle(TimelyUNATheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(TimelyUNATheme.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    /// Simulation frame with reserved chrome band (title + LIVE badge) above the canvas.
    private var simulationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            simulationChrome
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

            SunCanvasView(
                rocketProgress: simulation.rocketProgress,
                showRocket: simulation.isRocketFlying || simulation.rocketProgress > 0,
                showHit: simulation.showRocketHit,
                drawsChromeLabels: false
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: isCompact ? 220 : 250)
            .layoutPriority(1)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TimelyUNATheme.accent, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Sun Light-SpaceTime live simulation showing Earth, Apparent Sun, Actual Sun, light delay, and true direction"
        )
    }

    /// Reserved vertical region so the LIVE badge never covers the title.
    private var simulationChrome: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TIMELYUNA LIGHT-TIME LIVE SIMULATION")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.gold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text("Correcting for the finite speed of light")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .foregroundStyle(TimelyUNATheme.gold.opacity(0.85))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("LIVE SIMULATION")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 9 : 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(TimelyUNATheme.papyrus)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(TimelyUNATheme.accent.opacity(0.5), lineWidth: 1)
                )
                .fixedSize(horizontal: true, vertical: true)
                .accessibilityLabel("Live simulation")
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
                AppHaptics.selection()
                showingARSunrise = true
            } label: {
                Label("OPEN AR SUNRISE", systemImage: "arkit")
            }
            .buttonStyle(AncientButtonStyle())
            .frame(minHeight: 44)
            .accessibilityHint("Opens the camera experience showing Apparent Now, Actual Position, and the Lightline")

            Button {
                AppHaptics.selection()
                simulation.launchRocket()
            } label: {
                Label("LAUNCH BABY SPCX ROCKET", systemImage: "airplane.departure")
            }
            .buttonStyle(AncientButtonStyle())
            .frame(minHeight: 44)
            .disabled(simulation.isRocketFlying)
            .accessibilityHint("Launches a rocket toward Actual Position, correcting for Light-SpaceTime")

            Text("In AR, point toward the horizon and tap the scene to launch Baby X along the Lightline toward Actual Position.")
                .font(TimelyUNATheme.captionFont)
                .foregroundStyle(TimelyUNATheme.accent.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
