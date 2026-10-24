import Foundation
import UIKit
import Vision

/// One line of text on a receipt, e.g. "Kottu Roti 750.00".
nonisolated struct TextRow: Sendable, Equatable {
    var text: String
    /// Where the line is on the photo (Vision uses 0–1, starting from the bottom-left).
    var boundingBox: CGRect
}

/// Reads the total and items from a photo of a receipt.
/// Screens use this protocol, so previews and tests can swap in the mock.
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

/// Reads receipts with Apple's Vision text recognition. Everything happens on the phone.
struct VisionReceiptScanner: ReceiptScanner {
    func scan(_ image: UIImage) async throws -> ReceiptScan {
        guard let cgImage = image.cgImage else { throw ReceiptScanError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Reading text takes a second or two, so do it in the background to keep the screen smooth.
        let rows = try await Task.detached(priority: .userInitiated) {
            try Self.recognizeRows(in: cgImage, orientation: orientation)
        }.value

        guard !rows.isEmpty else { throw ReceiptScanError.noTextFound }
        return ReceiptParser.parse(rows)
    }

    /// Runs Vision on the photo and returns the receipt's lines from top to bottom.
    nonisolated private static func recognizeRows(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> [TextRow] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Spell-checking turns prices and codes into words, so it's switched off.
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

        // Every piece of text Vision found, from the top of the receipt down.
        var pieces: [TextRow] = []
        for observation in request.results ?? [] {
            if let best = observation.topCandidates(1).first {
                pieces.append(TextRow(text: best.string, boundingBox: observation.boundingBox))
            }
        }
        pieces.sort { $0.boundingBox.midY > $1.boundingBox.midY }

        // Vision often reads an item's name and price as two pieces.
        // Pieces at the same height belong to the same line, so put them back together.
        var lines: [[TextRow]] = []
        var lineBox = CGRect.null
        for piece in pieces {
            let box = piece.boundingBox
            let isSameLine = !lines.isEmpty && abs(lineBox.midY - box.midY) < min(lineBox.height, box.height) * 0.6

            if isSameLine {
                lines[lines.count - 1].append(piece)
                lineBox = lineBox.union(box)
            } else {
                lines.append([piece])
                lineBox = box
            }
        }

        // Join each line's pieces from left to right.
        return lines.map { line in
            let leftToRight = line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            var box = leftToRight[0].boundingBox
            for piece in leftToRight {
                box = box.union(piece.boundingBox)
            }
            return TextRow(text: leftToRight.map { $0.text }.joined(separator: " "), boundingBox: box)
        }
    }
}

/// Turns the lines of a receipt into a total and a list of items.
/// It only works with text (no Vision), so it's easy to unit test.
enum ReceiptParser {
    /// Words that mark the total, with a score. The highest score wins, e.g. "Grand total" beats "Total".
    /// Longest phrases are checked first, so "Sub total" scores 1 instead of matching "total".
    private static let totalKeywords: [(phrase: String, score: Int)] = [
        ("grand total", 5), ("net total", 5), ("total due", 5), ("amount due", 5), ("total payable", 5),
        ("balance due", 4), ("net amount", 4), ("bill amount", 4), ("total amount", 4),
        ("sub total", 1), ("subtotal", 1),
        ("total", 3),
    ].sorted { $0.phrase.count > $1.phrase.count }

    /// Lines with these words have numbers in them, but they're not items or the total.
    private static let ignoredWords = [
        "cash", "change", "tendered", "card", "visa", "master", "discount", "tax", "vat", "service charge",
        "total items", "total qty", "no of items", "qty", "invoice", "bill no", "receipt no", "order", "table",
        "tel", "phone", "mobile", "reg no",
        // Address lines, e.g. "No. 12, Reid Avenue": the house number isn't a price.
        "road", "rd", "street", "avenue", "mawatha", "lane",
    ]

    static func parse(_ rows: [TextRow]) -> ReceiptScan {
        let lines = rows.map { $0.text }
        let totalIndex = indexOfTotalLine(in: lines)

        var total: Int?
        var totalRow: Int?

        if let totalIndex {
            if let amount = amounts(in: lines[totalIndex]).last {
                total = amount
                totalRow = totalIndex
            } else if totalIndex + 1 < lines.count, let amount = amounts(in: lines[totalIndex + 1]).last {
                // Some receipts print the amount on the line under "TOTAL".
                total = amount
                totalRow = totalIndex + 1
            }
        }

        // Remember whether a real TOTAL line was found, before the fallback below.
        let foundTotalLine = total != nil

        // No TOTAL line: use the biggest amount instead (the screen asks the student to check it).
        if total == nil, let largest = largestAmount(in: lines) {
            total = largest.amount
            totalRow = largest.row
        }

        var totalBox: CGRect?
        if let totalRow {
            totalBox = rows[totalRow].boundingBox
        }

        return ReceiptScan(
            restaurantName: restaurantName(in: lines),
            date: firstDate(in: lines),
            items: lineItems(in: lines, before: totalIndex ?? lines.count),
            total: total,
            isTotalFromTotalLine: foundTotalLine,
            totalBoundingBox: totalBox
        )
    }

    // Lines

