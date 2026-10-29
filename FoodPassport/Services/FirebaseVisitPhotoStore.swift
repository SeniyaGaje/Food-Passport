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
/// A photo that can't upload (e.g. offline) stays on the phone and is queued, so the visit still saves.
actor FirebaseVisitPhotoStore: VisitPhotoStore {
    /// Photo IDs waiting to upload or to be deleted from Firebase, for each account.
    private struct PendingWork: Codable {
        var uploads: [String: Set<String>] = [:]
        var deletions: [String: Set<String>] = [:]
    }

    private let local: LocalVisitPhotoStore
    private let remote: MealPhotoRemote
    private let pendingFile: URL?
    private var pending: PendingWork

    init(local: LocalVisitPhotoStore = LocalVisitPhotoStore(), remote: MealPhotoRemote = FirebaseMealPhotoRemote(),
         pendingFile: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotoDeletions.json")) {
        self.local = local
        self.remote = remote
        self.pendingFile = pendingFile
        let data = pendingFile.flatMap { try? Data(contentsOf: $0) }
        if let data, let saved = try? JSONDecoder().decode(PendingWork.self, from: data) {
            pending = saved
        } else if let data, let oldDeletions = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            // Files from older versions only had the deletions.
            pending = PendingWork(deletions: oldDeletions)
        } else {
            pending = PendingWork()
        }
    }

    func save(_ images: [UIImage], userID: String) async throws -> [String] {
        let ids = try await local.save(images, userID: userID)
        for (index, id) in ids.enumerated() {
            do {
                try await upload(id: id, userID: userID)
            } catch {
                // Keep this photo and the rest on the phone, and upload them when we're back online.
                pending.uploads[userID, default: []].formUnion(ids[index...])
                persistPending()
                break
            }
        }
        return ids
    }

    func hasPendingUploads(ids: [String], userID: String) async -> Bool {
        !(pending.uploads[userID] ?? []).isDisjoint(with: ids)
    }

    func load(id: String, userID: String) async -> UIImage? {
        guard UUID(uuidString: id) != nil else { return nil }
        guard pending.deletions[userID]?.contains(id) != true else { return nil }
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
        let valid = ids.filter { UUID(uuidString: $0) != nil }
        pending.uploads[userID]?.subtract(valid)
        pending.deletions[userID, default: []].formUnion(valid)
        persistPending()
        await local.delete(ids: ids, userID: userID)
        await retryPendingWork(userID: userID)
    }

    /// Only for this account, after it next opens its passport or comes back online.
    func retryPendingWork(userID: String) async {
        for id in pending.uploads[userID] ?? [] {
            do {
                try await upload(id: id, userID: userID)
                pending.uploads[userID]?.remove(id)
                persistPending()
            } catch VisitPhotoError.unreadable {
                // The photo is gone from the phone (e.g. the visit was deleted), so there's nothing to upload.
                pending.uploads[userID]?.remove(id)
                persistPending()
            } catch {
                // Still offline. Try again next time.
                break
            }
        }
        for id in pending.deletions[userID] ?? [] {
            do {
                try await remote.remove(id: id, userID: userID)
                pending.deletions[userID]?.remove(id)
                persistPending()
            } catch {
                // Try again next time.
            }
        }
    }

    private func upload(id: String, userID: String) async throws {
        try Task.checkCancellation()
        guard let image = await local.load(id: id, userID: userID),
              let data = image.jpegData(compressionQuality: 0.9) else { throw VisitPhotoError.unreadable }
        try await remote.upload(data, id: id, userID: userID)
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
