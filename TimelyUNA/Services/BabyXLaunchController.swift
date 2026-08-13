import Foundation
import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Reliable Baby X launch state machine for Finder AR and 2D educational sky.
/// UI-facing mutations run on the main actor. Never blocks the main thread with sleeps outside Tasks.
@MainActor
final class BabyXLaunchController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case charging
        case ignition
        case launching
        case arrival
        case cooldown
    }

    enum BlockReason: Equatable {
        case none
        case busy
        case actualNowOff
        case calibrating
        case targetUnavailable
        case targetBehind
        case trackingLimited
        case reduceMotionOK // not a block
    }

    @Published private(set) var phase: Phase = .idle
    /// 3, 2, 1 during charging; nil otherwise.
    @Published private(set) var countdownMark: Int?
    /// 0…1 along liftoff for 2D drawing and AR progress mirrors.
    @Published private(set) var flightProgress: Double = 0
    @Published private(set) var showPhotonSlip: Bool = false
    @Published private(set) var confirmTitle: String?
    @Published private(set) var confirmSubtitle: String?
    /// User-visible reason when launch cannot start (never silent).
    @Published var blockMessage: String?
    /// VoiceOver announcements (set then cleared; views post them).
    @Published private(set) var accessibilityAnnouncement: String?

    private var sequenceTask: Task<Void, Never>?
    private var lastCompletionDay: String?

    var isBusy: Bool {
        switch phase {
        case .idle: return false
        default: return true
        }
    }

    var isLaunchingVisual: Bool {
        switch phase {
        case .charging, .ignition, .launching, .arrival: return true
        default: return false
        }
    }

    // MARK: - Entry

    /// Set false at sequence start; AR path must call `noteARIgnitionSucceeded()` or abort.
    private var arIgnitionSucceeded = false
    /// When true, sequence runs without requiring AR ignition ack (2D / mac educational).
    private var skipARIgnitionRequirement = false

    /// Validates and starts the cinematic sequence. Returns false if blocked.
    @discardableResult
    func requestLaunch(
        showActualNow: Bool,
        hasDisplayPair: Bool,
        targetInFront: Bool?,
        trackingLimited: Bool,
        reduceMotion: Bool,
        requiresARIgnition: Bool,
        onARIgnition: (() -> Void)?,
        onSuccess: (() -> Void)?
    ) -> Bool {
        guard !isBusy else {
            blockMessage = "Launch already in progress."
            return false
        }
        blockMessage = nil
        if !showActualNow {
            blockMessage = "Actual Now target unavailable. Turn on Actual Now."
            return false
        }
        if !hasDisplayPair {
            blockMessage = "Calibrating direction… Wait for sky placement."
            return false
        }
        if trackingLimited {
            blockMessage = "AR tracking unavailable. Try again when tracking recovers."
            return false
        }
        if let inFront = targetInFront, !inFront {
            blockMessage = "Turn toward Actual Now to launch."
            return false
        }

        skipARIgnitionRequirement = !requiresARIgnition
        arIgnitionSucceeded = !requiresARIgnition
        sequenceTask?.cancel()
        sequenceTask = Task { [weak self] in
            await self?.runSequence(
                reduceMotion: reduceMotion,
                onARIgnition: onARIgnition,
                onSuccess: onSuccess
            )
        }
        return true
    }

    /// Cancel without treating as success (Close, background, user abort).
    func cancel() {
        sequenceTask?.cancel()
        sequenceTask = nil
        arIgnitionSucceeded = false
        resetToIdle(clearConfirm: true)
    }

    /// AR coordinator confirmed rocket path lock.
    func noteARIgnitionSucceeded() {
        arIgnitionSucceeded = true
        blockMessage = nil
    }

    /// AR coordinator could not place rocket — abort cleanly, no ritual.
    func abortFailedLaunch(message: String) {
        sequenceTask?.cancel()
        sequenceTask = nil
        arIgnitionSucceeded = false
        blockMessage = message
        resetToIdle(clearConfirm: true)
        accessibilityAnnouncement = message
        postAnnouncement()
    }

    // MARK: - Sequence

    private func runSequence(
        reduceMotion: Bool,
        onARIgnition: (() -> Void)?,
        onSuccess: (() -> Void)?
    ) async {
        // CHARGE — immediate visual phase for button acknowledgement.
        phase = .charging
        flightProgress = 0
        showPhotonSlip = false
        confirmTitle = nil
        confirmSubtitle = nil
        accessibilityAnnouncement = "Baby X charging."
        postAnnouncement()

        if reduceMotion {
            countdownMark = nil
            lightHaptic()
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        } else {
            for mark in [3, 2, 1] {
                guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
                countdownMark = mark
                lightHaptic()
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            countdownMark = nil
        }

        // IGNITION — request AR path lock; 2D does not need coordinator ack.
        guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        phase = .ignition
        mediumHaptic()
        if !skipARIgnitionRequirement {
            arIgnitionSucceeded = false
        }
        onARIgnition?()
        // Yield so SwiftUI can run updateUIView → beginIgnitionFlight → ignition result callback.
        let ignitionWaitNs: UInt64 = reduceMotion ? 220_000_000 : 550_000_000
        let ignitionDeadline = Date().addingTimeInterval(Double(ignitionWaitNs) / 1_000_000_000.0)
        while !Task.isCancelled && !skipARIgnitionRequirement && !arIgnitionSucceeded && Date() < ignitionDeadline {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        if !skipARIgnitionRequirement && !arIgnitionSucceeded {
            // Coordinator may already have called abortFailedLaunch; if not, fail here.
            if blockMessage == nil {
                blockMessage = "Could not lock launch direction. Aim toward Actual Now."
            }
            accessibilityAnnouncement = blockMessage
            postAnnouncement()
            return resetToIdle(clearConfirm: true)
        }

        // LIFTOFF
        guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        phase = .launching
        accessibilityAnnouncement = "Baby X launched toward Actual Now."
        postAnnouncement()

        let flightNs: UInt64 = reduceMotion ? 450_000_000 : 1_500_000_000
        let start = Date()
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(start)
            let p = min(t / (Double(flightNs) / 1_000_000_000.0), 1.0)
            flightProgress = p
            if p >= 0.72 { showPhotonSlip = true }
            if p >= 1.0 { break }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        // PHOTON SLIP + ARRIVAL — only after a real flight segment.
        guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        phase = .arrival
        flightProgress = 1
        showPhotonSlip = true
        successHaptic()
        confirmTitle = "Reality corrected."
        confirmSubtitle = "Baby X aligned with Actual Now."
        accessibilityAnnouncement = "Launch complete."
        postAnnouncement()

        // Ritual only after full successful sequence (never on cancel/fail).
        onSuccess?()

        try? await Task.sleep(nanoseconds: reduceMotion ? 400_000_000 : 650_000_000)

        // COOLDOWN
        guard !Task.isCancelled else { return resetToIdle(clearConfirm: true) }
        phase = .cooldown
        showPhotonSlip = false
        try? await Task.sleep(nanoseconds: reduceMotion ? 200_000_000 : 400_000_000)

        resetToIdle(clearConfirm: true)
    }

    private func resetToIdle(clearConfirm: Bool) {
        phase = .idle
        countdownMark = nil
        flightProgress = 0
        showPhotonSlip = false
        if clearConfirm {
            confirmTitle = nil
            confirmSubtitle = nil
        }
        accessibilityAnnouncement = nil
    }

    private func postAnnouncement() {
        // Keep value long enough for accessibility to pick up; cleared on next phase.
        #if canImport(UIKit)
        if let a = accessibilityAnnouncement, !a.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: a)
        }
        #endif
    }

    // MARK: Haptics

    private func lightHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        #endif
    }

    private func mediumHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.95)
        #endif
    }

    private func successHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
