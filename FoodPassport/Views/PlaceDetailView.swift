import SwiftUI
import MapKit

struct PlaceDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingPlanSheet = false

    let restaurant: Restaurant

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FoodImageView(imageName: restaurant.imageName, cuisine: restaurant.cuisine)
                    .frame(height: 240)

                summary

                VStack(alignment: .leading, spacing: 12) {
                    Text("Popular dishes")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)

                    ForEach(restaurant.popularDishes) { dish in
                        HStack {
                            Text(dish.name)
                            Spacer()
                            Text(dish.price.lkr)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Theme.shadow.opacity(0.04), radius: 6, y: 2)
                    }

                    Label("Prices last updated \(restaurant.pricesUpdated)", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        Button("Plan visit") { isShowingPlanSheet = true }
                            .buttonStyle(.brandPrimary)

                        NavigationLink(value: AppRoute.directions(restaurant)) {
                            Text("Get directions")
                        }
                        .buttonStyle(.brandSecondary)

                        NavigationLink(value: AppRoute.logVisit(restaurant)) {
                            Text("I'm here – Log visit")
                        }
                        .buttonStyle(.brandText)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
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

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(restaurant.name)
                    .font(.title.bold())
                    .foregroundStyle(Theme.ink)
                Spacer()
                PillLabel(text: restaurant.cuisine.rawValue, font: .subheadline.weight(.medium))
            }

            HStack(spacing: 18) {
                Label(restaurant.distanceText, systemImage: "mappin.and.ellipse")
                Label(restaurant.priceRangeText, systemImage: "banknote")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }
}

/// Bottom sheet for choosing a date and time to visit a restaurant.
struct PlanVisitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    let restaurant: Restaurant

    @State private var selectedDayIndex = 2
    @State private var selectedMinutes = 13 * 60
    @State private var remindMe = true
    @State private var countsTowardsQuest = true

    private let days: [Date] = (0..<5).compactMap {
        Calendar.current.date(byAdding: .day, value: $0, to: .now)
    }
    /// Time slots as minutes after midnight: 12:30 PM, 1:00 PM, 1:30 PM and 6:30 PM.
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
                HStack(spacing: 8) {
                    ForEach(days.indices, id: \.self) { index in
                        dayChip(for: days[index], isSelected: index == selectedDayIndex) {
                            selectedDayIndex = index
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionCaption("Select time")
                HStack(spacing: 8) {
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
                Toggle("Remind me", isOn: $remindMe)
                    .padding(.vertical, 12)
                Divider()
                Toggle("Count towards my quest", isOn: $countsTowardsQuest)
                    .padding(.vertical, 12)
            }
            .tint(Theme.green)
            .padding(.horizontal, 18)
            .background(Theme.fieldGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func planVisit() {
        let visitDate = selectedVisitDate
        let wantsReminder = remindMe
        let restaurant = restaurant
        dismiss()

        Task {
            let reminderDate = await appState.planVisit(to: restaurant, at: visitDate, remind: wantsReminder)
            let day = visitDate.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())

            if let reminderDate {
                router.showToast("Visit planned for \(day). Reminder at \(reminderDate.formatted(date: .omitted, time: .shortened))")
            } else {
                router.showToast("Visit to \(restaurant.name) planned for \(day)")
            }
        }
    }

    private func date(on day: Date, minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    private func dayChip(for date: Date, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.subheadline)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.bold())
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.orange : Theme.fieldGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func timeChip(_ minutes: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(date(on: .now, minutes: minutes).formatted(date: .omitted, time: .shortened))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Theme.orange : Theme.fieldGray, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Walking route from the student to a restaurant. Start turns on the arrival alert for when they get there.
struct DirectionsView: View {
    @Environment(AppState.self) private var appState
    @State private var route: MKRoute?
    @State private var isLoadingRoute = true
    @State private var isNavigating = false
    @State private var position: MapCameraPosition = .automatic

    let restaurant: Restaurant

    /// The restaurant with its distance kept up to date as the student walks.
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
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            } else if let start = appState.userLocation?.coordinate {
                // No walking route (e.g. offline): a dotted straight line still shows the direction.
                MapPolyline(coordinates: [start, restaurant.coordinate])
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [1, 12]))
            }

            UserAnnotation()

            Annotation(restaurant.name, coordinate: restaurant.coordinate, anchor: .bottom) {
                RestaurantPin(isSelected: true)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .bottom) {
            routeCard
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .navigationTitleHidden("Directions")
        // Recalculated once the student's location first becomes known.
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
                Image(systemName: hasArrived ? "mappin.and.ellipse" : "figure.walk")
                    .font(.title2)
                    .foregroundStyle(Theme.orange)
                    .frame(width: 56, height: 56)
                    .background(Theme.orangeTint, in: Circle())

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
            }
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.1), radius: 20, y: 8)
    }

    // Actions

    /// Asks MapKit for a walking route from the student's location to the restaurant.
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
