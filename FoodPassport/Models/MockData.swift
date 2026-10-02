import Foundation
import CoreLocation

/// Sample content used while building the UI.
/// Replaced by Cloud Firestore data when the Firebase backend is integrated.
enum MockData {

    // MARK: Locations (University of Colombo area)

    static let campusCenter = CLLocationCoordinate2D(latitude: 6.9020, longitude: 79.8610)
    static let userLocation = CLLocationCoordinate2D(latitude: 6.9028, longitude: 79.8598)

    // MARK: Restaurants

    static let campusBites = Restaurant(
        id: "campus-bites",
        name: "Campus Bites",
        cuisine: .sriLankan,
        distanceKm: 0.4,
        walkingMinutes: 5,
        priceRange: 500...900,
        latitude: 6.9008,
        longitude: 79.8624,
        imageName: "restaurant_campus_bites",
        routeSummary: "Route via Campus Road",
        pricesUpdated: "2 weeks ago",
        popularDishes: [
            Dish(name: "Kottu Roti", price: 650),
            Dish(name: "Rice & Curry", price: 450),
            Dish(name: "String Hoppers", price: 400),
            Dish(name: "Lamprais", price: 650),
        ]
    )

    static let spiceRoute = Restaurant(
        id: "spice-route",
        name: "Spice Route",
        cuisine: .indian,
        distanceKm: 0.8,
        walkingMinutes: 10,
        priceRange: 600...1100,
        latitude: 6.8968,
        longitude: 79.8588,
        imageName: "restaurant_spice_route",
        routeSummary: "Route via Reid Avenue",
        pricesUpdated: "1 week ago",
        popularDishes: [
            Dish(name: "Masala Dosa", price: 400),
            Dish(name: "Butter Chicken", price: 850),
            Dish(name: "Chicken Biryani", price: 950),
            Dish(name: "Garlic Naan", price: 250),
        ]
    )

    static let dragonWok = Restaurant(
        id: "dragon-wok",
        name: "Dragon Wok",
        cuisine: .chinese,
        distanceKm: 1.1,
        walkingMinutes: 14,
        priceRange: 600...1000,
        latitude: 6.9083,
        longitude: 79.8545,
        imageName: "restaurant_dragon_wok",
        routeSummary: "Route via Thurstan Road",
        pricesUpdated: "3 days ago",
        popularDishes: [
            Dish(name: "Fried Rice", price: 650),
            Dish(name: "Devilled Chicken", price: 900),
            Dish(name: "Chop Suey", price: 400),
            Dish(name: "Noodles", price: 650),
        ]
    )

    static let hoppersHut = Restaurant(
        id: "hoppers-hut",
        name: "Hoppers Hut",
        cuisine: .sriLankan,
        distanceKm: 0.7,
        walkingMinutes: 9,
        priceRange: 400...700,
        latitude: 6.9052,
        longitude: 79.8655,
        imageName: "restaurant_hoppers_hut",
        routeSummary: "Route via Kumaratunga Munidasa Mawatha",
        pricesUpdated: "1 week ago",
        popularDishes: [
            Dish(name: "Egg Hoppers", price: 180),
            Dish(name: "Plain Hoppers (3)", price: 150),
            Dish(name: "String Hoppers", price: 400),
            Dish(name: "Pol Roti", price: 120),
        ]
    )

    static let pastaCorner = Restaurant(
        id: "pasta-corner",
        name: "Pasta Corner",
        cuisine: .italian,
        distanceKm: 1.3,
        walkingMinutes: 16,
        priceRange: 900...1500,
        latitude: 6.8955,
        longitude: 79.8678,
        imageName: "restaurant_pasta_corner",
        routeSummary: "Route via Independence Avenue",
        pricesUpdated: "2 weeks ago",
        popularDishes: [
            Dish(name: "Spaghetti Bolognese", price: 1200),
            Dish(name: "Margherita Pizza", price: 1400),
            Dish(name: "Penne Arrabbiata", price: 1050),
            Dish(name: "Garlic Bread", price: 450),
        ]
    )

    static let restaurants = [campusBites, spiceRoute, dragonWok, hoppersHut, pastaCorner]

    // MARK: Profile, visits and stamps

    static let profile = UserProfile(
        name: "John Doe",
        email: "john.doe@students.cmb.ac.lk",
        memberSince: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? .now,
        monthlyBudget: 3000
    )

    static let visits: [Visit] = [
        Visit(
            id: "visit-kottu",
            dishName: "Kottu Roti",
            cuisine: .sriLankan,
            restaurant: campusBites,
            amount: 950,
            rating: 4,
            notes: "Amazing kottu! Extra spicy, just how I like it. The portion was generous.",
            date: date(daysAgo: 0, hour: 13),
            isLocationVerified: true,
            isAutoDetected: true,
            isFromReceipt: true,
            imageName: "dish_kottu"
        ),
        Visit(
            id: "visit-masala-dosa",
            dishName: "Masala Dosa",
            cuisine: .indian,
            restaurant: spiceRoute,
            amount: 400,
            rating: 3,
            notes: "Crispy dosa with good sambar. A bit of a wait at lunch time.",
            date: date(daysAgo: 1, hour: 12),
            isLocationVerified: true,
            isAutoDetected: false,
            isFromReceipt: false,
            imageName: "dish_masala_dosa"
        ),
        Visit(
            id: "visit-butter-chicken",
            dishName: "Butter Chicken",
            cuisine: .indian,
            restaurant: spiceRoute,
            amount: 850,
            rating: 4,
            notes: "Rich and creamy. Big enough to share with a friend.",
            date: date(daysAgo: 8, hour: 19),
            isLocationVerified: true,
            isAutoDetected: true,
            isFromReceipt: true,
            imageName: "dish_butter_chicken"
        ),
    ]

