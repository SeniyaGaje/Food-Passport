import SwiftUI

/// Navigation for the whole app: the selected tab, each tab's screens, and pop-ups.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var tabPaths: [AppTab: [AppRoute]] = [:]
    var onboardingPath: [OnboardingRoute] = []

    var popup: AppPopup?
    var sheet: AppSheet?
    var toast: ToastMessage?
    var banner: InAppBanner?
    /// Set by the widgets' "Log visit" button. MainTabView picks the restaurant, since that needs AppState.
    var wantsQuickLog = false

    /// Widget links contain no account data; authentication still controls the root screen.
    func openWidgetURL(_ url: URL) {
        guard url.scheme == "foodpassport" else { return }
        switch url.host {
        case "quest":
            selectedTab = .passport
            tabPaths[.passport] = []
        case "budget":
            selectedTab = .profile
            tabPaths[.profile] = []
            sheet = .monthlyBudget
        case "challenge":
            open(.weeklyChallenge, in: .passport)
        case "log":
            wantsQuickLog = true
        default: break
        }
    }

    // Tab navigation

    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.tabPaths[tab] ?? [] },
            set: { self.tabPaths[tab] = $0 }
        )
    }

    func push(_ route: AppRoute) {
        tabPaths[selectedTab, default: []].append(route)
    }

    /// Switches to `tab` and opens `route` on it.
    func open(_ route: AppRoute, in tab: AppTab) {
        tabPaths[tab] = [route]
        selectedTab = tab
    }

    /// Closes Log Visit (and Directions) to go back to the restaurant's page.
    func closeVisitLoggingScreens() {
        var path = tabPaths[selectedTab] ?? []
        while let last = path.last, last.isVisitLoggingStep {
            path.removeLast()
        }
        tabPaths[selectedTab] = path
    }

    // Pop-ups, toasts and banners

    func present(_ popup: AppPopup) {
        self.popup = popup
    }

    func dismissPopup() {
        popup = nil
    }

    func showToast(_ text: String) {
        let message = ToastMessage(text: text)
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.id == message.id { toast = nil }
        }
    }

    func showBanner(_ newBanner: InAppBanner) {
        banner = newBanner
        Task {
            try? await Task.sleep(for: .seconds(6))
            if banner?.id == newBanner.id { banner = nil }
        }
    }

    func openBanner() {
        let route = banner?.route
        banner = nil
        if let route { push(route) }
    }

    /// After a new stamp: close the pop-up, show "Visit logged", then the budget update if the meal was part of a quest.
    func finishStampCelebration(for cuisine: Cuisine, budgetUpdate: BudgetUpdate? = nil) {
        dismissPopup()
        finishLoggingVisit(message: "Visit logged! You earned a \(cuisine.rawValue) stamp ✓", budgetUpdate: budgetUpdate)
    }

    /// Goes back to the restaurant's page, shows `message`, then the budget update (if any) once the message has been read.
    func finishLoggingVisit(message: String, budgetUpdate: BudgetUpdate?) {
        closeVisitLoggingScreens()
        showToast(message)
        guard let budgetUpdate else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if popup == nil { present(.budgetUpdate(budgetUpdate)) }
        }
    }

    func reset() {
        selectedTab = .home
        tabPaths = [:]
        onboardingPath = []
        popup = nil
        sheet = nil
        toast = nil
        banner = nil
        wantsQuickLog = false
    }
}

private extension AppRoute {
    var isVisitLoggingStep: Bool {
        switch self {
        case .logVisit, .directions: true
        default: false
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case passport
    case history
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .passport: "Passport"
        case .history: "History"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .explore: "magnifyingglass"
        case .passport: "book.closed"
        case .history: "clock"
        case .profile: "person"
        }
    }
}

/// Screens that can be opened on any tab.
enum AppRoute: Hashable {
    case placeDetail(Restaurant)
    case directions(Restaurant)
    case logVisit(Restaurant)
    case questDetail
    case foodTrail
    case weeklyChallenge
    case visitDetail(Visit)
    case spendingOverview(DashboardPeriod)
    case about
}

/// Screens in onboarding: welcome, sign up, permissions, budget.
enum OnboardingRoute: Hashable {
    case signIn
    case signUp
    case permissions
    case budgetSetup
}

/// Pop-ups shown in the middle of the screen.
enum AppPopup: Equatable {
    case stampEarned(Cuisine)
    /// What the last quest meal cost against its estimate, and how the plan changed.
    case budgetUpdate(BudgetUpdate)
    /// A place in the plan costs more than the quest has left.
    case budgetLimit
}

/// Bottom sheets that open from more than one screen.
enum AppSheet: String, Identifiable {
    case newQuest
    case editQuest
    case monthlyBudget

    var id: String { rawValue }
}

/// A short message at the top of the screen, e.g. "Visit logged".
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

/// A notification-style banner shown inside the app, e.g. "You've arrived".
struct InAppBanner: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var imageName: String?
    var route: AppRoute?
}
