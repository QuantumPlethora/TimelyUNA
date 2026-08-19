import SwiftUI

struct ChronosModeView: View {
    @EnvironmentObject private var simulation: SimulationState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("DEMONSTRATION TWO")
                    .font(TimelyUNATheme.smallCaptionFont)
                    .tracking(1.5)
                    .foregroundStyle(TimelyUNATheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TimelyUNATheme.accent.opacity(0.12))
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Chronos Mode")
                        .font(TimelyUNATheme.sectionFont)
                        .foregroundStyle(TimelyUNATheme.gold)

                    Text("Quantum Telescope • \(LightTimeConstants.chronosDistanceLabel)")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.accent)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("That equals \(LightTimeConstants.chronosEraLabel) on Earth.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                }

                DisclosureGroup("How Chronos Mode works") {
                    Text("By theoretically relocating our vantage point 65 million light-years away, we could look back across the gulf of SpaceTime. Light that left Earth 65 million years ago would only now be reaching that distant point.")
                        .font(TimelyUNATheme.bodyFont)
                        .foregroundStyle(TimelyUNATheme.papyrus)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .font(TimelyUNATheme.headlineFont)
                .foregroundStyle(TimelyUNATheme.accent)
                .padding(16)
                .background(TimelyUNATheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(TimelyUNATheme.accent, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        controls.frame(maxWidth: 340)
                        canvas
                            .frame(minWidth: 300, maxWidth: .infinity)
                            .frame(height: 320)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        controls
                        canvas.frame(height: compactCanvasHeight)
                    }
                }

                if simulation.chronosPhase != .idle {
                    Button("Reset Chronos Mode") {
                        AppHaptics.selection()
                        simulation.resetChronos()
                    }
                    .buttonStyle(AncientButtonStyle())
                    .accessibilityHint("Returns the quantum telescope demonstration to its starting state")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            // The shell owns the bottom tab bar. Extra trailing space lets the final
            // reset control rest fully above it on compact iPhones.
            .padding(.bottom, bottomScrollClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TimelyUNATheme.background.ignoresSafeArea())
        .navigationTitle("Chronos Mode")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var compactCanvasHeight: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .compact ? 340 : 300
        #else
        return 300
        #endif
    }

    private var bottomScrollClearance: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .compact ? 112 : 36
        #else
        return 36
        #endif
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                AppHaptics.selection()
                simulation.engageQuantumJump()
            } label: {
                Label("ENGAGE QUANTUM JUMP", systemImage: "atom")
                    .font(TimelyUNATheme.buttonFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(AncientButtonStyle(filled: simulation.chronosPhase == .idle))
            .disabled(simulation.chronosPhase != .idle)
            .accessibilityHint("Jumps your vantage point 65 million light-years from Earth")

            if simulation.chronosPhase != .idle {
                VStack(spacing: 7) {
                    Text("QUANTUM ENTANGLEMENT STABLE")
                        .font(TimelyUNATheme.smallCaptionFont)
                        .tracking(1.2)
                        .foregroundStyle(TimelyUNATheme.accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Text("65,000,000 LIGHT YEARS FROM EARTH")
                        .font(TimelyUNATheme.subheadingFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You are now seeing the universe from the Cretaceous period’s perspective.")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.papyrus.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(TimelyUNATheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TimelyUNATheme.accent, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if simulation.chronosPhase == .jumped || simulation.chronosPhase == .telescopeActive {
                Button {
                    AppHaptics.selection()
                    simulation.deployTelescope()
                } label: {
                    Label(
                        simulation.chronosPhase == .telescopeActive
                            ? "TELESCOPE LOCKED\nDINOSAUR ERA ACTIVE"
                            : "DEPLOY IMPROBABLE\nQUANTUM TELESCOPE",
                        systemImage: "binoculars.fill"
                    )
                    .font(TimelyUNATheme.buttonFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(AncientButtonStyle())
                .disabled(simulation.chronosPhase == .telescopeActive)
                .opacity(simulation.chronosPhase == .telescopeActive ? 0.85 : 1)
                .accessibilityHint("Deploys a quantum telescope looking back at Cretaceous Earth")
            }
        }
        .animation(.easeInOut(duration: 0.35), value: simulation.chronosPhase)
    }

    private var canvas: some View {
        VStack(spacing: 8) {
            ChronosCanvasView(phase: simulation.chronosPhase)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TimelyUNATheme.accent, lineWidth: 2))
                .shadow(
                    color: simulation.chronosPhase != .idle ? TimelyUNATheme.accent.opacity(0.45) : .clear,
                    radius: 12
                )
                .accessibilityLabel(chronoAccessibilityLabel)

            if simulation.chronosPhase != .idle {
                Text("Looking back through 65 million years of light...")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.accent.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chronoAccessibilityLabel: String {
        switch simulation.chronosPhase {
        case .idle:
            return "Deep space view awaiting quantum jump"
        case .jumped:
            return "View from 65 million light years away, showing distant Earth"
        case .telescopeActive:
            return "Artistic Cretaceous landscape with dinosaurs"
        }
    }
}

#Preview {
    NavigationStack { ChronosModeView() }
        .environmentObject(SimulationState())
}
