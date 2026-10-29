import UIKit
import ImageIO

/// Why a meal photo can't prove the student ate here today.
enum PhotoProblem: Equatable {
    /// It looks the same as a photo from an earlier visit.
    case reused
    /// It was taken too long ago (e.g. picked from Photos).
    case old(takenAt: Date)
    /// It has no date, so we can't tell when it was taken (e.g. a screenshot or a downloaded image).
    case noDate

    var message: String {
        switch self {
        case .reused:
            "This photo matches one from an earlier visit."
        case .old(let takenAt):
            "This photo was taken \(takenAt.formatted(.relative(presentation: .named)))."
        case .noDate:
            "We can't tell when this photo was taken."
        }
    }
}

/// Checks that a meal photo is new: taken recently, and not the same as an earlier visit's photo.
enum PhotoCheck {
    /// A photo older than this doesn't count as taken on this visit.
    static let maxAge: TimeInterval = 6 * 60 * 60
    /// Fingerprints that differ in this many of their 64 bits or fewer are treated as the same photo.
    static let sameImageDistance = 6

    /// A 64-bit "difference hash" as 16 hex characters. The photo is shrunk to 9 × 8 grey pixels,
    /// and each bit says whether a pixel is clearly brighter than the one to its right.
    /// "Clearly" (by more than a few shades) stops JPEG noise in flat areas, like a plain plate, flipping bits.
    /// Resizing, recompressing or small edits barely change it, so a reused photo is still recognised.
    static func fingerprint(of image: UIImage) -> String? {
        let width = 9, height = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cgImage = small.cgImage else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                hash <<= 1
                if Int(pixels[row * width + column]) > Int(pixels[row * width + column + 1]) + 4 { hash |= 1 }
            }
        }
        return String(format: "%016llx", hash)
    }

    /// How many bits two fingerprints differ in (0 means the same picture).
    static func distance(_ first: String, _ second: String) -> Int {
        guard let a = UInt64(first, radix: 16), let b = UInt64(second, radix: 16) else { return 64 }
        return (a ^ b).nonzeroBitCount
    }

    /// When the photo was taken, from its EXIF data. nil if the file doesn't say.
    static func captureDate(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        else { return nil }
        // EXIF dates look like "2026:10:29 13:05:42", in the phone's local time.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// The first problem with a photo, or nil if it can prove the visit.
    /// `takenAt` is nil if the photo's date is unknown; photos from the camera are taken now.
    static func problem(fingerprint: String?, takenAt: Date?, earlierFingerprints: [String], now: Date = .now) -> PhotoProblem? {
        if let fingerprint, earlierFingerprints.contains(where: { distance($0, fingerprint) <= sameImageDistance }) {
            return .reused
        }
        guard let takenAt else { return .noDate }
        if now.timeIntervalSince(takenAt) > maxAge { return .old(takenAt: takenAt) }
        return nil
    }
}
