import Testing
import Foundation
import CoreLocation
@testable import FoodPassport

@Suite("Models")
@MainActor
struct ModelTests {

    // Restaurant

    @Test("A restaurant measured from the student's own spot is 0 km away and at least 1 minute's walk")
    func distanceFromSameSpot() {
        let restaurant = MockData.campusBites
        let measured = restaurant.withDistance(from: restaurant.location)

        #expect(measured.distanceKm == 0)
        #expect(measured.walkingMinutes == 1)
    }

    @Test("Distance and walking time are measured from the student's real location")
    func distanceFromStudent() {
        let restaurant = MockData.campusBites
        let student = coordinate(1_100, northOf: restaurant.coordinate)
        let measured = restaurant.withDistance(from: CLLocation(latitude: student.latitude, longitude: student.longitude))

        #expect(abs(measured.distanceKm - 1.1) < 0.02)
        // 1.1 km at 80 m a minute is 13.75 minutes, rounded up.
        #expect(measured.walkingMinutes == 14)
        // Everything else about the restaurant stays the same.
        #expect(measured.id == restaurant.id)
        #expect(measured.priceRange == restaurant.priceRange)
    }

    @Test("Distance and price range are written for the screen")
    func restaurantText() {
        let decimal = Locale.current.decimalSeparator ?? "."
        let grouping = Locale.current.groupingSeparator ?? ","

        #expect(MockData.campusBites.distanceText == "0\(decimal)4 km")
        #expect(MockData.campusBites.priceRangeText == "LKR 500–900")
        #expect(MockData.spiceRoute.priceRangeText == "LKR 600–1\(grouping)100")
    }

    // History sections

    @Test("Visits are grouped into Today, Yesterday, This week, Last week and Earlier")
    func visitDateGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Colombo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!

        func group(daysAgo: Int, hour: Int = 12) -> VisitDateGroup {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            return VisitDateGroup(date: date, relativeTo: now, calendar: calendar)
        }

