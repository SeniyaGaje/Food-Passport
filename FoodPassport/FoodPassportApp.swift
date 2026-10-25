import SwiftUI
import FirebaseCore

@main
struct FoodPassportApp: App {
    @UIApplicationDelegateAdaptor(PushService.self) private var pushService
    @State private var appState: AppState
    @State private var router = AppRouter()
    @AppStorage(AppearanceSetting.darkModeKey) private var isDarkModeOn = false

    init() {
        // Face ID, notifications and location are part of the phone, so they always use the real services.
        let biometrics = LocalBiometricService()
        let notifications = UserNotificationService()
        let location = CoreLocationService()

        // Use Firebase if GoogleService-Info.plist is in the project (see README).
        // Without it the app runs on sample data instead.
        #if DEBUG
        let isDemo = CommandLine.arguments.contains("--demo")
        #else
        let isDemo = false
        #endif
        if isDemo {
            let database = MockDatabaseService()
            database.quest = QuestSettings(startedAt: Calendar.current.startOfDay(for: .now))
            _appState = State(initialValue: AppState(auth: MockAuthService(signedInUserID: "demo-user"),
                database: database, notifications: notifications, widgets: AppWidgetPublisher()))
        } else if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
            _appState = State(initialValue: AppState(
                auth: FirebaseAuthService(),
                database: FirestoreDatabaseService(),
                biometrics: biometrics,
                notifications: notifications,
                location: location,
                photoStore: FirebaseVisitPhotoStore(),
                widgets: AppWidgetPublisher()
            ))
        } else {
            _appState = State(initialValue: AppState(biometrics: biometrics, notifications: notifications, location: location))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                // Light mode unless "Dark mode" is turned on in Profile.
                .preferredColorScheme(isDarkModeOn ? .dark : .light)
        }
    }
}

/// Picks what to show: loading, onboarding, the main tabs, or the Face ID lock screen.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var network = NetworkMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            switch appState.stage {
            case .launching:
                LaunchView()
            case .onboarding:
                OnboardingFlowView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }

            if appState.isLocked {
                FaceIDLockView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { DataStatusView() }
        .onChange(of: network.isOffline, initial: true) { _, offline in
            appState.updateConnectivity(isOffline: offline)
        }
        .onOpenURL { router.openWidgetURL($0) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: appState.stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: appState.isLocked)
        .task {
            await appState.restoreSession()
        }
        // Track whether the app is on screen, and lock it when it goes to the background.
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            appState.isAppActive = newPhase == .active
            if newPhase == .background {
                appState.lockIfNeeded()
            } else if newPhase == .active, appState.stage == .main, !appState.isLocked {
                Task { await appState.refreshData() }
            }
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
            if appState.hasFailedWrites {
                Button("Retry changes") { appState.retryFailedWrites() }
            }
            if appState.stage == .onboarding {
                Button("Retry loading") { Task { await appState.refreshData() } }
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .alert("Notifications are off", isPresented: isShowingNotificationSettingsPrompt) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To get reminders, allow notifications for FoodPassport in Settings.")
        }
    }

    // Alerts need a true/false binding, so these turn AppState's values into one.

    private var isShowingNotificationSettingsPrompt: Binding<Bool> {
        Binding(
            get: { appState.isShowingNotificationSettingsPrompt },
            set: { appState.isShowingNotificationSettingsPrompt = $0 }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { isPresented in
                if !isPresented { appState.errorMessage = nil }
            }
        )
    }
}

/// Shown for a moment at launch while the passport loads.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 20) {
            AppLogo(size: 80)
            ProgressView()
                .accessibilityLabel("Loading your passport")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}

// Previews

#Preview {
    RootView()
        .previewEnvironment()
}
