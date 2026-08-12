import Foundation
import Combine

/// Shared live clock for solar refresh and countdown UI.
@MainActor
final class HorizonClock: ObservableObject {
    @Published private(set) var now: Date = Date()

    private var secondTimer: Timer?
    private var solarTimer: Timer?

    /// Fires when solar inputs should recompute (default ~30s, matching the web app).
    let solarTick = PassthroughSubject<Date, Never>()

    func start() {
        stop()
        now = Date()
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        solarTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.solarTick.send(self.now)
            }
        }
        if let secondTimer { RunLoop.main.add(secondTimer, forMode: .common) }
        if let solarTimer { RunLoop.main.add(solarTimer, forMode: .common) }
        solarTick.send(now)
    }

    func stop() {
        secondTimer?.invalidate()
        solarTimer?.invalidate()
        secondTimer = nil
        solarTimer = nil
    }

    deinit {
        secondTimer?.invalidate()
        solarTimer?.invalidate()
    }
}
