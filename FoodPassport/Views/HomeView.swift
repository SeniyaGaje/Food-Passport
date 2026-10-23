import SwiftUI
import Charts

/// Home tab dashboard: summary tiles, active quest, spending chart, cuisines and recent activity.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var period: DashboardPeriod = .thisMonth

    private let quest = MockData.activeQuest

    /// "Good evening, John" — changes with the time of day.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let partOfDay = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let firstName = appState.profile.name.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? partOfDay : "\(partOfDay), \(firstName)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ScreenHeader("Your overview", subtitle: greeting) {
                        ProfileAvatarButton()
                    }
                    periodMenu
                }

                HStack(spacing: Theme.Spacing.s) {
                    StatTile(value: "\(appState.visits.count)", label: "Visits", systemImage: "fork.knife")
                    StatTile(value: "\(appState.cuisinesTriedCount)", label: "Cuisines", systemImage: "globe.asia.australia.fill")
                    StatTile(value: "\(appState.stamps.count)", label: "Stamps", systemImage: "seal.fill")
                }

                NavigationLink(value: AppRoute.questDetail) {
                    QuestSummaryCard(quest: quest)
                }
                .buttonStyle(.pressableCard)

                WeeklySpendingCard(entries: MockData.weeklySpending)

                CuisineBreakdownCard(shares: MockData.cuisineShares)

                RecentActivitySection(visits: Array(appState.visits.prefix(3))) {
                    router.selectedTab = .history
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
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
                Image(systemName: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                Text(period.rawValue)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .surfaceBackground(Capsule(), shadowStrength: 0.6)
        }
        .accessibilityLabel("Period: \(period.rawValue)")
    }
}

/// Orange card on the dashboard showing quest progress, budget used and the next suggested place.
struct QuestSummaryCard: View {
    let quest: Quest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active quest")
                        .textCase(.uppercase)
                        .font(.caption.weight(.bold))
                        .kerning(0.6)
                        .opacity(0.85)
                    Text(quest.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .padding(10)
                    .background(.white.opacity(0.18), in: Circle())
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
                .fill(.white.opacity(0.3))
                .frame(height: 1)

            if let next = quest.nextPick {
                Label("Next pick: \(next.restaurant.name) – est. \(next.estimatedCost.lkr)", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            QuestCardBackground()
        }
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
                    .monospacedDigit()
            }
            .font(.subheadline)

            ProgressBar(value: value, tint: fill, track: .white.opacity(0.3))
        }
    }
}

struct WeeklySpendingCard: View {
    let entries: [DailySpending]

    private var highlightedDay: String? {
        entries.first(where: \.isHighlighted)?.day
    }

    private var total: Int {
        entries.map(\.amount).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionCaption("Weekly spending")
                Spacer()
                Text(total.lkr)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }

            Chart(entries) { entry in
                BarMark(
                    x: .value("Day", entry.day),
                    y: .value("Spent", entry.amount),
                    width: .ratio(0.55)
                )
                .foregroundStyle(entry.isHighlighted ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Theme.track))
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
                                .foregroundStyle(day == highlightedDay ? Theme.orange : Color.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .cardStyle(padding: 20)
    }
}

struct CuisineBreakdownCard: View {
    let shares: [CuisineShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCaption("Cuisines explored")

            // Side by side when there's room; stacked with large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    donut
                    legend
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 16) {
                    donut
                        .frame(maxWidth: .infinity)
                    legend
                }
            }
        }
        .cardStyle(padding: 20)
    }

    private var donut: some View {
        Chart(shares) { share in
            SectorMark(
                angle: .value("Share", share.percentage),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .foregroundStyle(color(for: share))
            .cornerRadius(4)
            .accessibilityLabel(share.cuisine.rawValue)
            .accessibilityValue("\(share.percentage) percent")
        }
        .frame(width: 120, height: 120)
        .overlay {
            VStack(spacing: 0) {
                Text("\(shares.count)")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text(shares.count == 1 ? "cuisine" : "cuisines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shares) { share in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: share))
                        .frame(width: 10, height: 10)
                    Text(share.cuisine.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "\(share.percentage)%")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func color(for share: CuisineShare) -> Color {
        let index = shares.firstIndex(of: share) ?? 0
        return Theme.chartPalette[index % Theme.chartPalette.count]
    }
}

struct RecentActivitySection: View {
    let visits: [Visit]
    let onViewHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recent activity", actionTitle: visits.isEmpty ? nil : "View history", action: onViewHistory)

            if visits.isEmpty {
                EmptyStateView(
                    systemImage: "fork.knife",
                    title: "No visits yet",
                    message: "Find a place in Explore and log your first meal to start your passport."
                )
            } else {
                ForEach(visits) { visit in
                    NavigationLink(value: AppRoute.visitDetail(visit)) {
                        VisitRow(visit: visit)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
        }
    }
}

// Previews

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
