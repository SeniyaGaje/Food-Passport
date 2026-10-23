import Foundation
import UIKit
import Vision

/// One line of a receipt as Vision read it: the words on one row, joined left to right.
nonisolated struct TextRow: Sendable, Equatable {
    var text: String
    /// Normalised Vision coordinates (0–1, origin bottom-left).
    var boundingBox: CGRect
}

/// Reads the total (and items) from a photo of a receipt.
/// The views only use this protocol, so previews and tests can use the mock instead of running Vision.
protocol ReceiptScanner {
    func scan(_ image: UIImage) async throws -> ReceiptScan
}

enum ReceiptScanError: LocalizedError {
    case unreadableImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be opened. Try another one."
        case .noTextFound: "No text was found. Retake the photo with the whole receipt in good light."
        }
    }
}

/// `ReceiptScanner` that uses Vision's on-device text recognition. The photo never leaves the phone.
struct VisionReceiptScanner: ReceiptScanner {
    func scan(_ image: UIImage) async throws -> ReceiptScan {
        guard let cgImage = image.cgImage else { throw ReceiptScanError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Text recognition takes a second or two, so it runs off the main thread to keep the screen responsive.
        let rows = try await Task.detached(priority: .userInitiated) {
            try Self.recognizeRows(in: cgImage, orientation: orientation)
        }.value

        guard !rows.isEmpty else { throw ReceiptScanError.noTextFound }
        return ReceiptParser.parse(rows)
    }

    /// Runs Vision and groups the recognised words into receipt rows, top to bottom.
    nonisolated private static func recognizeRows(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> [TextRow] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" prices and codes into words, so it is turned off for receipts.
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

        let words = (request.results ?? [])
            .compactMap { observation in
                observation.topCandidates(1).first.map { (text: $0.string, box: observation.boundingBox) }
            }
            .sorted { $0.box.midY > $1.box.midY }

        // Receipts print the item name on the left and the price on the right, and Vision often reads them
        // as separate pieces. Pieces whose centres are at the same height belong to the same row.
        var rows: [[(text: String, box: CGRect)]] = []
        var currentRowBox = CGRect.null
        for word in words {
            if !rows.isEmpty, abs(currentRowBox.midY - word.box.midY) < min(currentRowBox.height, word.box.height) * 0.6 {
                rows[rows.count - 1].append(word)
                currentRowBox = currentRowBox.union(word.box)
            } else {
                rows.append([word])
                currentRowBox = word.box
            }
        }

        return rows.map { pieces in
            let leftToRight = pieces.sorted { $0.box.minX < $1.box.minX }
            return TextRow(
                text: leftToRight.map(\.text).joined(separator: " "),
                boundingBox: leftToRight.map(\.box).reduce(leftToRight[0].box) { $0.union($1) }
            )
        }
    }
}

/// Turns receipt rows into a `ReceiptScan`. Kept separate from Vision so it can be unit tested with plain text.
enum ReceiptParser {
    /// Words that mark the line holding the amount to pay. A higher score wins, e.g. "Grand total" beats "Total".
    /// Longer phrases are checked first, so "Sub total" scores 1 rather than matching plain "total".
    private static let totalKeywords: [(phrase: String, score: Int)] = [
        ("grand total", 5), ("net total", 5), ("total due", 5), ("amount due", 5), ("total payable", 5),
        ("balance due", 4), ("net amount", 4), ("bill amount", 4), ("total amount", 4),
        ("sub total", 1), ("subtotal", 1),
        ("total", 3),
    ].sorted { $0.phrase.count > $1.phrase.count }

    /// Lines that hold a number but are neither the total nor an item.
    private static let ignoredWords = [
        "cash", "change", "tendered", "card", "visa", "master", "discount", "tax", "vat", "service charge",
        "total items", "total qty", "no of items", "qty", "invoice", "bill no", "receipt no", "order", "table",
        "tel", "phone", "mobile", "reg no",
    ]

    static func parse(_ rows: [TextRow]) -> ReceiptScan {
        let lines = rows.map(\.text)
        let totalIndex = indexOfTotalLine(in: lines)

        var total: Int?
        var totalRow: Int?
        if let totalIndex {
            if let amount = amounts(in: lines[totalIndex]).last {
                (total, totalRow) = (amount, totalIndex)
            } else if totalIndex + 1 < lines.count, let amount = amounts(in: lines[totalIndex + 1]).last {
                // Some receipts print the amount on the line under "TOTAL".
                (total, totalRow) = (amount, totalIndex + 1)
            }
        }

        let items = lineItems(in: lines, before: totalIndex ?? lines.count)

        // No total line found: offer the largest amount, but flag it so the student checks it.
        let isTotalFromTotalLine = total != nil
        if total == nil {
            let candidates = lines.indices
                .filter { !isIgnored(lines[$0]) }
                .compactMap { index in amounts(in: lines[index]).max().map { (index, $0) } }
            if let largest = candidates.max(by: { $0.1 < $1.1 }) {
                (totalRow, total) = (largest.0, largest.1)
            }
        }

        return ReceiptScan(
            restaurantName: restaurantName(in: lines),
            date: lines.lazy.compactMap { $0.firstMatch(of: datePattern).map { String($0.output) } }.first,
            items: items,
            total: total,
            isTotalFromTotalLine: isTotalFromTotalLine,
            totalBoundingBox: totalRow.map { rows[$0].boundingBox }
        )
    }

