import Foundation
import Testing
@testable import FoodPassport

/// Checks how the quest plan is picked, including the proposal's worked example.
@Suite("Quest planner")
@MainActor
struct QuestPlannerTests {
    /// A place with just the details the planner uses.
    private func place(_ id: String, _ cuisine: Cuisine, km: Double, prices: ClosedRange<Int>) -> Restaurant {
        Restaurant(id: id, name: id, cuisine: cuisine, distanceKm: km, walkingMinutes: Int(km * 12),
                   priceRange: prices, latitude: 6.9, longitude: 79.86, imageName: "", routeSummary: "",
                   pricesUpdated: "", popularDishes: [])
    }

    private let started = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
    /// Set on every test quest, so it's still running even when the tests run on the 1st of a month.
    private let ends = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

    /// Italian is closer but costs about 1,200; Chinese is further and costs about 750.
    private var italian: Restaurant { place("Pasta Corner", .italian, km: 0.5, prices: 1000...1400) }
    private var chinese: Restaurant { place("Dragon Wok", .chinese, km: 1.1, prices: 600...900) }
    private var indian: Restaurant { place("Spice Route", .indian, km: 0.8, prices: 500...800) }
    private var sriLankan: Restaurant { place("Campus Bites", .sriLankan, km: 0.4, prices: 500...900) }

    private func meal(_ restaurant: Restaurant, _ amount: Int, daysAgo: Double = 1) -> Visit {
        makeVisit(cuisine: restaurant.cuisine, restaurant: restaurant, amount: amount,
                  date: .now.addingTimeInterval(-daysAgo * 24 * 60 * 60))
    }

    private func planner(budget: Int = 3000, target: Int = 3, visits: [Visit],
                         restaurants: [Restaurant]? = nil, plans: [PlannedVisit] = []) -> QuestPlanner {
        QuestPlanner(settings: QuestSettings(targetCuisines: target, budget: budget, maxDistanceKm: 2, startedAt: started, extendedUntil: ends),
                     restaurants: restaurants ?? [italian, chinese, indian, sriLankan], visits: visits, plannedVisits: plans)
    }

    @Test("Worked example: LKR 3,000 budget, 2,200 spent – Italian at 1,200 is replaced by Chinese at 750")
    func proposalWorkedExample() {
        let quest = planner(visits: [meal(sriLankan, 1250), meal(indian, 950)]).quest()

        #expect(quest.spent == 2200)
        #expect(quest.remainingBudget == 800)
        #expect(quest.cuisinesTried == 2)
        #expect(quest.plan.map(\.restaurant.id) == ["Dragon Wok"])
        #expect(quest.plan.first?.estimatedCost == 750)
        #expect(quest.plan.first?.fitsBudget == true)
        #expect(quest.planExplanation.contains("Pasta Corner"))
        #expect(quest.planExplanation.contains("swapped"))
    }

    @Test("With enough money the nearest untried places are picked")
    func nearestWhenAffordable() {
        let quest = planner(visits: [meal(sriLankan, 600)]).quest()

        #expect(quest.plan.map(\.restaurant.id) == ["Pasta Corner", "Spice Route"])
        #expect(quest.plan.allSatisfy { $0.fitsBudget })
        #expect(quest.nextPick?.restaurant.id == "Pasta Corner")
    }

    @Test("Cuisines tried before the quest are never suggested, and don't count as new")
    func cuisinesTriedBeforeTheQuest() {
        let beforeQuest = meal(chinese, 700, daysAgo: 10)
        let quest = planner(visits: [beforeQuest, meal(chinese, 700)]).quest()

        #expect(quest.cuisinesTried == 0)
        #expect(!quest.plan.contains { $0.restaurant.cuisine == .chinese })
        // The meal before the start doesn't use the quest's money.
        #expect(quest.spent == 700)
    }

    @Test("A place that can't fit and has no cheaper swap is marked over budget")
    func overBudgetStop() {
        let quest = planner(budget: 1000, target: 1, visits: [], restaurants: [italian]).quest()

        #expect(quest.plan.count == 1)
        #expect(quest.plan[0].fitsBudget == false)
        #expect(quest.nextPick == nil)
        #expect(quest.planExplanation.contains("doesn't fit"))
    }

