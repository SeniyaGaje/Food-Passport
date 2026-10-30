import SwiftUI
import Charts

/// The Home tab: totals, the active quest, spending, cuisines and recent visits.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var period: DashboardPeriod = .thisMonth

    // The active quest, worked out from the real visits.
    private var quest: Quest { appState.activeQuest }

    /// Totals, chart bars and breakdowns for the chosen period.
    private var summary: SpendingSummary {
        SpendingSummary(visits: appState.visits, period: period, monthlyBudget: appState.profile.monthlyBudget)
    }

    /// "Good evening, John", depending on the time of day.
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
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ScreenHeader("Your overview", subtitle: greeting) {
                        ProfileAvatarButton()
                    }
                    DashboardPeriodMenu(period: $period)
                }

                // Visits, cuisines and stamps for the chosen period.
                AdaptiveStack(spacing: Theme.Spacing.s) {
                    StatTile(value: "\(summary.visits.count)", label: "Visits", systemImage: "fork.knife")
                    StatTile(value: "\(Set(summary.visits.map(\.cuisine)).count)", label: "Cuisines", systemImage: "globe.asia.australia.fill")
                    StatTile(value: "\(appState.stamps.count)", label: "Stamps", systemImage: "seal.fill")
                }

                // The quest card, or a prompt to start one.
                if appState.hasActiveQuest {
                NavigationLink(value: AppRoute.questDetail) {
                    QuestSummaryCard(quest: quest)
                }
                .buttonStyle(.pressableCard)
                .accessibilityIdentifier("home.quest")
                } else {
                    NoQuestCard()
                }

                // The spending chart; tapping it opens the full Spending Overview.
                NavigationLink(value: AppRoute.spendingOverview(period)) {
                    SpendingChartCard(summary: summary, showsChevron: true)
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Opens your spending overview")
                .accessibilityIdentifier("home.spending")

                // Where the money went, by cuisine.
                if summary.byCuisine.isEmpty {
                    EmptyStateView(systemImage: "chart.pie", title: "No meals in this period",
                        message: "Choose another period or log a meal to see your cuisine breakdown.")
                } else {
                    CuisineBreakdownCard(shares: summary.byCuisine)
                }

                // The three latest visits.
                RecentActivitySection(visits: Array(appState.visits.prefix(3))) {
                    router.selectedTab = .history
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        // Pull down to reload from Firebase.
        .refreshable { await appState.refreshData() }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Home")
        // The navigation bar only shows on iPad, where it holds the sidebar button.
        .toolbar(sizeClass == .regular ? .visible : .hidden, for: .navigationBar)
    }
}

/// The "This month ▾" button that picks the dashboard's period.
struct DashboardPeriodMenu: View {
    @Binding var period: DashboardPeriod

    var body: some View {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Period: \(period.rawValue)")
        .accessibilityHint("Changes the time period the totals cover")
    }
}

/// The orange quest card: progress, money spent and the next suggested place.
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
                title: "\(quest.cuisinesTried) of \(quest.targetCuisines) \(quest.progressUnit)",
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

/// The spending bar chart. Its bars follow the period: days this week, weeks of a month, or months.
struct SpendingChartCard: View {
    let summary: SpendingSummary
    var showsChevron = false

    private var bars: [SpendingBar] { summary.bars }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionCaption(summary.chartTitle)
                Spacer()
                Text(summary.total.lkr)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Chart(bars) { bar in
                BarMark(
                    x: .value("Period", bar.shortLabel),
                    y: .value("Spent", bar.amount),
                    width: .ratio(0.55)
                )
                // AnyShapeStyle lets one line choose between a gradient and a plain colour.
                .foregroundStyle(bar.isHighlighted ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Theme.track))
                .cornerRadius(8)
                .accessibilityLabel(bar.label)
                .accessibilityValue(bar.amount.lkr)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            let isHighlighted = bars.first { $0.shortLabel == label }?.isHighlighted == true
                            Text(label)
                                .font(bars.count > 7 ? .caption2 : .subheadline)
                                .fontWeight(isHighlighted ? .bold : .regular)
                                .foregroundStyle(isHighlighted ? Theme.orangeText : Color.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityLabel(summary.chartTitle)
            // VoiceOver's Audio Graph plays the bars as tones and reads a summary.
            .accessibilityChartDescriptor(SpendingChartDescriptor(title: summary.chartTitle, bars: bars))
        }
        .cardStyle(padding: 20)
    }
}

/// Describes the spending chart for VoiceOver's Audio Graphs.
struct SpendingChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let bars: [SpendingBar]

    func makeChartDescriptor() -> AXChartDescriptor {
        let highest = bars.max { $0.amount < $1.amount }
        let total = bars.map(\.amount).reduce(0, +)
        let summary = highest.map { total > 0 ? "\(total.lkr) in total. Most was \($0.amount.lkr) in \($0.label)." : "Nothing spent yet." } ?? ""
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Period", categoryOrder: bars.map(\.label))
        let yAxis = AXNumericDataAxisDescriptor(title: "Spent", range: 0...Double(max(highest?.amount ?? 0, 1)),
                                                gridlinePositions: []) { Int($0).lkr }
        let series = AXDataSeriesDescriptor(name: "Spending", isContinuous: false,
                                            dataPoints: bars.map { AXDataPoint(x: $0.label, y: Double($0.amount)) })
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}

/// What share of the money went on each cuisine, as a donut chart with a legend.
struct CuisineBreakdownCard: View {
    let shares: [CuisineShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCaption("Spending by cuisine")

            // Side by side if there's room, otherwise one above the other.
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
                angle: .value("Spent", max(share.amount, 1)),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .foregroundStyle(color(for: share))
            .cornerRadius(4)
            .accessibilityLabel(share.cuisine.rawValue)
            .accessibilityValue("\(share.amount.lkr), \(share.percentage) percent")
        }
        .frame(width: 120, height: 120)
        .accessibilityLabel("Spending by cuisine chart")
        .accessibilityChartDescriptor(CuisineChartDescriptor(shares: shares))
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
                    Text(verbatim: "\(share.percentage)% · \(share.amount.lkr)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// Each cuisine gets the next colour in the chart palette.
    private func color(for share: CuisineShare) -> Color {
        let index = shares.firstIndex(of: share) ?? 0
        return Theme.chartPalette[index % Theme.chartPalette.count]
    }
}

/// Describes the cuisine chart for VoiceOver's Audio Graphs.
struct CuisineChartDescriptor: AXChartDescriptorRepresentable {
    let shares: [CuisineShare]

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = shares.first.map { "Most went on \($0.cuisine.rawValue): \($0.amount.lkr), \($0.percentage) percent." } ?? ""
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Cuisine", categoryOrder: shares.map(\.cuisine.rawValue))
        let yAxis = AXNumericDataAxisDescriptor(title: "Spent", range: 0...Double(max(shares.map(\.amount).max() ?? 0, 1)),
                                                gridlinePositions: []) { Int($0).lkr }
        let series = AXDataSeriesDescriptor(name: "Spending by cuisine", isContinuous: false,
                                            dataPoints: shares.map { AXDataPoint(x: $0.cuisine.rawValue, y: Double($0.amount)) })
        return AXChartDescriptor(title: "Spending by cuisine", summary: top, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
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
    SpendingChartCard(summary: MockData.spendingSummary)
        .padding()
        .appBackground()
}

#Preview {
    CuisineBreakdownCard(shares: MockData.spendingSummary.byCuisine)
        .padding()
        .appBackground()
}

#Preview {
    RecentActivitySection(visits: MockData.visits) {}
        .padding()
        .previewInNavigationStack()
}
