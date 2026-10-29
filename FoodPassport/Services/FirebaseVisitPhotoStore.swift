import Foundation
import UIKit
import FirebaseStorage

nonisolated protocol MealPhotoRemote: Sendable {
    func upload(_ data: Data, id: String, userID: String) async throws
    func download(id: String, userID: String) async throws -> Data
    func remove(id: String, userID: String) async throws
}

actor FirebaseMealPhotoRemote: MealPhotoRemote {
    init() {
        let storage = Storage.storage()
        storage.maxUploadRetryTime = 30
        storage.maxDownloadRetryTime = 15
        storage.maxOperationRetryTime = 10
    }
    private func reference(id: String, userID: String) -> StorageReference {
        Storage.storage().reference().child("users").child(userID).child("mealPhotos").child(id + ".jpg")
    }

    func upload(_ data: Data, id: String, userID: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await reference(id: id, userID: userID).putDataAsync(data, metadata: metadata)
    }

    func download(id: String, userID: String) async throws -> Data {
        try await reference(id: id, userID: userID).data(maxSize: 5 * 1024 * 1024)
    }

    func remove(id: String, userID: String) async throws {
        do {
            try await reference(id: id, userID: userID).delete()
        } catch let error as NSError where error.code == StorageErrorCode.objectNotFound.rawValue {
            // Already deleted on another device.
        }
    }
}

/// Firebase is the source of truth; cached copies make previously viewed photos work offline.
actor FirebaseVisitPhotoStore: VisitPhotoStore {
    private let local: LocalVisitPhotoStore
    private let remote: MealPhotoRemote
    private let pendingFile: URL?
    private var pending: [String: Set<String>]

    init(local: LocalVisitPhotoStore = LocalVisitPhotoStore(), remote: MealPhotoRemote = FirebaseMealPhotoRemote(),
         pendingFile: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotoDeletions.json")) {
        self.local = local
        self.remote = remote
        self.pendingFile = pendingFile
        if let pendingFile, let data = try? Data(contentsOf: pendingFile),
           let saved = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            pending = saved
        } else {
            pending = [:]
        }
    }

    func save(_ images: [UIImage], userID: String) async throws -> [String] {
        let ids = try await local.save(images, userID: userID)
        do {
            for id in ids {
                try Task.checkCancellation()
                guard let image = await local.load(id: id, userID: userID),
                      let data = image.jpegData(compressionQuality: 0.9) else { throw VisitPhotoError.unreadable }
                try await remote.upload(data, id: id, userID: userID)
            }
            return ids
        } catch {
            // Do not create visit references to incomplete uploads.
            await delete(ids: ids, userID: userID)
            throw VisitPhotoError.cloudUnavailable
        }
    }

    func load(id: String, userID: String) async -> UIImage? {
        guard UUID(uuidString: id) != nil else { return nil }
        guard pending[userID]?.contains(id) != true else { return nil }
        if let image = await local.load(id: id, userID: userID) { return image }
        do {
            let data = try await remote.download(id: id, userID: userID)
            try await local.cache(data, id: id, userID: userID)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    func delete(ids: [String], userID: String) async {
        pending[userID, default: []].formUnion(ids.filter { UUID(uuidString: $0) != nil })
        persistPending()
        await local.delete(ids: ids, userID: userID)
        await retryPendingDeletions(userID: userID)
    }

    func retryPendingDeletions(userID: String) async {
        for id in pending[userID] ?? [] {
            do {
                try await remote.remove(id: id, userID: userID)
                pending[userID]?.remove(id)
                persistPending()
            } catch {
                // Retry only for this account after it next opens its passport.
            }
        }
    }

    private func persistPending() {
        guard let pendingFile else { return }
        do {
            try FileManager.default.createDirectory(at: pendingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pending).write(to: pendingFile,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // The in-memory queue can still retry during this launch.
        }
    }
}
