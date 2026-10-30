import SwiftUI

/// The five tabs (Home, Explore, Passport, History, Profile). Each tab has its own screens.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var router = router

        Group {
            // iPad (regular width): a sidebar with the five destinations.
            if sizeClass == .regular {
                NavigationSplitView {
                    List(selection: sidebarSelection) {
                        ForEach(AppTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.systemImage)
                                .accessibilityIdentifier("sidebar.\(tab.rawValue)").tag(tab)
                        }
                    }
                    .navigationTitle("FoodPassport")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
                } detail: {
                    navigation(for: router.selectedTab)
                        .id(router.selectedTab)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // iPhone (compact width): the tab bar.
                TabView(selection: $router.selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        navigation(for: tab)
                            .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                            .tag(tab)
                    }
                }
            }
        }
        .tint(Theme.orange)
        // Haptics when the tab changes, a message shows, or a stamp is earned.
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .sensoryFeedback(.success, trigger: router.toast?.id)
        .sensoryFeedback(.success, trigger: appState.stamps.count)

        // Pop-ups and top messages sit above every tab.
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
        // The widgets' "Log visit" button: log at the restaurant the student is at, or let them pick one.
        .onChange(of: router.wantsQuickLog, initial: true) { _, wantsQuickLog in
            guard wantsQuickLog else { return }
            router.wantsQuickLog = false
            startQuickLog()
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

    private var sidebarSelection: Binding<AppTab?> {
        Binding(get: { router.selectedTab }, set: { if let tab = $0 { router.selectedTab = tab } })
    }

    private func navigation(for tab: AppTab) -> some View {
        // Each tab has its own navigation stack, driven by the router.
        NavigationStack(path: router.path(for: tab)) {
            rootView(for: tab)
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
        }
    }

    private func startQuickLog() {
        appState.refreshLocation()
        if let restaurant = appState.restaurantHere {
            router.tabPaths[.explore] = [.placeDetail(restaurant), .logVisit(restaurant)]
            router.selectedTab = .explore
        } else {
            router.tabPaths[.explore] = []
            router.selectedTab = .explore
            router.showToast("Pick the place you're eating at, then tap Log visit")
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

    // The first screen of each tab.
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
    @Environment(AppState.self) private var appState
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
            QuestDetailView(quest: appState.activeQuest)
        case .foodTrail:
            FoodTrailView(trail: appState.currentTrail)
        case .weeklyChallenge:
            WeeklyChallengeView(challenge: appState.currentChallenge)
        case .visitDetail(let visit):
            VisitDetailView(visit: visit)
        case .spendingOverview(let period):
            SpendingOverviewView(period: period)
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
    @Environment(AppState.self) private var appState
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
                    // Pop-ups stay phone-sized on iPad instead of stretching across the screen.
                    .frame(maxWidth: 440)
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
                quest: appState.hasActiveQuest ? appState.activeQuest : nil,
                onViewPassport: {
                    router.dismissPopup()
                    router.closeVisitLoggingScreens()
                    router.selectedTab = .passport
                },
                onDone: {
                    router.finishStampCelebration(for: cuisine, budgetUpdate: appState.lastBudgetUpdate)
                }
            )
        case .budgetUpdate(let update):
            BudgetUpdatePopup(
                update: update,
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
                quest: appState.activeQuest,
                onIncreaseBudget: {
                    router.dismissPopup()
                    if let budget = appState.increaseQuestBudgetToFitPlan() {
                        router.showToast("Quest budget raised to \(budget.lkr)")
                    }
                },
                onExtendDeadline: {
                    router.dismissPopup()
                    if let end = appState.extendQuestDeadline() {
                        router.showToast("Quest now ends \(end.formatted(.dateTime.weekday(.abbreviated).day().month()))")
                    }
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
