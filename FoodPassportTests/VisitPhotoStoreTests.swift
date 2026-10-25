import Foundation
import Testing
import UIKit
@testable import FoodPassport

@Suite("Saved meal photos")
@MainActor
struct VisitPhotoStoreTests {
    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
        }
    }

    @Test("A photo survives reopening the store and is private to its account")
    func persistenceAndAccounts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = LocalVisitPhotoStore(folder: folder)
        let ids = try await first.save([photo(), photo()], userID: "student-a")
        #expect(ids.count == 1, "Identical photos on one visit are stored once")
        let reopened = LocalVisitPhotoStore(folder: folder)
        let saved = await reopened.load(id: ids[0], userID: "student-a")
        #expect(saved?.size.width == 30)
        #expect(await reopened.load(id: ids[0], userID: "student-b") == nil)
        #expect(await reopened.load(id: "../outside", userID: "student-a") == nil)
        await reopened.delete(ids: ids, userID: "student-b")
        #expect(await reopened.load(id: ids[0], userID: "student-a") != nil)
        await reopened.delete(ids: ids, userID: "student-a")
        #expect(await reopened.load(id: ids[0], userID: "student-a") == nil)
    }

    @Test("If any photo fails, no partial photo set is left behind")
    func failedSaveRollsBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalVisitPhotoStore(folder: folder)
        await #expect(throws: VisitPhotoError.self) {
            try await store.save([photo(), UIImage()], userID: "student")
        }
        let contents = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        #expect(!contents.contains { $0.pathExtension == "jpg" })
    }

    @Test("Large photos are resized before saving")
    func boundedPhotoSize() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { _ in }
        let store = LocalVisitPhotoStore(folder: folder)
        let ids = try await store.save([image], userID: "student")
        let saved = await store.load(id: ids[0], userID: "student")
        #expect(saved?.size == CGSize(width: 1600, height: 800))
    }

    @Test("Saving a visit stores photo references, and deleting it removes its photos")
    func visitPhotoLifecycle() async throws {
        let store = MemoryVisitPhotoStore()
        let app = TestApp(photoStore: store)
        try await app.signIn()
        let visit = makeVisit(id: "with-photo", isLocationVerified: false)
        _ = try await app.appState.saveVisit(visit, photos: [photo()])
        await app.appState.waitForPendingWrites()
        let saved = try #require(app.appState.visits.first { $0.id == visit.id })
        let id = try #require(saved.photoIDs?.first)
        #expect(app.database.visits.first { $0.id == visit.id }?.photoIDs == [id])
        #expect(await app.appState.mealPhoto(id: id) != nil)
        app.appState.deleteVisit(saved)
        await app.appState.waitForPendingWrites()
        #expect(await app.appState.mealPhoto(id: id) == nil)
    }

    @Test("A photo save failure keeps the visit and its stamp unsaved")
    func visitSaveFailure() async throws {
        let store = MemoryVisitPhotoStore(failsSaving: true)
        let app = TestApp(photoStore: store)
        try await app.signIn()
        let before = app.appState.visits
        await #expect(throws: VisitPhotoError.self) {
            try await app.appState.saveVisit(makeVisit(), photos: [photo()])
        }
        #expect(app.appState.visits == before)
        #expect(!app.appState.stamps.contains { $0.cuisine == .chinese })
    }

    @Test("Resetting visits clears saved photos, and signing out prevents access")
    func resetAndSignOut() async throws {
        let store = MemoryVisitPhotoStore()
        let app = TestApp(photoStore: store)
        try await app.signIn()
        _ = try await app.appState.saveVisit(makeVisit(isLocationVerified: false), photos: [photo()])
        let id = try #require(app.appState.visits.first?.photoIDs?.first)
        app.appState.resetAllData()
        await app.appState.waitForPendingWrites()
        #expect(await app.appState.mealPhoto(id: id) == nil)
        app.appState.signOut()
        await #expect(throws: VisitPhotoError.self) {
            try await app.appState.saveVisit(makeVisit(), photos: [photo()])
        }
        #expect(await app.appState.mealPhoto(id: id) == nil)
    }

    @Test("Older visits still decode, and new photo references and item details round-trip")
    func codingCompatibility() throws {
        var visit = makeVisit()
        visit.photoIDs = [UUID().uuidString]
        visit.items = [VisitItem(name: "Cake", price: 400, category: "Dessert", isDrink: false)]
        let data = try JSONEncoder().encode(visit)
        #expect(try JSONDecoder().decode(Visit.self, from: data) == visit)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "photoIDs")
        old.removeValue(forKey: "items")
        let decoded = try JSONDecoder().decode(Visit.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.photoIDs == nil)
        #expect(decoded.allItems.count == 1)
    }

    @Test("A pending photo save cannot bring a visit back after reset or sign-out", arguments: [false, true])
    func interruptedSave(signOut: Bool) async throws {
        let store = SuspendedVisitPhotoStore()
        let app = TestApp(photoStore: store)
        try await app.signIn()
        let visit = makeVisit(id: "pending-photo", isLocationVerified: false)
        let image = photo()
        let save = Task { try await app.appState.saveVisit(visit, photos: [image]) }
        await store.waitUntilStarted()
        if signOut { app.appState.signOut() } else { app.appState.resetAllData() }
        await store.finish()
        do {
            _ = try await save.value
            Issue.record("An interrupted save should fail")
        } catch {
            #expect(error is VisitPhotoError)
        }
        await app.appState.waitForPendingWrites()
        #expect(!app.appState.visits.contains { $0.id == visit.id })
        #expect(await store.deletedIDs == ["pending-photo-id"])
    }
}

private actor MemoryVisitPhotoStore: VisitPhotoStore {
    let failsSaving: Bool
    private var images: [String: [String: UIImage]] = [:]

    init(failsSaving: Bool = false) { self.failsSaving = failsSaving }

    func save(_ photos: [UIImage], userID: String) async throws -> [String] {
        if failsSaving { throw VisitPhotoError.unreadable }
        return photos.map { photo in
            let id = UUID().uuidString
            images[userID, default: [:]][id] = photo
            return id
        }
    }

    func load(id: String, userID: String) async -> UIImage? { images[userID]?[id] }

    func delete(ids: [String], userID: String) async {
        for id in ids { images[userID]?[id] = nil }
    }
}

private actor SuspendedVisitPhotoStore: VisitPhotoStore {
    private var pending: CheckedContinuation<[String], Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var deletedIDs: [String] = []

    func save(_ images: [UIImage], userID: String) async throws -> [String] {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        pending?.resume(returning: ["pending-photo-id"])
        pending = nil
    }

    func load(id: String, userID: String) async -> UIImage? { nil }
    func delete(ids: [String], userID: String) async { deletedIDs += ids }
}