    static let stamps: [Stamp] = [
        Stamp(
            cuisine: .sriLankan,
            restaurantName: "Campus Bites",
            earnedDate: date(daysAgo: 0, hour: 13),
            visitID: "visit-kottu",
            imageName: "dish_kottu"
        ),
        Stamp(
            cuisine: .indian,
            restaurantName: "Spice Route",
            earnedDate: date(daysAgo: 8, hour: 19),
            visitID: "visit-butter-chicken",
            imageName: "dish_butter_chicken"
        ),
    ]

    // MARK: Quests and challenges

    static let activeQuest = Quest(
        title: "Try 3 new cuisines this month",
        type: .newCuisines,
        targetCuisines: 3,
        cuisinesTried: 2,
        budget: 3000,
        spent: 2200,
        duration: .thisMonth,
        maxDistanceKm: 2,
        plan: [
            PlannedStop(restaurant: dragonWok, estimatedCost: 750),
            PlannedStop(restaurant: pastaCorner, estimatedCost: 1200, fitsBudget: false),
        ],
        planExplanation: "Dragon Wok fits your remaining LKR 800 and is a cuisine you haven't tried yet."
    )

    static let latestBudgetUpdate = BudgetUpdate(
        actualCost: 950,
        estimatedCost: 650,
        removedStop: PlannedStop(restaurant: pastaCorner, estimatedCost: 1200, fitsBudget: false),
        replacementStop: PlannedStop(restaurant: dragonWok, estimatedCost: 750)
    )

    static let campusFoodTrail = FoodTrail(
        id: "campus-food-trail",
        name: "Campus Food Trail",
        summary: "Visit 3 iconic campus eateries",
        stops: [
            TrailStop(restaurant: campusBites, isVisited: true),
            TrailStop(restaurant: hoppersHut, isVisited: false),
            TrailStop(restaurant: pastaCorner, isVisited: false),
        ]
    )

    static let spiceTrail = FoodTrail(
        id: "spice-trail",
        name: "Spice Trail",
        summary: "Three kitchens, three kinds of heat",
        stops: [
            TrailStop(restaurant: spiceRoute, isVisited: false),
            TrailStop(restaurant: dragonWok, isVisited: false),
            TrailStop(restaurant: hoppersHut, isVisited: false),
        ]
    )

    static let foodTrails = [campusFoodTrail, spiceTrail]

    static let weeklyChallenge = WeeklyChallenge(
        title: "Try a new cuisine this week",
        details: "Visit 1 restaurant offering a brand new cuisine to earn your stamp.",
        daysLeft: 5,
        completed: 0,
        target: 1,
        suggestions: [
            PlannedStop(restaurant: dragonWok, estimatedCost: 750),
            PlannedStop(restaurant: pastaCorner, estimatedCost: 1200),
        ]
    )

    // MARK: Dashboard

    static let weeklySpending: [DailySpending] = [
        DailySpending(day: "Mon", amount: 250),
        DailySpending(day: "Tue", amount: 400),
        DailySpending(day: "Wed", amount: 180),
        DailySpending(day: "Thu", amount: 650),
        DailySpending(day: "Fri", amount: 950, isHighlighted: true),
        DailySpending(day: "Sat", amount: 520),
        DailySpending(day: "Sun", amount: 800),
    ]

    static let cuisineShares: [CuisineShare] = [
        CuisineShare(cuisine: .sriLankan, percentage: 67),
        CuisineShare(cuisine: .indian, percentage: 33),
    ]

    // MARK: Scanning (stand-ins for Core ML / Vision results)

    static let mealPredictions: [MealPrediction] = [
        MealPrediction(label: "Kottu", dishName: "Kottu Roti", confidence: 0.87, cuisine: .sriLankan),
        MealPrediction(label: "Fried rice", dishName: "Fried Rice", confidence: 0.08, cuisine: .chinese),
        MealPrediction(label: "Noodles", dishName: "Noodles", confidence: 0.05, cuisine: .chinese),
    ]

    static let sampleReceipt = ReceiptScan(
        restaurantName: "CAMPUS BITES",
        timestamp: Date.now.formatted(date: .numeric, time: .shortened),
        items: [
            ReceiptScan.LineItem(name: "Kottu Roti", price: 750),
            ReceiptScan.LineItem(name: "Iced Milo", price: 200),
        ],
        total: 950
    )

    // MARK: Helpers

    private static func date(daysAgo: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day) ?? day
    }
}
