import XCTest
import UIKit

/// UI tests (XCTest, because Swift Testing can't drive the UI) for the iPad and iPhone layouts.
final class AdaptiveLayoutTests: XCTestCase {
    // Launches in landscape and checks Explore, then rotates to portrait.
    @MainActor
    func testExploreAndRotation() throws {
        let app = XCUIApplication()
        // --demo uses sample data, so the test needs no Firebase account.
        app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "sidebar.explore").firstMatch
        // iPad: the sidebar opens Explore, and the map must sit to the left of the list.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(sidebar.waitForExistence(timeout: 15))
            sidebar.tap()
            let map = app.descendants(matching: .any).matching(identifier: "explore.map").firstMatch
            let list = app.descendants(matching: .any).matching(identifier: "explore.list").firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            // The map's right edge is at or before the list's left edge, so they're side by side.
            XCTAssertLessThanOrEqual(map.frame.maxX, list.frame.minX + 2)
            XCTAssertGreaterThan(map.frame.height, 150)
            XCTAssertGreaterThan(list.frame.height, 150)
        } else {
            // iPhone: the tab bar opens Explore and shows the map.
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 15))
            explore.tap()
            XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        }
        attachScreenshot("Explore-landscape")
        // Back to portrait: the same screen and map must still show.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Explore food"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.maps.firstMatch.exists)
        attachScreenshot("Explore-portrait")
        XCUIDevice.shared.orientation = .portrait
    }

    // Turns on the weekly reminder in Profile and accepts the iOS permission prompt.
    @MainActor
    func testNotificationPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        // Open Profile from the sidebar on iPad, or the tab bar on iPhone.
        if UIDevice.current.userInterfaceIdiom == .pad {
            let profile = app.descendants(matching: .any).matching(identifier: "sidebar.profile").firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 15))
            profile.tap()
        } else {
            let profile = app.tabBars.buttons["Profile"]
            XCTAssertTrue(profile.waitForExistence(timeout: 15))
            profile.tap()
        }
        // Turn the Weekly challenge switch on if it's off.
        let toggle = app.switches["Weekly challenge"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.tap() }
        // Tap Allow on the system prompt (it belongs to SpringBoard, not the app).
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        // The switch must end up on.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        attachScreenshot("Notification-permission")
    }

    // Keeps a screenshot in the test report.
    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