    @Test("Estimates use what the student paid there before, rounded to LKR 50")
    func estimateFromPastVisits() {
        let planner = planner(visits: [meal(chinese, 620), meal(chinese, 700, daysAgo: 2)])

        #expect(planner.estimatedCost(at: chinese) == 650)
        // Never been: the middle of the price range.
        #expect(planner.estimatedCost(at: italian) == 1200)
    }

    @Test("A planned visit keeps its saved estimate and goes first when it counts towards the quest")
    func plannedVisitIsPinned() {
        let tomorrow = Date.now.addingTimeInterval(24 * 60 * 60)
        let plan = PlannedVisit(restaurantID: chinese.id, date: tomorrow, estimatedCost: 700, countsTowardsQuest: true)
        let quest = planner(target: 2, visits: [], plans: [plan]).quest()

        #expect(quest.plan.first?.restaurant.id == chinese.id)
        #expect(quest.plan.first?.estimatedCost == 700)
        #expect(quest.plan.first?.plannedFor == tomorrow)
        #expect(quest.planExplanation.contains("planned to go"))
    }

    @Test("A planned visit with \"Count towards my quest\" off isn't pushed to the top")
    func plannedVisitNotCounting() {
        let plan = PlannedVisit(restaurantID: chinese.id, date: .now.addingTimeInterval(3600), estimatedCost: 700, countsTowardsQuest: false)
        let quest = planner(target: 1, visits: [], plans: [plan]).quest()

        #expect(quest.plan.map(\.restaurant.id) == ["Campus Bites"])
    }

    @Test("When the target is reached there's nothing left to plan")
    func targetReached() {
        let quest = planner(target: 2, visits: [meal(sriLankan, 600), meal(indian, 600)]).quest()

        #expect(quest.plan.isEmpty)
        #expect(quest.planExplanation.contains("reached your target"))
    }

    @Test("A food trail plans the stops not visited yet, in order")
    func trailQuest() {
        let trail = FoodTrail(id: "t", name: "Test trail", summary: "", stops: [sriLankan, indian, chinese].map {
            TrailStop(restaurant: $0, isVisited: false)
        })
        let settings = QuestSettings(type: .foodTrail, budget: 1500, trailID: "t", startedAt: started, extendedUntil: ends)
        let quest = QuestPlanner(settings: settings, restaurants: [], visits: [meal(sriLankan, 700)], trails: [trail]).quest()

        #expect(quest.title == "Test trail")
        #expect(quest.cuisinesTried == 1)
        #expect(quest.targetCuisines == 3)
        #expect(quest.plan.map(\.restaurant.id) == ["Spice Route", "Dragon Wok"])
        #expect(quest.plan.map(\.fitsBudget) == [true, false])
    }

    // In the app

    @Test("Logging a meal that cost more than planned shows the swap in the budget update")
    func budgetUpdateAfterExpensiveMeal() async throws {
        let database = MockDatabaseService(restaurants: [italian, chinese, indian, sriLankan], visits: [meal(sriLankan, 950)], stamps: [])
        database.quest = QuestSettings(targetCuisines: 3, budget: 3000, maxDistanceKm: 2, startedAt: started, extendedUntil: ends)
        // No GPS, so the places keep the distances set above.
        let app = TestApp(database: database, coordinate: nil)
        try await app.signIn()
        // Before the meal: 2,050 left, so the two nearest fit.
        #expect(app.appState.activeQuest.plan.map(\.restaurant.id) == ["Pasta Corner", "Spice Route"])

        let update = try #require(try await app.appState.saveVisit(meal(indian, 1250, daysAgo: 0), photos: []).budgetUpdate)

        #expect(update.estimatedCost == 650)
        #expect(update.difference == 600)
        #expect(update.remainingBudget == 800)
        #expect(update.removedStop?.restaurant.id == "Pasta Corner")
        #expect(update.replacementStop?.restaurant.id == "Dragon Wok")
    }

