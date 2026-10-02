import Foundation
import Observation
import SwiftUI

// MARK: - AppState

/// App-wide session state shared through the environment.
/// Backed by mock data for now; Firebase-backed services replace it in the API milestone.
@Observable
final class AppState {
    enum Stage {
        case onboarding
        case main
    }

    var stage: Stage = .onboarding
    var isLocked = false
    var isFaceIDEnabled = true

    var profile = MockData.profile
    var visits = MockData.visits
    var stamps = MockData.stamps
    var bookmarkedRestaurantIDs: Set<Restaurant.ID> = []

    var cuisinesTriedCount: Int {
        Set(visits.map(\.cuisine)).count
    }

    // MARK: Session

    func enterApp() {
        stage = .main
        isLocked = false
    }

    func lockIfNeeded() {
        guard stage == .main, isFaceIDEnabled else { return }
        isLocked = true
    }

    func unlock() {
        isLocked = false
    }

    func signOut() {
        stage = .onboarding
        isLocked = false
    }

    // MARK: Data

    func deleteVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        stamps.removeAll { $0.visitID == visit.id }
    }

    func resetAllData() {
        visits = []
        stamps = []
    }

    func isBookmarked(_ restaurant: Restaurant) -> Bool {
        bookmarkedRestaurantIDs.contains(restaurant.id)
    }

    func toggleBookmark(for restaurant: Restaurant) {
        if bookmarkedRestaurantIDs.contains(restaurant.id) {
            bookmarkedRestaurantIDs.remove(restaurant.id)
        } else {
            bookmarkedRestaurantIDs.insert(restaurant.id)
        }
    }
}

// MARK: - AppRouter

/// Owns navigation state for the whole app: selected tab, each tab's stack, and global pop-ups/sheets.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var tabPaths: [AppTab: [AppRoute]] = [:]
    var onboardingPath: [OnboardingRoute] = []

    var popup: AppPopup?
    var sheet: AppSheet?
    var toast: ToastMessage?
    var banner: InAppBanner?

    // MARK: Tab navigation

    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.tabPaths[tab] ?? [] },
            set: { self.tabPaths[tab] = $0 }
        )
    }

    func push(_ route: AppRoute) {
        tabPaths[selectedTab, default: []].append(route)
    }

    /// Switches to `tab` and shows `route` directly on top of that tab's root screen.
    func open(_ route: AppRoute, in tab: AppTab) {
        tabPaths[tab] = [route]
        selectedTab = tab
    }

    /// Pops Log Visit (and Directions, if the visit started there) so the user lands back on Place Detail.
    func closeVisitLoggingScreens() {
        var path = tabPaths[selectedTab] ?? []
        while let last = path.last, last.isVisitLoggingStep {
            path.removeLast()
        }
        tabPaths[selectedTab] = path
    }

    // MARK: Pop-ups, toasts and banners

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

    /// Prototype flow after a visit is saved: Stamp Earned → "Visit logged" toast → Budget Update.
    func finishStampCelebration(for cuisine: Cuisine) {
        dismissPopup()
        closeVisitLoggingScreens()
        showToast("Visit logged! You earned a \(cuisine.rawValue) stamp ✓")
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            present(.budgetUpdate)
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
    }
}

// MARK: - AppRoute

private extension AppRoute {
    var isVisitLoggingStep: Bool {
        switch self {
        case .logVisit, .directions: true
        default: false
        }
    }
}

// MARK: - AppTab

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

// MARK: - AppRoute

/// Screens that can be pushed onto any tab's navigation stack.
enum AppRoute: Hashable {
    case placeDetail(Restaurant)
    case directions(Restaurant)
    case logVisit(Restaurant)
    case questDetail
    case foodTrail
    case weeklyChallenge
    case visitDetail(Visit)
    case about
}

// MARK: - OnboardingRoute

/// Screens in the welcome → sign up → permissions → budget flow.
enum OnboardingRoute: Hashable {
    case signIn
    case signUp
    case permissions
    case budgetSetup
}

// MARK: - AppPopup

/// Centred pop-ups shown over the whole app (prototype: Stamp Earned, Budget Update, Budget Limit).
enum AppPopup: Equatable {
    case stampEarned(Cuisine)
    case budgetUpdate
    case budgetLimit
}

// MARK: - AppSheet

/// Sheets that can be opened from more than one screen.
enum AppSheet: String, Identifiable {
    case newQuest
    case editQuest
    case monthlyBudget

    var id: String { rawValue }
}

// MARK: - ToastMessage

/// Short confirmation message shown at the top of the screen.
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - InAppBanner

/// In-app stand-in for a local notification, e.g. the geofence arrival alert.
struct InAppBanner: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var route: AppRoute?
}
