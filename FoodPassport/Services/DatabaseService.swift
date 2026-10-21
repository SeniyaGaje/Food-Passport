import Foundation
import FirebaseFirestore

// MARK: - DatabaseService

/// Reads and writes the student's data.
/// `AppState` only talks to this protocol, so the app can run on Cloud Firestore or on the
/// in-memory mock (previews, unit tests, or before a Firebase project has been set up).
///
/// Firestore layout:
/// ```
/// restaurants/{restaurantID}          shared restaurant list
/// users/{userID}                      UserProfile (name, budget, bookmarks)
/// users/{userID}/visits/{visitID}     Visit
/// users/{userID}/stamps/{cuisine}     Stamp (one per cuisine)
/// ```
protocol DatabaseService {
    func fetchRestaurants() async throws -> [Restaurant]

    /// Returns nil when the user has no profile document yet.
    func fetchProfile(userID: String) async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile, userID: String) async throws

    /// Newest visit first.
    func fetchVisits(userID: String) async throws -> [Visit]
    func saveVisit(_ visit: Visit, userID: String) async throws
    func deleteVisit(id: Visit.ID, userID: String) async throws

    func fetchStamps(userID: String) async throws -> [Stamp]
    func saveStamp(_ stamp: Stamp, userID: String) async throws
    func deleteStamp(cuisine: Cuisine, userID: String) async throws

    /// Deletes every visit and stamp but keeps the profile ("Reset all data" in Profile).
    func deleteVisitsAndStamps(userID: String) async throws
}

// MARK: - FirestoreDatabaseService

/// `DatabaseService` backed by Cloud Firestore.
/// Firestore caches data on the device, so reads work offline and writes sync once the device is back online.
/// Create it only after `FirebaseApp.configure()` has run.
final class FirestoreDatabaseService: DatabaseService {
    private let db = Firestore.firestore()
    private let encoder = Firestore.Encoder()

    // MARK: Paths

    private var restaurantsCollection: CollectionReference {
        db.collection("restaurants")
    }

    private func userDocument(_ userID: String) -> DocumentReference {
        db.collection("users").document(userID)
    }

    private func visitsCollection(_ userID: String) -> CollectionReference {
        userDocument(userID).collection("visits")
    }

    private func stampsCollection(_ userID: String) -> CollectionReference {
        userDocument(userID).collection("stamps")
    }

    // MARK: Restaurants

    func fetchRestaurants() async throws -> [Restaurant] {
        let snapshot = try await restaurantsCollection.order(by: "distanceKm").getDocuments()
        var restaurants = try snapshot.documents.map { try $0.data(as: Restaurant.self) }

        #if DEBUG
        // Upload any sample restaurant Firestore doesn't have yet: all of them on a new Firebase project,
        // or one added to MockData later (like the NIBM canteen). Restaurants already in Firestore are left
        // untouched, so edits made in the Firebase console are kept.
        let missing = MockData.restaurants.filter { sample in
            !restaurants.contains { $0.id == sample.id }
        }
        if !missing.isEmpty {
            upload(missing)
            restaurants += missing
        }
        #endif

        return restaurants
    }

    /// Not awaited: Firestore keeps the upload in its offline cache straight away and sends it once online,
    /// so signing in never waits on a slow connection. If the security rules block the write,
    /// this debug build still shows the restaurants; they just don't reach other phones.
    private func upload(_ restaurants: [Restaurant]) {
        let batch = db.batch()
        for restaurant in restaurants {
            guard let data = try? encoder.encode(restaurant) else { continue }
            batch.setData(data, forDocument: restaurantsCollection.document(restaurant.id))
        }
        batch.commit { _ in }
    }

    // MARK: Profile

    func fetchProfile(userID: String) async throws -> UserProfile? {
        let document = try await userDocument(userID).getDocument()
        guard document.exists else { return nil }
        return try document.data(as: UserProfile.self)
    }

    func saveProfile(_ profile: UserProfile, userID: String) async throws {
        try await userDocument(userID).setData(encoder.encode(profile))
    }

    // MARK: Visits

    func fetchVisits(userID: String) async throws -> [Visit] {
        let snapshot = try await visitsCollection(userID).order(by: "date", descending: true).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Visit.self) }
    }

    func saveVisit(_ visit: Visit, userID: String) async throws {
        try await visitsCollection(userID).document(visit.id).setData(encoder.encode(visit))
    }

    func deleteVisit(id: Visit.ID, userID: String) async throws {
        try await visitsCollection(userID).document(id).delete()
    }

    // MARK: Stamps

    func fetchStamps(userID: String) async throws -> [Stamp] {
        let snapshot = try await stampsCollection(userID).order(by: "earnedDate").getDocuments()
        return try snapshot.documents.map { try $0.data(as: Stamp.self) }
    }

    func saveStamp(_ stamp: Stamp, userID: String) async throws {
        try await stampsCollection(userID).document(stamp.cuisine.rawValue).setData(encoder.encode(stamp))
    }

    func deleteStamp(cuisine: Cuisine, userID: String) async throws {
        try await stampsCollection(userID).document(cuisine.rawValue).delete()
    }

    // MARK: Reset

    func deleteVisitsAndStamps(userID: String) async throws {
        let visits = try await visitsCollection(userID).getDocuments()
        let stamps = try await stampsCollection(userID).getDocuments()

        // A batch deletes everything in one request, so the reset either fully succeeds or fully fails.
        let batch = db.batch()
        for document in visits.documents + stamps.documents {
            batch.deleteDocument(document.reference)
        }
        try await batch.commit()
    }
}

// MARK: - MockDatabaseService

/// In-memory `DatabaseService` for previews, unit tests and running without Firebase.
/// Holds a single user's data, so the `userID` arguments are ignored.
final class MockDatabaseService: DatabaseService {
    var restaurants: [Restaurant]
    var profile: UserProfile?
    var visits: [Visit]
    var stamps: [Stamp]

    init(
        restaurants: [Restaurant] = MockData.restaurants,
        profile: UserProfile? = MockData.profile,
        visits: [Visit] = MockData.visits,
        stamps: [Stamp] = MockData.stamps
    ) {
        self.restaurants = restaurants
        self.profile = profile
        self.visits = visits
        self.stamps = stamps
    }

    func fetchRestaurants() async throws -> [Restaurant] {
        restaurants
    }

    func fetchProfile(userID: String) async throws -> UserProfile? {
        profile
    }

    func saveProfile(_ profile: UserProfile, userID: String) async throws {
        self.profile = profile
    }

    func fetchVisits(userID: String) async throws -> [Visit] {
        visits.sorted { $0.date > $1.date }
    }

    func saveVisit(_ visit: Visit, userID: String) async throws {
        visits.removeAll { $0.id == visit.id }
        visits.append(visit)
    }

    func deleteVisit(id: Visit.ID, userID: String) async throws {
        visits.removeAll { $0.id == id }
    }

    func fetchStamps(userID: String) async throws -> [Stamp] {
        stamps
    }

    func saveStamp(_ stamp: Stamp, userID: String) async throws {
        stamps.removeAll { $0.cuisine == stamp.cuisine }
        stamps.append(stamp)
    }

    func deleteStamp(cuisine: Cuisine, userID: String) async throws {
        stamps.removeAll { $0.cuisine == cuisine }
    }

    func deleteVisitsAndStamps(userID: String) async throws {
        visits = []
        stamps = []
    }
}