    // Lines

    /// The row with the strongest total keyword; the lowest one on the receipt if several score the same.
    static func indexOfTotalLine(in lines: [String]) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, line) in lines.enumerated() {
            guard !isIgnored(line) else { continue }
            guard let score = totalKeywords.first(where: { line.containsWords($0.phrase) })?.score else { continue }
            if score >= (best?.score ?? 0) {
                best = (index, score)
            }
        }
        // A lone "Sub total" is not the amount to pay.
        return best.flatMap { $0.score > 1 ? $0.index : nil }
    }

    private static func lineItems(in lines: [String], before endIndex: Int) -> [ReceiptScan.LineItem] {
        var items: [ReceiptScan.LineItem] = []
        for line in lines.prefix(endIndex) where !isIgnored(line) {
            guard !totalKeywords.contains(where: { line.containsWords($0.phrase) }),
                  let price = amounts(in: line).last
            else { continue }

            let name = itemName(from: line)
            if name.count >= 2 {
                items.append(ReceiptScan.LineItem(id: items.count, name: name, price: price))
            }
        }
        return items
    }

    /// The first line near the top with words but no prices or dates, e.g. "CAMPUS BITES".
    private static func restaurantName(in lines: [String]) -> String? {
        lines.prefix(4).first { line in
            line.filter(\.isLetter).count >= 3 && amounts(in: line).isEmpty && line.firstMatch(of: datePattern) == nil
        }
    }

    private static func isIgnored(_ line: String) -> Bool {
        ignoredWords.contains { line.containsWords($0) }
    }

    // Amounts

    private static let datePattern = #/\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}/#
    private static let timePattern = #/(?i)\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]\.?m\.?)?/#
    private static let phonePattern = #/(?:\+94|\b0)\d{2}[\s-]?\d{3}[\s-]?\d{4}/#
    private static let currencyPattern = #/(?i)\b(?:lkr|rs)\.?/#
    /// 950 · 950.00 · 1,250 · 1,250.00
    private static let amountPattern = #/\b(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\b/#

    /// Every price-like number on a line, in reading order. Dates, times and phone numbers are ignored.
    static func amounts(in line: String) -> [Int] {
        let cleaned = line
            .replacing(datePattern, with: " ")
            .replacing(timePattern, with: " ")
            .replacing(phonePattern, with: " ")
            .replacing(currencyPattern, with: " ")

        return cleaned.matches(of: amountPattern).compactMap { match in
            let rupees = match.output.1.replacingOccurrences(of: ",", with: "")
            let cents = match.output.2.map { "." + $0 } ?? ""
            guard let value = Double(rupees + cents), value > 0, value < 1_000_000 else { return nil }
            return Int(value.rounded())
        }
    }

    /// "2 x Kottu Roti   1,500.00" → "Kottu Roti"
    private static func itemName(from line: String) -> String {
        line.replacing(currencyPattern, with: " ")
            .replacing(amountPattern, with: " ")
            .replacing(#/^\s*[xX×@]\s*/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacing(#/\s{2,}/#, with: " ")
    }
}

private extension String {
    /// True when `phrase` appears as whole words, ignoring case and punctuation:
    /// "TOTAL:" contains "total", but "Hotel" doesn't contain "tel" and "Subtotal" doesn't contain "total".
    func containsWords(_ phrase: String) -> Bool {
        let words = lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return (" " + String(words) + " ").replacing(#/\s+/#, with: " ").contains(" \(phrase) ")
    }
}

/// `ReceiptScanner` for previews and tests: returns a fixed result without running Vision.
struct MockReceiptScanner: ReceiptScanner {
    var result: Result<ReceiptScan, ReceiptScanError> = .success(MockData.sampleReceipt)

    func scan(_ image: UIImage) async throws -> ReceiptScan {
        try result.get()
    }
}

extension CGImagePropertyOrientation {
    /// Vision needs the photo's orientation to read text that was photographed sideways or upside down.
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