        #expect(group(daysAgo: 0, hour: 0) == .today)
        #expect(group(daysAgo: 1, hour: 23) == .yesterday)
        #expect(group(daysAgo: 2) == .thisWeek)
        #expect(group(daysAgo: 6) == .thisWeek)
        #expect(group(daysAgo: 7) == .lastWeek)
        #expect(group(daysAgo: 13) == .lastWeek)
        #expect(group(daysAgo: 14) == .earlier)
        #expect(group(daysAgo: 400) == .earlier)
        // A visit dated in the future (e.g. a wrong phone clock) still shows under Today rather than disappearing.
        #expect(group(daysAgo: -1) == .today)
    }

    @Test("History sections are listed newest first")
    func visitDateGroupOrder() {
        #expect(VisitDateGroup.allCases.sorted() == [.today, .yesterday, .thisWeek, .lastWeek, .earlier])
        #expect(VisitDateGroup.thisWeek.title == "Earlier this week")
    }

    // Quests

    @Test("Quest progress, spending and the next pick")
    func questProgress() {
        let quest = MockData.activeQuest

        #expect(quest.remainingBudget == 800)
        #expect(abs(quest.cuisineProgress - 2.0 / 3.0) < 0.0001)
        #expect(abs(quest.budgetProgress - 2200.0 / 3000.0) < 0.0001)
        #expect(quest.nextPick?.restaurant.id == MockData.dragonWok.id)
    }

    @Test("The next pick skips places that no longer fit the budget")
    func nextPickSkipsOverBudgetStops() {
        let quest = makeQuest(plan: [
            PlannedStop(restaurant: MockData.pastaCorner, estimatedCost: 1200, fitsBudget: false),
            PlannedStop(restaurant: MockData.hoppersHut, estimatedCost: 400),
        ])
        #expect(quest.nextPick?.restaurant.id == MockData.hoppersHut.id)

        let nothingFits = makeQuest(plan: [PlannedStop(restaurant: MockData.pastaCorner, estimatedCost: 1200, fitsBudget: false)])
        #expect(nothingFits.nextPick == nil)
    }

    @Test("A quest with a zero target or budget doesn't divide by zero")
    func questWithZeroTargets() {
        let quest = makeQuest(targetCuisines: 0, cuisinesTried: 0, budget: 0, spent: 0)

        #expect(quest.cuisineProgress == 0)
        #expect(quest.budgetProgress == 0)
        #expect(quest.remainingBudget == 0)
    }

    @Test("Overspending shows as a negative remaining budget and progress over 100%")
    func overspentQuest() {
        let quest = makeQuest(budget: 3000, spent: 3200)

        #expect(quest.remainingBudget == -200)
        #expect(quest.budgetProgress > 1)
    }

    @Test("A budget update reports how much more (or less) the meal cost than estimated")
    func budgetUpdateDifference() {
        #expect(MockData.latestBudgetUpdate.difference == 300)
        let cheaper = BudgetUpdate(restaurantName: "Dragon Wok", actualCost: 600, estimatedCost: 750, remainingBudget: 900)
        #expect(cheaper.difference == -150)
        #expect(cheaper.removedStop == nil)
    }

    // Trails and challenges

    @Test("A food trail knows which stop is visited, next and upcoming")
    func foodTrailStatus() {
        let trail = MockData.campusFoodTrail

        #expect(trail.visitedCount == 1)
        #expect(abs(trail.progress - 1.0 / 3.0) < 0.0001)
        #expect(trail.nextStop?.restaurant.id == MockData.hoppersHut.id)
        #expect(trail.status(of: trail.stops[0]) == .visited)
        #expect(trail.status(of: trail.stops[1]) == .next)
        #expect(trail.status(of: trail.stops[2]) == .upcoming)
    }

    @Test("A finished trail has no next stop, and an empty trail doesn't crash")
    func finishedAndEmptyTrails() {
        let finished = FoodTrail(id: "done", name: "Done", summary: "", stops: [
            TrailStop(restaurant: MockData.campusBites, isVisited: true),
            TrailStop(restaurant: MockData.hoppersHut, isVisited: true),
        ])
        #expect(finished.nextStop == nil)
        #expect(finished.progress == 1)

        let empty = FoodTrail(id: "empty", name: "Empty", summary: "", stops: [])
        #expect(empty.progress == 0)
        #expect(empty.nextStop == nil)
    }

    @Test("Weekly challenge progress")
    func weeklyChallengeProgress() {
        #expect(MockData.weeklyChallenge.progress == 0)

        let finished = WeeklyChallenge(title: "", details: "", daysLeft: 2, completed: 1, target: 1, suggestions: [])
        #expect(finished.progress == 1)

        let noTarget = WeeklyChallenge(title: "", details: "", daysLeft: 2, completed: 0, target: 0, suggestions: [])
        #expect(noTarget.progress == 0)
    }

    // Profile

    @Test("Initials come from the first two names", arguments: [
        ("John Doe", "JD"),
        ("Seniya", "S"),
        ("Seniya Gajadeera Perera", "SG"),
        ("  Nimal   Silva ", "NS"),
        ("", ""),
    ])
    func initials(name: String, expected: String) {
        var profile = MockData.profile
        profile.name = name
        #expect(profile.initials == expected)
    }

    // Saving to Firestore

    @Test("A visit survives being encoded and decoded, as it is when saved to Firestore")
    func visitCodableRoundTrip() throws {
        let visit = MockData.visits[0]

        let data = try JSONEncoder().encode(visit)
        let decoded = try JSONDecoder().decode(Visit.self, from: data)

        #expect(decoded == visit)
        #expect(decoded.restaurant.priceRange == 500...900)
    }

    @Test("A stamp is identified by its cuisine, so there is only one stamp per cuisine")
    func stampIdentity() {
        #expect(MockData.stamps[0].id == .sriLankan)
    }

    // Helpers

    private func makeQuest(
        targetCuisines: Int = 3,
        cuisinesTried: Int = 1,
        budget: Int = 3000,
        spent: Int = 1000,
        plan: [PlannedStop] = []
    ) -> Quest {
        Quest(
            title: "Test quest",
            type: .newCuisines,
            targetCuisines: targetCuisines,
            cuisinesTried: cuisinesTried,
            budget: budget,
            spent: spent,
            duration: .thisMonth,
            maxDistanceKm: 2,
            plan: plan,
            planExplanation: ""
        )
    }
}
