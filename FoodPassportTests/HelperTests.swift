import Testing
import Foundation
import MapKit
@testable import FoodPassport

/// Small helpers from Theme.swift that many screens rely on.
@Suite("Formatting and map helpers")
@MainActor
struct HelperTests {

    @Test("Amounts are shown in Sri Lankan rupees")
    func rupees() {
        // The thousands separator depends on the phone's region settings.
        let grouping = Locale.current.groupingSeparator ?? ","

        #expect(950.lkr == "LKR 950")
        #expect(0.lkr == "LKR 0")
        #expect(12_500.lkr == "LKR 12\(grouping)500")
    }

    @Test("Form input is trimmed of spaces and new lines")
    func trimmed() {
        #expect("  Kottu Roti \n".trimmed == "Kottu Roti")
        #expect("   ".trimmed.isEmpty)
    }

    @Test("A map region fits every restaurant, with room around the edges")
    func regionFittingCoordinates() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 6.90, longitude: 79.85),
            CLLocationCoordinate2D(latitude: 6.92, longitude: 79.87),
        ]

        // Two points 0.02° apart with 1.8× padding give a 0.036° span.
        let region = MKCoordinateRegion.fitting(coordinates, paddingFactor: 1.8)

        #expect(abs(region.center.latitude - 6.91) < 0.000001)
        #expect(abs(region.center.longitude - 79.86) < 0.000001)
        #expect(abs(region.span.latitudeDelta - 0.036) < 0.000001)
        #expect(abs(region.span.longitudeDelta - 0.036) < 0.000001)
    }

    @Test("A single restaurant still gets a sensible zoom level")
    func regionForOneCoordinate() {
        // One point: use the minimum zoom instead of zero.
        let region = MKCoordinateRegion.fitting([MockData.campusBites.coordinate], minimumDelta: 0.006)

        #expect(region.center.latitude == MockData.campusBites.latitude)
        #expect(region.span.latitudeDelta == 0.006)
        #expect(region.span.longitudeDelta == 0.006)
    }

    @Test("No restaurants gives an empty region instead of crashing")
    func regionForNoCoordinates() {
        let region = MKCoordinateRegion.fitting([])

        #expect(region.span.latitudeDelta == 0)
        #expect(region.span.longitudeDelta == 0)
    }

    @Test("The Explore map frames places near the student, not ones far away")
    func exploreMapFramesNearbyPlaces() {
        let restaurants = MockData.restaurants
        let kade = MockData.ratmalanaTeaKade

        // Without a location, the map shows the places around campus, leaving out Ratmalana (about 9 km away).
        let campus = ExploreMapView.startRegion(for: restaurants, around: nil)
        #expect(campus.span.latitudeDelta < 0.05)
        #expect(abs(campus.center.latitude - kade.latitude) > 0.05)

        // A student on Chakkindarama Road sees the tea kade.
        let home = CLLocation(latitude: kade.latitude + 0.002, longitude: kade.longitude)
        let ratmalana = ExploreMapView.startRegion(for: restaurants, around: home)
        #expect(abs(ratmalana.center.latitude - kade.latitude) < 0.01)
        #expect(ratmalana.span.latitudeDelta < 0.05)
    }

    @Test("Each stamp has a small tilt, and not all stamps lean the same way")
    func stampTilt() {
        for cuisine in Cuisine.allCases {
            // Every stamp leans at most 10 degrees.
            #expect(abs(cuisine.stampTilt) <= 10)
        }
        #expect(Set(Cuisine.allCases.map(\.stampTilt)).count > 1)
    }
}
