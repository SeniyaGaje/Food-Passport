import AppIntents

/// The "Log visit" button on the widgets (and in Shortcuts). It opens FoodPassport on Log your visit.
nonisolated struct LogVisitIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a visit" }
    static var description: IntentDescription { IntentDescription("Opens FoodPassport to log the meal you're having.") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        QuickLogRequest.save()
        return .result()
    }
}
