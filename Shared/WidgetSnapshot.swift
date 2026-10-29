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

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    func current(at date: Date) -> WidgetSnapshot {
        var value = self
        if budgetMonth != Self.monthKey(for: date) { value.monthlySpent = 0 }
        if let questEndsAt, date >= questEndsAt { value.questTitle = nil }
        return value
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
