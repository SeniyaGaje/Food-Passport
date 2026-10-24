import Testing
import Foundation
import CoreLocation
@testable import FoodPassport

/// Live location, arrival alerts (geofencing) and location-verified visits, with a mock "student" moved around campus.
@Suite("Location and arrivals")
@MainActor
struct AppStateLocationTests {

    private let campusBites = MockData.campusBites

    @Test("After signing in, distances are measured from the student's real location")
    func realDistances() async throws {
        let app = TestApp()
        try await app.signIn()

        let student = try #require(app.appState.userLocation)
        let shown = try #require(app.appState.restaurants.first { $0.id == campusBites.id })

        #expect(app.location.isUpdatingLocation)
        #expect(app.location.monitoredRestaurantIDs.count == MockData.restaurants.count)
        #expect(shown.distanceKm == campusBites.withDistance(from: student).distanceKm)
    }

    @Test("Location isn't used before the student signs in")
    func noLocationBeforeSignIn() {
        let app = TestApp()

        #expect(app.appState.userLocation == nil)
        #expect(!app.location.isUpdatingLocation)
    }

    // Verifying visits

    @Test("A visit logged at the restaurant counts as verified")
    func verifiedAtRestaurant() async throws {
        let app = TestApp()
        try await app.signIn()

        app.location.simulateMove(to: campusBites.coordinate)

        #expect(app.appState.isAtRestaurant(campusBites))
    }

    @Test("110 m away is close enough to verify a visit, but not to trigger the arrival alert")
    func betweenArrivalAndVerificationRadius() async throws {
        let app = TestApp()
        app.appState.isAppActive = true
        try await app.signIn()
        let nearby = coordinate(110, northOf: campusBites.coordinate)
        let metres = distance(from: nearby, to: campusBites.coordinate)
        try #require(metres > Geofence.arrivalRadius && metres < Geofence.verificationRadius)

        app.location.simulateMove(to: nearby)

        #expect(app.appState.isAtRestaurant(campusBites))
        #expect(app.appState.arrivedRestaurant == nil)
    }

    @Test("A visit logged 200 m away is not verified")
    func tooFarToVerify() async throws {
        let app = TestApp()
        try await app.signIn()

        app.location.simulateMove(to: coordinate(200, northOf: campusBites.coordinate))

        #expect(!app.appState.isAtRestaurant(campusBites))
    }

    @Test("Without a known location, no visit is verified")
    func unknownLocation() async throws {
        let app = TestApp(coordinate: nil)
        try await app.signIn()

        #expect(app.appState.userLocation == nil)
        #expect(!app.appState.isAtRestaurant(campusBites))
    }

    // Arrival alerts

    @Test("Walking into a restaurant while the app is open shows the arrival banner")
    func arrivalBannerWhileOpen() async throws {
        let app = TestApp()
        app.appState.isAppActive = true
        try await app.signIn()

        app.location.simulateMove(to: campusBites.coordinate)
        await app.appState.waitForPendingWrites()

        #expect(app.appState.arrivedRestaurant?.id == campusBites.id)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    @Test("Walking into a restaurant while the app is closed sends a notification instead")
    func arrivalNotificationWhileClosed() async throws {
        let app = TestApp()
        app.appState.isAppActive = false
        try await app.signIn()

        app.location.simulateGeofenceEntry(at: campusBites.id)
        await app.appState.waitForPendingWrites()

        #expect(app.appState.arrivedRestaurant == nil)
        let reminder = try #require(app.notifications.scheduledReminders.first)
        #expect(reminder.id == "arrival-campus-bites")
        #expect(reminder.destination == .logVisit(restaurantID: campusBites.id))
    }

    @Test("Walking past the same door again within 3 hours doesn't alert twice")
    func arrivalCooldown() async throws {
        let app = TestApp()
        app.appState.isAppActive = true
        try await app.signIn()

        app.location.simulateMove(to: campusBites.coordinate)
        #expect(app.appState.arrivedRestaurant != nil)
        app.appState.arrivedRestaurant = nil  // the banner was shown and dismissed

        app.location.simulateMove(to: MockData.userLocation)
        app.location.simulateMove(to: campusBites.coordinate)

        #expect(app.appState.arrivedRestaurant == nil)
    }

    @Test("Tapping Start in Directions turns the alert back on and asks for Always location")
    func startArrivalAlertsResetsCooldown() async throws {
        let app = TestApp()
        app.appState.isAppActive = true
        try await app.signIn()
        app.location.simulateMove(to: campusBites.coordinate)
        app.appState.arrivedRestaurant = nil

        await app.appState.startArrivalAlerts(for: campusBites)

        #expect(app.location.hasRequestedAlwaysPermission)
        // The student is already there, so the alert shows again straight away.
        #expect(app.appState.arrivedRestaurant?.id == campusBites.id)
    }

    @Test("Arrivals are ignored when nobody is signed in or the restaurant is unknown")
    func ignoredArrivals() async throws {
        let signedOut = TestApp()
        signedOut.location.simulateGeofenceEntry(at: campusBites.id)
        await signedOut.appState.waitForPendingWrites()
        #expect(signedOut.notifications.scheduledReminders.isEmpty)

        let signedIn = TestApp()
        try await signedIn.signIn()
        signedIn.location.simulateGeofenceEntry(at: "a-closed-restaurant")
        await signedIn.appState.waitForPendingWrites()
        #expect(signedIn.notifications.scheduledReminders.isEmpty)
    }

    // Permission

    @Test("Allowing location during onboarding returns true")
    func allowLocation() async {
        let app = TestApp(locationPermission: .notDetermined, answerWhenAskedForLocation: .whenInUse)

        let isAllowed = await app.appState.requestLocationPermission()

        #expect(isAllowed)
        #expect(app.appState.locationPermission == .whenInUse)
    }

    @Test("Refusing location during onboarding returns false")
    func refuseLocation() async {
        let app = TestApp(locationPermission: .notDetermined, answerWhenAskedForLocation: .denied)

        let isAllowed = await app.appState.requestLocationPermission()

        #expect(!isAllowed)
        #expect(app.appState.locationPermission == .denied)
        #expect(app.appState.userLocation == nil)
    }

    @Test("Turning location off in Settings forgets the location and stops the geofences")
    func locationTurnedOff() async throws {
        let app = TestApp()
        try await app.signIn()
        #expect(app.appState.userLocation != nil)

        app.location.onPermissionChange?(.denied)

        #expect(app.appState.locationPermission == .denied)
        #expect(app.appState.userLocation == nil)
        #expect(!app.location.isUpdatingLocation)
        #expect(app.location.monitoredRestaurantIDs.isEmpty)
    }
}