    /// The line that holds the amount to pay, or nil if there isn't one.
    static func indexOfTotalLine(in lines: [String]) -> Int? {
        var bestIndex: Int?
        var bestScore = 0

        for (index, line) in lines.enumerated() where !isIgnored(line) {
            let score = totalScore(of: line)
            // ">=" means a lower line wins a tie, since the real total is usually further down.
            if score > 0 && score >= bestScore {
                bestIndex = index
                bestScore = score
            }
        }

        // A "Sub total" on its own (score 1) isn't the amount paid.
        return bestScore > 1 ? bestIndex : nil
    }

    /// How much a line looks like the total, or 0 if it has no total word.
    private static func totalScore(of line: String) -> Int {
        totalKeywords.first { line.containsWords($0.phrase) }?.score ?? 0
    }

    /// Lines above the total that end in a price, e.g. "Kottu Roti 750.00".
    private static func lineItems(in lines: [String], before endIndex: Int) -> [ReceiptScan.LineItem] {
        var items: [ReceiptScan.LineItem] = []

        for line in lines.prefix(endIndex) where !isIgnored(line) {
            guard totalScore(of: line) == 0, let price = amounts(in: line).last else { continue }

            let name = itemName(from: line)
            if name.count >= 2 {
                items.append(ReceiptScan.LineItem(id: items.count, name: name, price: price))
            }
        }
        return items
    }

    /// The biggest amount on the receipt and the line it's on, skipping lines like "Cash".
    private static func largestAmount(in lines: [String]) -> (amount: Int, row: Int)? {
        var largest: (amount: Int, row: Int)?

        for (row, line) in lines.enumerated() where !isIgnored(line) {
            guard let amount = amounts(in: line).max() else { continue }
            if amount > (largest?.amount ?? 0) {
                largest = (amount, row)
            }
        }
        return largest
    }

    /// The first line near the top with words but no prices or dates, e.g. "CAMPUS BITES".
    private static func restaurantName(in lines: [String]) -> String? {
        for line in lines.prefix(4) {
            let letterCount = line.filter { $0.isLetter }.count
            if letterCount >= 3 && amounts(in: line).isEmpty && line.firstMatch(of: datePattern) == nil {
                return line
            }
        }
        return nil
    }

    private static func firstDate(in lines: [String]) -> String? {
        for line in lines {
            if let match = line.firstMatch(of: datePattern) {
                return String(match.output)
            }
        }
        return nil
    }

    private static func isIgnored(_ line: String) -> Bool {
        ignoredWords.contains { line.containsWords($0) }
    }

    // Amounts

    private static let datePattern = #/\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}/#               // 26/10/2026
    private static let timePattern = #/(?i)\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]\.?m\.?)?/# // 12:45 PM
    private static let phonePattern = #/(?:\+94|\b0)\d{2}[\s-]?\d{3}[\s-]?\d{4}/#        // 011 234 5678
    private static let currencyPattern = #/(?i)\b(?:lkr|rs)\.?/#                        // LKR, Rs.
    private static let amountPattern = #/\b(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?\b/# // 950, 1,250.00

    /// Every price on a line, left to right. Dates, times and phone numbers are skipped.
    static func amounts(in line: String) -> [Int] {
        // Blank out things that contain numbers but aren't prices.
        let cleaned = line
            .replacing(datePattern, with: " ")
            .replacing(timePattern, with: " ")
            .replacing(phonePattern, with: " ")
            .replacing(currencyPattern, with: " ")

        var prices: [Int] = []
        for match in cleaned.matches(of: amountPattern) {
            let rupees = match.output.1.replacingOccurrences(of: ",", with: "")

            // "07" in "Colombo 07" is a postal zone. Prices never start with 0 (but "0.50" is fine).
            if rupees.count > 1 && rupees.hasPrefix("0") { continue }

            var number = rupees
            if let cents = match.output.2 {
                number += "." + String(cents)
            }

            // Skip zero and huge numbers like reference codes.
            guard let value = Double(number), value > 0, value < 1_000_000 else { continue }
            prices.append(Int(value.rounded()))
        }
        return prices
    }

    /// "2 x Kottu Roti   1,500.00" becomes "Kottu Roti".
    private static func itemName(from line: String) -> String {
        line.replacing(currencyPattern, with: " ")
            .replacing(amountPattern, with: " ")         // remove the numbers
            .replacing(#/^\s*[xX×@]\s*/#, with: "")       // remove the "x" left over from "2 x"
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacing(#/\s{2,}/#, with: " ")             // squash double spaces
    }
}

private extension String {
    /// True when the text has `phrase` as whole words, ignoring capitals and punctuation.
    /// "TOTAL:" contains "total", but "Hotel" doesn't contain "tel".
    func containsWords(_ phrase: String) -> Bool {
        // Turn punctuation into spaces and squash them: "TOTAL:  950" becomes " total 950 ".
        let lettersAndNumbers = lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        let spaced = (" " + String(lettersAndNumbers) + " ").replacing(#/\s+/#, with: " ")

        // The spaces on both sides make sure only whole words match.
        return spaced.contains(" \(phrase) ")
    }
}

/// Fake scanner for previews and tests. Returns a fixed result without running Vision.
struct MockReceiptScanner: ReceiptScanner {
    var result: Result<ReceiptScan, ReceiptScanError> = .success(MockData.sampleReceipt)

    func scan(_ image: UIImage) async throws -> ReceiptScan {
        try result.get()
    }
}

extension CGImagePropertyOrientation {
    /// Vision needs to know which way up the photo is, so sideways photos still read correctly.
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
