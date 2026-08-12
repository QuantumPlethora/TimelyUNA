import Foundation
import Combine

/// Lightweight persistence for streaks, unlocks, and collection items.
/// Backed by UserDefaults today; designed to migrate later to SwiftData / iCloud.
@MainActor
final class HorizonPersistence: ObservableObject {
    private let defaults: UserDefaults
    private let prefix = "th_"

    // Keys (stable for future migration)
    private enum Key {
        static let streak = "streak"
        static let lastRitual = "lastRitual"
        static let collection = "collection"
        static let unlockPrefix = "unlock_"
        static let sunriseReminder = "sunriseReminder"
    }

    struct CollectionItem: Identifiable, Codable, Equatable {
        var id: String
        var title: String
        var detail: String
        var createdAt: Date
    }

    @Published private(set) var streak: Int = 0
    @Published private(set) var ritualCompleteToday: Bool = false
    @Published private(set) var collection: [CollectionItem] = []
    @Published private(set) var sunriseReminderArmed: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    // MARK: - Ritual / streak

    func reload() {
        streak = defaults.integer(forKey: storageKey(Key.streak))
        let last = defaults.string(forKey: storageKey(Key.lastRitual))
        ritualCompleteToday = (last == Self.todayKey())
        collection = loadCollection()
        sunriseReminderArmed = defaults.bool(forKey: storageKey(Key.sunriseReminder))
    }

    /// Records today’s correction launch. Returns true if this call advanced the streak.
    @discardableResult
    func completeRitual() -> Bool {
        let today = Self.todayKey()
        let last = defaults.string(forKey: storageKey(Key.lastRitual))
        var advanced = false

        if last != today {
            let yesterday = Self.dateKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            if last == nil {
                streak = 1
            } else if last == yesterday {
                streak += 1
            } else {
                streak = 1
            }
            defaults.set(streak, forKey: storageKey(Key.streak))
            defaults.set(today, forKey: storageKey(Key.lastRitual))
            advanced = true
        }

        ritualCompleteToday = true
        addCollectionItem(
            id: "ritual-\(today)",
            title: "Daily correction",
            detail: "Rocket launched · \(today)"
        )
        unlock("after_launch")
        objectWillChange.send()
        return advanced
    }

    // MARK: - Unlocks

    func unlock(_ key: String) {
        defaults.set(true, forKey: storageKey(Key.unlockPrefix + key))
    }

    func isUnlocked(_ key: String) -> Bool {
        defaults.bool(forKey: storageKey(Key.unlockPrefix + key))
    }

    // MARK: - Collection

    func addCollectionItem(id: String, title: String, detail: String) {
        var items = loadCollection()
        guard !items.contains(where: { $0.id == id }) else {
            collection = items
            return
        }
        let item = CollectionItem(id: id, title: title, detail: detail, createdAt: Date())
        items.insert(item, at: 0)
        if items.count > 50 {
            items = Array(items.prefix(50))
        }
        saveCollection(items)
        collection = items
    }

    // MARK: - Sunrise reminder flag (notification scheduling lives in a dedicated service)

    func setSunriseReminderArmed(_ armed: Bool) {
        sunriseReminderArmed = armed
        defaults.set(armed, forKey: storageKey(Key.sunriseReminder))
    }

    // MARK: - Migration hook

    /// Flat dictionary export for a future SwiftData / CloudKit importer.
    func exportState() -> [String: Any] {
        [
            "streak": streak,
            "lastRitual": defaults.string(forKey: storageKey(Key.lastRitual)) as Any,
            "collection": collection.map { ["id": $0.id, "title": $0.title, "detail": $0.detail, "createdAt": $0.createdAt.timeIntervalSince1970] },
            "sunriseReminder": sunriseReminderArmed
        ]
    }

    // MARK: - Private

    private func storageKey(_ name: String) -> String { prefix + name }

    private func loadCollection() -> [CollectionItem] {
        guard let data = defaults.data(forKey: storageKey(Key.collection)) else { return [] }
        return (try? JSONDecoder().decode([CollectionItem].self, from: data)) ?? []
    }

    private func saveCollection(_ items: [CollectionItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey(Key.collection))
        }
    }

    static func todayKey(for date: Date = Date()) -> String {
        dateKey(date)
    }

    private static func dateKey(_ date: Date) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: date)
        let m = c.component(.month, from: date)
        let d = c.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
