import CryptoKit
import Foundation
import UIKit

enum VisitPhotoError: LocalizedError {
    case unreadable
    case signedOut
    case cancelled
    case cloudUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadable: "That meal photo couldn't be saved. Try another photo."
        case .signedOut: "Sign in again before saving your visit."
        case .cancelled: "This visit was cancelled because your data changed. Try again."
        case .cloudUnavailable: "Couldn't upload your meal photos. Check your connection and try Save again. Your photos are still in this form."
        }
    }
}

nonisolated protocol VisitPhotoStore: Sendable {
    func save(_ images: [UIImage], userID: String) async throws -> [String]
    func load(id: String, userID: String) async -> UIImage?
    func delete(ids: [String], userID: String) async
    func retryPendingDeletions(userID: String) async
}

extension VisitPhotoStore {
    nonisolated func retryPendingDeletions(userID: String) async {}
}

/// Photos stay in Application Support, separately for each signed-in account.
actor LocalVisitPhotoStore: VisitPhotoStore {
    private let folder: URL

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MealPhotos", isDirectory: true)) {
        self.folder = folder
    }

    func save(_ images: [UIImage], userID: String) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        let accountFolder = directory(for: userID)
        try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true)
        var saved: [String] = []
        var hashes: Set<Data> = []
        do {
            for image in images {
                guard image.size.width > 0, image.size.height > 0 else { throw VisitPhotoError.unreadable }
                let scale = min(1, 1600 / max(image.size.width, image.size.height))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let data = resized.jpegData(compressionQuality: 0.85) else { throw VisitPhotoError.unreadable }
                guard hashes.insert(Data(SHA256.hash(data: data))).inserted else { continue }
                let id = UUID().uuidString
                try data.write(to: accountFolder.appendingPathComponent(id + ".jpg"),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                saved.append(id)
            }
            return saved
        } catch {
            deleteFiles(ids: saved, userID: userID)
            throw error
        }
    }

    func load(id: String, userID: String) async -> UIImage? {
        guard UUID(uuidString: id) != nil else { return nil }
        return UIImage(contentsOfFile: directory(for: userID).appendingPathComponent(id + ".jpg").path)
    }

    func delete(ids: [String], userID: String) async {
        deleteFiles(ids: ids, userID: userID)
    }

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

    private func directory(for userID: String) -> URL {
        let account = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(account, isDirectory: true)
    }
}
