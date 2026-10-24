import Foundation
import CoreLocation
@testable import FoodPassport

/// An `AppState` wired to the in-memory mock services, so each test controls sign-in, saved data,
/// Face ID, notifications and the student's location without Firebase or real hardware.
@MainActor
final class TestApp {
    let appState: AppState
    let auth: MockAuthService
    let database: MockDatabaseService
    let biometrics: MockBiometricService
    let notifications: MockNotificationService
    let location: MockLocationService
    /// Name of this test's own settings storage, so tests never touch each other's (or the app's) settings.
    let settingsName: String
    /// Kept alive while this "relaunched" app is in use, so the earlier launch doesn't delete the shared settings.
    private let previousLaunch: TestApp?

    /// - Parameter previousLaunch: an earlier `TestApp` whose saved settings this one reads, like reopening the app.
    init(
        signedIn: Bool = false,
        database: MockDatabaseService = MockDatabaseService(),
        biometry: BiometryKind = .faceID,
        notificationPermission: NotificationPermission = .notDetermined,
        allowsNotificationsWhenAsked: Bool = true,
        locationPermission: LocationPermission = .whenInUse,
        coordinate: CLLocationCoordinate2D? = MockData.userLocation,
        answerWhenAskedForLocation: LocationPermission = .whenInUse,
        relaunching previousLaunch: TestApp? = nil
    ) {
        auth = MockAuthService(signedInUserID: signedIn ? "mock-user" : nil)
        self.database = database
        biometrics = MockBiometricService(availableBiometry: biometry)
        notifications = MockNotificationService(permission: notificationPermission, allowsWhenAsked: allowsNotificationsWhenAsked)
        location = MockLocationService(permission: locationPermission, location: coordinate, answerWhenAsked: answerWhenAskedForLocation)
        self.previousLaunch = previousLaunch
        settingsName = previousLaunch?.settingsName ?? "FoodPassportTests-\(UUID().uuidString)"

        appState = AppState(
            auth: auth,
            database: database,
            biometrics: biometrics,
            notifications: notifications,
            location: location,
            settings: UserDefaults(suiteName: settingsName)!
        )
    }

    deinit {
        // Delete this test's settings once the test has finished with them.
        UserDefaults.standard.removePersistentDomain(forName: settingsName)
    }

    func signIn() async throws {
        try await appState.signIn(email: "student@nibm.lk", password: "password123")
    }
}

/// A visit with sensible defaults; tests only spell out what matters to them.
@MainActor
func makeVisit(
    id: String = UUID().uuidString,
    cuisine: Cuisine = .chinese,
    restaurant: Restaurant = MockData.dragonWok,
    amount: Int = 750,
    isLocationVerified: Bool = true,
    date: Date = .now
) -> Visit {
    Visit(
        id: id,
        dishName: "Test dish",
        cuisine: cuisine,
        restaurant: restaurant,
        amount: amount,
        rating: 4,
        notes: "",
        date: date,
        isLocationVerified: isLocationVerified,
        isAutoDetected: false,
        isFromReceipt: false,
        imageName: restaurant.imageName
    )
}

/// A coordinate `metres` north of `coordinate` (one degree of latitude is about 110.6 km here).
func coordinate(_ metres: Double, northOf coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: coordinate.latitude + metres / 110_600, longitude: coordinate.longitude)
}

func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}

/// A database that is offline: every write fails, and reads fail too when `failsReads` is on.
/// Used to check that the student sees an error message instead of losing data silently.
@MainActor
final class OfflineDatabaseService: DatabaseService {
    struct OfflineError: LocalizedError {
        var errorDescription: String? { "The database is offline." }
    }

    var failsReads = false

    func fetchRestaurants() async throws -> [Restaurant] {
        if failsReads { throw OfflineError() }
        return MockData.restaurants
    }

    func fetchProfile(userID: String) async throws -> UserProfile? {
        if failsReads { throw OfflineError() }
        return MockData.profile
    }

    func fetchVisits(userID: String) async throws -> [Visit] {
        if failsReads { throw OfflineError() }
        return MockData.visits
    }

    func fetchStamps(userID: String) async throws -> [Stamp] {
        if failsReads { throw OfflineError() }
        return MockData.stamps
    }

    func saveProfile(_ profile: UserProfile, userID: String) async throws { throw OfflineError() }
    func saveVisit(_ visit: Visit, userID: String) async throws { throw OfflineError() }
    func deleteVisit(id: Visit.ID, userID: String) async throws { throw OfflineError() }
    func saveStamp(_ stamp: Stamp, userID: String) async throws { throw OfflineError() }
    func deleteStamp(cuisine: Cuisine, userID: String) async throws { throw OfflineError() }
    func deleteVisitsAndStamps(userID: String) async throws { throw OfflineError() }
}
