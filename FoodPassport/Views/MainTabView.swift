import SwiftUI

/// The five tabs (Home, Explore, Passport, History, Profile). Each tab has its own screens.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: router.path(for: tab)) {
                    rootView(for: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            AppRouteDestination(route: route)
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
        .tint(Theme.orange)
        .overlay { PopupHost() }
        .overlay(alignment: .top) { TopMessageHost() }
        .sheet(item: $router.sheet) { sheet in
            AppSheetContent(sheet: sheet)
        }
        // A notification was tapped. `initial: true` also catches a tap that opened the app.
        .onChange(of: appState.notificationDestination, initial: true) { _, destination in
            guard let destination else { return }
            appState.notificationDestination = nil
            open(destination)
        }
        // The student arrived at a restaurant while the app is open: show the banner.
        .onChange(of: appState.arrivedRestaurant) { _, restaurant in
            guard let restaurant else { return }
            appState.arrivedRestaurant = nil
            router.showBanner(
                InAppBanner(
                    title: "You've arrived at \(restaurant.name)! 📍",
                    message: "Log your visit now to earn a stamp and level up your \(restaurant.cuisine.rawValue) quest.",
                    imageName: restaurant.imageName,
                    route: .logVisit(restaurant)
                )
            )
        }
    }

    /// Opens the screen a notification is about.
    private func open(_ destination: NotificationDestination) {
        switch destination {
        case .restaurant(let id):
            if let restaurant = appState.restaurants.first(where: { $0.id == id }) {
                router.open(.placeDetail(restaurant), in: .explore)
            }
        case .logVisit(let id):
            if let restaurant = appState.restaurants.first(where: { $0.id == id }) {
                // Open the restaurant's page with Log your visit on top.
                router.tabPaths[.explore] = [.placeDetail(restaurant), .logVisit(restaurant)]
                router.selectedTab = .explore
            }
        case .weeklyChallenge:
            router.open(.weeklyChallenge, in: .passport)
        }
    }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .explore: ExploreView()
        case .passport: PassportView()
        case .history: HistoryView()
        case .profile: ProfileView()
        }
    }
}

/// Turns an `AppRoute` into its screen.
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .placeDetail(let restaurant):
            PlaceDetailView(restaurant: restaurant)
        case .directions(let restaurant):
            DirectionsView(restaurant: restaurant)
        case .logVisit(let restaurant):
            LogVisitView(restaurant: restaurant)
        case .questDetail:
            QuestDetailView(quest: MockData.activeQuest)
        case .foodTrail:
            FoodTrailView(trail: MockData.campusFoodTrail)
        case .weeklyChallenge:
            WeeklyChallengeView(challenge: MockData.weeklyChallenge)
        case .visitDetail(let visit):
            VisitDetailView(visit: visit)
        case .about:
            AboutView()
        }
    }
}

/// Turns an `AppSheet` into its sheet.
struct AppSheetContent: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .newQuest:
            QuestEditorSheet(mode: .create)
        case .editQuest:
            QuestEditorSheet(mode: .edit)
        case .monthlyBudget:
            MonthlyBudgetSheet()
        }
    }
}

/// Shows the current pop-up in the middle of a dimmed screen.
struct PopupHost: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let popup = router.popup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                popupContent(popup)
                    .padding(.horizontal, 28)
                    // Zooms in, or just fades in with Reduce Motion on.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                    // VoiceOver stays inside the pop-up until it's closed.
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: router.popup)
    }

    @ViewBuilder
    private func popupContent(_ popup: AppPopup) -> some View {
        switch popup {
        case .stampEarned(let cuisine):
            StampEarnedPopup(
                cuisine: cuisine,
                quest: MockData.activeQuest,
                onViewPassport: {
                    router.dismissPopup()
                    router.closeVisitLoggingScreens()
                    router.selectedTab = .passport
                },
                onDone: {
                    router.finishStampCelebration(for: cuisine)
                }
            )
        case .budgetUpdate:
            BudgetUpdatePopup(
                update: MockData.latestBudgetUpdate,
                onSeeUpdatedPlan: {
                    router.dismissPopup()
                    router.open(.questDetail, in: .passport)
                },
                onAdjustBudget: {
                    router.dismissPopup()
                    router.sheet = .editQuest
                }
            )
        case .budgetLimit:
            BudgetLimitPopup(
                quest: MockData.activeQuest,
                onIncreaseBudget: {
                    router.dismissPopup()
                    router.sheet = .editQuest
                },
                onExtendDeadline: {
                    router.dismissPopup()
                    router.sheet = .editQuest
                },
                onKeepAsIs: {
                    router.dismissPopup()
                }
            )
        }
    }
}

/// Shows banners and short messages at the top of the screen.
struct TopMessageHost: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slides down from the top, or just fades in with Reduce Motion on.
    private var messageTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let banner = router.banner {
                NotificationBannerView(title: banner.title, message: banner.message, imageName: banner.imageName) {
                    router.openBanner()
                }
                .transition(messageTransition)
            }

            if let toast = router.toast {
                ToastView(text: toast.text)
                    .transition(messageTransition)
            }
        }
        .padding(.horizontal, 12)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4), value: router.banner)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4), value: router.toast)
        // Read new messages out loud for VoiceOver users, since they disappear on their own.
        .onChange(of: router.toast) { _, toast in
            if let toast {
                AccessibilityNotification.Announcement(toast.text).post()
            }
        }
        .onChange(of: router.banner) { _, banner in
            if let banner {
                AccessibilityNotification.Announcement(banner.title).post()
            }
        }
    }
}

// Previews

#Preview {
    MainTabView()
        .previewEnvironment()
}
