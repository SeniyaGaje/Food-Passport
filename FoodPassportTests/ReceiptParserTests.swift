import Testing
import Foundation
@testable import FoodPassport

/// The receipt parser is tested with plain text rows, the same input Vision gives it after reading a photo.
@Suite("Receipt scanning")
@MainActor
struct ReceiptParserTests {

    /// Turns lines of text into receipt rows from the top of the page down.
    private func rows(_ lines: String...) -> [TextRow] {
        lines.enumerated().map { index, line in
            TextRow(text: line, boundingBox: CGRect(x: 0.1, y: 0.95 - Double(index) * 0.06, width: 0.8, height: 0.04))
        }
    }

    // Whole receipts

    @Test("Reads the restaurant, date, items and total from a typical campus receipt")
    func typicalReceipt() {
        let receipt = rows(
            "CAMPUS BITES",
            "Tel: 011 234 5678",
            "Date: 26/10/2026 12:45",
            "Kottu Roti 750.00",
            "Iced Milo 200.00",
            "Sub Total 950.00",
            "TOTAL LKR 950.00",
            "Cash 1,000.00",
            "Change 50.00"
        )

        let scan = ReceiptParser.parse(receipt)

        #expect(scan.restaurantName == "CAMPUS BITES")
        #expect(scan.date == "26/10/2026")
        #expect(scan.items.map(\.name) == ["Kottu Roti", "Iced Milo"])
        #expect(scan.items.map(\.price) == [750, 200])
        #expect(scan.total == 950)
        #expect(scan.isTotalFromTotalLine)
        // The orange highlight on the photo goes around the TOTAL line.
        #expect(scan.totalBoundingBox == receipt[6].boundingBox)
    }

    @Test("Finds the total when it is printed on the line under TOTAL")
    func totalOnNextLine() {
        let receipt = rows("Kottu Roti 1,250.00", "TOTAL", "LKR 1,250.00")

        let scan = ReceiptParser.parse(receipt)

        #expect(scan.total == 1250)
        #expect(scan.isTotalFromTotalLine)
        #expect(scan.totalBoundingBox == receipt[2].boundingBox)
    }

    @Test("Grand total beats an earlier total and service charge")
    func grandTotalWins() {
        let scan = ReceiptParser.parse(rows(
            "Fried Rice 1,000.00",
            "Total 1,000.00",
            "Service Charge 100.00",
            "Grand Total 1,100.00"
        ))

        #expect(scan.total == 1100)
        #expect(scan.isTotalFromTotalLine)
    }

    @Test("When two lines say TOTAL, the lower one is used")
    func lowestTotalLineWins() {
        #expect(ReceiptParser.indexOfTotalLine(in: ["Total 900.00", "Tea 200.00", "TOTAL 1,100.00"]) == 2)
    }

    @Test("A sub total on its own is not taken as the amount paid")
    func subTotalIsNotTheTotal() {
        #expect(ReceiptParser.indexOfTotalLine(in: ["Kottu Roti 750.00", "Sub Total 750.00"]) == nil)
        #expect(ReceiptParser.indexOfTotalLine(in: ["Kottu Roti 750.00", "Subtotal 750.00"]) == nil)
    }

    @Test("Without a TOTAL line the largest amount is offered, flagged so the student checks it")
    func largestAmountFallback() {
        let scan = ReceiptParser.parse(rows(
            "CAMPUS BITES",
            "Kottu Roti 750.00",
            "Iced Milo 200.00",
            "Cash 1,000.00"
        ))

        // The cash handed over is larger, but it isn't what the meal cost.
        #expect(scan.total == 750)
        #expect(!scan.isTotalFromTotalLine)
        #expect(scan.items.map(\.name) == ["Kottu Roti", "Iced Milo"])
    }

    @Test("A photo with no text gives an empty result instead of crashing")
    func emptyReceipt() {
        let scan = ReceiptParser.parse([])

        #expect(scan.total == nil)
        #expect(scan.items.isEmpty)
        #expect(scan.restaurantName == nil)
        #expect(scan.date == nil)
        #expect(scan.totalBoundingBox == nil)
        #expect(!scan.isTotalFromTotalLine)
    }

    @Test("A receipt with words but no prices has no total")
    func noAmounts() {
        let scan = ReceiptParser.parse(rows("CAMPUS BITES", "Thank you, come again!"))

        #expect(scan.total == nil)
        #expect(scan.items.isEmpty)
    }

    // Items

    @Test("Quantities are removed from item names")
    func quantityPrefix() {
        let scan = ReceiptParser.parse(rows("2 x Kottu Roti 1,500.00", "Total 1,500.00"))

        #expect(scan.items.first?.name == "Kottu Roti")
        #expect(scan.items.first?.price == 1500)
    }

    @Test("Two identical items stay as two separate items")
    func repeatedItems() {
        let scan = ReceiptParser.parse(rows("Tea 100.00", "Tea 100.00", "Total 200.00"))

        #expect(scan.items.count == 2)
        #expect(Set(scan.items.map(\.id)).count == 2)
    }

    @Test("Ignored words are matched as whole words: 'Hotel' is not 'Tel'")
    func wholeWordMatching() {
        let scan = ReceiptParser.parse(rows(
            "Tel: 011 234 5678",
            "Hotel Special Rice 650.00",
            "Total 650.00"
        ))

        #expect(scan.items.map(\.name) == ["Hotel Special Rice"])
    }

    // Amounts

    @Test("Reads rupee amounts written in different ways", arguments: [
        ("Rs. 1,250.00", 1250),
        ("LKR950", 950),
        ("1,250/=", 1250),
        ("Kottu 650.50", 651),
        ("Fish Curry 900", 900),
        ("Banquet 12,500.00", 12500),
    ])
    func amountFormats(line: String, expected: Int) {
        #expect(ReceiptParser.amounts(in: line) == [expected])
    }

    @Test("Dates, times and phone numbers are not read as prices", arguments: [
        "26/10/2026",
        "2026-10-26 12:45 PM",
        "Time 18:30:15",
        "0771234567",
        "011 234 5678",
    ])
    func notAmounts(line: String) {
        #expect(ReceiptParser.amounts(in: line).isEmpty)
    }

    @Test("Zero and absurdly large numbers are not prices")
    func outOfRangeAmounts() {
        #expect(ReceiptParser.amounts(in: "Discount 0.00").isEmpty)
        #expect(ReceiptParser.amounts(in: "Ref 1234567").isEmpty)
    }

    @Test("Every amount on a line is read, in order")
    func severalAmounts() {
        #expect(ReceiptParser.amounts(in: "2 Kottu Roti 750.00 1,500.00") == [2, 750, 1500])
    }

    // Known problems, found by these tests

    @Test("An address line with numbers is not mistaken for an item")
    func addressLineIsNotAnItem() {
        // The parser treats "Colombo 07" as an item costing LKR 7, and Log Visit then fills the
        // dish field with the address. Recorded here so the bug is tracked until the parser is fixed.
        withKnownIssue("Address lines that end in a number are read as receipt items") {
            let scan = ReceiptParser.parse(rows(
                "CAMPUS BITES",
                "No. 12, Reid Avenue, Colombo 07",
                "Kottu Roti 750.00",
                "Total 750.00"
            ))
            #expect(scan.items.map(\.name) == ["Kottu Roti"])
        }
    }
}
