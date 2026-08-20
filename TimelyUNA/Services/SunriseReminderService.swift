import Foundation
import UserNotifications
import Combine

/// Quantum Reminder local notification near true sunrise (educational).
@MainActor
final class SunriseReminderService: ObservableObject {
    static let notificationID = "truehorizon.true-sunrise.reminder"

    enum Authorization: Equatable {
        case notDetermined
        case authorized
        case denied
        case provisional
    }

    @Published private(set) var authorization: Authorization = .notDetermined
    @Published private(set) var isScheduled: Bool = false
    @Published private(set) var scheduledFireDate: Date?
    @Published private(set) var statusMessage: String = "Quantum Reminder off"

    private let center = UNUserNotificationCenter.current()

    init() {
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorization = map(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests()
        if let match = pending.first(where: { $0.identifier == Self.notificationID }),
           let trigger = match.trigger as? UNCalendarNotificationTrigger,
           let next = trigger.nextTriggerDate() {
            isScheduled = true
            scheduledFireDate = next
            statusMessage = "Quantum Reminder armed · \(next.formatted(date: .omitted, time: .shortened))"
        } else if pending.contains(where: { $0.identifier == Self.notificationID }) {
            isScheduled = true
            statusMessage = "Quantum Reminder armed"
        } else {
            isScheduled = false
            scheduledFireDate = nil
            if authorization == .denied {
                statusMessage = "Notifications denied · enable in System Settings"
            } else if authorization == .authorized || authorization == .provisional {
                statusMessage = "Quantum Reminder off"
            } else {
                statusMessage = "Quantum Reminder off"
            }
        }
    }

    /// Request notification permission if needed, then schedule at true sunrise.
    func armQuietReminder(trueSunrise: Date?, persistence: HorizonPersistence) async {
        guard let trueSunrise else {
            statusMessage = "Need live sunrise time before arming a reminder"
            return
        }

        let settings = await center.notificationSettings()
        authorization = map(settings.authorizationStatus)

        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorization = granted ? .authorized : .denied
                if !granted {
                    statusMessage = "Notifications denied · enable in System Settings"
                    persistence.setSunriseReminderArmed(false)
                    return
                }
            } catch {
                statusMessage = "Could not request notification permission"
                persistence.setSunriseReminderArmed(false)
                return
            }
        } else if settings.authorizationStatus == .denied {
            authorization = .denied
            statusMessage = "Notifications denied · enable in System Settings"
            persistence.setSunriseReminderArmed(false)
            return
        }

        await schedule(at: trueSunrise)
        persistence.setSunriseReminderArmed(true)
        await refreshStatus()
    }

    func disarm(persistence: HorizonPersistence) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        persistence.setSunriseReminderArmed(false)
        isScheduled = false
        scheduledFireDate = nil
        statusMessage = "Quantum Reminder off"
    }

    /// Reschedule if armed and a new true-sunrise time is available (e.g. after location lock).
    func rescheduleIfArmed(trueSunrise: Date?, persistence: HorizonPersistence) async {
        guard persistence.sunriseReminderArmed, let trueSunrise else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        #if os(iOS)
        case .ephemeral:
            break
        #endif
        default:
            return
        }
        await schedule(at: trueSunrise)
        await refreshStatus()
    }

    // MARK: - Private

    private func schedule(at trueSunrise: Date) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])

        // Fire a few minutes before true sunrise so the user can open the app at dawn.
        let fire = trueSunrise.addingTimeInterval(-5 * 60)
        let now = Date()
        let effective = fire > now.addingTimeInterval(30) ? fire : now.addingTimeInterval(60)

        let content = UNMutableNotificationContent()
        content.title = "TimelyUNA"
        content.body = "True sunrise is near. The Sun is late to its own horizon—Visible Now is already history."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: effective
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            isScheduled = true
            scheduledFireDate = effective
            statusMessage = "Quantum Reminder armed · \(effective.formatted(date: .omitted, time: .shortened))"
        } catch {
            isScheduled = false
            scheduledFireDate = nil
            statusMessage = "Could not schedule reminder"
        }
    }

    private func map(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        #if os(iOS)
        case .ephemeral: return .authorized
        #endif
        @unknown default: return .notDetermined
        }
    }
}
