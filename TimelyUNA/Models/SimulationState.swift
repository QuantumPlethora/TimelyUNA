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

    /// Horizon LightLine — process-lifetime, not reset by tab redraws.
    @Published var lightLineStartedAt: Date?
    @Published var lightLineFinished = false
    @Published private(set) var lightLineGeneration: Int = 0

    private var rocketTask: Task<Void, Never>?

    func beginLightLineIfNeeded() {
        // First appearance only. Tab remounts, redraws, and later onAppear
        // calls must not start a second run.
        if lightLineStartedAt == nil, !lightLineFinished {
            lightLineStartedAt = Date()
        }
    }

    func markLightLineFinished() {
        lightLineFinished = true
    }

    var isLightLineRunning: Bool {
        lightLineStartedAt != nil && !lightLineFinished
    }

    /// Starts a single new run. Ignored while a run is still in flight.
    func replayLightLine() {
        guard !isLightLineRunning else { return }
        lightLineFinished = false
        lightLineGeneration += 1
        lightLineStartedAt = Date()
    }

    func lightLineElapsed(now: Date) -> TimeInterval {
        guard let start = lightLineStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

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
            // Hold the hit state long enough to read “reality corrected” in the ritual sky.
            try? await Task.sleep(nanoseconds: 3_200_000_000)
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
