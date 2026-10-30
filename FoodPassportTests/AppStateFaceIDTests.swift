import Testing
import Foundation
@testable import FoodPassport

/// "Unlock with Face ID" and the lock screen, using a fake sensor that can pass or fail.
@Suite("Face ID lock")
@MainActor
struct AppStateFaceIDTests {

    @Test("Turning Face ID on asks for the student's face first, then remembers the choice")
    func turnOnFaceID() async {
        // A fresh app with fake services; its fake Face ID passes unless told to fail.
        let app = TestApp()

        await app.appState.setFaceIDEnabled(true)

        #expect(app.appState.isFaceIDEnabled)
        // The face was checked exactly once.
        #expect(app.biometrics.promptCount == 1)

        // The setting is saved on the phone, so it is still on next time the app opens.
        let relaunched = TestApp(relaunching: app)
        #expect(relaunched.appState.isFaceIDEnabled)
    }

    @Test("If Face ID doesn't recognise the student, it stays off and they see why")
    func failedScan() async {
        let app = TestApp()
        // Make the fake sensor fail.
        app.biometrics.errorToThrow = .failed

        await app.appState.setFaceIDEnabled(true)

        #expect(!app.appState.isFaceIDEnabled)
        #expect(app.appState.errorMessage == "Face ID didn't recognise you. Try again.")
    }

    @Test("Cancelling the Face ID prompt leaves it off without an error message")
    func cancelledScan() async {
        let app = TestApp()
        // Pretend the student cancels the prompt.
        app.biometrics.errorToThrow = .cancelled

        await app.appState.setFaceIDEnabled(true)

        #expect(!app.appState.isFaceIDEnabled)
        #expect(app.appState.errorMessage == nil)
    }

    @Test("Turning Face ID off doesn't ask for a face")
    func turnOffFaceID() async {
        let app = TestApp()
        await app.appState.setFaceIDEnabled(true)

        await app.appState.setFaceIDEnabled(false)

        #expect(!app.appState.isFaceIDEnabled)
        // Still 1: switching off didn't scan again.
        #expect(app.biometrics.promptCount == 1)
    }

    @Test("The passport locks in the background only when Face ID is on")
    func lockWhenBackgrounded() async throws {
        let app = TestApp()
        try await app.signIn()

        // Face ID is off, so going to the background doesn't lock.
        app.appState.lockIfNeeded()
        #expect(!app.appState.isLocked)

        // Turn Face ID on; now it locks.
        await app.appState.setFaceIDEnabled(true)
        app.appState.lockIfNeeded()
        #expect(app.appState.isLocked)
    }

    @Test("Nothing is locked before the student signs in, even with Face ID on")
    func noLockBeforeSignIn() async {
        let app = TestApp()
        await app.appState.setFaceIDEnabled(true)

        app.appState.lockIfNeeded()

        #expect(!app.appState.isLocked)
    }

    @Test("A successful scan unlocks the passport")
    func unlock() async throws {
        let app = TestApp()
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.lockIfNeeded()

        await app.appState.unlockWithBiometrics()

        #expect(!app.appState.isLocked)
        #expect(app.appState.lockMessage == nil)
    }

    @Test("A failed scan keeps the passport locked and explains why")
    func failedUnlock() async throws {
        let app = TestApp()
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.lockIfNeeded()
        // Too many failed tries: the sensor is locked out.
        app.biometrics.errorToThrow = .lockedOut

        await app.appState.unlockWithBiometrics()

        #expect(app.appState.isLocked)
        #expect(app.appState.lockMessage == BiometricError.lockedOut.errorDescription)
    }

    @Test("Reopening the app asks for Face ID before showing the passport")
    func lockedOnLaunch() async {
        let firstLaunch = TestApp(signedIn: true)
        await firstLaunch.appState.setFaceIDEnabled(true)

        // A second TestApp reads the first one's saved settings, like reopening the app.
        let nextLaunch = TestApp(signedIn: true, relaunching: firstLaunch)
        await nextLaunch.appState.restoreSession()

        #expect(nextLaunch.appState.stage == .main)
        #expect(nextLaunch.appState.isLocked)
    }

    @Test("With a 5 minute delay, a short break doesn't lock but a long one does")
    func lockDelay() async throws {
        let app = TestApp()
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.setLockDelay(.fiveMinutes)
        let start = Date.now

        // Away for 1 minute: shorter than the 5-minute delay, so no lock.
        app.appState.appDidEnterBackground(at: start)
        #expect(!app.appState.isLocked)
        app.appState.appDidBecomeActive(at: start.addingTimeInterval(60))
        #expect(!app.appState.isLocked)

        // Away for 6 minutes: longer than the delay, so it locks.
        app.appState.appDidEnterBackground(at: start)
        app.appState.appDidBecomeActive(at: start.addingTimeInterval(6 * 60))
        #expect(app.appState.isLocked)
    }

    @Test("\"Immediately\" locks as soon as the app goes to the background")
    func lockImmediately() async throws {
        let app = TestApp()
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)

        app.appState.appDidEnterBackground()

        #expect(app.appState.isLocked)
    }

    @Test("Widgets keep the passport until the delay ends, then hide it")
    func widgetsHideAfterDelay() async throws {
        // A publisher that records every widget snapshot the app sends.
        let publisher = RecordingWidgetPublisher()
        let app = TestApp(widgets: publisher)
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.setLockDelay(.fifteenMinutes)
        let start = Date.now

        app.appState.appDidEnterBackground(at: start)

        let snapshot = publisher.latest
        #expect(snapshot.isSignedIn)
        // Widgets know to hide 15 minutes after the app went to the background.
        #expect(snapshot.hiddenAfter == start.addingTimeInterval(15 * 60))
        // 1 minute later the widget still shows data; 16 minutes later it doesn't.
        #expect(snapshot.current(at: start.addingTimeInterval(60)).isSignedIn)
        #expect(!snapshot.current(at: start.addingTimeInterval(16 * 60)).isSignedIn)
    }

    @Test("Reopening soon after closing skips Face ID, but not after the delay")
    func relaunchWithinDelay() async throws {
        let firstLaunch = TestApp(signedIn: true)
        await firstLaunch.appState.restoreSession()
        await firstLaunch.appState.setFaceIDEnabled(true)
        firstLaunch.appState.setLockDelay(.fiveMinutes)
        // Close the app with a 5-minute delay.
        firstLaunch.appState.appDidEnterBackground()

        // Reopened straight away: no Face ID needed.
        let soon = TestApp(signedIn: true, relaunching: firstLaunch)
        await soon.appState.restoreSession()
        #expect(!soon.appState.isLocked)

        // Pretend it went to the background 10 minutes ago, then reopen: locked.
        soon.appState.appDidEnterBackground(at: .now.addingTimeInterval(-10 * 60))
        let later = TestApp(signedIn: true, relaunching: soon)
        await later.appState.restoreSession()
        #expect(later.appState.isLocked)
    }

    @Test("Labels follow the sensor on the phone, e.g. Touch ID")
    func touchIDPhone() {
        let app = TestApp(biometry: .touchID)

        #expect(app.appState.biometryKind.name == "Touch ID")
    }
}
