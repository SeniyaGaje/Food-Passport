import Testing
import Foundation
@testable import FoodPassport

@Suite("Signing in, signing up and the profile")
@MainActor
struct AppStateSessionTests {

    /// A student whose saved data is different from the sample data the app starts with,
    /// so the tests can tell that it really came from the database.
    private let savedProfile = UserProfile(
        name: "Seniya Gajadeera",
        email: "seniya@nibm.lk",
        memberSince: Date(timeIntervalSince1970: 1_790_000_000),
        monthlyBudget: 5000,
        bookmarkedRestaurantIDs: ["spice-route"]
    )

    // Signing in

    @Test("Signing in loads the student's own passport and opens the app")
    func signInLoadsSavedData() async throws {
        let visit = makeVisit(id: "saved-visit")
        let app = TestApp(database: MockDatabaseService(profile: savedProfile, visits: [visit], stamps: []))

        try await app.signIn()

        #expect(app.appState.stage == .main)
        #expect(app.appState.profile == savedProfile)
        #expect(app.appState.visits.map(\.id) == ["saved-visit"])
        #expect(app.appState.stamps.isEmpty)
        #expect(app.appState.restaurants.count == MockData.restaurants.count)
    }

    @Test("A wrong password shows an error and keeps the student out of the app")
    func wrongPassword() async {
        let app = TestApp()
        app.auth.errorToThrow = .invalidCredentials

        await #expect(throws: AuthServiceError.invalidCredentials) {
            try await app.signIn()
        }
        #expect(app.appState.stage != .main)
    }

    @Test("An empty password is rejected")
    func emptyPassword() async {
        let app = TestApp()

        await #expect(throws: AuthServiceError.invalidCredentials) {
            try await app.appState.signIn(email: "student@nibm.lk", password: "")
        }
    }

    @Test("An account whose profile was never saved gets a blank one, which is then saved")
    func missingProfileIsCreated() async throws {
        let database = MockDatabaseService(profile: nil)
        let app = TestApp(database: database)

        try await app.signIn()
        await app.appState.waitForPendingWrites()

        #expect(app.appState.profile.name.isEmpty)
        #expect(app.appState.profile.monthlyBudget == 3000)
        #expect(database.profile == app.appState.profile)
    }

    // Signing up

    @Test("Signing up creates and saves a profile with the default LKR 3,000 budget")
    func signUp() async throws {
        let database = MockDatabaseService(profile: nil)
        let app = TestApp(database: database)

        try await app.appState.signUp(name: "Seniya Gajadeera", email: "seniya@nibm.lk", password: "password123")

        #expect(app.appState.profile.name == "Seniya Gajadeera")
        #expect(app.appState.profile.email == "seniya@nibm.lk")
        #expect(app.appState.profile.monthlyBudget == 3000)
        #expect(app.appState.profile.initials == "SG")
        #expect(app.appState.visits.isEmpty)
        #expect(app.appState.stamps.isEmpty)
        #expect(database.profile == app.appState.profile)
        // Onboarding (permissions, budget) still comes next, so the tabs aren't shown yet.
        #expect(app.appState.stage != .main)
    }

    @Test("Signing up with an email that's already registered fails")
    func signUpWithUsedEmail() async {
        let app = TestApp()
        app.auth.errorToThrow = .emailAlreadyInUse

        await #expect(throws: AuthServiceError.emailAlreadyInUse) {
            try await app.appState.signUp(name: "Seniya", email: "seniya@nibm.lk", password: "password123")
        }
    }

    // Opening the app

    @Test("Opening the app with nobody signed in starts onboarding")
    func restoreWithoutUser() async {
        let app = TestApp(signedIn: false)

        await app.appState.restoreSession()

        #expect(app.appState.stage == .onboarding)
    }

    @Test("Opening the app while signed in goes straight to the passport")
    func restoreSignedInUser() async {
        let app = TestApp(signedIn: true, database: MockDatabaseService(profile: savedProfile))

        await app.appState.restoreSession()

        #expect(app.appState.stage == .main)
        #expect(app.appState.profile == savedProfile)
        #expect(!app.appState.isLocked)
    }

    @Test("If the passport can't be loaded, the student sees why and goes back to sign in")
    func restoreWhenOffline() async {
        let database = OfflineDatabaseService()
        database.failsReads = true
        let appState = AppState(auth: MockAuthService(signedInUserID: "mock-user"), database: database, settings: UserDefaults(suiteName: "offline-\(UUID())")!)

        await appState.restoreSession()

        #expect(appState.stage == .onboarding)
        #expect(appState.errorMessage?.hasPrefix("Couldn't load your passport.") == true)
    }

    // Signing out

    @Test("Signing out clears reminders and stops location for the next person on the phone")
    func signOut() async throws {
        let app = TestApp(notificationPermission: .allowed)
        try await app.signIn()
        _ = await app.appState.planVisit(to: MockData.campusBites, at: .now.addingTimeInterval(2 * 60 * 60), remind: true)
        #expect(!app.notifications.scheduledReminders.isEmpty)

        app.appState.signOut()

        #expect(app.appState.stage == .onboarding)
        #expect(app.auth.currentUserID == nil)
        #expect(app.notifications.scheduledReminders.isEmpty)
        #expect(!app.location.isUpdatingLocation)
        #expect(app.location.monitoredRestaurantIDs.isEmpty)
    }

    // Profile

    @Test("Changing the monthly budget is saved")
    func monthlyBudget() async throws {
        let app = TestApp()
        try await app.signIn()

        app.appState.updateMonthlyBudget(8000)
        await app.appState.waitForPendingWrites()

        #expect(app.appState.profile.monthlyBudget == 8000)
        #expect(app.database.profile?.monthlyBudget == 8000)
    }

    @Test("Bookmarking a place twice removes the bookmark")
    func toggleBookmark() async throws {
        let app = TestApp()
        try await app.signIn()
        let restaurant = MockData.dragonWok

        app.appState.toggleBookmark(for: restaurant)
        #expect(app.appState.isBookmarked(restaurant))

        app.appState.toggleBookmark(for: restaurant)
        await app.appState.waitForPendingWrites()

        #expect(!app.appState.isBookmarked(restaurant))
        #expect(app.database.profile?.bookmarkedRestaurantIDs.contains(restaurant.id) == false)
    }

    @Test("When saving fails, the student is told instead of the change being lost silently")
    func saveFailureShowsMessage() async throws {
        let appState = AppState(
            auth: MockAuthService(signedInUserID: "mock-user"),
            database: OfflineDatabaseService(),
            settings: UserDefaults(suiteName: "offline-\(UUID())")!
        )
        await appState.restoreSession()
        #expect(appState.errorMessage == nil)

        appState.addVisit(makeVisit())
        await appState.waitForPendingWrites()

        #expect(appState.errorMessage == "Couldn't save your changes. The database is offline.")
        // The visit still shows on screen; Firestore would sync it once the phone is back online.
        #expect(appState.visits.count == MockData.visits.count + 1)
    }
}
