import SwiftUI
import MapKit

struct PlaceDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingPlanSheet = false

    let restaurant: Restaurant

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero
                facts
                dishes
                actions
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitleHidden(restaurant.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BookmarkButton(isBookmarked: appState.isBookmarked(restaurant)) {
                    appState.toggleBookmark(for: restaurant)
                }
            }
        }
        .sheet(isPresented: $isShowingPlanSheet) {
            PlanVisitSheet(restaurant: restaurant)
        }
    }

    /// The photo with the name on a dark fade, so the name is easy to read.
    private var hero: some View {
        FoodImageView(imageName: restaurant.imageName, cuisine: restaurant.cuisine)
            .aspectRatio(1.45, contentMode: .fit)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    PhotoTag(text: restaurant.cuisine.rawValue, systemImage: restaurant.cuisine.symbolName)
                    Text(restaurant.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.14), radius: 18, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(restaurant.name), \(restaurant.cuisine.rawValue)")
            .accessibilityAddTraits(.isHeader)
    }

    private var facts: some View {
        // Side by side normally; one above the other with large text, where they wouldn't fit.
        let layout = dynamicTypeSize >= .xLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))

        return layout {
            FactTile(systemImage: "figure.walk", value: "\(restaurant.walkingMinutes) min walk", caption: "\(restaurant.distanceText) away")
            FactTile(systemImage: "banknote", value: restaurant.priceRangeText, caption: "Typical meal")
        }
    }

    private var dishes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Popular dishes")

            VStack(spacing: 0) {
                ForEach(Array(restaurant.popularDishes.enumerated()), id: \.element.id) { index, dish in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 18)
                    }
                    HStack {
                        Text(dish.name)
                        Spacer(minLength: 12)
                        Text(dish.price.lkr)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }
            .cardBackground()

            Label(restaurant.pricesUpdatedText, systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button {
                isShowingPlanSheet = true
            } label: {
                Label("Plan visit", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.brandPrimary)

            NavigationLink(value: AppRoute.directions(restaurant)) {
                Label("Get directions", systemImage: "figure.walk")
            }
            .buttonStyle(.brandSecondary)

            NavigationLink(value: AppRoute.logVisit(restaurant)) {
                Label("I'm here – Log visit", systemImage: "checkmark.circle")
            }
            .buttonStyle(.brandText)
        }
        .padding(.top, Theme.Spacing.xxs)
    }
}

