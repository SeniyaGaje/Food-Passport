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

    @Test("An upload failure rolls back files and leaves the visit uncreated")
    func uploadFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalVisitPhotoStore(folder: root)
        let remote = FakeMealPhotoRemote()
        await remote.setOffline(true)
        let store = FirebaseVisitPhotoStore(local: local, remote: remote, pendingFile: nil)
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []), photoStore: store)
        try await app.signIn()
        await #expect(throws: VisitPhotoError.self) {
            try await app.appState.saveVisit(makeVisit(), photos: [photo()])
        }
        #expect(app.appState.visits.isEmpty)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        #expect(!files.contains { $0.pathExtension == "jpg" })
    }

    @Test("A later upload failure removes the earlier uploaded photo too")
    func partialUploadRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = FakeMealPhotoRemote()
        await remote.failUpload(number: 2)
        let store = FirebaseVisitPhotoStore(local: LocalVisitPhotoStore(folder: root), remote: remote, pendingFile: nil)
        await #expect(throws: VisitPhotoError.self) {
            try await store.save([photo(), photo(color: .blue)], userID: "alice")
        }
        #expect(await remote.count() == 0)
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
        await reopened.retryPendingDeletions(userID: "bob")
        #expect(await remote.count() == 1)
        await reopened.retryPendingDeletions(userID: "alice")
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