    @Test("A meal outside the quest gives no budget update")
    func noBudgetUpdateWithoutQuest() async throws {
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []))
        try await app.signIn()

        let result = try await app.appState.saveVisit(makeVisit(), photos: [])

        #expect(result.budgetUpdate == nil)
    }

    @Test("Increase budget adds just enough for the stop that doesn't fit")
    func increaseBudget() async throws {
        let database = MockDatabaseService(restaurants: [italian], visits: [], stamps: [])
        database.quest = QuestSettings(targetCuisines: 1, budget: 1000, maxDistanceKm: 2, startedAt: started, extendedUntil: ends)
        let app = TestApp(database: database)
        try await app.signIn()
        #expect(app.appState.activeQuest.nextPick == nil)

        let budget = app.appState.increaseQuestBudgetToFitPlan()

        #expect(budget == 1200)
        #expect(app.appState.activeQuest.nextPick?.restaurant.id == italian.id)
    }

    @Test("Extend deadline gives the quest another week")
    func extendDeadline() async throws {
        let database = MockDatabaseService(visits: [], stamps: [])
        database.quest = QuestSettings(duration: .thisWeek, startedAt: started)
        let app = TestApp(database: database)
        try await app.signIn()
        let oldEnd = try #require(app.appState.questSettings?.endDate())

        let newEnd = try #require(app.appState.extendQuestDeadline())

        #expect(Calendar.current.dateComponents([.day], from: max(oldEnd, .now), to: newEnd).day == 7)
        #expect(app.appState.questSettings?.endDate() == newEnd)
        await app.appState.waitForPendingWrites()
        #expect(app.database.quest?.extendedUntil == newEnd)
    }

    @Test("Finishing onboarding starts a first quest with the chosen budget, only once")
    func firstQuestFromOnboarding() async throws {
        let app = TestApp(database: MockDatabaseService(visits: [], stamps: []))
        try await app.signIn()

        app.appState.startFirstQuestIfNeeded(budget: 5000)
        app.appState.startFirstQuestIfNeeded(budget: 8000)

        #expect(app.appState.questSettings?.budget == 5000)
        #expect(app.appState.questSettings?.targetCuisines == 3)
        #expect(app.appState.hasActiveQuest)
    }

    @Test("Planning a visit saves it with its estimate, and logging the visit completes it")
    func plannedVisitLifecycle() async throws {
        let database = MockDatabaseService(restaurants: [italian, chinese], visits: [], stamps: [])
        database.quest = QuestSettings(targetCuisines: 2, startedAt: started, extendedUntil: ends)
        let app = TestApp(database: database)
        try await app.signIn()

        _ = await app.appState.planVisit(to: chinese, at: .now.addingTimeInterval(2 * 60 * 60), remind: false, countsTowardsQuest: true)
        await app.appState.waitForPendingWrites()

        #expect(app.database.plannedVisits.first?.estimatedCost == 750)
        #expect(app.database.plannedVisits.first?.countsTowardsQuest == true)

        // Planning the same place again replaces the plan instead of adding a second one.
        _ = await app.appState.planVisit(to: chinese, at: .now.addingTimeInterval(3 * 60 * 60), remind: false, countsTowardsQuest: true)
        await app.appState.waitForPendingWrites()
        #expect(app.database.plannedVisits.count == 1)
        #expect(app.appState.plannedVisits.count == 1)
        #expect(app.appState.activeQuest.plan.first?.restaurant.id == chinese.id)

        app.appState.addVisit(meal(chinese, 800, daysAgo: 0))
        await app.appState.waitForPendingWrites()

        #expect(app.appState.plannedVisits.isEmpty)
        #expect(app.database.plannedVisits.isEmpty)
        #expect(app.appState.lastBudgetUpdate?.estimatedCost == 750)
    }

    @Test("Trails from the database replace the built-in ones")
    func trailsFromDatabase() async throws {
        let database = MockDatabaseService(restaurants: [italian, chinese], visits: [], stamps: [])
        database.trails = [TrailDocument(id: "noodles", name: "Noodle walk", summary: "Two stops",
                                         restaurantIDs: [chinese.id, "missing", italian.id])]
        database.weeklyChallenge = ChallengeDocument(title: "Try 2 cuisines", details: "Any two.", target: 2)
        let app = TestApp(database: database)
        try await app.signIn()

        #expect(app.appState.trails.map(\.name) == ["Noodle walk"])
        #expect(app.appState.trails[0].stops.map(\.id) == [chinese.id, italian.id])
        #expect(app.appState.currentChallenge.title == "Try 2 cuisines")
        #expect(app.appState.currentChallenge.target == 2)
    }
}
