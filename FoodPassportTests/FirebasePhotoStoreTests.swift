import Foundation
import Testing
import UIKit
@testable import FoodPassport

@Suite("Cloud meal photos")
@MainActor
struct FirebasePhotoStoreTests {
    private func photo(color: UIColor = .orange) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
        }
    }

    @Test("A second device downloads an uploaded photo, then opens its cache offline")
    func secondDeviceAndOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = FakeMealPhotoRemote()
        let first = FirebaseVisitPhotoStore(local: LocalVisitPhotoStore(folder: root.appendingPathComponent("first")), remote: remote, pendingFile: nil)
        let ids = try await first.save([photo()], userID: "alice")
        let second = FirebaseVisitPhotoStore(local: LocalVisitPhotoStore(folder: root.appendingPathComponent("second")), remote: remote, pendingFile: nil)
        #expect(await second.load(id: ids[0], userID: "alice") != nil)
        #expect(await second.load(id: ids[0], userID: "bob") == nil)
        await remote.setOffline(true)
        #expect(await second.load(id: ids[0], userID: "alice") != nil)
        #expect(await second.load(id: "../outside", userID: "alice") == nil)
    }

    @Test("Offline, the visit still saves and its photo waits on the phone to upload")
    func uploadFailureStillSavesVisit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalVisitPhotoStore(folder: root)
        let remote = FakeMealPhotoRemote()
        await remote.setOffline(true)
        let store = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: nil)
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []), photoStore: store)
        try await app.signIn()

        let result = try await app.appState.saveVisit(makeVisit(), photos: [photo()])

        #expect(app.appState.visits.count == 1)
        #expect(result.photosWaitingToUpload)
        let id = try #require(app.appState.visits[0].photoIDs?.first)
        #expect(await local.load(id: id, userID: "mock-user") != nil)
        #expect(await remote.count() == 0)

        // Back online: the queued photo uploads.
        await remote.setOffline(false)
        app.appState.updateConnectivity(isOffline: true)
        app.appState.updateConnectivity(isOffline: false)
        await app.appState.waitForPendingWrites()
        #expect(await remote.count() == 1)
        #expect(await !store.hasPendingUploads(ids: [id], userID: "mock-user"))
    }

    @Test("If the second upload fails, the first stays uploaded and the second is queued")
    func partialUploadQueued() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = FakeMealPhotoRemote()
        await remote.failUpload(number: 2)
        let queue = root.appendingPathComponent("pending.json")
        let local = LocalVisitPhotoStore(folder: root.appendingPathComponent("cache"))
        let store = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: queue)

        let ids = try await store.save([photo(), photo(color: .blue)], userID: "alice")

        #expect(ids.count == 2)
        #expect(await remote.count() == 1)
        #expect(await store.hasPendingUploads(ids: [ids[1]], userID: "alice"))
        // The queue survives reopening the app, and only uploads for the right account.
        let reopened = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: queue)
        await reopened.retryPendingWork(userID: "bob")
        #expect(await remote.count() == 1)
        await reopened.retryPendingWork(userID: "alice")
        #expect(await remote.count() == 2)
    }

    @Test("Failed remote deletions survive reopening and retry for the correct account")
    func deletionRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalVisitPhotoStore(folder: root.appendingPathComponent("cache"))
        let queue = root.appendingPathComponent("pending.json")
        let remote = FakeMealPhotoRemote()
        let first = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: queue)
        let ids = try await first.save([photo()], userID: "alice")
        await remote.setOffline(true)
        await first.delete(ids: ids, userID: "alice")
        #expect(await local.load(id: ids[0], userID: "alice") == nil)
        let reopened = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: queue)
        await remote.setOffline(false)
        await reopened.retryPendingWork(userID: "bob")
        #expect(await remote.count() == 1)
        await reopened.retryPendingWork(userID: "alice")
        #expect(await remote.count() == 0)
    }
}

actor FakeMealPhotoRemote: MealPhotoRemote {
    private var files: [String: Data] = [:]
    private var offline = false
    private var uploadNumber = 0
    private var rejectedUpload: Int?
    func failUpload(number: Int) { rejectedUpload = number }
    struct Offline: Error {}
    func setOffline(_ value: Bool) { offline = value }
    func count() -> Int { files.count }
    func upload(_ data: Data, id: String, userID: String) async throws {
        uploadNumber += 1
        if offline || uploadNumber == rejectedUpload { throw Offline() }
        files[userID + "/" + id] = data
    }
    func download(id: String, userID: String) async throws -> Data {
        if offline { throw Offline() }
        guard let data = files[userID + "/" + id] else { throw Offline() }
        return data
    }
    func remove(id: String, userID: String) async throws {
        if offline { throw Offline() }
        files[userID + "/" + id] = nil
    }
}
