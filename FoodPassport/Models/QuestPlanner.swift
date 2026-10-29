import Foundation

/// Works out a quest's progress and suggested places from the student's real visits.
/// It only uses plain values, so tests can check a plan without the rest of the app.
///
/// How the plan is picked (new cuisines quest):
/// 1. Candidates are places within the distance limit serving a cuisine the student has never logged,
///    one per cuisine (the cheapest place for it).
/// 2. Places the student planned with "Count towards my quest" go first.
/// 3. The rest of the plan is filled with the nearest candidates.
/// 4. While the plan costs more than the money left, the most expensive stop is swapped
///    for a cheaper candidate.
/// 5. Any stop that still doesn't fit is marked, so the "Budget limit" pop-up can explain it.
struct QuestPlanner {
    let settings: QuestSettings
    let restaurants: [Restaurant]
    let visits: [Visit]
    var trails: [FoodTrail] = MockData.foodTrails
    var plannedVisits: [PlannedVisit] = []
    var now: Date = .now

    /// Meals logged while the quest is running.
    var questVisits: [Visit] {
        visits.filter { settings.contains($0.date) }
    }

    var trail: FoodTrail {
        trails.first { $0.id == settings.trailID } ?? trails.first ?? MockData.campusFoodTrail
    }

    /// What a meal here should cost: what the student usually pays at this place,
    /// or the middle of its price range if they haven't been yet. Rounded to LKR 50.
    /// A planned visit keeps the estimate it was given when it was planned.
    func estimatedCost(at restaurant: Restaurant) -> Int {
        if let planned = upcomingPlan(for: restaurant) {
            return planned.estimatedCost
        }
        let paid = visits.filter { $0.restaurant.id == restaurant.id }.map(\.amount)
        let typical = paid.isEmpty
            ? (restaurant.priceRange.lowerBound + restaurant.priceRange.upperBound) / 2
            : paid.reduce(0, +) / paid.count
        return Int((Double(typical) / 50).rounded()) * 50
    }

    func quest() -> Quest {
        settings.type == .foodTrail ? trailQuest() : cuisineQuest()
    }

    // New cuisines

    private func cuisineQuest() -> Quest {
        let meals = questVisits
        let spent = meals.map(\.amount).reduce(0, +)
        let remaining = max(0, settings.budget - spent)

        // Only cuisines that are new to the student count, not ones they had before the quest.
        let triedBefore = Set(visits.filter { $0.date < settings.startedAt }.map(\.cuisine))
        let newCuisines = Set(meals.map(\.cuisine)).subtracting(triedBefore)
        let needed = max(0, settings.targetCuisines - newCuisines.count)

        let triedEver = Set(visits.map(\.cuisine))
        let candidates = cheapestPlacePerCuisine(excluding: triedEver)
        var swappedOut: [PlannedStop] = []
        var plan = pickStops(from: candidates, count: needed, remaining: remaining, swappedOut: &swappedOut)
        plan = markWhatFits(plan, remaining: remaining)

        return Quest(
            title: "Try \(settings.targetCuisines) new \(settings.targetCuisines == 1 ? "cuisine" : "cuisines")",
            type: .newCuisines,
            targetCuisines: settings.targetCuisines,
            cuisinesTried: newCuisines.count,
            budget: settings.budget,
            spent: spent,
            duration: settings.duration,
            maxDistanceKm: settings.maxDistanceKm,
            plan: plan,
            planExplanation: cuisineExplanation(plan: plan, needed: needed, hasCandidates: !candidates.isEmpty,
                                                remaining: remaining, swappedOut: swappedOut)
        )
    }

