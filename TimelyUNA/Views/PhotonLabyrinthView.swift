import SwiftUI

/// Time-picker + photon labyrinth gate + rocket journey (entry to AR on device).
struct PhotonLabyrinthView: View {
    @State private var selectedDate = Date()
    @State private var puzzleSolved = false
    @State private var showAR = false
    @State private var journeyMessage = ""
    @State private var puzzleResetID = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Timely Una")
                    .font(papyrus(42).weight(.bold))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .accessibilityAddTraits(.isHeader)

                Text("Because the Sun is always late to its own dawn ☀️")
                    .font(papyrus(18).italic())
                    .foregroundStyle(TimelyUNATheme.papyrus)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("CHOOSE A MOMENT IN TIME")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .tracking(1.5)
                        .foregroundStyle(TimelyUNATheme.accent)

                    DatePicker(
                        "Choose a Moment in Time",
                        selection: $selectedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(TimelyUNATheme.accent)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TimelyUNATheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(TimelyUNATheme.accent, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                InfoCard(
                    indicator: TimelyUNATheme.actualSun,
                    title: "MISSION BRIEFING",
                    body: "Light takes \(LightTimeConstants.sunLightTravelDescription) to reach Earth. Trace the photon path through the labyrinth — EARTH → PHOTONS → APPARENT → ACTUAL — then launch the Baby X rocket toward the Sun’s true position."
                )

                if !puzzleSolved {
                    PhotonLabyrinthPuzzle(onSolved: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            puzzleSolved = true
                            journeyMessage = ""
                        }
                    })
                    .id(puzzleResetID)
                } else {
                    Label("Photon Labyrinth cleared", systemImage: "checkmark.seal.fill")
                        .font(papyrus(18).weight(.semibold))
                        .foregroundStyle(TimelyUNATheme.gold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TimelyUNATheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(TimelyUNATheme.gold, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if puzzleSolved {
                    Button {
                        AppHaptics.selection()
                        journeyMessage = simulateJourney(to: selectedDate)
                        #if os(iOS)
                        showAR = true
                        #endif
                    } label: {
                        Label("Launch Baby X Rocket at the Sun", systemImage: "airplane.departure")
                            .font(papyrus(20).weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TimelyUNATheme.gold)
                    .foregroundStyle(TimelyUNATheme.background)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityHint("Opens AR and launches a rocket synchronized to the Sun light delay")

                    #if !os(iOS)
                    Text("AR rocket launch requires an iPhone or iPad with a camera.")
                        .font(papyrus(15))
                        .foregroundStyle(TimelyUNATheme.accent.opacity(0.8))
                        .multilineTextAlignment(.center)
                    #endif
                }

                if !journeyMessage.isEmpty {
                    Text(journeyMessage)
                        .font(papyrus(17))
                        .foregroundStyle(TimelyUNATheme.papyrus.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(TimelyUNATheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(TimelyUNATheme.accent.opacity(0.6), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if puzzleSolved {
                Button("Reset Labyrinth") {
                    AppHaptics.selection()
                    withAnimation {
                            puzzleSolved = false
                            journeyMessage = ""
                            showAR = false
                            puzzleResetID += 1
                        }
                    }
                    .font(papyrus(16))
                    .foregroundStyle(TimelyUNATheme.accent)
                }
            }
            .padding(24)
        }
        .background(TimelyUNATheme.background.ignoresSafeArea())
        .navigationTitle("Labyrinth")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showAR) {
            ARSunRocketView(selectedDate: selectedDate)
        }
        #endif
    }

    func simulateJourney(to date: Date) -> String {
        let lightDelay = LightTimeConstants.sunLightTravelSeconds
        let lightLeftAt = date.addingTimeInterval(-lightDelay)
        let formatter = lightLeftAt.formatted(date: .abbreviated, time: .shortened)
        return """
        🚀 Rocket synchronized with the Sun’s true position
        Photons that arrive at your chosen moment left at \(formatter)
        Light delay: \(LightTimeConstants.sunLightTravelDescription)
        Navigating the true time of arrival.
        """
    }

    private func papyrus(_ size: CGFloat) -> Font {
        .custom("Papyrus", size: size, relativeTo: .body)
    }
}

#Preview {
    NavigationStack {
        PhotonLabyrinthView()
    }
}
