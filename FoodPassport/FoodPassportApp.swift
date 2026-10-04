import SwiftUI
import FirebaseCore

// MARK: - FoodPassportApp

@main
struct FoodPassportApp: App {
    @State private var appState: AppState
    @State private var router = AppRouter()

    init() {
        // Use Firebase once GoogleService-Info.plist has been added to the project (see README).
        // Without it the app runs on mock data, so it still builds and runs before Firebase is set up.
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
            _appState = State(initialValue: AppState(auth: FirebaseAuthService(), database: FirestoreDatabaseService()))
        } else {
            _appState = State(initialValue: AppState())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                // The prototype is designed for light mode only.
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - RootView

/// Decides which top-level flow is on screen: launch, onboarding/auth, the main tabs, or the Face ID lock.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

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
        .animation(.easeInOut(duration: 0.3), value: appState.stage)
        .animation(.easeInOut(duration: 0.25), value: appState.isLocked)
        .task {
            await appState.restoreSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appState.lockIfNeeded()
            }
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
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

// MARK: - LaunchView

/// Shown briefly at launch while the signed-in user's passport loads.
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

// MARK: - Previews

#Preview {
    RootView()
        .previewEnvironment()
}
