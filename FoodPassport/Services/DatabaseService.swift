import Foundation
import FirebaseFirestore

/// Reads and writes the student's data. AppState only uses this protocol, so it can run on Firestore or the mock.
/// Firestore layout: restaurants/{id}, users/{userID}, users/{userID}/visits/{id}, users/{userID}/stamps/{cuisine}.
protocol DatabaseService {
    func fetchRestaurants() async throws -> [Restaurant]

    /// nil if this user has no profile saved yet.
    func fetchProfile(userID: String) async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile, userID: String) async throws

    /// Newest visit first.
    func fetchVisits(userID: String) async throws -> [Visit]
    func saveVisit(_ visit: Visit, userID: String) async throws
    func deleteVisit(id: Visit.ID, userID: String) async throws

    func fetchStamps(userID: String) async throws -> [Stamp]
    func saveStamp(_ stamp: Stamp, userID: String) async throws
    func deleteStamp(cuisine: Cuisine, userID: String) async throws

    /// "Reset all data" in Profile: deletes visits and stamps but keeps the profile.
    func deleteVisitsAndStamps(userID: String) async throws
}

/// The real database, Cloud Firestore. It keeps a copy on the phone, so it works offline too.
/// Only create this after `FirebaseApp.configure()` has run.
final class FirestoreDatabaseService: DatabaseService {
    private let db = Firestore.firestore()
    private let encoder = Firestore.Encoder()

    // Paths

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

    // Restaurants

    func fetchRestaurants() async throws -> [Restaurant] {
        let snapshot = try await restaurantsCollection.order(by: "distanceKm").getDocuments()
        var restaurants = try snapshot.documents.map { try $0.data(as: Restaurant.self) }

        #if DEBUG
        // Upload any sample restaurants that Firestore doesn't have yet (e.g. on a new project).
        // Ones already there are left alone, so edits made in the Firebase console are kept.
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

    /// We don't wait for this: Firestore saves it offline first and sends it when online,
    /// so signing in is never slowed down by the upload.
    private func upload(_ restaurants: [Restaurant]) {
        let batch = db.batch()
        for restaurant in restaurants {
            guard let data = try? encoder.encode(restaurant) else { continue }
            batch.setData(data, forDocument: restaurantsCollection.document(restaurant.id))
        }
        batch.commit { _ in }
    }

    // Profile

    func fetchProfile(userID: String) async throws -> UserProfile? {
        let document = try await userDocument(userID).getDocument()
        guard document.exists else { return nil }
        return try document.data(as: UserProfile.self)
    }

    func saveProfile(_ profile: UserProfile, userID: String) async throws {
        try await userDocument(userID).setData(encoder.encode(profile))
    }

    // Visits

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

    // Stamps

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

    // Reset

    func deleteVisitsAndStamps(userID: String) async throws {
        let visits = try await visitsCollection(userID).getDocuments()
        let stamps = try await stampsCollection(userID).getDocuments()

        // A batch deletes everything at once, so the reset never half-finishes.
        let batch = db.batch()
        for document in visits.documents + stamps.documents {
            batch.deleteDocument(document.reference)
        }
        try await batch.commit()
    }
}

/// Fake database kept in memory, for previews, tests and running without Firebase.
/// It only holds one user, so `userID` is ignored.
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