/// A small fact tile, e.g. "5 min walk".
private struct FactTile: View {
    let systemImage: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: systemImage, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .cardStyle(padding: 12, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// The sheet for picking a day and time to visit.
struct PlanVisitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let restaurant: Restaurant

    @State private var selectedDayIndex = 2
    @State private var selectedMinutes = 13 * 60
    @State private var remindMe = true
    @State private var countsTowardsQuest = true

    /// Today and the next four days.
    private let days: [Date] = (0..<5).compactMap {
        Calendar.current.date(byAdding: .day, value: $0, to: .now)
    }
    /// The times to pick from, in minutes after midnight (12:30, 13:00, 13:30, 18:30).
    private let timeSlots = [12 * 60 + 30, 13 * 60, 13 * 60 + 30, 18 * 60 + 30]

    private var selectedVisitDate: Date {
        date(on: days[selectedDayIndex], minutes: selectedMinutes)
    }

    private var isSelectedTimeInPast: Bool {
        selectedVisitDate <= .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                title: "Plan your visit",
                confirmTitle: "Plan",
                onCancel: { dismiss() },
                onConfirm: planVisit,
                isConfirmEnabled: !isSelectedTimeInPast
            )

            VStack(alignment: .leading, spacing: 10) {
                SectionCaption("Select date")
                LazyVGrid(columns: chipColumns(count: days.count, minimumWidth: 110), spacing: 8) {
                    ForEach(days.indices, id: \.self) { index in
                        dayChip(for: days[index], isSelected: index == selectedDayIndex) {
                            selectedDayIndex = index
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionCaption("Select time")
                LazyVGrid(columns: chipColumns(count: timeSlots.count, minimumWidth: 140), spacing: 8) {
                    ForEach(timeSlots, id: \.self) { minutes in
                        timeChip(minutes, isSelected: minutes == selectedMinutes) {
                            selectedMinutes = minutes
                        }
                    }
                }

                if isSelectedTimeInPast {
                    Text("That time has passed. Pick a later time or another day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                }
            }

            VStack(spacing: 0) {
                Toggle(isOn: $remindMe) {
                    Label("Remind me", systemImage: "bell.badge")
                }
                .padding(.vertical, 12)
                Divider()
                Toggle(isOn: $countsTowardsQuest) {
                    Label("Count towards my quest", systemImage: "flag.checkered")
                }
                .padding(.vertical, 12)
                .accessibilityHint("Puts this place at the top of your quest plan")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(Theme.ink)
            .tint(Theme.green)
            .padding(.horizontal, 18)
            .cardBackground(cornerRadius: 18, shadowStrength: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .sensoryFeedback(.selection, trigger: selectedDayIndex)
        .sensoryFeedback(.selection, trigger: selectedMinutes)
        .fittedSheetHeight()
        .brandSheetStyle()
    }

    /// Plans the visit, sets the reminder, and shows a confirmation.
    private func planVisit() {
        let visitDate = selectedVisitDate
        let wantsReminder = remindMe
        let countsForQuest = countsTowardsQuest
        let restaurant = restaurant
        dismiss()

        Task {
            let reminderDate = await appState.planVisit(to: restaurant, at: visitDate, remind: wantsReminder,
                                                        countsTowardsQuest: countsForQuest)
            let day = visitDate.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())

            if let reminderDate {
                router.showToast("Visit planned for \(day). Reminder at \(reminderDate.formatted(date: .omitted, time: .shortened))")
            } else {
                router.showToast("Visit to \(restaurant.name) planned for \(day)")
            }
        }
    }

    /// All chips in one row normally; with the largest text sizes, as many as fit per row.
    private func chipColumns(count: Int, minimumWidth: CGFloat) -> [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: minimumWidth), spacing: 8)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    /// The day at that time, e.g. 780 minutes is 1:00 PM.
    private func date(on day: Date, minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    private func dayChip(for date: Date, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.bold())
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                selectionBackground(isSelected: isSelected, cornerRadius: 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func timeChip(_ minutes: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(date(on: .now, minutes: minutes).formatted(date: .omitted, time: .shortened))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    selectionBackground(isSelected: isSelected, cornerRadius: 12)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Orange for the chosen chip, plain for the rest.
    @ViewBuilder
    private func selectionBackground(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.primaryGradient)
        } else {
            Color.clear
                .cardBackground(cornerRadius: cornerRadius, shadowStrength: 0.4)
        }
    }
}

/// The walking route to a restaurant. Start turns on the "You've arrived" alert.
struct DirectionsView: View {
    @Environment(AppState.self) private var appState
    @State private var route: MKRoute?
    @State private var isLoadingRoute = true
    @State private var isNavigating = false
    @State private var position: MapCameraPosition = .automatic

    let restaurant: Restaurant

    /// The restaurant with its distance updated as the student walks.
    private var liveRestaurant: Restaurant {
        appState.restaurants.first { $0.id == restaurant.id } ?? restaurant
    }

    private var hasArrived: Bool {
        appState.isAtRestaurant(restaurant)
    }

    var body: some View {
        Map(position: $position) {
            if let route {
                MapPolyline(route.polyline)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            } else if let start = appState.userLocation?.coordinate {
                // No route (e.g. offline): draw a dotted straight line instead.
                MapPolyline(coordinates: [start, restaurant.coordinate])
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [1, 12]))
            }

            UserAnnotation()

            Annotation(restaurant.name, coordinate: restaurant.coordinate, anchor: .bottom) {
                RestaurantPin(isSelected: true)
                    .accessibilityElement()
                    .accessibilityLabel(restaurant.name)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .bottom) {
            routeCard
                .padding(.horizontal, Theme.screenMargin)
                .padding(.bottom, 12)
        }
        .navigationTitleHidden("Directions")
        // Work out the route again once we know where the student is.
        .task(id: appState.userLocation == nil) {
            await loadRoute()
        }
    }

    // Route details

    private var walkingMinutes: Int {
        guard let route else { return liveRestaurant.walkingMinutes }
        return max(1, Int((route.expectedTravelTime / 60).rounded(.up)))
    }

    private var distanceText: String {
        guard let route else { return liveRestaurant.distanceText }
        return Measurement(value: route.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var routeSummary: String {
        guard let route, !route.name.isEmpty else { return restaurant.routeSummary }
        return "Route via \(route.name)"
    }

    private var routeCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                IconTile(systemImage: hasArrived ? "mappin.and.ellipse" : "figure.walk", size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasArrived ? "You're here" : "\(walkingMinutes) min walk")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                    Text(hasArrived ? restaurant.name : "\(distanceText) • \(routeSummary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLoadingRoute && !hasArrived {
                    ProgressView()
                        .accessibilityLabel("Finding a walking route")
                }
            }

            if appState.locationPermission.allowsLocation == false {
                Text("Allow location access in Settings to see your route and get an alert when you arrive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasArrived {
                NavigationLink(value: AppRoute.logVisit(restaurant)) {
                    Label("Log your visit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.brandPrimary)
            } else {
                Button(action: startNavigation) {
                    Label(
                        isNavigating ? "We'll alert you when you arrive" : "Start",
                        systemImage: isNavigating ? "location.fill" : "arrow.triangle.turn.up.right.diamond.fill"
                    )
                }
                .buttonStyle(.brandPrimary)
                .disabled(isNavigating)

                Button(action: openInMaps) {
                    Label("Open in Apple Maps", systemImage: "map")
                }
                .buttonStyle(.brandTinted)
                .accessibilityHint("Turn-by-turn walking directions in the Maps app")
            }
        }
        .padding(20)
        .cardBackground(cornerRadius: Theme.Radius.sheet, shadowStrength: 2)
    }

    // Actions

    /// Asks Apple Maps for a walking route to the restaurant.
    private func loadRoute() async {
        guard let start = appState.userLocation?.coordinate else {
            isLoadingRoute = appState.locationPermission.allowsLocation
            return
        }

        isLoadingRoute = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: restaurant.coordinate))
        request.transportType = .walking

        do {
            route = try await MKDirections(request: request).calculate().routes.first
        } catch {
            route = nil
        }
        isLoadingRoute = false
    }

    /// Hands the walk over to Apple Maps for spoken turn-by-turn directions.
    private func openInMaps() {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: restaurant.coordinate))
        destination.name = restaurant.name
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        // Still alert them in FoodPassport when they get there.
        startNavigation()
    }

    /// Turns on the "You've arrived" alert for this restaurant.
    private func startNavigation() {
        isNavigating = true
        Task {
            await appState.startArrivalAlerts(for: restaurant)
        }
    }
}

// Previews

#Preview {
    PlaceDetailView(restaurant: MockData.campusBites)
        .previewInNavigationStack()
}

#Preview {
    Text("Campus Bites")
        .sheet(isPresented: .constant(true)) {
            PlanVisitSheet(restaurant: MockData.campusBites)
        }
        .previewEnvironment()
}

#Preview {
    DirectionsView(restaurant: MockData.campusBites)
        .previewInNavigationStack()
}
