import Foundation
import CoreLocation

// MARK: - Cuisine

enum Cuisine: String, CaseIterable, Identifiable, Hashable {
    case sriLankan = "Sri Lankan"
    case indian = "Indian"
    case chinese = "Chinese"
    case italian = "Italian"
    case japanese = "Japanese"
    case thai = "Thai"

    var id: String { rawValue }
}

// MARK: - Dish

struct Dish: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let price: Int
}

// MARK: - Restaurant

struct Restaurant: Identifiable, Hashable {
    let id: String
    let name: String
    let cuisine: Cuisine
    let distanceKm: Double
    let walkingMinutes: Int
    let priceRange: ClosedRange<Int>
    let latitude: Double
    let longitude: Double
    let imageName: String
    let routeSummary: String
    let pricesUpdated: String
    let popularDishes: [Dish]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Restaurant

extension Restaurant {
    var distanceText: String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(1)))) km"
    }

    var priceRangeText: String {
        "LKR \(priceRange.lowerBound.formatted())–\(priceRange.upperBound.formatted())"
    }
}

// MARK: - Visit

struct Visit: Identifiable, Hashable {
    let id: String
    let dishName: String
    let cuisine: Cuisine
    let restaurant: Restaurant
    let amount: Int
    let rating: Int
    let notes: String
    let date: Date
    let isLocationVerified: Bool
    let isAutoDetected: Bool
    let isFromReceipt: Bool
    let imageName: String
}

// MARK: - VisitDateGroup

/// Section headings used by the History list.
enum VisitDateGroup: Int, CaseIterable, Comparable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case earlier

    init(date: Date, relativeTo now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: start, to: today).day ?? 0

        switch daysAgo {
        case ...0: self = .today
        case 1: self = .yesterday
        case 2..<7: self = .thisWeek
        case 7..<14: self = .lastWeek
        default: self = .earlier
        }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "Earlier this week"
        case .lastWeek: "Last week"
        case .earlier: "Earlier"
        }
    }

    static func < (lhs: VisitDateGroup, rhs: VisitDateGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Stamp

/// A cuisine stamp in the student's passport, earned by a location-verified visit.
struct Stamp: Identifiable, Hashable {
    var id: Cuisine { cuisine }
    let cuisine: Cuisine
    let restaurantName: String
    let earnedDate: Date
    let visitID: Visit.ID?
    let imageName: String
}

// MARK: - QuestType

enum QuestType: String, CaseIterable, Identifiable {
    case newCuisines = "New cuisines"
    case foodTrail = "Food trail"

    var id: Self { self }
}

// MARK: - QuestDuration

enum QuestDuration: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case thisMonth = "This month"

    var id: Self { self }
}

// MARK: - PlannedStop

/// A suggested place in the quest plan, with its estimated cost.
struct PlannedStop: Identifiable, Hashable {
    var id: Restaurant.ID { restaurant.id }
    let restaurant: Restaurant
    let estimatedCost: Int
    var fitsBudget = true
}

// MARK: - Quest

struct Quest: Hashable {
    let title: String
    let type: QuestType
    let targetCuisines: Int
    let cuisinesTried: Int
    let budget: Int
    let spent: Int
    let duration: QuestDuration
    let maxDistanceKm: Double
    let plan: [PlannedStop]
    let planExplanation: String

    var remainingBudget: Int { budget - spent }

    var cuisineProgress: Double {
        Double(cuisinesTried) / Double(max(targetCuisines, 1))
    }

    var budgetProgress: Double {
        Double(spent) / Double(max(budget, 1))
    }

    var nextPick: PlannedStop? {
        plan.first(where: \.fitsBudget)
    }
}

// MARK: - BudgetUpdate

/// What the Adaptive Food Quest changed after the latest visit.
struct BudgetUpdate: Hashable {
    let actualCost: Int
    let estimatedCost: Int
    let removedStop: PlannedStop
    let replacementStop: PlannedStop

    var overspend: Int { actualCost - estimatedCost }
}

// MARK: - TrailStopStatus

enum TrailStopStatus {
    case visited
    case next
    case upcoming
}

// MARK: - TrailStop

struct TrailStop: Identifiable, Hashable {
    var id: Restaurant.ID { restaurant.id }
    let restaurant: Restaurant
    let isVisited: Bool
}

// MARK: - FoodTrail

struct FoodTrail: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let stops: [TrailStop]

    var visitedCount: Int {
        stops.filter(\.isVisited).count
    }

    var progress: Double {
        Double(visitedCount) / Double(max(stops.count, 1))
    }

    var nextStop: TrailStop? {
        stops.first { !$0.isVisited }
    }

    func status(of stop: TrailStop) -> TrailStopStatus {
        if stop.isVisited { return .visited }
        return stop.id == nextStop?.id ? .next : .upcoming
    }
}

// MARK: - WeeklyChallenge

struct WeeklyChallenge: Hashable {
    let title: String
    let details: String
    let daysLeft: Int
    let completed: Int
    let target: Int
    let suggestions: [PlannedStop]

    var progress: Double {
        Double(completed) / Double(max(target, 1))
    }
}

// MARK: - UserProfile

struct UserProfile: Hashable {
    var name: String
    var email: String
    var memberSince: Date
    var monthlyBudget: Int

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}

// MARK: - DashboardPeriod

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case allTime = "All time"

    var id: Self { self }
}

// MARK: - DailySpending

struct DailySpending: Identifiable, Hashable {
    var id: String { day }
    let day: String
    let amount: Int
    var isHighlighted = false
}

// MARK: - CuisineShare

struct CuisineShare: Identifiable, Hashable {
    var id: Cuisine { cuisine }
    let cuisine: Cuisine
    let percentage: Int
}

// MARK: - MealPrediction

/// One of the top results returned by the on-device dish classifier.
struct MealPrediction: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let dishName: String
    let confidence: Double
    let cuisine: Cuisine
}

// MARK: - ReceiptScan

/// Text read from a receipt by Vision, with the detected total.
struct ReceiptScan: Hashable {
    struct LineItem: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let price: Int
    }

    let restaurantName: String
    let timestamp: String
    let items: [LineItem]
    let total: Int
}
