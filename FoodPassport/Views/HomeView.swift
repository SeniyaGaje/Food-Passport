import SwiftUI
import Charts

// MARK: - HomeView

/// Home tab dashboard: summary tiles, active quest, spending chart, cuisines and recent activity.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var period: DashboardPeriod = .thisMonth

    private let quest = MockData.activeQuest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader("Your overview") {
                        ProfileAvatarButton()
                    }
                    periodMenu
                }

                HStack(spacing: 12) {
                    StatTile(value: "\(appState.visits.count)", label: "Visits")
                    StatTile(value: "\(appState.cuisinesTriedCount)", label: "Cuisines")
                    StatTile(value: "\(appState.stamps.count)", label: "Stamps")
                }

                NavigationLink(value: AppRoute.questDetail) {
                    QuestSummaryCard(quest: quest)
                }
                .buttonStyle(.plain)

                WeeklySpendingCard(entries: MockData.weeklySpending)

                CuisineBreakdownCard(shares: MockData.cuisineShares)

                RecentActivitySection(visits: Array(appState.visits.prefix(3))) {
                    router.selectedTab = .history
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                ForEach(DashboardPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(period.rawValue)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .accessibilityLabel("Period: \(period.rawValue)")
    }
}

// MARK: - QuestSummaryCard

/// Orange card on the dashboard showing quest progress, budget used and the next suggested place.
struct QuestSummaryCard: View {
    let quest: Quest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(quest.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
            }

            progressRow(
                title: "\(quest.cuisinesTried) of \(quest.targetCuisines) cuisines tried",
                value: quest.cuisineProgress,
                fill: .white
            )

            progressRow(
                title: "\(quest.spent.lkr) of \(quest.budget.formatted()) spent",
                value: quest.budgetProgress,
                fill: .white.opacity(0.6)
            )

            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(height: 1)

            if let next = quest.nextPick {
                Label("Next pick: \(next.restaurant.name) – est. \(next.estimatedCost.lkr)", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.questGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.orange.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens quest details")
    }

    private func progressRow(title: String, value: Double, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int(value * 100))%")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            ProgressBar(value: value, tint: fill, track: .white.opacity(0.3))
        }
    }
}

// MARK: - WeeklySpendingCard

struct WeeklySpendingCard: View {
    let entries: [DailySpending]

    private var highlightedDay: String? {
        entries.first(where: \.isHighlighted)?.day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCaption("Weekly spending")

            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.day),
                    y: .value("Spent", entry.amount),
                    width: .fixed(24)
                )
                .foregroundStyle(entry.isHighlighted ? Theme.ink : Color(hex: 0xEEEEEF))
                .cornerRadius(8)
                .accessibilityLabel(entry.day)
                .accessibilityValue(entry.amount.lkr)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let day = value.as(String.self) {
                            Text(String(day.prefix(1)))
                                .font(.subheadline)
                                .fontWeight(day == highlightedDay ? .bold : .regular)
                                .foregroundStyle(day == highlightedDay ? Theme.ink : Color.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .cardStyle(padding: 20)
    }
}

// MARK: - CuisineBreakdownCard

struct CuisineBreakdownCard: View {
    let shares: [CuisineShare]

    private let palette: [Color] = [Theme.ink, Color(hex: 0x6B6B70), Color(hex: 0xB0B0B5), Theme.orange]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCaption("Cuisines explored")

            HStack(spacing: 28) {
                Chart(shares) { share in
                    SectorMark(
                        angle: .value("Share", share.percentage),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(color(for: share))
                    .cornerRadius(3)
                    .accessibilityLabel(share.cuisine.rawValue)
                    .accessibilityValue("\(share.percentage) percent")
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(shares) { share in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color(for: share))
                                .frame(width: 16, height: 16)
                            Text(verbatim: "\(share.cuisine.rawValue) (\(share.percentage)%)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .accessibilityHidden(true)

                Spacer(minLength: 0)
            }
        }
        .cardStyle(padding: 20)
    }

    private func color(for share: CuisineShare) -> Color {
        let index = shares.firstIndex(of: share) ?? 0
        return palette[index % palette.count]
    }
}

// MARK: - RecentActivitySection

struct RecentActivitySection: View {
    let visits: [Visit]
    let onViewHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent activity")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("View history", action: onViewHistory)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            if visits.isEmpty {
                Text("No visits yet — find a place in Explore and log your first meal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                ForEach(visits) { visit in
                    NavigationLink(value: AppRoute.visitDetail(visit)) {
                        VisitRow(visit: visit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview {
    HomeView()
        .previewInNavigationStack()
}

#Preview {
    QuestSummaryCard(quest: MockData.activeQuest)
        .padding()
}

#Preview {
    WeeklySpendingCard(entries: MockData.weeklySpending)
        .padding()
        .appBackground()
}

#Preview {
    CuisineBreakdownCard(shares: MockData.cuisineShares)
        .padding()
        .appBackground()
}

#Preview {
    RecentActivitySection(visits: MockData.visits) {}
        .padding()
        .previewInNavigationStack()
}
