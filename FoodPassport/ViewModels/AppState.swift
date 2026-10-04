import Foundation
import Observation
import SwiftUI

// MARK: - AppState

/// App-wide session state shared through the environment: who is signed in and their data.
/// Reads and writes go through `AuthService` and `DatabaseService`, which are passed in (dependency injection),
/// so the same code runs on Firebase in the app and on in-memory mocks in previews and unit tests.
@Observable
final class AppState {
    enum Stage {
        /// Checking for a signed-in user at launch.
        case launching
        case onboarding
        case main
    }

    var stage: Stage = .launching
    var isLocked = false
    var isFaceIDEnabled = true

    var profile = MockData.profile
    var restaurants = MockData.restaurants
    var visits = MockData.visits
    var stamps = MockData.stamps

    /// Shown in an alert by `RootView` when loading or saving fails.
    var errorMessage: String?

    private let auth: AuthService
    private let database: DatabaseService

    /// Background saves that haven't finished yet, so unit tests can wait for them.
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]

    init(auth: AuthService = MockAuthService(), database: DatabaseService = MockDatabaseService()) {
        self.auth = auth
        self.database = database
    }

    var cuisinesTriedCount: Int {
        Set(visits.map(\.cuisine)).count
    }

    // MARK: Session

    /// Called once at launch: skips onboarding when a user is still signed in from last time.
    func restoreSession() async {
        guard let userID = auth.currentUserID else {
            stage = .onboarding
            return
        }

        do {
            try await loadUserData(userID: userID)
            enterApp()
        } catch {
            errorMessage = "Couldn't load your passport. \(error.localizedDescription)"
            stage = .onboarding
        }
    }

    func signIn(email: String, password: String) async throws {
        let userID = try await auth.signIn(email: email, password: password)
        try await loadUserData(userID: userID)
        enterApp()
    }

    /// Creates the account and its profile document. Onboarding (permissions, budget) continues afterwards.
    func signUp(name: String, email: String, password: String) async throws {
        let userID = try await auth.signUp(email: email, password: password)
        let newProfile = UserProfile(
            name: name,
            email: email,
            memberSince: .now,
            monthlyBudget: 3000,
            bookmarkedRestaurantIDs: []
        )
        try await database.saveProfile(newProfile, userID: userID)

        profile = newProfile
        visits = []
        stamps = []
        restaurants = try await database.fetchRestaurants()
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(email: email)
    }

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
        do {
            try auth.signOut()
        } catch {
            errorMessage = "Couldn't sign out. \(error.localizedDescription)"
            return
        }
        stage = .onboarding
        isLocked = false
    }

    private func loadUserData(userID: String) async throws {
        restaurants = try await database.fetchRestaurants()
        visits = try await database.fetchVisits(userID: userID)
        stamps = try await database.fetchStamps(userID: userID)

        if let savedProfile = try await database.fetchProfile(userID: userID) {
            profile = savedProfile
        } else {
            // The account exists but its profile was never saved (e.g. sign-up was interrupted).
            profile = UserProfile(name: "", email: "", memberSince: .now, monthlyBudget: 3000, bookmarkedRestaurantIDs: [])
            save { database, userID in try await database.saveProfile(self.profile, userID: userID) }
        }
    }

    // MARK: Visits and stamps

    /// Adds a logged visit and saves it.
    /// Returns the new stamp when this is the first location-verified visit for the visit's cuisine.
    @discardableResult
    func addVisit(_ visit: Visit) -> Stamp? {
        visits.insert(visit, at: 0)
        save { database, userID in try await database.saveVisit(visit, userID: userID) }

        guard visit.isLocationVerified, !stamps.contains(where: { $0.cuisine == visit.cuisine }) else {
            return nil
        }

        let stamp = Stamp(
            cuisine: visit.cuisine,
            restaurantName: visit.restaurant.name,
            earnedDate: visit.date,
            visitID: visit.id,
            imageName: visit.imageName
        )
        stamps.append(stamp)
        save { database, userID in try await database.saveStamp(stamp, userID: userID) }
        return stamp
    }

    /// Deletes a visit, and the stamp it earned if there was one.
    func deleteVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        save { database, userID in try await database.deleteVisit(id: visit.id, userID: userID) }

        for stamp in stamps where stamp.visitID == visit.id {
            stamps.removeAll { $0.cuisine == stamp.cuisine }
            save { database, userID in try await database.deleteStamp(cuisine: stamp.cuisine, userID: userID) }
        }
    }

    func resetAllData() {
        visits = []
        stamps = []
        save { database, userID in try await database.deleteVisitsAndStamps(userID: userID) }
    }

    // MARK: Profile

    func updateMonthlyBudget(_ amount: Int) {
        profile.monthlyBudget = amount
        saveProfile()
    }

    func isBookmarked(_ restaurant: Restaurant) -> Bool {
        profile.bookmarkedRestaurantIDs.contains(restaurant.id)
    }

    func toggleBookmark(for restaurant: Restaurant) {
        if profile.bookmarkedRestaurantIDs.contains(restaurant.id) {
            profile.bookmarkedRestaurantIDs.remove(restaurant.id)
        } else {
            profile.bookmarkedRestaurantIDs.insert(restaurant.id)
        }
        saveProfile()
    }

    private func saveProfile() {
        let profile = profile
        save { database, userID in try await database.saveProfile(profile, userID: userID) }
    }

    // MARK: Saving

    /// Runs a database write in the background. The screen has already been updated, so the student never waits.
    /// Firestore keeps the change in its offline cache straight away and syncs it when the device is online.
    private func save(_ write: @escaping (DatabaseService, String) async throws -> Void) {
        guard let userID = auth.currentUserID else { return }

        let id = UUID()
        pendingWrites[id] = Task { [database] in
            do {
                try await write(database, userID)
            } catch {
                errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
            }
            pendingWrites[id] = nil
        }
    }

    /// Waits until every background save has finished. Used by unit tests.
    func waitForPendingWrites() async {
        for task in pendingWrites.values {
            await task.value
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
    var imageName: String?
    var route: AppRoute?
}
