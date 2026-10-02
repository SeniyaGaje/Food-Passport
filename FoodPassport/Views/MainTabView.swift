import SwiftUI

// MARK: - MainTabView

/// The five-tab shell (Home, Explore, Passport, History, Profile), each with its own navigation stack.
struct MainTabView: View {
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

// MARK: - AppRouteDestination

/// Maps a pushed `AppRoute` to its screen.
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

// MARK: - AppSheetContent

/// Maps a global `AppSheet` to its sheet content.
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

// MARK: - PopupHost

/// Shows the current `AppPopup` centred over a dimmed background with a fade-and-scale animation.
struct PopupHost: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            if let popup = router.popup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                popupContent(popup)
                    .padding(.horizontal, 28)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: router.popup)
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

// MARK: - TopMessageHost

/// Shows in-app notification banners and toasts at the top of the screen.
struct TopMessageHost: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 8) {
            if let banner = router.banner {
                NotificationBannerView(title: banner.title, message: banner.message) {
                    router.openBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let toast = router.toast {
                ToastView(text: toast.text)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .animation(.spring(duration: 0.4), value: router.banner)
        .animation(.spring(duration: 0.4), value: router.toast)
    }
}

// MARK: - Previews

#Preview {
    MainTabView()
        .previewEnvironment()
}
