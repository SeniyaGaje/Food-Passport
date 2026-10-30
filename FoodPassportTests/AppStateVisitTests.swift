import Testing
import Foundation
@testable import FoodPassport

/// Logging visits and earning stamps: the core rules of the passport.
@Suite("Visits and stamps")
@MainActor
struct AppStateVisitTests {

    @Test("A verified visit to a new cuisine earns a stamp, and both are saved")
    func verifiedVisitEarnsStamp() async throws {
        let app = TestApp()
        try await app.signIn()
        // Dragon Wok is Chinese, a cuisine with no stamp in the sample data.
        let visit = makeVisit(id: "first-chinese", cuisine: .chinese, restaurant: MockData.dragonWok)

        let stamp = try #require(app.appState.addVisit(visit))
        // Wait for the background saves to reach the fake database.
        await app.appState.waitForPendingWrites()

        #expect(stamp.cuisine == .chinese)
        #expect(stamp.restaurantName == "Dragon Wok")
        #expect(stamp.visitID == "first-chinese")
        #expect(app.appState.visits.first?.id == "first-chinese")
        #expect(app.appState.stamps.contains { $0.cuisine == .chinese })
        // Both the visit and the stamp reached the database.
        #expect(app.database.visits.contains { $0.id == "first-chinese" })
        #expect(app.database.stamps.contains { $0.cuisine == .chinese })
    }

    @Test("A visit logged away from the restaurant is saved but earns no stamp")
    func unverifiedVisitEarnsNoStamp() async throws {
        let app = TestApp()
        try await app.signIn()
        let stampsBefore = app.appState.stamps

        // isLocationVerified false: logged away from the restaurant.
        let stamp = app.appState.addVisit(makeVisit(id: "away", cuisine: .chinese, isLocationVerified: false))
        await app.appState.waitForPendingWrites()

        #expect(stamp == nil)
        #expect(app.appState.stamps == stampsBefore)
        #expect(app.database.visits.contains { $0.id == "away" })
    }

    @Test("A cuisine is only stamped once")
    func oneStampPerCuisine() async throws {
        let app = TestApp()
        try await app.signIn()

        // Two verified Chinese visits in a row.
        let first = app.appState.addVisit(makeVisit(id: "wok-1", cuisine: .chinese))
        let second = app.appState.addVisit(makeVisit(id: "wok-2", cuisine: .chinese))

        #expect(first != nil)
        #expect(second == nil)
        #expect(app.appState.stamps.filter { $0.cuisine == .chinese }.count == 1)
        // Newest visit first.
        #expect(app.appState.visits.prefix(2).map(\.id) == ["wok-2", "wok-1"])
    }

    @Test("A cuisine already stamped in the saved data earns no second stamp")
    func existingStampIsKept() async throws {
        let app = TestApp()
        try await app.signIn()
        // The sample data already has a Sri Lankan stamp.
        let original = try #require(app.appState.stamps.first { $0.cuisine == .sriLankan })

        let stamp = app.appState.addVisit(makeVisit(cuisine: .sriLankan, restaurant: MockData.hoppersHut))

        #expect(stamp == nil)
        #expect(app.appState.stamps.first { $0.cuisine == .sriLankan } == original)
    }

    @Test("Deleting the visit that earned a stamp removes the stamp too")
    func deletingVisitRemovesItsStamp() async throws {
        let app = TestApp()
        try await app.signIn()
        // In the sample data, the kottu visit earned the Sri Lankan stamp.
        let kottu = try #require(app.appState.visits.first { $0.id == "visit-kottu" })

        app.appState.deleteVisit(kottu)
        await app.appState.waitForPendingWrites()

        #expect(!app.appState.visits.contains { $0.id == "visit-kottu" })
        #expect(!app.appState.stamps.contains { $0.cuisine == .sriLankan })
        #expect(!app.database.visits.contains { $0.id == "visit-kottu" })
        #expect(!app.database.stamps.contains { $0.cuisine == .sriLankan })
    }

    @Test("Deleting a visit that didn't earn the stamp keeps the stamp")
    func deletingOtherVisitKeepsStamp() async throws {
        let app = TestApp()
        try await app.signIn()
        // The Indian stamp was earned by the butter chicken visit, not the masala dosa one.
        let dosa = try #require(app.appState.visits.first { $0.id == "visit-masala-dosa" })

        app.appState.deleteVisit(dosa)

        #expect(app.appState.stamps.contains { $0.cuisine == .indian })
    }

    @Test("Reset all data removes every visit and stamp but keeps the profile")
    func resetAllData() async throws {
        let app = TestApp()
        try await app.signIn()
        // Remember the profile, to check it survives the reset.
        let profile = app.appState.profile

        app.appState.resetAllData()
        await app.appState.waitForPendingWrites()

        #expect(app.appState.visits.isEmpty)
        #expect(app.appState.stamps.isEmpty)
        #expect(app.database.visits.isEmpty)
        #expect(app.database.stamps.isEmpty)
        #expect(app.appState.profile == profile)
    }

    @Test("Cuisines tried counts each cuisine once")
    func cuisinesTriedCount() async throws {
        let app = TestApp()
        try await app.signIn()

        // Sample data: one Sri Lankan visit and two Indian visits.
        #expect(app.appState.cuisinesTriedCount == 2)

        // An unverified Italian visit still counts as a cuisine tried (but earns no stamp).
        app.appState.addVisit(makeVisit(cuisine: .italian, isLocationVerified: false))
        #expect(app.appState.cuisinesTriedCount == 3)
    }
}
