import AppIntents

/// The "Log visit" button on the widgets (and in Shortcuts). It opens FoodPassport on Log your visit.
nonisolated struct LogVisitIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a visit" }
    static var description: IntentDescription { IntentDescription("Opens FoodPassport to log the meal you're having.") }
    // Opens the app, since Log your visit is a screen in the app.
    static var openAppWhenRun: Bool { true }

    // Leaves a note in the App Group; the app opens Log your visit when it becomes active.
    func perform() async throws -> some IntentResult {
        QuickLogRequest.save()
        return .result()
    }
}
