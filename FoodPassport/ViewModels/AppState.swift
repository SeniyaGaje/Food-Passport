import Foundation
import CoreLocation
import Observation
import SwiftUI
import UIKit

/// The app's shared data: who is signed in, their visits and stamps, and their settings.
/// The services (Firebase, Face ID, notifications, location) are passed in, so tests can pass in mocks instead.
@Observable
final class AppState {
    enum Stage {
        /// Checking if someone is already signed in.
        case launching
        case onboarding
        case main
    }

    var stage: Stage = .launching
    var isLocked = false
    /// Why the last Face ID try on the lock screen failed.
    var lockMessage: String?

    var profile = MockData.profile
    var restaurants = MockData.restaurants
    var visits = MockData.visits
    var stamps = MockData.stamps
    private(set) var questSettings: QuestSettings?
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isOffline = false
    var isSavingChanges: Bool { !pendingWrites.isEmpty }

    /// Shown as an alert when loading or saving fails.
    var errorMessage: String?
    /// Shows the "Notifications are off" alert, which links to Settings.
    var isShowingNotificationSettingsPrompt = false
    /// Set when a notification is tapped, so MainTabView can open the right screen.
    var notificationDestination: NotificationDestination?

    // Location state

    private(set) var locationPermission: LocationPermission = .notDetermined
    /// Where the student is, or nil if we don't know.
    private(set) var userLocation: CLLocation?
    /// Set when the student arrives at a restaurant with the app open, so the banner shows.
    var arrivedRestaurant: Restaurant?
    /// True while the app is on screen. Arrivals then show a banner instead of a notification.
    var isAppActive = false
    /// When each restaurant last alerted, so walking past twice doesn't alert twice.
    private var lastArrivalAlerts: [Restaurant.ID: Date] = [:]
    static let arrivalAlertCooldown: TimeInterval = 3 * 60 * 60

    // Device settings
    // Saved in UserDefaults (not Firestore), because they belong to this phone, not the account.

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

    // Services

    private let auth: AuthService
    private let database: DatabaseService
    private let biometrics: BiometricService
    private let notifications: NotificationService
    private let location: LocationService
    private let settings: UserDefaults
    private let photoStore: VisitPhotoStore
    private let widgets: WidgetPublishing
    private var photoSaveGeneration = 0

    /// Background saves that haven't finished yet, so tests can wait for them.
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    private var failedWrites: [UUID: (userID: String, write: (DatabaseService, String) async throws -> Void)] = [:]
    var hasFailedWrites: Bool { !failedWrites.isEmpty }

