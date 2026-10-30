import Testing
import Foundation
@testable import FoodPassport

/// Visits with more than one dish or drink, and the item list on Log your visit.
@Suite("Visit items")
@MainActor
struct VisitItemTests {

    // Saved visits

    @Test("A visit lists every item, and its title names the first one")
    func visitWithSeveralItems() {
        // The first sample visit has Kottu Roti and Iced Milo.
        let visit = MockData.visits[0]

        #expect(visit.allItems.map(\.name) == ["Kottu Roti", "Iced Milo"])
        #expect(visit.allItems.map(\.price) == [750, 200])
        #expect(visit.title == "Kottu Roti + 1 more")
    }

    @Test("An older visit without items shows its dish and amount as one item")
    func olderVisitWithoutItems() {
        // makeVisit has no items, like a visit saved before items existed.
        let visit = makeVisit(amount: 650)

        #expect(visit.items == nil)
        #expect(visit.allItems.count == 1)
        #expect(visit.allItems[0].name == "Test dish")
        #expect(visit.allItems[0].price == 650)
        #expect(visit.title == "Test dish")
    }

    @Test("Visits saved in Firestore before items existed still load")
    func decodeOldVisit() throws {
        // Save a visit, then remove "items" from it, like a document saved by an older version of the app.
        let data = try JSONEncoder().encode(makeVisit(id: "old-visit"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["items"] = nil
        let oldData = try JSONSerialization.data(withJSONObject: json)

        let visit = try JSONDecoder().decode(Visit.self, from: oldData)

        #expect(visit.id == "old-visit")
        #expect(visit.items == nil)
        #expect(visit.allItems.count == 1)
    }

    @Test("A visit with items is saved and loaded with all of them")
    func itemsRoundTrip() throws {
        let visit = MockData.visits[0]

        let decoded = try JSONDecoder().decode(Visit.self, from: JSONEncoder().encode(visit))

        #expect(decoded.items == visit.items)
    }

    // Typing items on Log your visit

    @Test("Prices typed with LKR or commas are read as numbers")
    func draftPrices() {
        #expect(VisitItemDraft(priceText: "750").price == 750)
        #expect(VisitItemDraft(priceText: "LKR 1,250").price == 1250)
        #expect(VisitItemDraft(priceText: "").price == nil)
    }

    @Test("A row counts as empty only when both name and price are blank")
    func emptyRows() {
        #expect(VisitItemDraft().isEmpty)
        #expect(VisitItemDraft(name: "  ").isEmpty)
        #expect(!VisitItemDraft(name: "Tea").isEmpty)
        #expect(!VisitItemDraft(priceText: "60").isEmpty)
    }

    @Test("The total adds up every price, and items without a price count as 0")
    func draftTotal() {
        let items = [
            VisitItemDraft(name: "Kottu Roti", priceText: "750"),
            VisitItemDraft(name: "Iced Milo", priceText: "200"),
            VisitItemDraft(name: "Water"),
        ]

        #expect(VisitItemDraft.total(of: items) == 950)
        #expect(VisitItemDraft.total(of: []) == 0)
    }

    @Test("Scanned dishes replace the blank starting row")
    func scannedDishesFillBlankRow() {
        // A scanned Kottu Roti replaces the empty row.
        let result = VisitItemDraft.adding([VisitItemDraft(name: "Kottu Roti", priceText: "650")], to: [VisitItemDraft()])

        #expect(result.map(\.name) == ["Kottu Roti"])
    }

    @Test("Scanning a dish that's already listed doesn't add it twice")
    func scannedDishesAreNotDuplicated() {
        let list = [VisitItemDraft(name: "Kottu Roti", priceText: "650")]
        // "kottu roti" is already listed (different capitals); Iced Milo is new.
        let scanned = [VisitItemDraft(name: "kottu roti"), VisitItemDraft(name: "Iced Milo")]

        let result = VisitItemDraft.adding(scanned, to: list)

        #expect(result.map(\.name) == ["Kottu Roti", "Iced Milo"])
        // The price the student already had is kept.
        #expect(result[0].price == 650)
    }

    @Test("Adding nothing to an empty list still leaves one row to type in")
    func alwaysOneRow() {
        let result = VisitItemDraft.adding([], to: [])

        #expect(result.count == 1)
        #expect(result[0].isEmpty)
    }

    // Using a receipt

    @Test("A receipt adds prices to the dishes already picked, and keeps their names")
    func receiptAddsPricesOnly() {
        // The student picked these dishes; the receipt uses different names.
        let picked = [VisitItemDraft(name: "Kottu Roti"), VisitItemDraft(name: "Iced Milo")]
        let receipt = [
            ReceiptScan.LineItem(id: 0, name: "MILO ICED 400ML", price: 200),
            ReceiptScan.LineItem(id: 1, name: "CHICKEN KOTTU", price: 750),
        ]

        let result = VisitItemDraft.applyingReceipt(receipt, to: picked)

        #expect(result.map(\.name) == ["Kottu Roti", "Iced Milo"])
        #expect(result.map(\.price) == [750, 200])
    }

    @Test("Receipt lines that match nothing aren't added to the student's list")
    func extraReceiptLinesAreIgnored() {
        // "Takeaway Box" matches no dish.
        let picked = [VisitItemDraft(name: "Fried Rice")]
        let receipt = [
            ReceiptScan.LineItem(id: 0, name: "Fried Rice", price: 650),
            ReceiptScan.LineItem(id: 1, name: "Takeaway Box", price: 50),
        ]

        let result = VisitItemDraft.applyingReceipt(receipt, to: picked)

        #expect(result.map(\.name) == ["Fried Rice"])
        #expect(result[0].price == 650)
    }

    @Test("One dish and one receipt line left over are paired, even if the names differ")
    func lastDishGetsLastPrice() {
        let picked = [VisitItemDraft(name: "Hoppers"), VisitItemDraft(name: "Plain Tea")]
        let receipt = [
            ReceiptScan.LineItem(id: 0, name: "TEA", price: 60),
            // "APPA" shares no word with "Hoppers", but it's the only line left.
            ReceiptScan.LineItem(id: 1, name: "APPA x3", price: 150),
        ]

        let result = VisitItemDraft.applyingReceipt(receipt, to: picked)

        #expect(result.map(\.name) == ["Hoppers", "Plain Tea"])
        #expect(result.map(\.price) == [150, 60])
    }

    @Test("With no dishes picked yet, the receipt's items are used")
    func receiptFillsEmptyList() {
        let receipt = [ReceiptScan.LineItem(id: 0, name: "Kottu Roti", price: 750)]

        let result = VisitItemDraft.applyingReceipt(receipt, to: [VisitItemDraft()])

        #expect(result.map(\.name) == ["Kottu Roti"])
        #expect(result[0].price == 750)
    }

    @Test("Each receipt line is only used once")
    func receiptLineUsedOnce() {
        // Only one receipt line, so only Milk Tea gets a price.
        let picked = [VisitItemDraft(name: "Plain Tea"), VisitItemDraft(name: "Milk Tea"), VisitItemDraft(name: "Vadai")]
        let receipt = [ReceiptScan.LineItem(id: 0, name: "Milk Tea", price: 100)]

        let result = VisitItemDraft.applyingReceipt(receipt, to: picked)

        #expect(result.map(\.price) == [nil, 100, nil])
    }

    @Test("Names match on whole words, ignoring sizes and capitals", arguments: [
        ("Kottu Roti", "CHICKEN KOTTU", 1),
        ("Egg Hoppers", "egg hopper", 2),
        ("Iced Milo", "Milo (Large)", 1),
        ("Fried Rice", "Fish Curry", 0),
        ("Plain Tea", "Large Plate", 0),
    ])
    func matchScores(first: String, second: String, expected: Int) {
        #expect(VisitItemDraft.matchScore(first, second) == expected)
    }

    // Saving through AppState

    @Test("A visit with several items is saved with all of them")
    func saveVisitWithItems() async throws {
        let app = TestApp()
        try await app.signIn()
        let items = [VisitItem(name: "Fried Rice", price: 650), VisitItem(name: "Chop Suey", price: 400)]
        var visit = makeVisit(id: "two-dishes", amount: 1050)
        visit.items = items

        // Saved through AppState into the fake database.
        app.appState.addVisit(visit)
        await app.appState.waitForPendingWrites()

        let saved = try #require(app.database.visits.first { $0.id == "two-dishes" })
        #expect(saved.allItems.map(\.name) == ["Fried Rice", "Chop Suey"])
        #expect(saved.amount == 1050)
    }
}
