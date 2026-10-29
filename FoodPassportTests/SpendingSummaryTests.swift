import Foundation
import Testing
import CoreLocation
@testable import FoodPassport

@Suite("Spending overview")
@MainActor
struct SpendingSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Colombo")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Thursday 15 October 2026, at noon.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 13))!
    }

    private var visits: [Visit] {
        [
            makeVisit(cuisine: .sriLankan, restaurant: MockData.campusBites, amount: 600, date: day(10, 14)),
            makeVisit(cuisine: .sriLankan, restaurant: MockData.campusBites, amount: 400, date: day(10, 13)),
            makeVisit(cuisine: .chinese, restaurant: MockData.dragonWok, amount: 1000, date: day(10, 2)),
            makeVisit(cuisine: .italian, restaurant: MockData.pastaCorner, amount: 1200, date: day(9, 20)),
        ]
    }

    @Test("This month: total, average per meal, and the budget")
    func thisMonthTotals() {
        let summary = SpendingSummary(visits: visits, period: .thisMonth, monthlyBudget: 5000, now: now, calendar: calendar)

        #expect(summary.visits.count == 3)
        #expect(summary.total == 2000)
        #expect(summary.averagePerMeal == 666)
        #expect(summary.spentThisMonth == 2000)
        #expect(summary.budgetLeft == 3000)
        #expect(abs(summary.budgetFraction - 0.4) < 0.0001)
    }

    @Test("Spending by restaurant is biggest first, with the number of visits")
    func byRestaurant() {
        let summary = SpendingSummary(visits: visits, period: .thisMonth, monthlyBudget: 5000, now: now, calendar: calendar)

        #expect(summary.byRestaurant.map(\.name) == ["Campus Bites", "Dragon Wok"])
        #expect(summary.byRestaurant[0].amount == 1000)
        #expect(summary.byRestaurant[0].visits == 2)
    }

    @Test("The cuisine chart shares the money, not the number of meals")
    func cuisineByMoney() {
        let summary = SpendingSummary(visits: visits, period: .allTime, monthlyBudget: 5000, now: now, calendar: calendar)

        // Sri Lankan has two meals but less money than Italian's one.
        #expect(summary.byCuisine.map(\.cuisine) == [.italian, .chinese, .sriLankan])
        #expect(summary.byCuisine.map(\.amount) == [1200, 1000, 1000])
        #expect(summary.byCuisine.map(\.percentage) == [38, 31, 31])
    }

    @Test("This week shows Monday to Sunday with today highlighted")
    func weekBars() {
        let summary = SpendingSummary(visits: visits, period: .thisWeek, monthlyBudget: 5000, now: now, calendar: calendar)

        #expect(summary.bars.count == 7)
        #expect(summary.bars.map(\.amount) == [0, 400, 600, 0, 0, 0, 0])
        #expect(summary.bars.filter(\.isHighlighted).count == 1)
        #expect(summary.bars[3].isHighlighted)
        #expect(summary.bars[0].label == "Monday")
    }

    @Test("Last month shows last month's weeks, not the last seven days")
    func lastMonthBars() {
        let summary = SpendingSummary(visits: visits, period: .lastMonth, monthlyBudget: 5000, now: now, calendar: calendar)

        #expect(summary.total == 1200)
        // 30 days of September: 1–7, 8–14, 15–21, 22–28, 29–30.
        #expect(summary.bars.map(\.shortLabel) == ["1–7", "8–14", "15–21", "22–28", "29–30"])
        #expect(summary.bars.map(\.amount) == [0, 0, 1200, 0, 0])
        #expect(summary.bars[2].isHighlighted)
        #expect(summary.bars.map(\.amount).reduce(0, +) == summary.total)
    }

    @Test("All time shows a bar for each month since the first visit")
    func allTimeBars() {
        let summary = SpendingSummary(visits: visits, period: .allTime, monthlyBudget: 5000, now: now, calendar: calendar)

        #expect(summary.bars.count == 2)
        #expect(summary.bars.map(\.amount) == [1200, 2000])
        #expect(summary.bars.last?.isHighlighted == true)
    }

    @Test("No visits: zero totals and no division by zero")
    func empty() {
        let summary = SpendingSummary(visits: [], period: .thisMonth, monthlyBudget: 0, now: now, calendar: calendar)

        #expect(summary.total == 0)
        #expect(summary.averagePerMeal == 0)
        #expect(summary.budgetFraction == 0)
        #expect(summary.byCuisine.isEmpty)
        #expect(summary.bars.allSatisfy { $0.amount == 0 })
    }
}