    init(
        auth: AuthService = MockAuthService(),
        database: DatabaseService = MockDatabaseService(),
        biometrics: BiometricService = MockBiometricService(),
        notifications: NotificationService = MockNotificationService(),
        location: LocationService = MockLocationService(),
        settings: UserDefaults = .standard,
        photoStore: VisitPhotoStore = LocalVisitPhotoStore(),
        widgets: WidgetPublishing = NoWidgetPublisher()
    ) {
        self.auth = auth
        self.database = database
        self.biometrics = biometrics
        self.notifications = notifications
        self.location = location
        self.settings = settings
        self.photoStore = photoStore
        self.widgets = widgets

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

    var activeQuest: Quest {
        let settings = questSettings ?? QuestSettings()
        let end = settings.endDate()
        let meals = visits.filter { $0.date >= settings.startedAt && $0.date < end }
        let tried = Set(meals.map(\.cuisine))
        let spent = meals.map(\.amount).reduce(0, +)
        let trail = MockData.foodTrails.first { $0.id == settings.trailID } ?? MockData.campusFoodTrail
        let completedStops = Set(meals.map { $0.restaurant.id })
        let target = settings.type == .foodTrail ? trail.stops.count : settings.targetCuisines
        var suggestedCuisines = tried
        let candidates = settings.type == .foodTrail
            ? trail.stops.map(\.restaurant).filter { !completedStops.contains($0.id) }
            : restaurants.sorted { $0.distanceKm < $1.distanceKm }.filter {
                $0.distanceKm <= settings.maxDistanceKm && suggestedCuisines.insert($0.cuisine).inserted
            }
        var remaining = max(0, settings.budget - spent)
        let plan = candidates.prefix(target).map { restaurant in
            let estimate = restaurant.priceRange.lowerBound
            let fits = estimate <= remaining
            if fits { remaining -= estimate }
            return PlannedStop(restaurant: restaurant, estimatedCost: estimate, fitsBudget: fits)
        }
        return Quest(title: settings.type == .foodTrail ? trail.name : "Explore \(settings.targetCuisines) cuisines",
                     type: settings.type, targetCuisines: target,
                     cuisinesTried: settings.type == .foodTrail ? completedStops.intersection(Set(trail.stops.map(\.id))).count : tried.count,
                     budget: settings.budget, spent: spent, duration: settings.duration,
                     maxDistanceKm: settings.maxDistanceKm, plan: plan,
                     planExplanation: "Suggestions use your distance limit, untried cuisines and remaining budget. Prices are estimates.")
    }

    var hasActiveQuest: Bool {
        guard let questSettings else { return false }
        return questSettings.endDate() > .now
    }

    var currentTrail: FoodTrail {
        let sample = MockData.campusFoodTrail
        let visited = Set(visits.map { $0.restaurant.id })
        return FoodTrail(id: sample.id, name: sample.name, summary: sample.summary,
                         stops: sample.stops.map { TrailStop(restaurant: $0.restaurant, isVisited: visited.contains($0.id)) })
    }

    var currentChallenge: WeeklyChallenge {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        let meals = visits.filter { week?.contains($0.date) == true }
        return WeeklyChallenge(title: "Try 3 cuisines this week", details: "Log meals from three different cuisines.",
                               daysLeft: max(0, Calendar.current.dateComponents([.day], from: .now, to: week?.end ?? .now).day ?? 0),
                               completed: Set(meals.map(\.cuisine)).count, target: 3, suggestions: activeQuest.plan)
    }

    func saveQuest(_ settings: QuestSettings) {
        questSettings = settings
        save { database, userID in try await database.saveQuest(settings, userID: userID) }
        publishWidgets()
    }

    func updateConnectivity(isOffline: Bool) { self.isOffline = isOffline }

    func refreshData() async {
        guard let userID = auth.currentUserID, !isLoading else { return }
        do {
            try await loadUserData(userID: userID)
            if stage == .onboarding { enterApp() }
        } catch {
            loadError = "Couldn't refresh your passport. Your current data is still available."
        }
    }

    private func publishWidgets() {
        guard auth.currentUserID != nil, stage == .main, !isLocked else {
            widgets.publish(WidgetSnapshot())
            return
        }
        let month = Calendar.current.dateInterval(of: .month, for: .now)
        let spent = visits.filter { month?.contains($0.date) == true }.map(\.amount).reduce(0, +)
        widgets.publish(WidgetSnapshot(isSignedIn: true, questTitle: hasActiveQuest ? activeQuest.title : nil,
            cuisinesTried: activeQuest.cuisinesTried, targetCuisines: activeQuest.targetCuisines,
            questUnit: activeQuest.progressUnit,
            questEndsAt: questSettings?.endDate(), monthlyBudget: profile.monthlyBudget,
            monthlySpent: spent, budgetMonth: WidgetSnapshot.monthKey(for: .now)))
    }

    // Session

    /// Runs once at launch. Skips onboarding if the student is still signed in.
    func restoreSession() async {
        guard let userID = auth.currentUserID else {
            stage = .onboarding
            return
        }

        do {
            try await loadUserData(userID: userID)
            enterApp()
            // Opening the app is like signing in again, so ask for Face ID first.
            isLocked = isFaceIDEnabled
            publishWidgets()
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

    /// Creates the account and its profile. Onboarding (permissions, budget) comes next.
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
        publishWidgets()
    }

    func signOut() {
        do {
            try auth.signOut()
        } catch {
            errorMessage = "Couldn't sign out. \(error.localizedDescription)"
            return
        }
        // Clear this student's reminders, so the next person on the phone doesn't get them.
        photoSaveGeneration += 1
        notifications.cancelAllReminders()
        notificationDestination = nil
        location.stopMonitoringArrivals()
        location.stopUpdatingLocation()
        lastArrivalAlerts = [:]
        arrivedRestaurant = nil
        stage = .onboarding
        isLocked = false
        questSettings = nil
        failedWrites = [:]
        visits = []
        stamps = []
        loadError = nil
        widgets.publish(WidgetSnapshot())
    }

    // Location and arrivals

    /// The "Allow location" button in onboarding. Returns true if allowed.
    func requestLocationPermission() async -> Bool {
        let permission = await location.requestWhenInUsePermission()
        locationPermissionChanged(to: permission)
        return permission.allowsLocation
    }

    /// The Start button in Directions: alert the student when they reach the restaurant.
    func startArrivalAlerts(for restaurant: Restaurant) async {
        // "Always" lets iOS notice the arrival even with the phone in a pocket.
        if locationPermission == .whenInUse {
            location.requestAlwaysPermission()
        }
        // If the app is closed the alert is a notification, so ask for notifications too.
        if await notifications.permission() == .notDetermined {
            _ = await notifications.requestPermission()
        }
        // They're heading there on purpose, so alert again even if it alerted earlier.
        lastArrivalAlerts[restaurant.id] = nil

        if let userLocation {
            checkForArrival(at: userLocation)
        }
    }

    /// True if the student is close enough for the visit to count as verified.
    func isAtRestaurant(_ restaurant: Restaurant) -> Bool {
        guard let userLocation else { return false }
        return userLocation.distance(from: restaurant.location) <= Geofence.verificationRadius
    }

    /// Starts tracking location and watching restaurants, if location is allowed.
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
            // Location was turned off: forget it, so distances go back to the campus estimates.
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

    /// Checks if the student has reached a restaurant while the app is open.
    /// (iOS handles this itself when the app is closed, but only with "Always" permission.)
    private func checkForArrival(at currentLocation: CLLocation) {
        var closest: Restaurant?
        var closestDistance = 0.0

        for restaurant in restaurants {
            let metres = currentLocation.distance(from: restaurant.location)
            guard metres <= Geofence.arrivalRadius else { continue }

            if closest == nil || metres < closestDistance {
                closest = restaurant
                closestDistance = metres
            }
        }

        if let closest {
            handleArrival(at: closest.id)
        }
    }

    /// The student arrived: show the banner, or a notification if the app is closed.
    private func handleArrival(at restaurantID: Restaurant.ID) {
        guard auth.currentUserID != nil,
              let restaurant = restaurants.first(where: { $0.id == restaurantID })
        else { return }

        // Don't alert again for the same place within 3 hours.
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

    /// Swaps the saved campus distances for real ones from the student's location.
    private func withRealDistances(_ restaurants: [Restaurant]) -> [Restaurant] {
        guard let userLocation else { return restaurants }
        return restaurants.map { $0.withDistance(from: userLocation) }
    }

    // Face ID

    var biometryKind: BiometryKind {
        biometrics.availableBiometry
    }

    /// Turning Face ID on scans the face first, so we know it works.
    func setFaceIDEnabled(_ isOn: Bool) async {
        guard isOn else {
            isFaceIDEnabled = false
            return
        }

        do {
            try await biometrics.authenticate(reason: "Turn on \(biometryKind.name) to keep your passport private.")
            isFaceIDEnabled = true
        } catch {
            // Cancelling has no message, so no alert is shown.
            errorMessage = (error as? BiometricError)?.errorDescription
        }
    }

    /// Locks the app when it goes to the background, if Face ID is on.
    func lockIfNeeded() {
        guard stage == .main, isFaceIDEnabled else { return }
        isLocked = true
        lockMessage = nil
        publishWidgets()
    }

    func unlockWithBiometrics() async {
        guard isLocked else { return }
        lockMessage = nil

        do {
            try await biometrics.authenticate(reason: "Unlock your FoodPassport.")
            isLocked = false
            publishWidgets()
        } catch {
            lockMessage = (error as? BiometricError)?.errorDescription
        }
    }

    // Reminders

    var weeklyReminderTime: Date {
        Calendar.current.date(bySettingHour: weeklyReminderHour, minute: weeklyReminderMinute, second: 0, of: .now) ?? .now
    }

    /// The "Allow notifications" button in onboarding. If allowed, both reminders are turned on.
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

    /// Sets a reminder 30 minutes before a planned visit, if `remind` is on.
    /// Returns the reminder time, or nil if none was set (e.g. the visit is too soon).
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

    /// Asks for permission the first time. If they said no before, we can't ask again,
    /// so show the alert that links to Settings.
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

    /// At launch, turn the switches off if notifications were turned off in Settings.
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
        let generation = photoSaveGeneration
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        // Assign together, so a failed refresh cannot replace just half the passport.
        let places = try await database.fetchRestaurants()
        let meals = try await database.fetchVisits(userID: userID)
        let earned = try await database.fetchStamps(userID: userID)
        let quest = try await database.fetchQuest(userID: userID)
        let savedProfile = try await database.fetchProfile(userID: userID)
        guard auth.currentUserID == userID else { throw VisitPhotoError.signedOut }
        guard generation == photoSaveGeneration else { throw VisitPhotoError.cancelled }
        restaurants = withRealDistances(places)
        visits = meals
        stamps = earned
        questSettings = quest
        if let savedProfile {
            profile = savedProfile
        } else {
            // The account has no profile yet (e.g. sign-up was interrupted), so make a blank one.
            profile = UserProfile(name: "", email: "", memberSince: .now, monthlyBudget: 3000, bookmarkedRestaurantIDs: [])
            saveProfile()
        }
        publishWidgets()
        runInBackground { [photoStore] in await photoStore.retryPendingDeletions(userID: userID) }
    }

    // Visits and stamps

    /// Save photos first, so a visit never points to a photo that failed to save.
    func saveVisit(_ visit: Visit, photos: [UIImage]) async throws -> Stamp? {
        guard let userID = auth.currentUserID else { throw VisitPhotoError.signedOut }
        let generation = photoSaveGeneration
        let ids = try await photoStore.save(photos, userID: userID)
        guard auth.currentUserID == userID else {
            await photoStore.delete(ids: ids, userID: userID)
            throw VisitPhotoError.signedOut
        }
        guard generation == photoSaveGeneration else {
            await photoStore.delete(ids: ids, userID: userID)
            throw VisitPhotoError.cancelled
        }
        var savedVisit = visit
        savedVisit.photoIDs = ids.isEmpty ? nil : ids
        return addVisit(savedVisit)
    }

    func mealPhoto(id: String) async -> UIImage? {
        guard let userID = auth.currentUserID else { return nil }
        let image = await photoStore.load(id: id, userID: userID)
        return auth.currentUserID == userID ? image : nil
    }

    /// Adds a visit and saves it.
    /// Returns a new stamp if it's the first verified visit for that cuisine.
    @discardableResult
    func addVisit(_ visit: Visit) -> Stamp? {
        visits.insert(visit, at: 0)
        publishWidgets()
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

    /// Deletes a visit, and the stamp it earned (if any).
    func deleteVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        publishWidgets()
        save { database, userID in
            try await database.deleteVisit(id: visit.id, userID: userID)
            await self.photoStore.delete(ids: visit.photoIDs ?? [], userID: userID)
        }

        for stamp in stamps where stamp.visitID == visit.id {
            stamps.removeAll { $0.cuisine == stamp.cuisine }
            save { database, userID in try await database.deleteStamp(cuisine: stamp.cuisine, userID: userID) }
        }
    }

    func resetAllData() {
        photoSaveGeneration += 1
        failedWrites = [:]
        let photoIDs = visits.flatMap { $0.photoIDs ?? [] }
        visits = []
        stamps = []
        publishWidgets()
        save { database, userID in
            try await database.deleteVisitsAndStamps(userID: userID)
            await self.photoStore.delete(ids: photoIDs, userID: userID)
        }
    }

    // Profile

    func updateMonthlyBudget(_ amount: Int) {
        profile.monthlyBudget = amount
        publishWidgets()
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

    // Saving

    /// Saves to the database in the background, so the student never waits.
    /// Firestore keeps the change offline and syncs it when the phone is online.
    private func save(_ write: @escaping (DatabaseService, String) async throws -> Void) {
        guard let userID = auth.currentUserID else { return }

        let id = UUID()
        let generation = photoSaveGeneration
        runInBackground { [database] in
            do {
                try await write(database, userID)
            } catch {
                guard self.auth.currentUserID == userID, self.photoSaveGeneration == generation else { return }
                self.failedWrites[id] = (userID, write)
                self.errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
            }
        }
    }

    func retryFailedWrites() {
        let failed = failedWrites.values.filter { $0.userID == auth.currentUserID }
        failedWrites = [:]
        for operation in failed { save(operation.write) }
    }

    /// Runs work in the background, and remembers it so tests can wait for it.
    private func runInBackground(_ work: @escaping () async throws -> Void) {
        let id = UUID()
        pendingWrites[id] = Task {
            try? await work()
            pendingWrites[id] = nil
        }
    }

    /// Waits for all background work to finish. Used by tests.
    func waitForPendingWrites() async {
        for task in pendingWrites.values {
            await task.value
        }
    }
}

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

    /// After a new stamp: close the pop-up, show "Visit logged", then the budget update.
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
    case budgetUpdate
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
