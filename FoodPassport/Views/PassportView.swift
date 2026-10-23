import SwiftUI

/// Passport tab: earned stamps, the active quest and challenges.
struct PassportView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var selectedStamp: Stamp?

    private let quest = MockData.activeQuest
    private let trail = MockData.campusFoodTrail
    private let challenge = MockData.weeklyChallenge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader("My food passport", subtitle: "Every new cuisine is a new stamp") {
                    newQuestButton
                }

                StampGridCard(stamps: appState.stamps) { stamp in
                    selectedStamp = stamp
                }

                NavigationLink(value: AppRoute.questDetail) {
                    ActiveQuestCard(quest: quest)
                }
                .buttonStyle(.pressableCard)

                SectionHeader("Challenges")

                NavigationLink(value: AppRoute.foodTrail) {
                    ChallengeRow(
                        systemImage: "mappin.and.ellipse",
                        tint: .blue,
                        title: trail.name,
                        subtitle: "\(trail.visitedCount) of \(trail.stops.count) stops visited",
                        progress: trail.progress
                    )
                }
                .buttonStyle(.pressableCard)

                NavigationLink(value: AppRoute.weeklyChallenge) {
                    ChallengeRow(
                        systemImage: "clock",
                        tint: Theme.gold,
                        title: "Weekly challenge",
                        subtitle: challenge.title,
                        footnote: "\(challenge.daysLeft) days left"
                    )
                }
                .buttonStyle(.pressableCard)
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("Passport")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedStamp) { stamp in
            StampDetailSheet(stamp: stamp, visit: visit(for: stamp)) { visit in
                selectedStamp = nil
                router.push(.visitDetail(visit))
            }
        }
    }

    private var newQuestButton: some View {
        Button {
            router.sheet = .newQuest
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 44)
                .background(Theme.primaryGradient, in: Capsule())
                .shadow(color: Theme.orange.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("New quest")
    }

    private func visit(for stamp: Stamp) -> Visit? {
        appState.visits.first { $0.id == stamp.visitID }
    }
}

/// "Stamps earned" grid: earned stamps followed by empty "Next cuisine" slots.
struct StampGridCard: View {
    let stamps: [Stamp]
    var totalSlots = 6
    let onSelect: (Stamp) -> Void

    /// As many columns as fit (three on every iPhone in portrait), each at least 92 points wide.
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                SectionCaption("Stamps earned")
                Spacer()
                Text("\(stamps.count) of \(max(totalSlots, stamps.count))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(stamps) { stamp in
                    Button {
                        onSelect(stamp)
                    } label: {
                        VStack(spacing: 8) {
                            StampBadgeView(cuisine: stamp.cuisine, showsCheckmark: true)
                            Text(stamp.cuisine.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityLabel("\(stamp.cuisine.rawValue) stamp")
                    .accessibilityHint("Shows stamp details")
                }

                ForEach(0..<max(totalSlots - stamps.count, 0), id: \.self) { _ in
                    VStack(spacing: 8) {
                        StampBadgeView(cuisine: nil)
                        Text("Next cuisine")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle(padding: 20)
    }
}

struct StampDetailSheet: View {
    let stamp: Stamp
    let visit: Visit?
    let onViewVisit: (Visit) -> Void

    private var earnedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(stamp.earnedDate) { return "today" }
        if calendar.isDateInYesterday(stamp.earnedDate) { return "yesterday" }
        return "on \(stamp.earnedDate.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        VStack(spacing: 16) {
            StampBadgeView(cuisine: stamp.cuisine, size: 140)
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text(stamp.cuisine.rawValue)
                    .font(.title.bold())
                    .foregroundStyle(Theme.ink)
                Text("Earned \(earnedText) at \(stamp.restaurantName)")
                    .foregroundStyle(.secondary)
            }

            FoodImageView(imageName: stamp.imageName, cuisine: stamp.cuisine, cornerRadius: 24)
                .aspectRatio(2, contentMode: .fit)

            if let visit {
                Button {
                    onViewVisit(visit)
                } label: {
                    Label("View visit", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.brandPrimary)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .fittedSheetHeight()
        .brandSheetStyle()
    }
}

/// Orange "Active quest" card on the Passport tab.
struct ActiveQuestCard: View {
    let quest: Quest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active quest")
                    .textCase(.uppercase)
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
                Spacer()
                HStack(spacing: 4) {
                    Text("View quest")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
            }

            Text(quest.title)
                .font(.title3.bold())

            ProgressBar(value: quest.cuisineProgress, tint: .white, track: .white.opacity(0.3))

            Text("\(quest.cuisinesTried) of \(quest.targetCuisines) cuisines · \(quest.remainingBudget.lkr) left")
                .font(.footnote.weight(.medium))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background { QuestCardBackground() }
        .shadow(color: Theme.orange.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// Challenge row with a tinted icon, e.g. "Campus Food Trail" or "Weekly challenge".
struct ChallengeRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    var progress: Double?
    var footnote: String?

    var body: some View {
        HStack(spacing: 16) {
            IconTile(systemImage: systemImage, tint: tint, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let progress {
                    ProgressBar(value: progress, tint: tint, height: 6)
                        .padding(.top, 4)
                }

                if let footnote {
                    Label(footnote, systemImage: "timer")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.green)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// A place in the quest plan with its estimated cost; faded when it no longer fits the budget.
struct PlanStopRow: View {
    let stop: PlannedStop

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .strokeBorder(stop.fitsBudget ? Theme.orange : Theme.faintInk, lineWidth: 2)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.headline)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !stop.fitsBudget {
                    Text("Over budget – optional")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Est. \(stop.estimatedCost.lkr)")
                .font(.headline)
                .monospacedDigit()
                .fixedSize()
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .cardBackground(shadowStrength: stop.fitsBudget ? 1 : 0.3)
        .opacity(stop.fitsBudget ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

// Previews

#Preview {
    PassportView()
        .previewInNavigationStack()
}

#Preview {
    StampGridCard(stamps: MockData.stamps) { _ in }
        .padding()
        .appBackground()
}

#Preview {
    Text("Passport")
        .sheet(isPresented: .constant(true)) {
            StampDetailSheet(stamp: MockData.stamps[0], visit: MockData.visits[0]) { _ in }
        }
}

#Preview {
    VStack(spacing: 16) {
        ActiveQuestCard(quest: MockData.activeQuest)
        ChallengeRow(systemImage: "mappin.and.ellipse", tint: .blue, title: "Campus Food Trail", subtitle: "1 of 3 stops visited", progress: 0.33)
        PlanStopRow(stop: MockData.activeQuest.plan[0])
        PlanStopRow(stop: MockData.activeQuest.plan[1])
    }
    .padding()
    .appBackground()
}
