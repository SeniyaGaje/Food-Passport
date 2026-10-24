import Testing
import SwiftUI
@testable import FoodPassport

/// Navigation: tabs, each tab's screen stack, pop-ups, toasts and the in-app arrival banner.
@Suite("Navigation")
@MainActor
struct AppRouterTests {

    private let place = MockData.campusBites

    @Test("The app opens on Home with nothing pushed")
    func startsOnHome() {
        let router = AppRouter()

        #expect(router.selectedTab == .home)
        #expect(router.tabPaths.isEmpty)
        #expect(router.popup == nil)
    }

    @Test("A screen is pushed onto the tab that is showing")
    func pushOntoSelectedTab() {
        let router = AppRouter()
        router.selectedTab = .profile

        router.push(.about)

        #expect(router.tabPaths[.profile] == [.about])
        #expect(router.tabPaths[.home] == nil)
    }

    @Test("Each tab keeps its own stack of screens")
    func separateStacks() {
        let router = AppRouter()

        router.path(for: .explore).wrappedValue = [.placeDetail(place)]
        router.path(for: .history).wrappedValue = [.visitDetail(MockData.visits[0])]

        #expect(router.path(for: .explore).wrappedValue == [.placeDetail(place)])
        #expect(router.path(for: .history).wrappedValue == [.visitDetail(MockData.visits[0])])
        #expect(router.path(for: .home).wrappedValue.isEmpty)
    }

    @Test("Opening a screen from elsewhere switches tab and shows it on top of the tab's first screen")
    func openInTab() {
        let router = AppRouter()
        router.tabPaths[.passport] = [.foodTrail, .placeDetail(place)]

        router.open(.weeklyChallenge, in: .passport)

        #expect(router.selectedTab == .passport)
        #expect(router.tabPaths[.passport] == [.weeklyChallenge])
    }

    @Test("After logging a visit, Directions and Log visit close and Place detail shows again")
    func closeVisitLoggingScreens() {
        let router = AppRouter()
        router.selectedTab = .explore
        router.tabPaths[.explore] = [.placeDetail(place), .directions(place), .logVisit(place)]

        router.closeVisitLoggingScreens()

        #expect(router.tabPaths[.explore] == [.placeDetail(place)])
    }

    @Test("Pop-ups open and close")
    func popups() {
        let router = AppRouter()

        router.present(.budgetLimit)
        #expect(router.popup == .budgetLimit)

        router.dismissPopup()
        #expect(router.popup == nil)
    }

    @Test("A toast shows its message")
    func toast() {
        let router = AppRouter()

        router.showToast("Visit logged ✓")

        #expect(router.toast?.text == "Visit logged ✓")
    }

    @Test("Tapping the arrival banner opens Log your visit and hides the banner")
    func openBanner() {
        let router = AppRouter()
        router.selectedTab = .explore
        router.showBanner(InAppBanner(title: "You've arrived", message: "", route: .logVisit(place)))

        router.openBanner()

        #expect(router.banner == nil)
        #expect(router.tabPaths[.explore] == [.logVisit(place)])
    }

    @Test("Finishing the stamp celebration closes the pop-up and the logging screens")
    func finishStampCelebration() {
        let router = AppRouter()
        router.selectedTab = .explore
        router.tabPaths[.explore] = [.placeDetail(place), .logVisit(place)]
        router.present(.stampEarned(.sriLankan))

        router.finishStampCelebration(for: .sriLankan)

        #expect(router.popup == nil)
        #expect(router.tabPaths[.explore] == [.placeDetail(place)])
        #expect(router.toast?.text == "Visit logged! You earned a Sri Lankan stamp ✓")
    }

    @Test("Signing out resets all navigation")
    func reset() {
        let router = AppRouter()
        router.selectedTab = .history
        router.tabPaths[.history] = [.about]
        router.onboardingPath = [.signIn]
        router.sheet = .monthlyBudget
        router.present(.budgetUpdate)

        router.reset()

        #expect(router.selectedTab == .home)
        #expect(router.tabPaths.isEmpty)
        #expect(router.onboardingPath.isEmpty)
        #expect(router.sheet == nil)
        #expect(router.popup == nil)
    }
}