    /// One place for each untried cuisine within the distance limit: the cheapest, then the nearest.
    /// A place the student planned to visit for the quest wins, even if it's further away.
    private func cheapestPlacePerCuisine(excluding tried: Set<Cuisine>) -> [PlannedStop] {
        let untried = restaurants.filter { !tried.contains($0.cuisine) }
        let byCuisine = Dictionary(grouping: untried, by: \.cuisine)
        return byCuisine.values.compactMap { places in
            if let planned = places.first(where: { upcomingPlan(for: $0, countingTowardsQuest: true) != nil }) {
                return stop(for: planned)
            }
            return places
                .filter { $0.distanceKm <= settings.maxDistanceKm }
                .map { stop(for: $0) }
                .min { ($0.estimatedCost, $0.restaurant.distanceKm) < ($1.estimatedCost, $1.restaurant.distanceKm) }
        }
        .sorted { ($0.restaurant.distanceKm, $0.restaurant.name) < ($1.restaurant.distanceKm, $1.restaurant.name) }
    }

    private func pickStops(from candidates: [PlannedStop], count: Int, remaining: Int,
                           swappedOut: inout [PlannedStop]) -> [PlannedStop] {
        guard count > 0 else { return [] }

        // Planned visits first, in date order, if their cuisine still needs trying.
        let pinned = candidates
            .compactMap { candidate in
                upcomingPlan(for: candidate.restaurant, countingTowardsQuest: true).map { (candidate, $0.date) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        var plan = Array(pinned.prefix(count))
        let pinnedIDs = Set(plan.map(\.id))

        // Then the nearest of the rest (candidates are already nearest first).
        for candidate in candidates where plan.count < count && !plan.contains(where: { $0.id == candidate.id }) {
            plan.append(candidate)
        }

        // Too expensive: swap the priciest stop for the cheapest candidate that costs less.
        func cost(_ stops: [PlannedStop]) -> Int { stops.map(\.estimatedCost).reduce(0, +) }
        while cost(plan) > remaining {
            guard let priciest = plan.indices
                .filter({ !pinnedIDs.contains(plan[$0].id) })
                .max(by: { plan[$0].estimatedCost < plan[$1].estimatedCost }),
                  let cheaper = candidates
                .filter({ spare in !plan.contains { $0.id == spare.id } && !swappedOut.contains { $0.id == spare.id } })
                .filter({ $0.estimatedCost < plan[priciest].estimatedCost })
                .min(by: { $0.estimatedCost < $1.estimatedCost })
            else { break }
            swappedOut.append(plan[priciest])
            plan[priciest] = cheaper
        }
        return plan
    }

    // Food trail

    private func trailQuest() -> Quest {
        let meals = questVisits
        let spent = meals.map(\.amount).reduce(0, +)
        let remaining = max(0, settings.budget - spent)
        let visited = Set(meals.map(\.restaurant.id))
        let trail = trail
        let stopsLeft = trail.stops.filter { !visited.contains($0.id) }.map { stop(for: $0.restaurant) }
        let plan = markWhatFits(stopsLeft, remaining: remaining)

        let explanation: String
        if let next = plan.first {
            let fit = next.fitsBudget ? "fits the \(remaining.lkr) you have left" : "costs more than the \(remaining.lkr) you have left"
            explanation = "Trail stops are visited in order. Next is \(next.restaurant.name), about \(next.estimatedCost.lkr), which \(fit)."
        } else {
            explanation = "You've visited every stop on \(trail.name). Well done!"
        }

        return Quest(
            title: trail.name,
            type: .foodTrail,
            targetCuisines: trail.stops.count,
            cuisinesTried: trail.stops.count - stopsLeft.count,
            budget: settings.budget,
            spent: spent,
            duration: settings.duration,
            maxDistanceKm: settings.maxDistanceKm,
            plan: plan,
            planExplanation: explanation
        )
    }

    // Shared steps

    private func stop(for restaurant: Restaurant) -> PlannedStop {
        PlannedStop(restaurant: restaurant, estimatedCost: estimatedCost(at: restaurant),
                    plannedFor: upcomingPlan(for: restaurant)?.date)
    }

    /// Goes down the plan keeping a running total. A stop that would go over is marked as not fitting.
    private func markWhatFits(_ plan: [PlannedStop], remaining: Int) -> [PlannedStop] {
        var left = remaining
        return plan.map { stop in
            var stop = stop
            stop.fitsBudget = stop.estimatedCost <= left
            if stop.fitsBudget { left -= stop.estimatedCost }
            return stop
        }
    }

    /// The student's next planned visit to this place (today or later).
    private func upcomingPlan(for restaurant: Restaurant, countingTowardsQuest: Bool = false) -> PlannedVisit? {
        let today = Calendar.current.startOfDay(for: now)
        return plannedVisits
            .filter { $0.restaurantID == restaurant.id && $0.date >= today && (!countingTowardsQuest || $0.countsTowardsQuest) }
            .min { $0.date < $1.date }
    }

    /// The "Why these picks?" text, written from the actual plan.
    private func cuisineExplanation(plan: [PlannedStop], needed: Int, hasCandidates: Bool,
                                    remaining: Int, swappedOut: [PlannedStop]) -> String {
        if needed == 0 {
            return "You've reached your target. Any new cuisine from now on is a bonus."
        }
        if !hasCandidates {
            return "There are no cuisines you haven't tried within \(settings.maxDistanceKm.formatted()) km. Raise the distance limit to see more places."
        }

        var sentences: [String] = []
        let fitting = plan.filter(\.fitsBudget)
        if !fitting.isEmpty {
            let names = fitting.map { "\($0.restaurant.name) (\($0.restaurant.cuisine.rawValue), \($0.restaurant.distanceText))" }
            let total = fitting.map(\.estimatedCost).reduce(0, +)
            sentences.append("\(ListFormatter.localizedString(byJoining: names)) \(fitting.count == 1 ? "serves a cuisine" : "serve cuisines") you haven't tried yet.")
            sentences.append("Together they should cost about \(total.lkr) of the \(remaining.lkr) you have left.")
        }
        let planned = plan.filter { upcomingPlan(for: $0.restaurant, countingTowardsQuest: true) != nil }
        if !planned.isEmpty {
            sentences.append("\(ListFormatter.localizedString(byJoining: planned.map(\.restaurant.name))) went first because you planned to go.")
        }
        for stop in swappedOut {
            sentences.append("\(stop.restaurant.name) (about \(stop.estimatedCost.lkr)) was swapped for a cheaper place to stay in budget.")
        }
        for stop in plan where !stop.fitsBudget {
            sentences.append("\(stop.restaurant.name) (about \(stop.estimatedCost.lkr)) doesn't fit what's left. Raise the budget or extend the deadline.")
        }
        if plan.count < needed {
            sentences.append("Only \(plan.count) untried \(plan.count == 1 ? "cuisine is" : "cuisines are") within \(settings.maxDistanceKm.formatted()) km.")
        }
        sentences.append("Estimates use what you've paid before, or the middle of each place's price range.")
        return sentences.joined(separator: " ")
    }
}

extension QuestPlanner {
    /// Compares the plan from just before a meal with the plan after it, for the "Budget update" pop-up.
    static func budgetUpdate(before: Quest, after: Quest, visit: Visit, estimatedCost: Int) -> BudgetUpdate {
        // The first place that fitted before and now doesn't (or was dropped), ignoring the one just visited.
        let removed = before.plan.first { old in
            guard old.fitsBudget, old.id != visit.restaurant.id, old.restaurant.cuisine != visit.cuisine else { return false }
            let now = after.plan.first { $0.id == old.id }
            return now == nil || now?.fitsBudget == false
        }
        let added = after.plan.first { new in new.fitsBudget && !before.plan.contains { $0.id == new.id } }

        return BudgetUpdate(
            restaurantName: visit.restaurant.name,
            actualCost: visit.amount,
            estimatedCost: estimatedCost,
            remainingBudget: after.remainingBudget,
            removedStop: removed,
            replacementStop: removed == nil ? nil : added
        )
    }
}
