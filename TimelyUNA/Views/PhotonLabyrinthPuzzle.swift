import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Interactive light-path puzzle: connect EARTH → PHOTONS → APPARENT → ACTUAL in order.
/// Correct sequence unlocks the Baby X rocket launch.
struct PhotonLabyrinthPuzzle: View {
    var onSolved: () -> Void

    private let solution: [LabyrinthNode] = [.earth, .photons, .apparent, .actual]

    @State private var path: [LabyrinthNode] = []
    @State private var status: PuzzleStatus = .idle
    @State private var shakeToken = 0
    @State private var pulseSolved = false

    enum LabyrinthNode: String, CaseIterable, Identifiable {
        case earth = "EARTH"
        case photons = "PHOTONS"
        case apparent = "APPARENT"
        case actual = "ACTUAL"
        case decoyA = "ORBIT"
        case decoyB = "ECLIPSE"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .earth: return "🌍"
            case .photons: return "✨"
            case .apparent: return "☉"
            case .actual: return "🌞"
            case .decoyA: return "🌀"
            case .decoyB: return "🌑"
            }
        }

        var subtitle: String {
            switch self {
            case .earth: return "Observer"
            case .photons: return "8m 19s path"
            case .apparent: return "Where light says"
            case .actual: return "Where it is"
            case .decoyA: return "Red herring"
            case .decoyB: return "Red herring"
            }
        }

        var isDecoy: Bool {
            self == .decoyA || self == .decoyB
        }
    }

    enum PuzzleStatus: Equatable {
        case idle
        case tracing
        case wrong
        case solved
    }

    /// Shuffled board layout (stable for a session after first appear).
    @State private var board: [LabyrinthNode] = LabyrinthNode.allCases.shuffled()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PHOTON LABYRINTH")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .tracking(2)
                        .foregroundStyle(TimelyUNATheme.accent)
                    Text("Trace light’s true story — tap nodes in order")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(TimelyUNATheme.papyrus)
                }
                Spacer()
                Text("\(min(path.count, solution.count))/\(solution.count)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TimelyUNATheme.accent.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(instructionText)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: status)

            // Path trail
            HStack(spacing: 6) {
                ForEach(0..<solution.count, id: \.self) { index in
                    trailSlot(index: index)
                    if index < solution.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(TimelyUNATheme.accent.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Node grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(board) { node in
                    nodeButton(node)
                }
            }
            .modifier(ShakeEffect(animatableData: CGFloat(shakeToken)))

            HStack {
                Button("Clear Path") {
                    resetPath(keepSolved: false)
                }
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(TimelyUNATheme.accent)
                .disabled(path.isEmpty || status == .solved)

                Spacer()

                Button("Shuffle") {
                    withAnimation {
                        board.shuffle()
                        if status != .solved {
                            resetPath(keepSolved: false)
                        }
                    }
                }
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(TimelyUNATheme.accent)
                .disabled(status == .solved)
            }

            if status == .solved {
                Label("Labyrinth solved — light-delay navigation unlocked", systemImage: "checkmark.seal.fill")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(TimelyUNATheme.gold)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(16)
        .background(TimelyUNATheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    status == .solved ? TimelyUNATheme.gold : TimelyUNATheme.accent,
                    lineWidth: status == .solved ? 3 : 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: pulseSolved ? TimelyUNATheme.gold.opacity(0.45) : .clear, radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photon labyrinth puzzle")
        .accessibilityHint("Tap Earth, Photons, Apparent Sun, then Actual Sun in that order")
    }

    private var instructionText: String {
        switch status {
        case .idle:
            return "Start at EARTH. Follow the photons. Don’t aim at where the Sun looks — aim where it is."
        case .tracing:
            if let next = solution[safe: path.count] {
                return "Next: \(next.rawValue) — \(next.subtitle)"
            }
            return "Complete the path…"
        case .wrong:
            return "Wrong path. Light doesn’t work that way — try again."
        case .solved:
            return "Path complete. You corrected for the finite speed of light."
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle, .tracing: return TimelyUNATheme.papyrus.opacity(0.85)
        case .wrong: return Color.orange.opacity(0.95)
        case .solved: return TimelyUNATheme.gold
        }
    }

    private func trailSlot(index: Int) -> some View {
        let filled = index < path.count
        let node = filled ? path[index] : nil
        let correctSoFar = filled && index < solution.count && path[index] == solution[index]

        return VStack(spacing: 2) {
            Text(node?.symbol ?? "·")
                .font(.system(size: 18))
            Text(node?.rawValue ?? "—")
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(filled
                      ? (correctSoFar ? TimelyUNATheme.accent.opacity(0.25) : Color.orange.opacity(0.2))
                      : Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TimelyUNATheme.accent.opacity(filled ? 0.8 : 0.3), lineWidth: 1)
        )
    }

    private func nodeButton(_ node: LabyrinthNode) -> some View {
        let selected = path.contains(node)
        let isNext = status != .solved && solution[safe: path.count] == node

        return Button {
            tap(node)
        } label: {
            VStack(spacing: 6) {
                Text(node.symbol)
                    .font(.system(size: 28))
                Text(node.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(TimelyUNATheme.gold)
                Text(node.subtitle)
                    .font(.system(size: 9, design: .serif))
                    .foregroundStyle(TimelyUNATheme.papyrus.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected
                          ? TimelyUNATheme.accent.opacity(0.28)
                          : Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isNext ? TimelyUNATheme.gold : (selected ? TimelyUNATheme.accent : TimelyUNATheme.accent.opacity(0.35)),
                        lineWidth: isNext ? 2.5 : 1.5
                    )
            )
            .scaleEffect(selected ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .disabled(status == .solved || selected)
        .accessibilityLabel("\(node.rawValue), \(node.subtitle)")
        .accessibilityAddTraits(isNext ? .isSelected : [])
    }

    private func tap(_ node: LabyrinthNode) {
        guard status != .solved else { return }
        guard !path.contains(node) else { return }

        let expectedIndex = path.count
        let expected = solution[safe: expectedIndex]

        if node.isDecoy || node != expected {
            path.append(node)
            status = .wrong
            shakeToken += 1
            #if canImport(UIKit) && os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.25)) {
                    resetPath(keepSolved: false)
                }
            }
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            path.append(node)
            status = .tracing
        }
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        if path == solution {
            status = .solved
            withAnimation(.easeInOut(duration: 0.5)) {
                pulseSolved = true
            }
            #if canImport(UIKit) && os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onSolved()
            }
        }
    }

    private func resetPath(keepSolved: Bool) {
        path = []
        if !keepSolved {
            status = .idle
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Horizontal shake used when the player picks a wrong node.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 2) * 8
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

#Preview {
    ZStack {
        TimelyUNATheme.background.ignoresSafeArea()
        PhotonLabyrinthPuzzle(onSolved: {})
            .padding()
    }
}
