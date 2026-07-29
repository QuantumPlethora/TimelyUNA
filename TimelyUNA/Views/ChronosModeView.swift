import SwiftUI

struct ChronosModeView: View {
    @EnvironmentObject private var simulation: SimulationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("DEMONSTRATION TWO")
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(TimelyUNATheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TimelyUNATheme.accent.opacity(0.12))
                    .clipShape(Capsule())

                HStack(alignment: .firstTextBaseline) {
                    Text("Chronos Mode • Quantum Telescope")
                        .font(TimelyUNATheme.sectionFont)
                        .foregroundStyle(TimelyUNATheme.gold)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(LightTimeConstants.chronosDistanceLabel)
                            .font(TimelyUNATheme.captionFont)
                            .foregroundStyle(TimelyUNATheme.accent.opacity(0.85))
                        Text("= \(LightTimeConstants.chronosEraLabel) on Earth")
                            .font(TimelyUNATheme.captionFont.weight(.semibold))
                            .foregroundStyle(TimelyUNATheme.gold)
                    }
                }

                Text("By using (theoretically) quantum entanglement to instantaneously relocate our vantage point 65 million light-years away, we can look back across the gulf of space and time. The light that left Earth 65 million years ago is only now reaching that distant point. A sufficiently advanced quantum telescope could therefore observe the dinosaurs in their own era.")
                    .font(TimelyUNATheme.bodyFont)
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .padding(16)
                    .background(TimelyUNATheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(TimelyUNATheme.accent, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        controls
                            .frame(maxWidth: 340)
                        canvas
                            .frame(minWidth: 300, maxWidth: .infinity)
                            .frame(height: 320)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        controls
                        canvas
                            .frame(height: 300)
                    }
                }

                if simulation.chronosPhase != .idle {
                    Button("Reset Chronos Mode") {
                        simulation.resetChronos()
                    }
                    .buttonStyle(AncientButtonStyle())
                    .accessibilityHint("Returns the quantum telescope demonstration to its starting state")
                }
            }
            .padding(20)
        }
        .background(TimelyUNATheme.background.ignoresSafeArea())
        .navigationTitle("Chronos Mode")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                simulation.engageQuantumJump()
            } label: {
                Label("ENGAGE QUANTUM JUMP", systemImage: "atom")
                    .font(TimelyUNATheme.buttonFont)
            }
            .buttonStyle(AncientButtonStyle(filled: simulation.chronosPhase == .idle))
            .disabled(simulation.chronosPhase != .idle)
            .accessibilityHint("Jumps your vantage point 65 million light-years from Earth")

            if simulation.chronosPhase != .idle {
                VStack(spacing: 6) {
                    Text("QUANTUM ENTANGLEMENT STABLE")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .tracking(1.5)
                        .foregroundStyle(TimelyUNATheme.accent)
                    Text("65,000,000 LIGHT YEARS FROM EARTH")
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(TimelyUNATheme.gold)
                        .multilineTextAlignment(.center)
                    Text("You are now seeing the universe from the Cretaceous period’s perspective")
                        .font(TimelyUNATheme.captionFont)
                        .foregroundStyle(TimelyUNATheme.papyrus.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(TimelyUNATheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(TimelyUNATheme.accent, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if simulation.chronosPhase == .jumped || simulation.chronosPhase == .telescopeActive {
                Button {
                    simulation.deployTelescope()
                } label: {
                    Label(
                        simulation.chronosPhase == .telescopeActive
                            ? "TELESCOPE LOCKED • DINOSAUR ERA ACTIVE"
                            : "DEPLOY IMPROBABLE QUANTUM TELESCOPE",
                        systemImage: "binoculars.fill"
                    )
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(TimelyUNATheme.accent, lineWidth: 2)
                )
                .shadow(
                    color: simulation.chronosPhase != .idle
                        ? TimelyUNATheme.accent.opacity(0.45)
                        : .clear,
                    radius: 12
                )
                .accessibilityLabel(chronoAccessibilityLabel)

            if simulation.chronosPhase != .idle {
                Text("Looking back through 65 million years of light...")
                    .font(TimelyUNATheme.captionFont)
                    .foregroundStyle(TimelyUNATheme.accent.opacity(0.75))
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
    NavigationStack {
        ChronosModeView()
    }
    .environmentObject(SimulationState())
}
