import SwiftUI
import MapKit

/// The Explore tab: search, cuisine filters, and a map or list of restaurants.
struct ExploreView: View {
    private enum DisplayMode {
        case map
        case list
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var selectedCuisine: Cuisine?
    @State private var displayMode: DisplayMode = .map
    @State private var selectedRestaurantID: Restaurant.ID?

    // Every restaurant from Firestore, with distances from the student.
    private var restaurants: [Restaurant] {
        appState.restaurants
    }

    /// Only show filter chips for cuisines that have a restaurant.
    private var cuisineFilters: [Cuisine] {
        Cuisine.allCases.filter { cuisine in
            restaurants.contains { $0.cuisine == cuisine }
        }
    }

    /// Restaurants that match the chosen cuisine and the search text, nearest first.
    private var filteredRestaurants: [Restaurant] {
        restaurants
            .filter { selectedCuisine == nil || $0.cuisine == selectedCuisine }
            .filter { restaurant in
                searchText.isEmpty
                    || restaurant.name.localizedCaseInsensitiveContains(searchText)
                    || restaurant.cuisine.rawValue.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.distanceKm < $1.distanceKm }
    }

    /// The restaurant whose card shows under the map (the nearest one until a pin is tapped).
    private var selectedRestaurant: Restaurant? {
        filteredRestaurants.first { $0.id == selectedRestaurantID } ?? filteredRestaurants.first
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Explore food", subtitle: "Around campus") {
                    HStack(spacing: 10) {
                        if sizeClass != .regular { displayModePicker }
                        ProfileAvatarButton()
                    }
                }

                SearchField(placeholder: "Search places or cuisines", text: $searchText)
            }
            .padding(.horizontal, Theme.screenMargin)

            cuisineChips

