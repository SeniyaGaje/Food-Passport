import SwiftUI
import MapKit

// MARK: - QuestDetailView

/// Active quest progress, budget and the adaptive plan of suggested places.
struct QuestDetailView: View {
    @Environment(AppRouter.self) private var router

    let quest: Quest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressCard
                budgetCard

                Text("Your plan")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)

                ForEach(quest.plan) { stop in
                    if stop.fitsBudget {
                        NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                            PlanStopRow(stop: stop)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            router.present(.budgetLimit)
                        } label: {
                            PlanStopRow(stop: stop)
                        }
                        .buttonStyle(.plain)
                    }
                }

                explanationCard

                Button("Edit quest") { router.sheet = .editQuest }
                    .buttonStyle(.brandTinted)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Quest")
    }

    private var progressCard: some View {
        VStack(spacing: 20) {
            Text(quest.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            ZStack {
                RingProgress(value: quest.cuisineProgress, lineWidth: 24)
                VStack(spacing: 2) {
                    Text(verbatim: "\(quest.cuisinesTried)/\(quest.targetCuisines)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("cuisines tried")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 24)
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption("Quest budget")
            ProgressBar(value: quest.budgetProgress, height: 14)
            HStack {
                Text("\(quest.spent.lkr) spent")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(quest.remainingBudget.lkr) remaining")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .cardStyle(padding: 20)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why these picks?", systemImage: "lightbulb")
                .textCase(.uppercase)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text(quest.planExplanation)
                .foregroundStyle(Theme.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xEBEAEA), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: - QuestEditorSheet

/// Bottom sheet for creating or editing a quest.
struct QuestEditorSheet: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    let mode: Mode

    @State private var questType: QuestType = .newCuisines
    @State private var cuisineCount = 3
    @State private var budget = 3000
    @State private var duration: QuestDuration = .thisMonth
    @State private var maxDistanceKm = 2.0
    @State private var selectedTrailID: FoodTrail.ID? = MockData.campusFoodTrail.id

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: mode == .create ? "New quest" : "Edit quest",
                confirmTitle: mode == .create ? "Create" : "Save",
                onCancel: { dismiss() },
                onConfirm: save
            )
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Quest type", selection: $questType) {
                        ForEach(QuestType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if questType == .newCuisines {
                        cuisineCountRow
                    } else {
                        trailPicker
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionCaption("Budget")
                        CurrencyField(amount: $budget, background: Theme.fieldGray)
                    }

                    durationPicker

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionCaption("Max distance")
                            Spacer()
                            Text(verbatim: "\(maxDistanceKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                        }
                        Slider(value: $maxDistanceKm, in: 0.5...5, step: 0.5)
                            .tint(Theme.orange)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var cuisineCountRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Number of cuisines")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Try different cultural styles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CountStepper(value: $cuisineCount, range: 1...8)
                .accessibilityLabel("Number of cuisines")
        }
    }

    private var trailPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption("Choose a trail")
            ForEach(MockData.foodTrails) { trail in
                let isSelected = trail.id == selectedTrailID
                Button {
                    selectedTrailID = trail.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trail.name)
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text("\(trail.summary) · \(trail.stops.count) stops")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.orange : Color.secondary)
                    }
                    .padding(16)
                    .background(Theme.fieldGray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption("Duration")
            HStack(spacing: 12) {
                ForEach(QuestDuration.allCases) { option in
                    let isSelected = option == duration
                    Button {
                        duration = option
                    } label: {
                        Text(option.rawValue)
                            .font(.headline)
                            .foregroundStyle(isSelected ? .white : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(isSelected ? Theme.orange : Theme.fieldGray, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func save() {
        dismiss()
        router.showToast(mode == .create ? "Quest created – your plan is ready" : "Quest updated – plan recalculated")
    }
}

// MARK: - FoodTrailView

/// A food trail: map of numbered stops, progress and the list of stops.
struct FoodTrailView: View {
    let trail: FoodTrail

    @State private var position: MapCameraPosition

    init(trail: FoodTrail) {
        self.trail = trail
        _position = State(initialValue: .region(.fitting(trail.stops.map(\.restaurant.coordinate), paddingFactor: 1.6)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(trail.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                trailMap
                    .frame(height: 260)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(trail.visitedCount) of \(trail.stops.count) stops")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(Int(trail.progress * 100))%")
                            .font(.headline)
                            .foregroundStyle(Theme.green)
                    }

                    ProgressBar(value: trail.progress, tint: Color(hex: 0x555558), height: 12)

                    ForEach(Array(trail.stops.enumerated()), id: \.element.id) { index, stop in
                        NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                            TrailStopRow(number: index + 1, stop: stop, status: trail.status(of: stop))
                        }
                        .buttonStyle(.plain)
                    }

                    if let next = trail.nextStop {
                        NavigationLink(value: AppRoute.directions(next.restaurant)) {
                            Text("Start trail")
                        }
                        .buttonStyle(.brandPrimary)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle(trail.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var trailMap: some View {
        Map(position: $position) {
            MapPolyline(coordinates: trail.stops.map(\.restaurant.coordinate))
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 8]))

            ForEach(Array(trail.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.restaurant.name, coordinate: stop.restaurant.coordinate) {
                    NumberedMapMarker(number: index + 1, status: trail.status(of: stop))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

// MARK: - TrailStopRow

private struct TrailStopRow: View {
    let number: Int
    let stop: TrailStop
    let status: TrailStopStatus

    var body: some View {
        HStack(spacing: 14) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.title3.bold())
                    .foregroundStyle(status == .visited ? Color.secondary : Theme.ink)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .visited:
                PillLabel(text: "Visited", font: .subheadline.weight(.medium))
            case .next:
                PillLabel(text: "Next stop", style: .orange, font: .subheadline.weight(.semibold))
            case .upcoming:
                EmptyView()
            }
        }
        .padding(18)
        .background(.white.opacity(status == .visited ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.orange, lineWidth: status == .next ? 2 : 0)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .visited:
            Image(systemName: "checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(hex: 0xEDEDEF), in: Circle())
        case .next:
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.orange, in: Circle())
        case .upcoming:
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color(hex: 0xD8D8DC), lineWidth: 2))
        }
    }
}

// MARK: - WeeklyChallengeView

struct WeeklyChallengeView: View {
    let challenge: WeeklyChallenge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(challenge.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        PillLabel(
                            text: "\(challenge.daysLeft) days left",
                            systemImage: "timer",
                            style: .yellow,
                            font: .subheadline.weight(.semibold)
                        )
                        Spacer()
                        Text("\(challenge.completed) of \(challenge.target) completed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ProgressBar(value: challenge.progress, tint: Theme.orange)

                    Text(challenge.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .cardStyle(padding: 20)

                Text("Suggested places")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)

                ForEach(challenge.suggestions) { stop in
                    NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                        SuggestedPlaceRow(stop: stop)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Weekly challenge")
    }
}

// MARK: - SuggestedPlaceRow

private struct SuggestedPlaceRow: View {
    let stop: PlannedStop

    var body: some View {
        HStack(spacing: 14) {
            FoodImageView(imageName: stop.restaurant.imageName, cuisine: stop.restaurant.cuisine, cornerRadius: 14)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Est. \(stop.estimatedCost.lkr)")
                .font(.headline)
                .foregroundStyle(Theme.ink)
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - BudgetUpdatePopup

/// "Budget update" — explains how the Adaptive Food Quest replanned after a visit cost more than estimated.
struct BudgetUpdatePopup: View {
    let update: BudgetUpdate
    let onSeeUpdatedPlan: () -> Void
    let onAdjustBudget: () -> Void

    var body: some View {
        PopupCard {
            PopupIcon(systemImage: "info.circle")

            VStack(spacing: 8) {
                Text("Budget update")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)

                Text("Your meal cost \(update.actualCost.lkr), \(update.overspend.lkr) more than estimated. We've updated your plan to stay within budget.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("\(update.removedStop.restaurant.name) – \(update.removedStop.estimatedCost.lkr)")
                        .strikethrough()
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Theme.destructive)
                }

                Divider()

                Label {
                    Text("\(update.replacementStop.restaurant.name) – \(update.replacementStop.estimatedCost.lkr)")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fieldGray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 10) {
                Button("See updated plan", action: onSeeUpdatedPlan)
                    .buttonStyle(.brandPrimary)
                Button("Adjust budget", action: onAdjustBudget)
                    .buttonStyle(.brandTinted)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - BudgetLimitPopup

/// "Budget limit reached" — shown when no remaining suggestion fits the quest budget.
struct BudgetLimitPopup: View {
    let quest: Quest
    let onIncreaseBudget: () -> Void
    let onExtendDeadline: () -> Void
    let onKeepAsIs: () -> Void

    private var blockedStop: PlannedStop? {
        quest.plan.first { !$0.fitsBudget }
    }

    var body: some View {
        PopupCard {
            PopupIcon(systemImage: "exclamationmark.triangle")

            VStack(spacing: 8) {
                Text("Budget limit reached")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)

                if let blockedStop {
                    Text("Your remaining \(quest.remainingBudget.lkr) can't cover \(blockedStop.restaurant.name) (est. \(blockedStop.estimatedCost.lkr)) before the quest ends.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                Button("Increase budget", action: onIncreaseBudget)
                    .buttonStyle(.brandPrimary)
                Button("Extend deadline", action: onExtendDeadline)
                    .buttonStyle(.brandTinted)
                Button("Keep as is", action: onKeepAsIs)
                    .buttonStyle(BrandTextButtonStyle(color: .secondary))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Previews

#Preview {
    QuestDetailView(quest: MockData.activeQuest)
        .previewInNavigationStack()
}

#Preview {
    Text("Passport")
        .sheet(isPresented: .constant(true)) {
            QuestEditorSheet(mode: .create)
        }
        .previewEnvironment()
}

#Preview {
    FoodTrailView(trail: MockData.campusFoodTrail)
        .previewInNavigationStack()
}

#Preview {
    WeeklyChallengeView(challenge: MockData.weeklyChallenge)
        .previewInNavigationStack()
}

#Preview("Budget update") {
    BudgetUpdatePopup(update: MockData.latestBudgetUpdate, onSeeUpdatedPlan: {}, onAdjustBudget: {})
        .padding()
        .background(Color.black.opacity(0.4))
}

#Preview("Budget limit") {
    BudgetLimitPopup(quest: MockData.activeQuest, onIncreaseBudget: {}, onExtendDeadline: {}, onKeepAsIs: {})
        .padding()
        .background(Color.black.opacity(0.4))
}
