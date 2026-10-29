import Foundation
import CoreLocation
@testable import FoodPassport

/// An AppState that uses fake services, so tests control sign-in, data, Face ID,
/// notifications and location without Firebase or a real phone.
@MainActor
final class TestApp {
    let appState: AppState
    let auth: MockAuthService
    let database: MockDatabaseService
    let biometrics: MockBiometricService
    let notifications: MockNotificationService
    let location: MockLocationService
    /// Each test gets its own settings, so tests don't affect each other.
    let settingsName: String
    /// Keeps the earlier launch alive, so it doesn't delete the settings we're reading.
    private let previousLaunch: TestApp?

    /// Pass `relaunching:` to read another TestApp's saved settings, like reopening the app.
    init(
        signedIn: Bool = false,
        database: MockDatabaseService? = nil,
        biometry: BiometryKind = .faceID,
        notificationPermission: NotificationPermission = .notDetermined,
        allowsNotificationsWhenAsked: Bool = true,
        locationPermission: LocationPermission = .whenInUse,
        // On campus, the same spot as MockData.userLocation.
        coordinate: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: 6.9028, longitude: 79.8598),
        answerWhenAskedForLocation: LocationPermission = .whenInUse,
        relaunching previousLaunch: TestApp? = nil,
        photoStore: VisitPhotoStore = LocalVisitPhotoStore(),
        widgets: WidgetPublishing = NoWidgetPublisher()
    ) {
        auth = MockAuthService(signedInUserID: signedIn ? "mock-user" : nil)
        let database = database ?? MockDatabaseService()
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
            settings: UserDefaults(suiteName: settingsName)!,
            photoStore: photoStore,
            widgets: widgets
        )
    }

    deinit {
        // Delete this test's settings when it's finished.
        UserDefaults.standard.removePersistentDomain(forName: settingsName)
    }

    func signIn() async throws {
        try await appState.signIn(email: "student@nibm.lk", password: "password123")
    }
}

/// Makes a visit with default values, so tests only set what they care about.
@MainActor
func makeVisit(
    id: String = UUID().uuidString,
    cuisine: Cuisine = .chinese,
    restaurant: Restaurant? = nil,
    amount: Int = 750,
    isLocationVerified: Bool = true,
    date: Date = .now
) -> Visit {
    let restaurant = restaurant ?? MockData.dragonWok
    return Visit(
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

/// A point the given number of metres north (1 degree of latitude is about 110.6 km).
func coordinate(_ metres: Double, northOf coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: coordinate.latitude + metres / 110_600, longitude: coordinate.longitude)
}

func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
    CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}

/// A fake offline database: saving always fails, and loading fails too if `failsReads` is on.
/// Used to check the student sees an error message.
@MainActor
final class OfflineDatabaseService: DatabaseService {
    struct OfflineError: LocalizedError {
        var errorDescription: String? { "The database is offline." }
    }

    var failsReads = false
    var failsWrites = true
    var writtenVisitIDs: [String] = []

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
    func saveVisit(_ visit: Visit, userID: String) async throws {
        if failsWrites { throw OfflineError() }
        writtenVisitIDs.append(visit.id)
    }
    func deleteVisit(id: Visit.ID, userID: String) async throws { throw OfflineError() }
    func saveStamp(_ stamp: Stamp, userID: String) async throws { throw OfflineError() }
    func deleteStamp(cuisine: Cuisine, userID: String) async throws { throw OfflineError() }
    func deleteVisitsAndStamps(userID: String) async throws {
        if failsWrites { throw OfflineError() }
        writtenVisitIDs = []
    }
}
