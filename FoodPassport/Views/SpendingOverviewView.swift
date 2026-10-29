import SwiftUI
import Charts

/// Spending overview: this month against the budget, totals for the period,
/// the spending chart, and where the money went (by restaurant and by cuisine).
struct SpendingOverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var period: DashboardPeriod

    init(period: DashboardPeriod = .thisMonth) {
        _period = State(initialValue: period)
    }

    private var summary: SpendingSummary {
        SpendingSummary(visits: appState.visits, period: period, monthlyBudget: appState.profile.monthlyBudget)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Spending")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    DashboardPeriodMenu(period: $period)
                }

                budgetCard(summary)

                AdaptiveStack(spacing: Theme.Spacing.s) {
                    StatTile(value: summary.total.lkr, label: "Spent", systemImage: "banknote")
                    StatTile(value: "\(summary.visits.count)", label: summary.visits.count == 1 ? "Meal" : "Meals", systemImage: "fork.knife")
                    StatTile(value: summary.averagePerMeal.lkr, label: "Per meal", systemImage: "divide")
                }

                SpendingChartCard(summary: summary)

                if summary.visits.isEmpty {
                    EmptyStateView(systemImage: "chart.bar", title: "No meals in this period",
                        message: "Choose another period or log a meal to see where your money goes.")
                } else {
                    restaurantCard(summary)
                    CuisineBreakdownCard(shares: summary.byCuisine)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Spending")
    }

    /// This month's spending against the monthly budget, whatever period is picked.
    private func budgetCard(_ summary: SpendingSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionCaption("Monthly budget")
                Spacer()
                Button("Edit") { router.sheet = .monthlyBudget }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.orangeText)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Edit monthly budget")
            }

            ProgressBar(value: summary.budgetFraction, tint: summary.budgetLeft < 0 ? Theme.destructive : Theme.orange,
                        height: 14, label: "Budget used this month")

            AdaptiveStack(spacing: 4) {
                Text("\(summary.spentThisMonth.lkr) of \(summary.monthlyBudget.lkr)")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(summary.budgetLeft >= 0 ? "\(summary.budgetLeft.lkr) left" : "\((-summary.budgetLeft).lkr) over")
                    .foregroundStyle(summary.budgetLeft >= 0 ? Color.secondary : Theme.destructive)
            }
            .font(.subheadline)
            .monospacedDigit()
        }
        .cardStyle(padding: 20)
        .accessibilityElement(children: .contain)
    }

    /// Each restaurant's share as a bar, biggest first.
    private func restaurantCard(_ summary: SpendingSummary) -> some View {
        let biggest = Double(max(summary.byRestaurant.first?.amount ?? 0, 1))
        return VStack(alignment: .leading, spacing: 14) {
            SectionCaption("By restaurant")

            ForEach(summary.byRestaurant) { place in
                VStack(alignment: .leading, spacing: 6) {
                    AdaptiveStack(spacing: 4) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                        Text("\(place.amount.lkr) · \(place.visits) \(place.visits == 1 ? "visit" : "visits")")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressBar(value: Double(place.amount) / biggest, tint: Theme.orange, height: 8, label: place.name)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle(padding: 20)
    }
}

// Previews

#Preview {
    SpendingOverviewView()
        .previewInNavigationStack()
}
