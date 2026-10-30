import SwiftUI

/// Shown on Home and Passport when there's no active quest, with a button to create one.
struct NoQuestCard: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        EmptyStateView(systemImage: "flag.checkered", title: "Start your next quest",
            message: "Choose a cuisine goal and a budget. Your logged meals will update your progress.",
            actionTitle: "Create quest", action: { router.sheet = .newQuest })
    }
}
