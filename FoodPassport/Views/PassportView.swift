import SwiftUI

// MARK: - PassportView

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
                .buttonStyle(.plain)

                Text("Challenges")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)

                NavigationLink(value: AppRoute.foodTrail) {
                    ChallengeRow(
                        systemImage: "mappin.and.ellipse",
                        tint: .blue,
                        title: trail.name,
                        subtitle: "\(trail.visitedCount) of \(trail.stops.count) stops visited",
                        progress: trail.progress
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: AppRoute.weeklyChallenge) {
                    ChallengeRow(
                        systemImage: "clock",
                        tint: Theme.gold,
                        title: "Weekly challenge",
                        subtitle: challenge.title,
                        footnote: "\(challenge.daysLeft) days left"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
        .buttonStyle(.plain)
        .accessibilityLabel("New quest")
    }

    private func visit(for stamp: Stamp) -> Visit? {
        appState.visits.first { $0.id == stamp.visitID }
    }
}

// MARK: - StampGridCard

/// "Stamps earned" grid: earned stamps followed by empty "Next cuisine" slots.
struct StampGridCard: View {
    let stamps: [Stamp]
    var totalSlots = 6
    let onSelect: (Stamp) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCaption("Stamps earned")

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
                        }
                    }
                    .buttonStyle(.plain)
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

// MARK: - StampDetailSheet

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
                .frame(height: 180)

            if let visit {
                Button("View visit") { onViewVisit(visit) }
                    .buttonStyle(.brandPrimary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(580), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - ActiveQuestCard

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
                Text("View quest")
                    .font(.subheadline.weight(.semibold))
            }

            Text(quest.title)
                .font(.title3.bold())

            ProgressBar(value: quest.cuisineProgress, tint: .white, track: .white.opacity(0.3))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.questGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.orange.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ChallengeRow

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
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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

// MARK: - PlanStopRow

/// A place in the quest plan with its estimated cost; faded when it no longer fits the budget.
struct PlanStopRow: View {
    let stop: PlannedStop

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 2)
                .frame(width: 30, height: 30)

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
                .fixedSize()
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(.white.opacity(stop.fitsBudget ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(stop.fitsBudget ? 0.06 : 0.02), radius: 10, y: 4)
        .opacity(stop.fitsBudget ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

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
