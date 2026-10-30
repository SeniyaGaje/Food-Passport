import CryptoKit
import Foundation
import UIKit

/// Why saving or loading a meal photo failed.
enum VisitPhotoError: LocalizedError {
    case unreadable
    case signedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable: "That meal photo couldn't be saved. Try another photo."
        case .signedOut: "Sign in again before saving your visit."
        case .cancelled: "This visit was cancelled because your data changed. Try again."
        }
    }
}

/// Where meal photos are kept: on the phone only, or on the phone plus Firebase.
nonisolated protocol VisitPhotoStore: Sendable {
    func save(_ images: [UIImage], userID: String) async throws -> [String]
    func load(id: String, userID: String) async -> UIImage?
    func delete(ids: [String], userID: String) async
    /// Uploads photos saved while offline and finishes deletions that failed.
    func retryPendingWork(userID: String) async
    /// True if any of these photos is saved on the phone but not uploaded yet.
    func hasPendingUploads(ids: [String], userID: String) async -> Bool
}

// Defaults for the local store, which has nothing to upload.
extension VisitPhotoStore {
    nonisolated func retryPendingWork(userID: String) async {}
    nonisolated func hasPendingUploads(ids: [String], userID: String) async -> Bool { false }
}

/// Photos stay in Application Support, separately for each signed-in account.
actor LocalVisitPhotoStore: VisitPhotoStore {
    private let folder: URL

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MealPhotos", isDirectory: true)) {
        self.folder = folder
    }

    /// Resizes and saves the photos, returning a new ID for each. If one fails, none are kept.
    func save(_ images: [UIImage], userID: String) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        let accountFolder = directory(for: userID)
        try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true)
        var saved: [String] = []
        var hashes: Set<Data> = []
        do {
            for image in images {
                guard image.size.width > 0, image.size.height > 0 else { throw VisitPhotoError.unreadable }
                // Shrink so the longest side is at most 1,600 px.
                let scale = min(1, 1600 / max(image.size.width, image.size.height))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                // Save as JPEG at 85% quality.
                guard let data = resized.jpegData(compressionQuality: 0.85) else { throw VisitPhotoError.unreadable }
                // Skip a photo identical to one already saved for this visit.
                guard hashes.insert(Data(SHA256.hash(data: data))).inserted else { continue }
                let id = UUID().uuidString
                // Write atomically, protected until the phone is first unlocked.
                try data.write(to: accountFolder.appendingPathComponent(id + ".jpg"),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                saved.append(id)
            }
            return saved
        } catch {
            // Something failed: delete the photos already written, so nothing half-saved is left.
            deleteFiles(ids: saved, userID: userID)
            throw error
        }
    }

    /// Loads a photo by ID. IDs must be UUIDs, so a path like "../x" is refused.
    func load(id: String, userID: String) async -> UIImage? {
        guard UUID(uuidString: id) != nil else { return nil }
        return UIImage(contentsOfFile: directory(for: userID).appendingPathComponent(id + ".jpg").path)
    }

    func delete(ids: [String], userID: String) async {
        deleteFiles(ids: ids, userID: userID)
    }

    /// Saves a photo downloaded from Firebase, so it opens offline next time.
    func cache(_ data: Data, id: String, userID: String) throws {
        guard UUID(uuidString: id) != nil, UIImage(data: data) != nil else { throw VisitPhotoError.unreadable }
        let directory = directory(for: userID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(id + ".jpg"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func deleteFiles(ids: [String], userID: String) {
        for id in ids where UUID(uuidString: id) != nil {
            try? FileManager.default.removeItem(at: directory(for: userID).appendingPathComponent(id + ".jpg"))
        }
    }

    /// Each account's folder is named after a hash of its user ID.
    private func directory(for userID: String) -> URL {
        let account = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(account, isDirectory: true)
    }
}
