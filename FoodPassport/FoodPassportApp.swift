import SwiftUI

// MARK: - FoodPassportApp

@main
struct FoodPassportApp: App {
    @State private var appState = AppState()
    @State private var router = AppRouter()

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

/// Decides which top-level flow is on screen: onboarding/auth, the main tabs, or the Face ID lock.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch appState.stage {
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appState.lockIfNeeded()
            }
        }
    }
}

// MARK: - Previews

#Preview {
    RootView()
        .previewEnvironment()
}
