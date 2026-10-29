import Foundation

/// The money side of the dashboard for one period: the total, the chart bars,
/// and what was spent at each restaurant and on each cuisine.
/// It only uses plain values, so tests can check the numbers directly.
struct SpendingSummary {
    struct RestaurantSpend: Identifiable, Hashable {
        var id: Restaurant.ID { restaurantID }
        let restaurantID: Restaurant.ID
        let name: String
        let amount: Int
        let visits: Int
    }

    let period: DashboardPeriod
    /// The visits in the period, newest first.
    let visits: [Visit]
    let total: Int
    /// Spent so far in the current calendar month, compared with the monthly budget.
    let spentThisMonth: Int
    let monthlyBudget: Int
    let bars: [SpendingBar]
    /// Biggest first.
    let byRestaurant: [RestaurantSpend]
    /// Biggest first, as a share of the money spent (not the number of meals).
    let byCuisine: [CuisineShare]

    init(visits allVisits: [Visit], period: DashboardPeriod, monthlyBudget: Int,
         now: Date = .now, calendar: Calendar = .current) {
        let interval = Self.interval(for: period, now: now, calendar: calendar)
        let visits = allVisits
            .filter { visit in interval.map { $0.start <= visit.date && visit.date < $0.end } ?? true }
            .sorted { $0.date > $1.date }
        let month = calendar.dateInterval(of: .month, for: now)

        self.period = period
        self.visits = visits
        self.monthlyBudget = monthlyBudget
        total = visits.map(\.amount).reduce(0, +)
        spentThisMonth = allVisits.filter { visit in month.map { $0.start <= visit.date && visit.date < $0.end } == true }
            .map(\.amount).reduce(0, +)
        bars = Self.bars(for: period, visits: visits, interval: interval, now: now, calendar: calendar)

        let total = total
        byRestaurant = Dictionary(grouping: visits, by: \.restaurant.id).values
            .map { meals in
                RestaurantSpend(restaurantID: meals[0].restaurant.id, name: meals[0].restaurant.name,
                                amount: meals.map(\.amount).reduce(0, +), visits: meals.count)
            }
            .sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }

        byCuisine = Dictionary(grouping: visits, by: \.cuisine)
            .map { cuisine, meals in
                let amount = meals.map(\.amount).reduce(0, +)
                let share = total > 0 ? Double(amount) / Double(total) : Double(meals.count) / Double(max(1, visits.count))
                return CuisineShare(cuisine: cuisine, amount: amount, percentage: Int((share * 100).rounded()))
            }
            .sorted { ($0.amount, $1.cuisine.rawValue) > ($1.amount, $0.cuisine.rawValue) }
    }

    var averagePerMeal: Int {
        visits.isEmpty ? 0 : total / visits.count
    }

    var budgetFraction: Double {
        Double(spentThisMonth) / Double(max(monthlyBudget, 1))
    }

    var budgetLeft: Int {
        monthlyBudget - spentThisMonth
    }

    /// e.g. "This week" uses days, a month uses weeks, and "All time" uses months.
    var chartTitle: String {
        switch period {
        case .thisWeek: "Spending this week"
        case .thisMonth: "Spending by week this month"
        case .lastMonth: "Spending by week last month"
        case .allTime: "Spending by month"
        }
    }

    // Working out the bars

    static func interval(for period: DashboardPeriod, now: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return calendar.dateInterval(of: .month, for: previous)
        case .allTime:
            return nil
        }
    }

    private static func bars(for period: DashboardPeriod, visits: [Visit], interval: DateInterval?,
                             now: Date, calendar: Calendar) -> [SpendingBar] {
        func spent(in range: DateInterval) -> Int {
            visits.filter { range.contains($0.date) && $0.date < range.end }.map(\.amount).reduce(0, +)
        }
        // Labels use the same calendar and time zone as the bars, e.g. in tests.
        func text(_ date: Date, _ style: Date.FormatStyle) -> String {
            var style = style
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }

        switch period {
        case .thisWeek:
            guard let interval else { return [] }
            return (0..<7).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start),
                      let range = calendar.dateInterval(of: .day, for: day) else { return nil }
                return SpendingBar(start: day, label: text(day, .dateTime.weekday(.wide)),
                                   shortLabel: text(day, .dateTime.weekday(.narrow)),
                                   amount: spent(in: range), isHighlighted: calendar.isDate(day, inSameDayAs: now))
            }

        case .thisMonth, .lastMonth:
            // Weeks of the month: 1–7, 8–14, 15–21, 22–28 and what's left.
            guard let interval else { return [] }
            var bars: [SpendingBar] = []
            var start = interval.start
            while start < interval.end {
                let next = min(calendar.date(byAdding: .day, value: 7, to: start) ?? interval.end, interval.end)
                let lastDay = calendar.date(byAdding: .day, value: -1, to: next) ?? start
                let first = calendar.component(.day, from: start)
                let last = calendar.component(.day, from: lastDay)
                let month = text(start, .dateTime.month(.abbreviated))
                let range = DateInterval(start: start, end: next)
                bars.append(SpendingBar(start: start, label: "\(first) to \(last) \(month)", shortLabel: "\(first)–\(last)",
                                        amount: spent(in: range), isHighlighted: range.contains(now) && now < next))
                start = next
            }
            // Last month has no "today", so the biggest week stands out instead.
            if period == .lastMonth, let biggest = bars.indices.max(by: { bars[$0].amount < bars[$1].amount }), bars[biggest].amount > 0 {
                bars[biggest].isHighlighted = true
            }
            return bars

        case .allTime:
            // Up to the last 12 months, from the first month with a visit.
            guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
            let firstVisit = visits.map(\.date).min() ?? now
            let firstMonth = calendar.dateInterval(of: .month, for: firstVisit)?.start ?? thisMonth
            let monthsBack = min(11, max(0, calendar.dateComponents([.month], from: firstMonth, to: thisMonth).month ?? 0))
            return (0...monthsBack).reversed().compactMap { back in
                guard let month = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                      let range = calendar.dateInterval(of: .month, for: month) else { return nil }
                return SpendingBar(start: month, label: text(month, .dateTime.month(.wide).year()),
                                   shortLabel: text(month, .dateTime.month(.abbreviated)),
                                   amount: spent(in: range), isHighlighted: back == 0)
            }
        }
    }
}
