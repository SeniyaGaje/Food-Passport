import Foundation

/// Only the values a widget needs. No email, photos or Firebase credentials.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var isSignedIn = false
    var questTitle: String?
    var cuisinesTried = 0
    var targetCuisines = 0
    var questUnit = "cuisines tried"
    var questEndsAt: Date?
    var monthlyBudget = 0
    var monthlySpent = 0
    var budgetMonth = ""
    var updatedAt: Date = .now
    // Added later, so they're optional: a file saved by an older version still opens.
    var questBudgetLeft: Int?
    var nextPickName: String?
    var nextPickCost: Int?
    var challengeTitle: String?
    var challengeCompleted: Int?
    var challengeTarget: Int?
    var challengeEndsAt: Date?

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    func current(at date: Date) -> WidgetSnapshot {
        var value = self
        if budgetMonth != Self.monthKey(for: date) { value.monthlySpent = 0 }
        if let questEndsAt, date >= questEndsAt { value.questTitle = nil }
        // A new week starts a new challenge, so last week's progress no longer counts.
        if let challengeEndsAt, date >= challengeEndsAt { value.challengeCompleted = 0 }
        return value
    }

    var questFraction: Double {
        guard targetCuisines > 0 else { return 0 }
        return min(1, Double(cuisinesTried) / Double(targetCuisines))
    }

    var challengeFraction: Double {
        guard let challengeTarget, challengeTarget > 0 else { return 0 }
        return min(1, Double(challengeCompleted ?? 0) / Double(challengeTarget))
    }

    var budgetFraction: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(1, max(0, Double(monthlySpent) / Double(monthlyBudget)))
    }

    var remainingBudget: Int { max(0, monthlyBudget - monthlySpent) }
}

nonisolated struct WidgetSnapshotStore: Sendable {
    static let groupID = "group.com.seniyagajadeera.FoodPassport"
    let file: URL?

    init(file: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
        .appendingPathComponent("widget-snapshot.json")) {
        self.file = file
    }

    func read(at date: Date = .now) -> WidgetSnapshot {
        guard let file, let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return value.current(at: date)
    }

    func save(_ value: WidgetSnapshot) throws {
        guard let file else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The widgets' "Log visit" button can run in the widget's own process, where the app's screens
/// don't exist. It leaves a note in the shared App Group, and the app opens Log your visit when it next becomes active.
nonisolated enum QuickLogRequest {
    private static let key = "quickLogRequestedAt"
    /// Posted too, for when the button runs inside the app itself and the app is already open.
    static let notification = Notification.Name("FoodPassportQuickLogRequested")

    static func save(at date: Date = .now) {
        UserDefaults(suiteName: WidgetSnapshotStore.groupID)?.set(date, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// True (once) if the button was tapped in the last five minutes.
    static func take(now: Date = .now) -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshotStore.groupID),
              let requested = defaults.object(forKey: key) as? Date else { return false }
        defaults.removeObject(forKey: key)
        return now.timeIntervalSince(requested) < 5 * 60
    }
}
