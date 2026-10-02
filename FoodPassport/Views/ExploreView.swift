import SwiftUI
import MapKit

// MARK: - ExploreView

/// Explore tab: search, cuisine filters, and a map or list of nearby restaurants.
struct ExploreView: View {
    private enum DisplayMode {
        case map
        case list
    }

    @State private var searchText = ""
    @State private var selectedCuisine: Cuisine?
    @State private var displayMode: DisplayMode = .map
    @State private var selectedRestaurantID: Restaurant.ID?

    private let restaurants = MockData.restaurants

    private var cuisineFilters: [Cuisine] {
        Cuisine.allCases.filter { cuisine in
            restaurants.contains { $0.cuisine == cuisine }
        }
    }

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

    private var selectedRestaurant: Restaurant? {
        filteredRestaurants.first { $0.id == selectedRestaurantID } ?? filteredRestaurants.first
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Explore food", subtitle: "Around campus") {
                    HStack(spacing: 10) {
                        displayModeButton
                        ProfileAvatarButton()
                    }
                }

                SearchField(placeholder: "Search places or cuisines", text: $searchText)
            }
            .padding(.horizontal, 20)

            cuisineChips

            switch displayMode {
            case .map:
                mapContent
            case .list:
                listContent
            }
        }
        .padding(.top, 8)
        .appBackground()
        .navigationTitle("Explore")
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.25), value: displayMode)
    }

    private var displayModeButton: some View {
        Button {
            displayMode = displayMode == .map ? .list : .map
        } label: {
            Label(
                displayMode == .map ? "List" : "Map",
                systemImage: displayMode == .map ? "list.bullet" : "map"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: 0xE6E6EA), in: Capsule())
        }
        .buttonStyle(.plain)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var mapContent: some View {
        ExploreMapView(
            restaurants: filteredRestaurants,
            highlightedRestaurantID: selectedRestaurant?.id
        ) { restaurant in
            withAnimation(.spring(duration: 0.3)) {
                selectedRestaurantID = restaurant.id
            }
        }
        .overlay(alignment: .bottom) {
            if let restaurant = selectedRestaurant {
                RestaurantCard(restaurant: restaurant, highlightsCuisine: true)
                    .id(restaurant.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredRestaurants) { restaurant in
                    RestaurantCard(restaurant: restaurant)
                }

                if filteredRestaurants.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - ExploreMapView

/// Map centred on campus with a pin for each restaurant.
struct ExploreMapView: View {
    let restaurants: [Restaurant]
    let highlightedRestaurantID: Restaurant.ID?
    let onSelect: (Restaurant) -> Void

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: MockData.campusCenter, latitudinalMeters: 2600, longitudinalMeters: 2600)
    )

    var body: some View {
        Map(position: $position) {
            Annotation("You", coordinate: MockData.userLocation) {
                UserLocationDot()
            }
            .annotationTitles(.hidden)

            ForEach(restaurants) { restaurant in
                Annotation(restaurant.name, coordinate: restaurant.coordinate, anchor: .bottom) {
                    Button {
                        onSelect(restaurant)
                    } label: {
                        RestaurantPin(isSelected: restaurant.id == highlightedRestaurantID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(restaurant.name)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
    }
}

// MARK: - RestaurantCard

/// Restaurant summary card used in the Explore list and under the map.
struct RestaurantCard: View {
    @Environment(AppState.self) private var appState

    let restaurant: Restaurant
    var highlightsCuisine = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: AppRoute.placeDetail(restaurant)) {
                HStack(spacing: 14) {
                    FoodImageView(imageName: restaurant.imageName, cuisine: restaurant.cuisine, cornerRadius: 16)
                        .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(restaurant.cuisine.rawValue)
                                .foregroundStyle(highlightsCuisine ? Theme.green : Color.secondary)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(restaurant.distanceText)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)

                        Text(restaurant.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.ink)

                        Text(restaurant.priceRangeText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
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

// MARK: - Previews

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
