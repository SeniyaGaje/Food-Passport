import XCTest
import UIKit

/// Walks the main flows the same way on iPhone (tab bar) and iPad (sidebar),
/// so we know every screen works on both. Screenshots are kept in the test report.
final class SameFlowsTests: XCTestCase {
    private var app: XCUIApplication!

    // Each test starts the app fresh in demo mode, in portrait.
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
    }

    @MainActor
    func testMainFlowsWorkOnEveryDevice() throws {
        // Home, then the spending overview.
        XCTAssertTrue(app.staticTexts["Your overview"].waitForExistence(timeout: 15))
        attachScreenshot("1-Home")
        element("home.spending").tap()
        XCTAssertTrue(text("By restaurant").waitForExistence(timeout: 5))
        attachScreenshot("2-Spending")
        goBack()

        // The quest and its plan.
        XCTAssertTrue(element("home.quest").waitForExistence(timeout: 5))
        element("home.quest").tap()
        XCTAssertTrue(text("Why these picks?").waitForExistence(timeout: 5))
        attachScreenshot("3-Quest")
        goBack()

        // Explore, a place, Plan visit and Log your visit.
        open(tab: "explore", title: "Explore")
        let place = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Campus Bites'")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        attachScreenshot("4-Explore")
        place.tap()
        XCTAssertTrue(text("Popular dishes").waitForExistence(timeout: 5))
        attachScreenshot("5-Place")

        // The Plan visit sheet must offer "Count towards my quest".
        app.buttons["Plan visit"].tap()
        XCTAssertTrue(app.staticTexts["Plan your visit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Count towards my quest"].exists)
        attachScreenshot("6-Plan-visit")
        app.buttons["Cancel"].tap()

        // Open Log your visit from the place's page.
        let logVisit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Log visit'")).firstMatch
        XCTAssertTrue(logVisit.waitForExistence(timeout: 5))
        logVisit.tap()
        XCTAssertTrue(app.buttons["Save visit"].waitForExistence(timeout: 5))
        attachScreenshot("7-Log-visit")
        goBack()

        // The other tabs.
        open(tab: "passport", title: "Passport")
        XCTAssertTrue(app.staticTexts["Weekly challenge"].firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts["My passport"].firstMatch.waitForExistence(timeout: 2))
        attachScreenshot("8-Passport")
        open(tab: "history", title: "History")
        attachScreenshot("9-History")
        open(tab: "profile", title: "Profile")
        XCTAssertTrue(app.switches["Weekly challenge"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("10-Profile")

        // Landscape still shows the same content.
        XCUIDevice.shared.orientation = .landscapeLeft
        open(tab: "home", title: "Home")
        XCTAssertTrue(app.staticTexts["Your overview"].waitForExistence(timeout: 5))
        attachScreenshot("11-Home-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    // Helpers

    /// Captions are shown in capitals, so text is matched ignoring case.
    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    // Finds a view by its accessibility identifier, e.g. "home.spending".
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The sidebar on iPad, the tab bar on iPhone.
    private func open(tab: String, title: String) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let row = element("sidebar.\(tab)")
            if !row.waitForExistence(timeout: 3) {
                // Portrait iPad hides the sidebar until it's asked for.
                app.navigationBars.buttons["Show Sidebar"].firstMatch.tap()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        } else {
            let button = app.tabBars.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
    }

    /// The Back button, not the sidebar button that shares the top bar on iPad.
    private func goBack() {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
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
