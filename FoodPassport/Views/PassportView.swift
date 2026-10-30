import SwiftUI

/// The Passport tab: stamps, the active quest and challenges.
struct PassportView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var selectedStamp: Stamp?

    private var quest: Quest { appState.activeQuest }
    private var trail: FoodTrail { appState.currentTrail }
    private var challenge: WeeklyChallenge { appState.currentChallenge }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader("My food passport", subtitle: "Every new cuisine is a new stamp") {
                    newQuestButton
                }

                // The stamp grid; tapping a stamp shows where it was earned.
                StampGridCard(stamps: appState.stamps) { stamp in
                    selectedStamp = stamp
                }

                // The active quest, or a prompt to start one.
                if appState.hasActiveQuest {
                NavigationLink(value: AppRoute.questDetail) {
                    ActiveQuestCard(quest: quest)
                }
                .buttonStyle(.pressableCard)
                } else {
                    NoQuestCard()
                }

                SectionHeader("Challenges")

                // The food trail and its progress.
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

                // This week's challenge.
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
        .refreshable { await appState.refreshData() }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Passport")
        .toolbar(sizeClass == .regular ? .visible : .hidden, for: .navigationBar)
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

    /// The visit that earned this stamp.
    private func visit(for stamp: Stamp) -> Visit? {
        appState.visits.first { $0.id == stamp.visitID }
    }
}

/// The grid of stamps, with empty "Next cuisine" spaces after them.
struct StampGridCard: View {
    let stamps: [Stamp]
    var totalSlots = 6
    let onSelect: (Stamp) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// As many columns as fit (three on an iPhone). One column with the largest text sizes.
    private var columns: [GridItem] {
        let minimumWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 240 : 92
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: 12)]
    }

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
                    .accessibilityValue("Earned at \(stamp.restaurantName)")
                    .accessibilityHint("Shows stamp details")
                }

                ForEach(0..<max(totalSlots - stamps.count, 0), id: \.self) { _ in
                    VStack(spacing: 8) {
                        StampBadgeView(cuisine: nil)
                        Text("Next cuisine")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Empty stamp, waiting for your next cuisine")
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle(padding: 20)
    }
}

/// A stamp's details: where and when it was earned, with a link to its visit.
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

            VisitPhotoView(photoID: visit?.photoIDs?.first, fallbackImage: stamp.imageName, cuisine: stamp.cuisine)
                .aspectRatio(2, contentMode: .fit)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 24))

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

/// The orange "Active quest" card.
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
        .accessibilityHint("Opens the quest")
    }
}

/// A challenge row, e.g. "Campus Food Trail".
struct ChallengeRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    var progress: Double?
    var footnote: String?

    var body: some View {
        AdaptiveStack(spacing: 16) {
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
                        .foregroundStyle(Theme.greenText)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the challenge")
    }
}

/// A place in the quest plan. Faded if it no longer fits the budget.
struct PlanStopRow: View {
    let stop: PlannedStop

    var body: some View {
        AdaptiveStack(spacing: 14) {
            Circle()
                .strokeBorder(stop.fitsBudget ? Theme.orange : Theme.faintInk, lineWidth: 2)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.headline)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let planned = stop.plannedFor {
                    Label("Planned \(planned.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", systemImage: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.orangeText)
                }
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
        .accessibilityHint(stop.fitsBudget ? "Opens this place" : "Over budget. Shows your options")
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
