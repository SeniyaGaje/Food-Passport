import SwiftUI
import MapKit

// MARK: - PlaceDetailView

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
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
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
        .background(.white)
    }
}

// MARK: - PlanVisitSheet

/// Bottom sheet for choosing a date and time to visit a restaurant.
struct PlanVisitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    let restaurant: Restaurant

    @State private var selectedDayIndex = 2
    @State private var selectedTime = "1:00 PM"
    @State private var remindMe = true
    @State private var countsTowardsQuest = true

    private let days: [Date] = (0..<5).compactMap {
        Calendar.current.date(byAdding: .day, value: $0, to: .now)
    }
    private let times = ["12:30 PM", "1:00 PM", "1:30 PM", "6:30 PM"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                title: "Plan your visit",
                confirmTitle: "Plan",
                onCancel: { dismiss() },
                onConfirm: planVisit
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
                    ForEach(times, id: \.self) { time in
                        timeChip(time, isSelected: time == selectedTime) {
                            selectedTime = time
                        }
                    }
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
        let day = days[selectedDayIndex].formatted(.dateTime.weekday(.abbreviated).day())
        dismiss()
        router.showToast("Visit to \(restaurant.name) planned for \(day), \(selectedTime)")
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

    private func timeChip(_ time: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(time)
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

// MARK: - DirectionsView

/// Walking route to a restaurant with a Start button.
struct DirectionsView: View {
    @Environment(AppRouter.self) private var router
    @State private var isNavigating = false
    @State private var position: MapCameraPosition

    let restaurant: Restaurant

    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        _position = State(initialValue: .region(.fitting([MockData.userLocation, restaurant.coordinate], paddingFactor: 2.6)))
    }

    /// Placeholder path drawn until real MapKit walking directions are added.
    private var routeCoordinates: [CLLocationCoordinate2D] {
        let start = MockData.userLocation
        let end = restaurant.coordinate
        return [start, CLLocationCoordinate2D(latitude: start.latitude, longitude: end.longitude), end]
    }

    var body: some View {
        Map(position: $position) {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [1, 12]))

            Annotation("You", coordinate: MockData.userLocation) {
                UserLocationDot()
            }
            .annotationTitles(.hidden)

            Annotation(restaurant.name, coordinate: restaurant.coordinate, anchor: .bottom) {
                RestaurantPin(isSelected: true)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            routeCard
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .navigationTitleHidden("Directions")
    }

    private var routeCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundStyle(Theme.orange)
                    .frame(width: 56, height: 56)
                    .background(Theme.orangeTint, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(restaurant.walkingMinutes) min walk")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                    Text("\(restaurant.distanceText) • \(restaurant.routeSummary)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                startNavigation()
            } label: {
                Label(
                    isNavigating ? "Navigating…" : "Start",
                    systemImage: isNavigating ? "location.fill" : "arrow.triangle.turn.up.right.diamond.fill"
                )
            }
            .buttonStyle(.brandPrimary)
            .disabled(isNavigating)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
    }

    private func startNavigation() {
        isNavigating = true
        // Stand-in for the geofence arrival alert so the prototype flow can be clicked through.
        Task {
            try? await Task.sleep(for: .seconds(2))
            router.showBanner(
                InAppBanner(
                    title: "You've arrived at \(restaurant.name)! 📍",
                    message: "Log your visit now to earn a stamp and level up your \(restaurant.cuisine.rawValue) quest.",
                    route: .logVisit(restaurant)
                )
            )
        }
    }
}

// MARK: - Previews

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
