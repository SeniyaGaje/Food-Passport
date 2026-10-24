import Foundation
import CoreLocation

enum Cuisine: String, CaseIterable, Identifiable, Hashable, Codable {
    case sriLankan = "Sri Lankan"
    case indian = "Indian"
    case chinese = "Chinese"
    case italian = "Italian"
    case japanese = "Japanese"
    case thai = "Thai"
    case american = "American"
    case mexican = "Mexican"
    case korean = "Korean"
    case middleEastern = "Middle Eastern"
    case french = "French"
    case vietnamese = "Vietnamese"

    var id: String { rawValue }
}

struct Dish: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let price: Int
}

/// A place to eat. Saved in Firestore under restaurants/{id}.
struct Restaurant: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let cuisine: Cuisine
    /// Starts as the distance from campus, then becomes the real distance once we know where the student is.
    var distanceKm: Double
    var walkingMinutes: Int
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

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Normal walking speed: 80 metres a minute (about 4.8 km/h).
    static let walkingMetresPerMinute = 80.0

    /// A copy with the distance and walking time measured from the student.
    func withDistance(from location: CLLocation) -> Restaurant {
        let metres = location.distance(from: self.location)
        var copy = self
        copy.distanceKm = metres / 1000
        copy.walkingMinutes = max(1, Int((metres / Self.walkingMetresPerMinute).rounded(.up)))
        return copy
    }
}

extension Restaurant {
    var distanceText: String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(1)))) km"
    }

    var priceRangeText: String {
        "LKR \(priceRange.lowerBound.formatted())–\(priceRange.upperBound.formatted())"
    }
}

/// A logged meal. Saved in Firestore under users/{userID}/visits/{id}.
/// It keeps its own copy of the restaurant, so History still works if the restaurant changes.
struct Visit: Identifiable, Hashable, Codable {
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
    /// Everything eaten on this visit. Visits saved before this existed don't have it.
    var items: [VisitItem]? = nil

    /// The visit's items. Older visits get one item made from their dish name and amount.
    var allItems: [VisitItem] {
        if let items, !items.isEmpty {
            return items
        }
        return [VisitItem(name: dishName, price: amount)]
    }

    /// A short title for lists, e.g. "Kottu Roti + 1 more".
    var title: String {
        let items = allItems
        if items.count > 1 {
            return "\(items[0].name) + \(items.count - 1) more"
        }
        return items[0].name
    }
}

/// One food or drink on a visit, e.g. Kottu Roti for LKR 750.
struct VisitItem: Identifiable, Hashable, Codable {
    var id = UUID().uuidString
    var name: String
    /// nil if the student didn't enter a price for it.
    var price: Int?
}

/// An item while it's being typed on Log your visit. The price is kept as text until saving.
struct VisitItemDraft: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var priceText = ""

    /// The price as a number, ignoring "LKR" and commas.
    var price: Int? {
        Int(priceText.filter { $0.isNumber })
    }

    var isEmpty: Bool {
        name.trimmed.isEmpty && priceText.trimmed.isEmpty
    }

    /// Adds scanned dishes to the list. Dishes already listed aren't added twice,
    /// and empty rows are dropped, so the list never has a blank row before the new dishes.
    static func adding(_ newItems: [VisitItemDraft], to list: [VisitItemDraft]) -> [VisitItemDraft] {
        var result = list.filter { !$0.isEmpty }

        for item in newItems {
            let alreadyListed = result.contains { $0.name.trimmed.caseInsensitiveCompare(item.name.trimmed) == .orderedSame }
            if !alreadyListed {
                result.append(item)
            }
        }

        // Always leave at least one row to type in.
        return result.isEmpty ? [VisitItemDraft()] : result
    }

    /// The prices added up. Items without a price count as 0.
    static func total(of items: [VisitItemDraft]) -> Int {
        var sum = 0
        for item in items {
            sum += item.price ?? 0
        }
        return sum
    }
}

/// The headings in the History list.
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

/// A passport stamp, earned by a verified visit to a new cuisine.
/// Saved in Firestore under users/{userID}/stamps/{cuisine}.
struct Stamp: Identifiable, Hashable, Codable {
    var id: Cuisine { cuisine }
    let cuisine: Cuisine
    let restaurantName: String
    let earnedDate: Date
    let visitID: Visit.ID?
    let imageName: String
}

enum QuestType: String, CaseIterable, Identifiable {
    case newCuisines = "New cuisines"
    case foodTrail = "Food trail"

    var id: Self { self }
}

enum QuestDuration: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case thisMonth = "This month"

    var id: Self { self }
}

/// A suggested place in the quest plan, with what it should cost.
struct PlannedStop: Identifiable, Hashable {
    var id: Restaurant.ID { restaurant.id }
    let restaurant: Restaurant
    let estimatedCost: Int
    var fitsBudget = true
}

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

/// How the quest plan changed after a meal cost more than expected.
struct BudgetUpdate: Hashable {
    let actualCost: Int
    let estimatedCost: Int
    let removedStop: PlannedStop
    let replacementStop: PlannedStop

    var overspend: Int { actualCost - estimatedCost }
}

enum TrailStopStatus {
    case visited
    case next
    case upcoming
}

struct TrailStop: Identifiable, Hashable {
    var id: Restaurant.ID { restaurant.id }
    let restaurant: Restaurant
    let isVisited: Bool
}

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

/// The student's account details. Saved in Firestore as users/{userID}.
struct UserProfile: Hashable, Codable {
    var name: String
    var email: String
    var memberSince: Date
    var monthlyBudget: Int
    var bookmarkedRestaurantIDs: Set<Restaurant.ID>

    /// First letters of the first two names, e.g. "John Doe" gives "JD".
    var initials: String {
        var letters = ""
        for word in name.split(separator: " ").prefix(2) {
            if let first = word.first {
                letters.append(first)
            }
        }
        return letters
    }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case allTime = "All time"

    var id: Self { self }
}

struct DailySpending: Identifiable, Hashable {
    var id: String { day }
    let day: String
    let amount: Int
    var isHighlighted = false
}

struct CuisineShare: Identifiable, Hashable {
    var id: Cuisine { cuisine }
    let cuisine: Cuisine
    let percentage: Int
}

/// One of the dishes the meal recogniser thinks the photo shows.
struct MealPrediction: Identifiable, Hashable {
    var id: String { label }
    let label: String
    /// The name saved on the visit; uses the restaurant's menu name if it has one (e.g. "Chicken Kottu").
    let dishName: String
    /// How sure we are, from 0 to 1.
    let confidence: Double
    let cuisine: Cuisine
    /// True if this restaurant sells the dish.
    var isOnMenu = false
}

/// What we read from a photo of a receipt.
struct ReceiptScan: Hashable {
    struct LineItem: Identifiable, Hashable {
        /// Its position on the receipt, so two "Tea" lines stay separate.
        let id: Int
        let name: String
        let price: Int
    }

    var restaurantName: String?
    var date: String?
    var items: [LineItem]
    /// The amount paid, or nil if none was found.
    var total: Int?
    /// False if there was no TOTAL line and we guessed the biggest amount, so the student should check it.
    var isTotalFromTotalLine: Bool
    /// Where the total is on the photo, so it can be highlighted.
    var totalBoundingBox: CGRect?
}
