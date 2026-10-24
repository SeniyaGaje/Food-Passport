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

        let region = MKCoordinateRegion.fitting(coordinates, paddingFactor: 1.8)

        #expect(abs(region.center.latitude - 6.91) < 0.000001)
        #expect(abs(region.center.longitude - 79.86) < 0.000001)
        #expect(abs(region.span.latitudeDelta - 0.036) < 0.000001)
        #expect(abs(region.span.longitudeDelta - 0.036) < 0.000001)
    }

    @Test("A single restaurant still gets a sensible zoom level")
    func regionForOneCoordinate() {
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

    @Test("Each stamp has a small tilt, and not all stamps lean the same way")
    func stampTilt() {
        for cuisine in Cuisine.allCases {
            #expect(abs(cuisine.stampTilt) <= 10)
        }
        #expect(Set(Cuisine.allCases.map(\.stampTilt)).count > 1)
    }
}
