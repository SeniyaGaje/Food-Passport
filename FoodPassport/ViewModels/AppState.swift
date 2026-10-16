import Foundation
import CoreLocation
import Observation
import SwiftUI

// MARK: - AppState

/// App-wide session state shared through the environment: who is signed in, their data, and their device settings.
/// Every outside system (Firebase, Face ID, notifications, settings storage) is passed in (dependency injection),
/// so the same code runs on the real services in the app and on in-memory mocks in previews and unit tests.
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
    /// Why the last Face ID attempt on the lock screen failed, if it did.
    var lockMessage: String?

    var profile = MockData.profile
    var restaurants = MockData.restaurants
    var visits = MockData.visits
    var stamps = MockData.stamps

    /// Shown in an alert by `RootView` when loading or saving fails.
    var errorMessage: String?
    /// Shows `RootView`'s "Notifications are off" alert, which links to Settings.
    var isShowingNotificationSettingsPrompt = false
    /// Set when the student taps a notification; `MainTabView` opens the matching screen.
    var notificationDestination: NotificationDestination?

    // MARK: Location state

    private(set) var locationPermission: LocationPermission = .notDetermined
    /// The student's latest real location, or nil before it is known or without permission.
    private(set) var userLocation: CLLocation?
    /// Set when the student walks into a restaurant while the app is open; `MainTabView` shows the arrival banner.
    var arrivedRestaurant: Restaurant?
    /// Kept up to date by `RootView`. While the app is open, arrivals show an in-app banner instead of a notification.
    var isAppActive = false
    /// When each restaurant's arrival alert last fired, so walking past the door twice doesn't alert twice.
    private var lastArrivalAlerts: [Restaurant.ID: Date] = [:]
    static let arrivalAlertCooldown: TimeInterval = 3 * 60 * 60

    // MARK: Device settings
    // Stored in UserDefaults rather than Firestore because they belong to this phone, not to the account.

    private(set) var isFaceIDEnabled = false {
        didSet { settings.set(isFaceIDEnabled, forKey: SettingsKey.faceIDEnabled) }
    }
    private(set) var plannedVisitRemindersEnabled = false {
        didSet { settings.set(plannedVisitRemindersEnabled, forKey: SettingsKey.plannedVisitReminders) }
    }
    private(set) var weeklyChallengeReminderEnabled = false {
        didSet { settings.set(weeklyChallengeReminderEnabled, forKey: SettingsKey.weeklyChallengeReminder) }
    }
    private(set) var weeklyReminderHour = 9 {
        didSet { settings.set(weeklyReminderHour, forKey: SettingsKey.weeklyReminderHour) }
    }
    private(set) var weeklyReminderMinute = 0 {
        didSet { settings.set(weeklyReminderMinute, forKey: SettingsKey.weeklyReminderMinute) }
    }

    private enum SettingsKey {
        static let faceIDEnabled = "faceIDEnabled"
        static let plannedVisitReminders = "plannedVisitRemindersEnabled"
        static let weeklyChallengeReminder = "weeklyChallengeReminderEnabled"
        static let weeklyReminderHour = "weeklyReminderHour"
        static let weeklyReminderMinute = "weeklyReminderMinute"
    }

    // MARK: Services

    private let auth: AuthService
    private let database: DatabaseService
    private let biometrics: BiometricService
    private let notifications: NotificationService
    private let location: LocationService
    private let settings: UserDefaults

    /// Background saves and notifications that haven't finished yet, so unit tests can wait for them.
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]

    init(
        auth: AuthService = MockAuthService(),
        database: DatabaseService = MockDatabaseService(),
        biometrics: BiometricService = MockBiometricService(),
        notifications: NotificationService = MockNotificationService(),
        location: LocationService = MockLocationService(),
        settings: UserDefaults = .standard
    ) {
        self.auth = auth
        self.database = database
        self.biometrics = biometrics
        self.notifications = notifications
        self.location = location
        self.settings = settings

        isFaceIDEnabled = settings.bool(forKey: SettingsKey.faceIDEnabled)
        plannedVisitRemindersEnabled = settings.bool(forKey: SettingsKey.plannedVisitReminders)
        weeklyChallengeReminderEnabled = settings.bool(forKey: SettingsKey.weeklyChallengeReminder)
        weeklyReminderHour = settings.object(forKey: SettingsKey.weeklyReminderHour) as? Int ?? 9
        weeklyReminderMinute = settings.object(forKey: SettingsKey.weeklyReminderMinute) as? Int ?? 0

        notifications.onOpen = { [weak self] destination in
            self?.notificationDestination = destination
        }

        locationPermission = location.permission
        location.onLocationChange = { [weak self] newLocation in
            self?.updateLocation(newLocation)
        }
        location.onPermissionChange = { [weak self] permission in
            self?.locationPermissionChanged(to: permission)
        }
        location.onEnterRestaurant = { [weak self] restaurantID in
            self?.handleArrival(at: restaurantID)
        }
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
            // Reopening the app is like logging in again, so Face ID is asked for before the passport shows.
            isLocked = isFaceIDEnabled
            await refreshReminders()
            startLocationServices()
        } catch {
            errorMessage = "Couldn't load your passport. \(error.localizedDescription)"
            stage = .onboarding
        }
    }

    func signIn(email: String, password: String) async throws {
        let userID = try await auth.signIn(email: email, password: password)
        try await loadUserData(userID: userID)
        enterApp()
        await refreshReminders()
        startLocationServices()
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
        restaurants = withRealDistances(try await database.fetchRestaurants())
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(email: email)
    }

    func enterApp() {
        stage = .main
        isLocked = false
    }

    func signOut() {
        do {
            try auth.signOut()
        } catch {
            errorMessage = "Couldn't sign out. \(error.localizedDescription)"
            return
        }
        // Reminders belong to the signed-in student, so the next person on this phone doesn't get them.
        notifications.cancelAllReminders()
        notificationDestination = nil
        location.stopMonitoringArrivals()
        location.stopUpdatingLocation()
        lastArrivalAlerts = [:]
        arrivedRestaurant = nil
        stage = .onboarding
        isLocked = false
    }

    // MARK: Location and arrivals (Core Location + geofencing)

    /// Onboarding's "Allow location" button. Returns whether location was allowed.
    func requestLocationPermission() async -> Bool {
        let permission = await location.requestWhenInUsePermission()
        locationPermissionChanged(to: permission)
        return permission.allowsLocation
    }

    /// Directions' Start button: get ready to alert the student when they reach `restaurant`.
    func startArrivalAlerts(for restaurant: Restaurant) async {
        // "Always" lets iOS notice the arrival even with the phone locked in a pocket.
        if locationPermission == .whenInUse {
            location.requestAlwaysPermission()
        }
        // The alert is a notification when the app is closed, so make sure notifications are allowed.
        if await notifications.permission() == .notDetermined {
            _ = await notifications.requestPermission()
        }
        // Heading there on purpose, so alert again even if this restaurant alerted earlier today.
        lastArrivalAlerts[restaurant.id] = nil

        if let userLocation {
            checkForArrival(at: userLocation)
        }
    }

    /// True when the student is close enough to `restaurant` for a visit there to count as location verified.
    func isAtRestaurant(_ restaurant: Restaurant) -> Bool {
        guard let userLocation else { return false }
        return userLocation.distance(from: restaurant.location) <= Geofence.verificationRadius
    }

    /// Starts live location and the restaurant geofences, if the student allowed location access.
    private func startLocationServices() {
        guard locationPermission.allowsLocation, auth.currentUserID != nil else { return }

        if let lastKnown = location.currentLocation {
            updateLocation(lastKnown)
        }
        location.startUpdatingLocation()
        location.monitorArrivals(at: restaurants)
    }

    private func locationPermissionChanged(to permission: LocationPermission) {
        locationPermission = permission

        if permission.allowsLocation {
            startLocationServices()
        } else {
            // Location was turned off (possibly in Settings): forget it, so distances fall back to campus estimates.
            location.stopUpdatingLocation()
            location.stopMonitoringArrivals()
            userLocation = nil
        }
    }

    private func updateLocation(_ newLocation: CLLocation) {
        userLocation = newLocation
        restaurants = withRealDistances(restaurants)
        checkForArrival(at: newLocation)
    }

    /// The geofence check while the app is open: iOS's own region monitoring covers the app being closed,
    /// and also needs "Always" permission, so live location is checked here as well.
    private func checkForArrival(at currentLocation: CLLocation) {
        let nearby = restaurants
            .map { (restaurant: $0, metres: currentLocation.distance(from: $0.location)) }
            .filter { $0.metres <= Geofence.arrivalRadius }
            .min { $0.metres < $1.metres }

        if let nearby {
            handleArrival(at: nearby.restaurant.id)
        }
    }

    /// The student walked into a restaurant's geofence: show the arrival banner, or a notification if the app is closed.
    private func handleArrival(at restaurantID: Restaurant.ID) {
        guard auth.currentUserID != nil,
              let restaurant = restaurants.first(where: { $0.id == restaurantID })
        else { return }

        if let lastAlert = lastArrivalAlerts[restaurantID], Date.now.timeIntervalSince(lastAlert) < Self.arrivalAlertCooldown {
            return
        }
        lastArrivalAlerts[restaurantID] = .now

        if isAppActive && stage == .main {
            arrivedRestaurant = restaurant
        } else {
            runInBackground { [notifications] in
                try await notifications.schedule(.arrival(at: restaurant))
            }
        }
    }

    /// Replaces stored campus distances with real ones measured from the student, when their location is known.
    private func withRealDistances(_ restaurants: [Restaurant]) -> [Restaurant] {
        guard let userLocation else { return restaurants }
        return restaurants.map { $0.withDistance(from: userLocation) }
    }

    // MARK: Face ID

    var biometryKind: BiometryKind {
        biometrics.availableBiometry
    }

    /// Turning Face ID on asks for the student's face first, so they know it works before the app relies on it.
    func setFaceIDEnabled(_ isOn: Bool) async {
        guard isOn else {
            isFaceIDEnabled = false
            return
        }

        do {
            try await biometrics.authenticate(reason: "Turn on \(biometryKind.name) to keep your passport private.")
            isFaceIDEnabled = true
        } catch {
            // A cancelled prompt has no description, so no alert is shown for it.
            errorMessage = (error as? BiometricError)?.errorDescription
        }
    }

    /// Locks the passport when the app goes to the background, if Face ID is on.
    func lockIfNeeded() {
        guard stage == .main, isFaceIDEnabled else { return }
        isLocked = true
        lockMessage = nil
    }

    func unlockWithBiometrics() async {
        guard isLocked else { return }
        lockMessage = nil

        do {
            try await biometrics.authenticate(reason: "Unlock your FoodPassport.")
            isLocked = false
        } catch {
            lockMessage = (error as? BiometricError)?.errorDescription
        }
    }

    // MARK: Reminders (local notifications)

    var weeklyReminderTime: Date {
        Calendar.current.date(bySettingHour: weeklyReminderHour, minute: weeklyReminderMinute, second: 0, of: .now) ?? .now
    }

    /// Onboarding's "Allow notifications" button. If the student allows them, both kinds of reminder are turned on.
    /// Returns whether notifications were allowed.
    func allowRemindersDuringOnboarding() async -> Bool {
        guard await notifications.requestPermission() else { return false }
        plannedVisitRemindersEnabled = true
        weeklyChallengeReminderEnabled = true
        await scheduleWeeklyChallengeReminder()
        return true
    }

    func setPlannedVisitReminders(_ isOn: Bool) async {
        if isOn {
            guard await ensureNotificationPermission() else { return }
            plannedVisitRemindersEnabled = true
        } else {
            plannedVisitRemindersEnabled = false
            await notifications.cancelReminders(withIDPrefix: LocalReminder.visitReminderIDPrefix)
        }
    }

    func setWeeklyChallengeReminder(_ isOn: Bool) async {
        if isOn {
            guard await ensureNotificationPermission() else { return }
            weeklyChallengeReminderEnabled = true
            await scheduleWeeklyChallengeReminder()
        } else {
            weeklyChallengeReminderEnabled = false
            await notifications.cancelReminders(withIDPrefix: LocalReminder.weeklyChallengeID)
        }
    }

    func setWeeklyReminderTime(_ time: Date) async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        weeklyReminderHour = parts.hour ?? 9
        weeklyReminderMinute = parts.minute ?? 0

        if weeklyChallengeReminderEnabled {
            await scheduleWeeklyChallengeReminder()
        }
    }

    /// Plans a visit and, when `remind` is on, schedules a reminder 30 minutes before it.
    /// Returns when the reminder will fire, or nil when no reminder was set
    /// (not asked for, notifications not allowed, or the visit is less than 30 minutes away).
    func planVisit(to restaurant: Restaurant, at visitDate: Date, remind: Bool) async -> Date? {
        let reminder = LocalReminder.plannedVisit(to: restaurant, at: visitDate)
        guard remind, case .once(let fireDate) = reminder.schedule, fireDate > .now else { return nil }
        guard await ensureNotificationPermission() else { return nil }

        do {
            try await notifications.schedule(reminder)
            plannedVisitRemindersEnabled = true
            return fireDate
        } catch {
            errorMessage = "Couldn't set the reminder. \(error.localizedDescription)"
            return nil
        }
    }

    /// Asks for permission the first time. If the student blocked notifications earlier,
    /// shows the alert that links to Settings, because the app can't ask again.
    private func ensureNotificationPermission() async -> Bool {
        switch await notifications.permission() {
        case .allowed:
            return true
        case .notDetermined:
            return await notifications.requestPermission()
        case .denied:
            isShowingNotificationSettingsPrompt = true
            return false
        }
    }

    private func scheduleWeeklyChallengeReminder() async {
        do {
            try await notifications.schedule(.weeklyChallenge(hour: weeklyReminderHour, minute: weeklyReminderMinute))
        } catch {
            errorMessage = "Couldn't set the weekly reminder. \(error.localizedDescription)"
        }
    }

    /// Keeps the reminder switches honest at launch, e.g. if notifications were turned off in Settings.
    private func refreshReminders() async {
        guard await notifications.permission() == .allowed else {
            plannedVisitRemindersEnabled = false
            weeklyChallengeReminderEnabled = false
            return
        }

        if weeklyChallengeReminderEnabled {
            await scheduleWeeklyChallengeReminder()
        }
    }

    private func loadUserData(userID: String) async throws {
        restaurants = withRealDistances(try await database.fetchRestaurants())
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

        runInBackground { [database] in
            do {
                try await write(database, userID)
            } catch {
                self.errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
            }
        }
    }

    /// Starts work the screen doesn't wait for, keeping track of it so unit tests can wait for it to finish.
    private func runInBackground(_ work: @escaping () async throws -> Void) {
        let id = UUID()
        pendingWrites[id] = Task {
            try? await work()
            pendingWrites[id] = nil
        }
    }

    /// Waits until every background save and notification has finished. Used by unit tests.
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
