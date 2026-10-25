import XCTest
import UIKit

final class AdaptiveLayoutTests: XCTestCase {
    @MainActor
    func testExploreAndRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "sidebar.explore").firstMatch
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(sidebar.waitForExistence(timeout: 15))
            sidebar.tap()
            let map = app.descendants(matching: .any).matching(identifier: "explore.map").firstMatch
            let list = app.descendants(matching: .any).matching(identifier: "explore.list").firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(map.frame.maxX, list.frame.minX + 2)
            XCTAssertGreaterThan(map.frame.height, 150)
            XCTAssertGreaterThan(list.frame.height, 150)
        } else {
            let explore = app.tabBars.buttons["Explore"]
            XCTAssertTrue(explore.waitForExistence(timeout: 15))
            explore.tap()
            XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        }
        attachScreenshot("Explore-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Explore food"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.maps.firstMatch.exists)
        attachScreenshot("Explore-portrait")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testNotificationPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let profile = app.descendants(matching: .any).matching(identifier: "sidebar.profile").firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 15))
            profile.tap()
        } else {
            let profile = app.tabBars.buttons["Profile"]
            XCTAssertTrue(profile.waitForExistence(timeout: 15))
            profile.tap()
        }
        let toggle = app.switches["Weekly challenge"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.tap() }
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        attachScreenshot("Notification-permission")
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
