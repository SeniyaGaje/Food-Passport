import SwiftUI
import MapKit

/// The active quest: progress, budget and the suggested places.
struct QuestDetailView: View {
    @Environment(AppRouter.self) private var router

    let quest: Quest

    /// The big "2/3" grows with larger text sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var ringNumberSize: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressCard
                budgetCard

                SectionHeader("Your plan")

                ForEach(quest.plan) { stop in
                    if stop.fitsBudget {
                        NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                            PlanStopRow(stop: stop)
                        }
                        .buttonStyle(.pressableCard)
                    } else {
                        Button {
                            router.present(.budgetLimit)
                        } label: {
                            PlanStopRow(stop: stop)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }

                explanationCard

                Button {
                    router.sheet = .editQuest
                } label: {
                    Label("Edit quest", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.brandTinted)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
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
                RingProgress(
                    value: quest.cuisineProgress,
                    lineWidth: 22,
                    tint: AnyShapeStyle(
                        AngularGradient(
                            colors: [Theme.orangeLight, Theme.orange, Theme.orangeDark],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(quest.cuisineProgress, 0.01))
                        )
                    )
                )
                VStack(spacing: 2) {
                    Text(verbatim: "\(quest.cuisinesTried)/\(quest.targetCuisines)")
                        .font(.system(size: ringNumberSize, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("cuisines tried")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // About half the screen width, so it looks the same on every iPhone.
            .containerRelativeFrame(.horizontal) { width, _ in
                min(width * 0.5, 230)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .combine)

            HStack(spacing: Theme.Spacing.xs) {
                PillLabel(text: quest.duration.rawValue, systemImage: "calendar", style: .orange)
                PillLabel(text: "\(max(quest.targetCuisines - quest.cuisinesTried, 0)) to go", systemImage: "flag.checkered")
            }
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
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemImage: "lightbulb.fill", tint: Theme.gold, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                SectionCaption("Why these picks?")
                Text(quest.planExplanation)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.yellowTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.25), lineWidth: 1)
        }
    }
}

/// The sheet for making or editing a quest.
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
                        CurrencyField(amount: $budget)
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
        .brandSheetStyle()
        .sensoryFeedback(.selection, trigger: duration)
        .sensoryFeedback(.selection, trigger: cuisineCount)
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
                    .cardBackground(cornerRadius: 16, shadowStrength: 0.4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.orange, lineWidth: isSelected ? 1.5 : 0)
                    }
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
                            .foregroundStyle(isSelected ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background {
                                if isSelected {
                                    Capsule().fill(Theme.primaryGradient)
                                } else {
                                    Color.clear.surfaceBackground(Capsule(), shadowStrength: 0.4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    /// Closes the sheet and confirms. (Quests aren't saved to Firestore yet.)
    private func save() {
        dismiss()
        router.showToast(mode == .create ? "Quest created – your plan is ready" : "Quest updated – plan recalculated")
    }
}

/// A food trail: a map of the stops, progress, and the list of stops.
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

                // The map's height follows the screen width, so it keeps its shape.
                trailMap
                    .aspectRatio(1.5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    }
                    .shadow(color: Theme.shadow.opacity(0.1), radius: 14, y: 6)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(trail.visitedCount) of \(trail.stops.count) stops")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(verbatim: "\(Int(trail.progress * 100))%")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.green)
                    }

                    ProgressBar(value: trail.progress, tint: Theme.green, height: 10)
                }
                .cardStyle(padding: 18)

                ForEach(Array(trail.stops.enumerated()), id: \.element.id) { index, stop in
                    NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                        TrailStopRow(number: index + 1, stop: stop, status: trail.status(of: stop))
                    }
                    .buttonStyle(.pressableCard)
                }

                if let next = trail.nextStop {
                    NavigationLink(value: AppRoute.directions(next.restaurant)) {
                        Label("Start trail", systemImage: "figure.walk")
                    }
                    .buttonStyle(.brandPrimary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.bottom, Theme.Spacing.xl)
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

private struct TrailStopRow: View {
    let number: Int
    let stop: TrailStop
    let status: TrailStopStatus

    var body: some View {
        HStack(spacing: 14) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.headline)
                    .foregroundStyle(status == .visited ? Color.secondary : Theme.ink)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .visited:
                PillLabel(text: "Visited", systemImage: "checkmark", style: .green)
            case .next:
                PillLabel(text: "Next stop", style: .orange)
            case .upcoming:
                EmptyView()
            }
        }
        .padding(18)
        .cardBackground(shadowStrength: status == .visited ? 0.3 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.orange, lineWidth: status == .next ? 2 : 0)
        }
        .opacity(status == .visited ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .visited:
            Image(systemName: "checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.green)
                .frame(width: 36, height: 36)
                .background(Theme.greenTint, in: Circle())
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
                .overlay(Circle().strokeBorder(Color(light: 0xD8D8DC, dark: 0x5C5652), lineWidth: 2))
        }
    }
}

struct WeeklyChallengeView: View {
    let challenge: WeeklyChallenge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(challenge.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)

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

                SectionHeader("Suggested places")

                ForEach(challenge.suggestions) { stop in
                    NavigationLink(value: AppRoute.placeDetail(stop.restaurant)) {
                        SuggestedPlaceRow(stop: stop)
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden("Weekly challenge")
    }
}

private struct SuggestedPlaceRow: View {
    let stop: PlannedStop

    var body: some View {
        // The price goes under the name, so long names fit on small iPhones.
        HStack(spacing: 14) {
            FoodImageView(imageName: stop.restaurant.imageName, cuisine: stop.restaurant.cuisine, cornerRadius: 14)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.restaurant.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(stop.restaurant.cuisine.rawValue) · \(stop.restaurant.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Est. \(stop.estimatedCost.lkr)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.orange)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// "Budget update": a meal cost more than expected, so the plan changed.
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
            .background(Theme.insetFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }

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

/// "Budget limit reached": none of the suggestions fit the money left.
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

// Previews

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
