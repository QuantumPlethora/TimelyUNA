import Foundation
import Combine

@MainActor
final class SimulationState: ObservableObject {
    enum ChronosPhase: Equatable {
        case idle
        case jumped
        case telescopeActive
    }

    @Published var rocketProgress: Double = 0
    @Published var isRocketFlying = false
    @Published var showRocketHit = false
    @Published var chronosPhase: ChronosPhase = .idle
    @Published var showShareCopied = false

    private var rocketTask: Task<Void, Never>?

    func launchRocket() {
        rocketTask?.cancel()
        isRocketFlying = true
        showRocketHit = false
        rocketProgress = 0

        rocketTask = Task { [weak self] in
            let duration: Double = 1.45
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let p = min(elapsed / duration, 1.0)
                await MainActor.run {
                    self?.rocketProgress = p
                }
                if p >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                self?.showRocketHit = true
                self?.isRocketFlying = false
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self?.showRocketHit = false
                self?.rocketProgress = 0
            }
        }
    }

    func engageQuantumJump() {
        chronosPhase = .jumped
    }

    func deployTelescope() {
        chronosPhase = .telescopeActive
    }

    func resetChronos() {
        chronosPhase = .idle
    }

    func markShareCopied() {
        showShareCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run { self.showShareCopied = false }
        }
    }
}
