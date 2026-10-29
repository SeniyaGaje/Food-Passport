import Foundation
import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import FoodPassport

@Suite("Meal photo checks")
@MainActor
struct PhotoCheckTests {
    /// A photo with a dark left half and a light right half, or stripes, so the fingerprints differ.
    private func photo(striped: Bool = false, size: CGSize = CGSize(width: 300, height: 200)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            if striped {
                for column in stride(from: 0, to: Int(size.width), by: Int(size.width / 6)) {
                    context.fill(CGRect(x: CGFloat(column), y: 0, width: size.width / 12, height: size.height))
                }
            } else {
                context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
            }
        }
    }

    @Test("The same photo, resized and recompressed, has a matching fingerprint")
    func samePhotoMatches() throws {
        let original = photo()
        let resized = photo(size: CGSize(width: 900, height: 600))
        let jpeg = try #require(original.jpegData(compressionQuality: 0.3))
        let recompressed = try #require(UIImage(data: jpeg))

        let a = try #require(PhotoCheck.fingerprint(of: original))
        let b = try #require(PhotoCheck.fingerprint(of: resized))
        let c = try #require(PhotoCheck.fingerprint(of: recompressed))
        #expect(PhotoCheck.distance(a, b) <= PhotoCheck.sameImageDistance)
        #expect(PhotoCheck.distance(a, c) <= PhotoCheck.sameImageDistance)
    }

    @Test("A different photo doesn't match")
    func differentPhotoDoesNotMatch() throws {
        let a = try #require(PhotoCheck.fingerprint(of: photo()))
        let b = try #require(PhotoCheck.fingerprint(of: photo(striped: true)))

        #expect(PhotoCheck.distance(a, b) > PhotoCheck.sameImageDistance)
        #expect(PhotoCheck.distance(a, "not hex") == 64)
    }

    @Test("Reused, old and undated photos can't prove a visit; a new camera photo can")
    func problems() throws {
        let fingerprint = try #require(PhotoCheck.fingerprint(of: photo()))
        let now = Date.now

        #expect(PhotoCheck.problem(fingerprint: fingerprint, takenAt: now, earlierFingerprints: [fingerprint]) == .reused)
        let lastWeek = now.addingTimeInterval(-7 * 24 * 60 * 60)
        #expect(PhotoCheck.problem(fingerprint: fingerprint, takenAt: lastWeek, earlierFingerprints: [], now: now) == .old(takenAt: lastWeek))
        #expect(PhotoCheck.problem(fingerprint: fingerprint, takenAt: nil, earlierFingerprints: []) == .noDate)
        #expect(PhotoCheck.problem(fingerprint: fingerprint, takenAt: now.addingTimeInterval(-60), earlierFingerprints: [], now: now) == nil)
    }

    @Test("The capture date is read from the photo's EXIF data")
    func captureDateFromExif() throws {
        let cgImage = try #require(photo().cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let exif = [kCGImagePropertyExifDateTimeOriginal: "2026:10:12 13:05:42"] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let date = try #require(PhotoCheck.captureDate(of: data as Data))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        #expect(parts == DateComponents(year: 2026, month: 10, day: 12, hour: 13, minute: 5))
        let png = try #require(photo().pngData())
        #expect(PhotoCheck.captureDate(of: png) == nil)
    }

    @Test("A visit's photo fingerprints are remembered for later visits")
    func fingerprintsAreRemembered() async throws {
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []))
        try await app.signIn()
        var visit = makeVisit()
        visit.photoFingerprints = ["00ff00ff00ff00ff"]

        app.appState.addVisit(visit)

        #expect(app.appState.earlierPhotoFingerprints == ["00ff00ff00ff00ff"])
    }
}
