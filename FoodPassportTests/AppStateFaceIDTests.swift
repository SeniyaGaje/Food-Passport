import Testing
import Foundation
@testable import FoodPassport

/// "Unlock with Face ID" and the lock screen, using a fake sensor that can pass or fail.
@Suite("Face ID lock")
@MainActor
struct AppStateFaceIDTests {

    @Test("Turning Face ID on asks for the student's face first, then remembers the choice")
    func turnOnFaceID() async {
        let app = TestApp()

        await app.appState.setFaceIDEnabled(true)

        #expect(app.appState.isFaceIDEnabled)
        #expect(app.biometrics.promptCount == 1)

        // The setting is saved on the phone, so it is still on next time the app opens.
        let relaunched = TestApp(relaunching: app)
        #expect(relaunched.appState.isFaceIDEnabled)
    }

    @Test("If Face ID doesn't recognise the student, it stays off and they see why")
    func failedScan() async {
        let app = TestApp()
        app.biometrics.errorToThrow = .failed

        await app.appState.setFaceIDEnabled(true)

        #expect(!app.appState.isFaceIDEnabled)
        #expect(app.appState.errorMessage == "Face ID didn't recognise you. Try again.")
    }

    @Test("Cancelling the Face ID prompt leaves it off without an error message")
    func cancelledScan() async {
        let app = TestApp()
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
        #expect(app.biometrics.promptCount == 1)
    }

    @Test("The passport locks in the background only when Face ID is on")
    func lockWhenBackgrounded() async throws {
        let app = TestApp()
        try await app.signIn()

        app.appState.lockIfNeeded()
        #expect(!app.appState.isLocked)

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
        app.biometrics.errorToThrow = .lockedOut

        await app.appState.unlockWithBiometrics()

        #expect(app.appState.isLocked)
        #expect(app.appState.lockMessage == BiometricError.lockedOut.errorDescription)
    }

    @Test("Reopening the app asks for Face ID before showing the passport")
    func lockedOnLaunch() async {
        let firstLaunch = TestApp(signedIn: true)
        await firstLaunch.appState.setFaceIDEnabled(true)

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

        app.appState.appDidEnterBackground(at: start)
        #expect(!app.appState.isLocked)
        app.appState.appDidBecomeActive(at: start.addingTimeInterval(60))
        #expect(!app.appState.isLocked)

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
        let publisher = RecordingWidgetPublisher()
        let app = TestApp(widgets: publisher)
        try await app.signIn()
        await app.appState.setFaceIDEnabled(true)
        app.appState.setLockDelay(.fifteenMinutes)
        let start = Date.now

        app.appState.appDidEnterBackground(at: start)

        let snapshot = publisher.latest
        #expect(snapshot.isSignedIn)
        #expect(snapshot.hiddenAfter == start.addingTimeInterval(15 * 60))
        #expect(snapshot.current(at: start.addingTimeInterval(60)).isSignedIn)
        #expect(!snapshot.current(at: start.addingTimeInterval(16 * 60)).isSignedIn)
    }

    @Test("Reopening soon after closing skips Face ID, but not after the delay")
    func relaunchWithinDelay() async throws {
        let firstLaunch = TestApp(signedIn: true)
        await firstLaunch.appState.restoreSession()
        await firstLaunch.appState.setFaceIDEnabled(true)
        firstLaunch.appState.setLockDelay(.fiveMinutes)
        firstLaunch.appState.appDidEnterBackground()

        let soon = TestApp(signedIn: true, relaunching: firstLaunch)
        await soon.appState.restoreSession()
        #expect(!soon.appState.isLocked)

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
