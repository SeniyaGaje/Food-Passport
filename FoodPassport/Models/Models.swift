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
    /// Local photo references; older visits don't have photos.
    var photoIDs: [String]? = nil

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
    var cuisine: Cuisine? = nil
    var category: String? = nil
    var isDrink: Bool? = nil
}

/// An item while it's being typed on Log your visit. The price is kept as text until saving.
struct VisitItemDraft: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var priceText = ""
    var cuisine: Cuisine? = nil
    var category: String? = nil
    var isDrink: Bool? = nil

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

    /// Uses a scanned receipt. The student's own dishes are kept and only get the receipt's prices,
    /// matched by name (e.g. "Kottu Roti" gets the price of "CHICKEN KOTTU"). If the student hasn't
    /// added any dishes yet, the receipt's items are used instead.
    static func applyingReceipt(_ receiptItems: [ReceiptScan.LineItem], to list: [VisitItemDraft]) -> [VisitItemDraft] {
        var result = list.filter { !$0.name.trimmed.isEmpty }

        if result.isEmpty {
            let fromReceipt = receiptItems.map { VisitItemDraft(name: $0.name, priceText: "\($0.price)") }
            return fromReceipt.isEmpty ? [VisitItemDraft()] : fromReceipt
        }

        // Every dish/receipt-line pair that shares a word, closest names first,
        // so "Milk Tea" gets the MILK TEA line even if "Plain Tea" comes first in the list.
        var pairs: [(dish: Int, line: Int, score: Int)] = []
        for dish in result.indices {
            for line in receiptItems.indices {
                let score = matchScore(result[dish].name, receiptItems[line].name)
                if score > 0 {
                    pairs.append((dish, line, score))
                }
            }
        }
        pairs.sort { $0.score > $1.score }

        var pricedDishes = Set<Int>()
        var usedLines = Set<Int>()
        for pair in pairs where !pricedDishes.contains(pair.dish) && !usedLines.contains(pair.line) {
            result[pair.dish].priceText = "\(receiptItems[pair.line].price)"
            pricedDishes.insert(pair.dish)
            usedLines.insert(pair.line)
        }

        // One dish and one receipt line left over: they're almost certainly the same thing
        // (e.g. the scanner said "Hoppers" but the receipt says "APPA").
        let leftoverDishes = result.indices.filter { !pricedDishes.contains($0) }
        let leftoverLines = receiptItems.indices.filter { !usedLines.contains($0) }
        if leftoverDishes.count == 1 && leftoverLines.count == 1 {
            result[leftoverDishes[0]].priceText = "\(receiptItems[leftoverLines[0]].price)"
        }
        return result
    }

    /// How many words two item names share, e.g. "Iced Milo" and "MILO ICED 400ML" share 2.
    /// Words match on their first four letters, so "Hopper" and "Hoppers" count as the same word.
    static func matchScore(_ first: String, _ second: String) -> Int {
        Set(keyWords(first)).intersection(keyWords(second)).count
    }

    /// Words that mean nothing on their own for matching, like sizes.
    private static let fillerWords: Set<String> = ["with", "and", "the", "large", "small", "regular", "plate", "portion", "extra", "half", "full"]

    private static func keyWords(_ name: String) -> [String] {
        name.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !fillerWords.contains($0) }
            .map { String($0.prefix(4)) }
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
    /// nil for drinks that don't belong to a cuisine, like coffee.
    let cuisine: Cuisine?
    /// True if this restaurant sells the dish.
    var isOnMenu = false
    var isDrink = false
    var category: String? = nil

    /// The cuisine to suggest for a visit: the first food's, or a drink's if only drinks were picked.
    static func suggestedCuisine(in items: [MealPrediction]) -> Cuisine? {
        let food = items.first { !$0.isDrink && $0.cuisine != nil }
        let drink = items.first { $0.cuisine != nil }
        return (food ?? drink)?.cuisine
    }
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