            if appState.restaurants.isEmpty {
                EmptyStateView(systemImage: "map", title: "No places available",
                    message: "Refresh when you're online. New restaurants are added by the catalogue administrator.",
                    actionTitle: "Refresh", action: { Task { await appState.refreshData() } })
                    .frame(maxHeight: .infinity)
            } else if filteredRestaurants.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            // iPad (regular width): map and list together.
            } else if sizeClass == .regular {
                GeometryReader { space in
                    // Side by side when there's room (680 pt) and the text isn't at an accessibility size.
                    if space.size.width >= 680 && !dynamicTypeSize.isAccessibilitySize {
                        HStack(spacing: 0) {
                            mapCard.frame(maxWidth: .infinity)
                                .padding(.leading, Theme.screenMargin)
                                .padding(.bottom, Theme.Spacing.s)
                                .accessibilityIdentifier("explore.map")
                            listContent.frame(width: max(300, space.size.width * 0.43)).accessibilityIdentifier("explore.list")
                        }
                    } else {
                        // Narrower window: map on top, list underneath.
                        VStack(spacing: 8) {
                            mapCard.frame(height: max(180, space.size.height * 0.45))
                                .padding(.horizontal, Theme.screenMargin)
                            listContent
                        }
                    }
                }
            } else {
                // iPhone: map or list, chosen with the switch.
                switch displayMode {
                case .map: mapContent
                case .list: listContent
                }
            }
        }
        .padding(.top, 8)
        .appBackground()
        .navigationTitleHidden("Explore")
        .toolbar(sizeClass == .regular ? .visible : .hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: displayMode)
        .sensoryFeedback(.selection, trigger: displayMode)
    }

    /// The Map / List switch.
    private var displayModePicker: some View {
        HStack(spacing: 2) {
            displayModeButton(.map, systemImage: "map", label: "Map")
            displayModeButton(.list, systemImage: "list.bullet", label: "List")
        }
        .padding(3)
        .surfaceBackground(Capsule(), shadowStrength: 0.6)
    }

    private func displayModeButton(_ mode: DisplayMode, systemImage: String, label: String) -> some View {
        let isSelected = displayMode == mode

        return Button {
            displayMode = mode
        } label: {
            // A fixed icon size so it fits its pill; Large Content Viewer shows it bigger when pressed.
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.onInk : Theme.ink)
                .frame(width: 40, height: 34)
                .background(isSelected ? Theme.ink : .clear, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) view")
        .accessibilityShowsLargeContentViewer {
            Label("\(label) view", systemImage: systemImage)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cuisineChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedCuisine == nil) {
                    selectedCuisine = nil
                }
                ForEach(cuisineFilters) { cuisine in
                    FilterChip(title: cuisine.rawValue, isSelected: selectedCuisine == cuisine) {
                        selectedCuisine = cuisine
                    }
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selectedCuisine)
    }

    private var mapContent: some View {
        ExploreMapView(
            restaurants: filteredRestaurants,
            highlightedRestaurantID: selectedRestaurant?.id,
            userLocation: appState.userLocation
        ) { restaurant in
            withAnimation(.spring(duration: 0.3)) {
                selectedRestaurantID = restaurant.id
            }
        }
        .overlay(alignment: .bottom) {
            if sizeClass != .regular, let restaurant = selectedRestaurant {
                RestaurantCard(restaurant: restaurant, highlightsCuisine: true)
                    .id(restaurant.id)
                    // Slides up, or fades with Reduce Motion on.
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, Theme.screenMargin)
                    .padding(.bottom, 16)
            }
        }
    }

    /// On iPad the map sits in a rounded card, so it doesn't run under the see-through sidebar.
    private var mapCard: some View {
        mapContent
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !filteredRestaurants.isEmpty {
                    Text(filteredRestaurants.count == 1 ? "1 place nearby" : "\(filteredRestaurants.count) places nearby")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(filteredRestaurants) { restaurant in
                    RestaurantCard(restaurant: restaurant)
                        .overlay {
                            if sizeClass == .regular, restaurant.id == selectedRestaurant?.id {
                                RoundedRectangle(cornerRadius: 20).stroke(Theme.orange, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if filteredRestaurants.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .refreshable { await appState.refreshData() }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

/// A map with a pin for each restaurant.
struct ExploreMapView: View {
    let restaurants: [Restaurant]
    let highlightedRestaurantID: Restaurant.ID?
    let onSelect: (Restaurant) -> Void

    @State private var position: MapCameraPosition

    /// Places this close to the student (or to campus) are framed when the map opens.
    static let nearbyDistance: CLLocationDistance = 3000

    init(
        restaurants: [Restaurant],
        highlightedRestaurantID: Restaurant.ID?,
        userLocation: CLLocation? = nil,
        onSelect: @escaping (Restaurant) -> Void
    ) {
        self.restaurants = restaurants
        self.highlightedRestaurantID = highlightedRestaurantID
        self.onSelect = onSelect
        // Start framed on the places nearby.
        _position = State(initialValue: .region(Self.startRegion(for: restaurants, around: userLocation)))
    }

    /// Frames the places near the student, so a far-away place (e.g. one in Ratmalana)
    /// doesn't zoom the map right out. Shows everything if nothing is nearby.
    static func startRegion(for restaurants: [Restaurant], around userLocation: CLLocation?) -> MKCoordinateRegion {
        let centre = userLocation ?? CLLocation(latitude: MockData.userLocation.latitude, longitude: MockData.userLocation.longitude)
        let nearby = restaurants.filter { $0.location.distance(from: centre) <= nearbyDistance }

        var points = (nearby.isEmpty ? restaurants : nearby).map(\.coordinate)
        if let userLocation {
            points.append(userLocation.coordinate)
        }
        return .fitting(points, paddingFactor: 1.4)
    }

    var body: some View {
        Map(position: $position) {
            // The blue dot for the student (once location is allowed).
            UserAnnotation()

            // A tappable pin for each restaurant, at least 44 pt for easy tapping.
            ForEach(restaurants) { restaurant in
                Annotation(restaurant.name, coordinate: restaurant.coordinate, anchor: .bottom) {
                    Button {
                        onSelect(restaurant)
                    } label: {
                        RestaurantPin(isSelected: restaurant.id == highlightedRestaurantID)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(restaurant.name)
                    .accessibilityValue("\(restaurant.cuisine.rawValue), \(restaurant.distanceText) away")
                    .accessibilityHint("Shows this place's card below the map")
                    .accessibilityAddTraits(restaurant.id == highlightedRestaurantID ? .isSelected : [])
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }
}

/// A restaurant's card, used in the list and under the map.
struct RestaurantCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let restaurant: Restaurant
    var highlightsCuisine = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: AppRoute.placeDetail(restaurant)) {
                AdaptiveStack(spacing: 14) {
                    FoodImageView(imageName: restaurant.imageName, cuisine: restaurant.cuisine, cornerRadius: 16)
                        .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 4) {
                        AdaptiveStack(spacing: 6) {
                            Text(restaurant.cuisine.rawValue)
                                .fontWeight(.semibold)
                                .foregroundStyle(highlightsCuisine ? Theme.greenText : Theme.orangeText)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text("•")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(restaurant.distanceText)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)

                        Text(restaurant.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(restaurant.priceRangeText, systemImage: "banknote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .labelStyle(CompactLabelStyle())
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            BookmarkButton(isBookmarked: appState.isBookmarked(restaurant)) {
                appState.toggleBookmark(for: restaurant)
            }
        }
        .cardStyle(padding: 14)
    }
}

// Previews

#Preview {
    ExploreView()
        .previewInNavigationStack()
}

#Preview {
    ExploreMapView(restaurants: MockData.restaurants, highlightedRestaurantID: "campus-bites") { _ in }
}

#Preview {
    RestaurantCard(restaurant: MockData.campusBites, highlightsCuisine: true)
        .padding()
        .previewInNavigationStack()
}