@Suite("Location checks")
@MainActor
struct LocationCheckTests {
    private let campusBites = MockData.campusBites

    @Test("An old GPS fix at the restaurant doesn't verify the visit")
    func oldFixIsNotTrusted() async throws {
        let app = TestApp()
        try await app.signIn()
        app.location.simulateMove(to: campusBites.coordinate)

        let later = Date.now.addingTimeInterval(Geofence.maxLocationAge + 60)

        #expect(app.appState.locationCheck(for: campusBites) == .verified)
        #expect(app.appState.locationCheck(for: campusBites, now: later) == .outOfDate)
    }

    @Test("A very rough GPS fix doesn't verify the visit")
    func roughFixIsNotTrusted() async throws {
        let app = TestApp()
        try await app.signIn()
        let rough = CLLocation(coordinate: campusBites.coordinate, altitude: 0, horizontalAccuracy: 500,
                               verticalAccuracy: 10, timestamp: .now)
        app.location.onLocationChange?(rough)

        #expect(app.appState.locationCheck(for: campusBites) == .inaccurate)
        #expect(!app.appState.isAtRestaurant(campusBites))
    }

    @Test("Opening Log your visit asks for a fresh fix")
    func refreshOnLogVisit() async throws {
        let app = TestApp()
        try await app.signIn()

        app.appState.refreshLocation()

        #expect(app.location.refreshCount == 1)
    }

    @Test("The widget's Log visit button picks the restaurant the student is at")
    func restaurantHere() async throws {
        let app = TestApp()
        try await app.signIn()
        #expect(app.appState.restaurantHere == nil)

        app.location.simulateMove(to: campusBites.coordinate)

        #expect(app.appState.restaurantHere?.id == campusBites.id)
    }
}

@Suite("Widget data")
@MainActor
struct WidgetDataTests {
    @Test("A widget file saved before the new fields existed still opens")
    func oldSnapshotDecodes() throws {
        let old = #"{"isSignedIn":true,"cuisinesTried":1,"targetCuisines":3,"questUnit":"cuisines tried","monthlyBudget":5000,"monthlySpent":1000,"budgetMonth":"2026-10","updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))

        #expect(snapshot.isSignedIn)
        #expect(snapshot.nextPickName == nil)
        #expect(snapshot.challengeFraction == 0)
        #expect(abs(snapshot.questFraction - 1.0 / 3.0) < 0.0001)
    }

    @Test("Last week's challenge progress is cleared when the week ends")
    func challengeRollsOver() {
        var snapshot = WidgetSnapshot(isSignedIn: true)
        snapshot.challengeCompleted = 2
        snapshot.challengeTarget = 3
        snapshot.challengeEndsAt = Date.now.addingTimeInterval(60)

        #expect(snapshot.current(at: .now).challengeCompleted == 2)
        #expect(snapshot.current(at: .now.addingTimeInterval(120)).challengeCompleted == 0)
    }

    @Test("The quest widget gets the budget left and the next pick")
    func questWidgetValues() async throws {
        let publisher = RecordingWidgetPublisher()
        let database = MockDatabaseService(visits: [], stamps: [])
        database.quest = QuestSettings(budget: 3000, startedAt: .now.addingTimeInterval(-60))
        let app = TestApp(database: database, widgets: publisher)
        try await app.signIn()

        #expect(publisher.latest.questBudgetLeft == 3000)
        #expect(publisher.latest.nextPickName == app.appState.activeQuest.nextPick?.restaurant.name)
        #expect(publisher.latest.challengeTarget == 3)
    }

    @Test("Widget links open the weekly challenge and Log visit")
    func newWidgetLinks() {
        let router = AppRouter()
        router.openWidgetURL(URL(string: "foodpassport://challenge")!)
        #expect(router.selectedTab == .passport)
        #expect(router.tabPaths[.passport] == [.weeklyChallenge])

        router.openWidgetURL(URL(string: "foodpassport://log")!)
        #expect(router.wantsQuickLog)
    }
}
