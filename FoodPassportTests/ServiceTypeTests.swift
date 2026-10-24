import Testing
import Foundation
@testable import FoodPassport

/// Reminders, notification taps, permissions and error messages.
@Suite("Reminders, permissions and messages")
@MainActor
struct ServiceTypeTests {

    // Reminders

    @Test("A planned-visit reminder fires 30 minutes before the visit and opens the restaurant")
    func plannedVisitReminder() {
        let visitDate = Date(timeIntervalSince1970: 1_800_000_000)
        let reminder = LocalReminder.plannedVisit(to: MockData.campusBites, at: visitDate)

        #expect(reminder.id == "visit-campus-bites-1800000000")
        #expect(reminder.schedule == .once(visitDate.addingTimeInterval(-30 * 60)))
        #expect(reminder.destination == .restaurant(id: "campus-bites"))
        #expect(reminder.title.contains("Campus Bites"))
        #expect(reminder.body.contains("Sri Lankan"))
    }

    @Test("Two visits to the same place get different reminders")
    func plannedVisitReminderIDsAreUnique() {
        let lunch = LocalReminder.plannedVisit(to: MockData.campusBites, at: Date(timeIntervalSince1970: 1_800_000_000))
        let dinner = LocalReminder.plannedVisit(to: MockData.campusBites, at: Date(timeIntervalSince1970: 1_800_020_000))

        #expect(lunch.id != dinner.id)
    }

    @Test("The arrival alert shows straight away and opens Log your visit")
    func arrivalReminder() {
        let reminder = LocalReminder.arrival(at: MockData.campusBites)

        #expect(reminder.id == "arrival-campus-bites")
        #expect(reminder.schedule == .immediately)
        #expect(reminder.destination == .logVisit(restaurantID: "campus-bites"))
        #expect(reminder.title == "You've arrived at Campus Bites! 📍")
    }

    @Test("The weekly challenge reminder repeats every Monday at the chosen time")
    func weeklyChallengeReminder() {
        let reminder = LocalReminder.weeklyChallenge(hour: 18, minute: 30)

        #expect(reminder.id == LocalReminder.weeklyChallengeID)
        #expect(reminder.schedule == .weekly(weekday: 2, hour: 18, minute: 30))
        #expect(reminder.destination == .weeklyChallenge)
    }

    // Tapping a notification

    @Test("A tapped notification opens the screen it was created for")
    func notificationDestinationRoundTrip() {
        let destinations: [NotificationDestination] = [
            .restaurant(id: "campus-bites"),
            .logVisit(restaurantID: "spice-route"),
            .weeklyChallenge,
        ]

        for destination in destinations {
            let userInfo = destination.userInfo
            let decoded = NotificationDestination(destination: userInfo["destination"], restaurantID: userInfo["restaurantID"])
            #expect(decoded == destination)
        }
    }

    @Test("A notification with missing or unknown details opens nothing")
    func invalidNotificationDestinations() {
        #expect(NotificationDestination(destination: "restaurant", restaurantID: nil) == nil)
        #expect(NotificationDestination(destination: "logVisit", restaurantID: nil) == nil)
        #expect(NotificationDestination(destination: "somewhere-else", restaurantID: "campus-bites") == nil)
        #expect(NotificationDestination(destination: nil, restaurantID: nil) == nil)
    }

    // Location

    @Test("Only While Using and Always count as location allowed")
    func locationPermissions() {
        #expect(LocationPermission.whenInUse.allowsLocation)
        #expect(LocationPermission.always.allowsLocation)
        #expect(!LocationPermission.notDetermined.allowsLocation)
        #expect(!LocationPermission.denied.allowsLocation)
        #expect(LocationPermission.whenInUse.label == "While Using")
        #expect(LocationPermission.denied.label == "Off")
    }

    @Test("Visit verification allows more GPS drift than the arrival alert")
    func geofenceSizes() {
        #expect(Geofence.arrivalRadius == 100)
        #expect(Geofence.verificationRadius == 150)
        #expect(Geofence.verificationRadius > Geofence.arrivalRadius)
        // iOS lets an app watch at most 20 regions.
        #expect(Geofence.maxMonitoredRestaurants == 20)
    }

    // Face ID and sign-in messages

    @Test("Labels follow the phone's biometric sensor")
    func biometryNames() {
        #expect(BiometryKind.faceID.name == "Face ID")
        #expect(BiometryKind.touchID.name == "Touch ID")
        #expect(BiometryKind.touchID.systemImage == "touchid")
        // A phone without a set-up sensor still shows the familiar Face ID wording.
        #expect(BiometryKind.none.name == "Face ID")
    }

    @Test("Cancelling Face ID shows no error; real failures explain what to do")
    func biometricErrorMessages() {
        #expect(BiometricError.cancelled.errorDescription == nil)
        #expect(BiometricError.failed.errorDescription == "Face ID didn't recognise you. Try again.")
        #expect(BiometricError.notEnrolled.errorDescription?.contains("Settings") == true)
        #expect(BiometricError.lockedOut.errorDescription?.contains("passcode") == true)
    }

    @Test("Sign-in errors are worded for the student")
    func authErrorMessages() {
        #expect(AuthServiceError.invalidCredentials.errorDescription == "Incorrect email or password.")
        #expect(AuthServiceError.network.errorDescription?.contains("offline") == true)
        #expect(AuthServiceError.other("Something specific").errorDescription == "Something specific")
    }
}
