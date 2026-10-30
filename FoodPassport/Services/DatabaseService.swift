import Foundation
import FirebaseFirestore

/// Reads and writes the student's data. AppState only uses this protocol, so it can run on Firestore or the mock.
/// Firestore layout: restaurants/{id}, trails/{id}, challenges/current, users/{userID},
/// users/{userID}/visits/{id}, users/{userID}/stamps/{cuisine}, users/{userID}/plannedVisits/{id}.
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

    func fetchQuest(userID: String) async throws -> QuestSettings?
    func saveQuest(_ quest: QuestSettings, userID: String) async throws

    func fetchPlannedVisits(userID: String) async throws -> [PlannedVisit]
    func savePlannedVisit(_ plan: PlannedVisit, userID: String) async throws
    func deletePlannedVisit(id: PlannedVisit.ID, userID: String) async throws

    /// Trails and the weekly challenge are set up by an administrator. Empty or nil means use the built-in ones.
    func fetchTrails() async throws -> [TrailDocument]
    func fetchWeeklyChallenge() async throws -> ChallengeDocument?
}

extension DatabaseService {
    func fetchQuest(userID: String) async throws -> QuestSettings? { nil }
    func saveQuest(_ quest: QuestSettings, userID: String) async throws {}
    func fetchPlannedVisits(userID: String) async throws -> [PlannedVisit] { [] }
    func savePlannedVisit(_ plan: PlannedVisit, userID: String) async throws {}
    func deletePlannedVisit(id: PlannedVisit.ID, userID: String) async throws {}
    func fetchTrails() async throws -> [TrailDocument] { [] }
    func fetchWeeklyChallenge() async throws -> ChallengeDocument? { nil }
}

/// A food trail as saved in Firestore (trails/{id}). The stops are restaurant IDs, in walking order.
struct TrailDocument: Codable, Hashable {
    var id = ""
    let name: String
    let summary: String
    let restaurantIDs: [Restaurant.ID]

    // The ID is the document's name, not a field inside it.
    enum CodingKeys: String, CodingKey { case name, summary, restaurantIDs }

    /// The trail with its restaurants filled in. Stops for restaurants that no longer exist are skipped.
    func trail(using restaurants: [Restaurant]) -> FoodTrail? {
        let stops = restaurantIDs.compactMap { id in restaurants.first { $0.id == id } }
        guard !stops.isEmpty else { return nil }
        return FoodTrail(id: id, name: name, summary: summary, stops: stops.map { TrailStop(restaurant: $0, isVisited: false) })
    }
}

/// This week's challenge as saved in Firestore (challenges/current): try `target` different cuisines.
struct ChallengeDocument: Codable, Hashable {
    let title: String
    let details: String
    let target: Int

    static let standard = ChallengeDocument(title: "Try 3 cuisines this week",
                                            details: "Log meals from three different cuisines.", target: 3)
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
        return try snapshot.documents.map { try $0.data(as: Restaurant.self) }
    }

    func fetchQuest(userID: String) async throws -> QuestSettings? {
        let document = try await userDocument(userID).collection("quests").document("active").getDocument()
        return document.exists ? try document.data(as: QuestSettings.self) : nil
    }

    func saveQuest(_ quest: QuestSettings, userID: String) async throws {
        try await userDocument(userID).collection("quests").document("active").setData(encoder.encode(quest))
    }

    // Planned visits

    private func plannedVisitsCollection(_ userID: String) -> CollectionReference {
        userDocument(userID).collection("plannedVisits")
    }

    func fetchPlannedVisits(userID: String) async throws -> [PlannedVisit] {
        let snapshot = try await plannedVisitsCollection(userID).order(by: "date").getDocuments()
        return try snapshot.documents.map { try $0.data(as: PlannedVisit.self) }
    }

    func savePlannedVisit(_ plan: PlannedVisit, userID: String) async throws {
        try await plannedVisitsCollection(userID).document(plan.id).setData(encoder.encode(plan))
    }

    func deletePlannedVisit(id: PlannedVisit.ID, userID: String) async throws {
        try await plannedVisitsCollection(userID).document(id).delete()
    }

    // Trails and challenges

    func fetchTrails() async throws -> [TrailDocument] {
        let snapshot = try await db.collection("trails").getDocuments()
        return try snapshot.documents.map { document in
            var trail = try document.data(as: TrailDocument.self)
            trail.id = document.documentID
            return trail
        }
    }

    func fetchWeeklyChallenge() async throws -> ChallengeDocument? {
        let document = try await db.collection("challenges").document("current").getDocument()
        return document.exists ? try document.data(as: ChallengeDocument.self) : nil
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
    var quest: QuestSettings?
    var plannedVisits: [PlannedVisit] = []
    var trails: [TrailDocument] = []
    var weeklyChallenge: ChallengeDocument?

    func fetchQuest(userID: String) async throws -> QuestSettings? { quest }
    func saveQuest(_ quest: QuestSettings, userID: String) async throws { self.quest = quest }
    func fetchPlannedVisits(userID: String) async throws -> [PlannedVisit] { plannedVisits }
    func savePlannedVisit(_ plan: PlannedVisit, userID: String) async throws {
        plannedVisits.removeAll { $0.id == plan.id }
        plannedVisits.append(plan)
    }
    func deletePlannedVisit(id: PlannedVisit.ID, userID: String) async throws { plannedVisits.removeAll { $0.id == id } }
    func fetchTrails() async throws -> [TrailDocument] { trails }
    func fetchWeeklyChallenge() async throws -> ChallengeDocument? { weeklyChallenge }
    // Restaurants, profile, visits and stamps, starting as the sample data.
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

    // Saving replaces any visit with the same ID, like Firestore's setData.
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

    // One stamp per cuisine, like the Firestore document ID.
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
