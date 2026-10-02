import SwiftUI

// MARK: - OnboardingFlowView

/// Navigation stack for Welcome → Sign up / Sign in → Permissions → Budget setup.
struct OnboardingFlowView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.onboardingPath) {
            WelcomeView()
                .navigationDestination(for: OnboardingRoute.self) { route in
                    OnboardingDestination(route: route)
                }
        }
        .tint(Theme.orange)
    }
}

// MARK: - OnboardingDestination

private struct OnboardingDestination: View {
    let route: OnboardingRoute

    var body: some View {
        switch route {
        case .signIn: SignInView()
        case .signUp: SignUpView()
        case .permissions: PermissionsView()
        case .budgetSetup: BudgetSetupView()
        }
    }
}

// MARK: - WelcomeView

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack(alignment: .bottom) {
                FoodImageView(imageName: "welcome_hero", cuisine: .sriLankan)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 240)
                    }
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    NavigationLink(value: OnboardingRoute.signUp) {
                        Text("Get started")
                    }
                    .buttonStyle(.brandPrimary)

                    NavigationLink(value: OnboardingRoute.signIn) {
                        Text("I already have an account")
                    }
                    .buttonStyle(BrandTextButtonStyle(color: .white))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppLogo(size: 84)

            Text("FoodPassport")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text("Every new cuisine is a new stamp")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background {
            LinearGradient(colors: [Color(hex: 0xFFC9A6), Color(hex: 0xFCE3D4)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - PermissionsView

/// "Before we begin" — explains each permission before it is requested.
struct PermissionsView: View {
    @Environment(AppRouter.self) private var router
    @State private var grantedPermissions: Set<OnboardingPermission> = []

    private var nextPermission: OnboardingPermission? {
        OnboardingPermission.allCases.first { !grantedPermissions.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before we begin")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)

            Text("FoodPassport works best with these permissions. You can change them anytime in Settings.")
                .foregroundStyle(.secondary)

            ForEach(OnboardingPermission.allCases) { permission in
                PermissionCard(permission: permission, isGranted: grantedPermissions.contains(permission))
            }

            Spacer()

            if let nextPermission {
                Button(nextPermission.buttonTitle) {
                    // UI only: the real system permission request is added with each feature.
                    withAnimation { _ = grantedPermissions.insert(nextPermission) }
                }
                .buttonStyle(.brandPrimary)

                Button("Continue") { router.onboardingPath.append(.budgetSetup) }
                    .buttonStyle(BrandTextButtonStyle(color: .secondary))
            } else {
                Button("Continue") { router.onboardingPath.append(.budgetSetup) }
                    .buttonStyle(.brandPrimary)
            }
        }
        .padding(24)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - OnboardingPermission

private enum OnboardingPermission: CaseIterable, Identifiable {
    case location
    case notifications
    case camera

    var id: Self { self }

    var title: String {
        switch self {
        case .location: "Location access"
        case .notifications: "Notifications"
        case .camera: "Camera"
        }
    }

    var message: String {
        switch self {
        case .location: "We verify your visits to earn stamps and track nearby food spots around campus."
        case .notifications: "Get reminders for planned visits, quest deadlines and new weekly challenges."
        case .camera: "Scan your meal and receipt. Photos are processed on your device."
        }
    }

    var systemImage: String {
        switch self {
        case .location: "mappin.and.ellipse"
        case .notifications: "bell"
        case .camera: "camera"
        }
    }

    var tint: Color {
        switch self {
        case .location: Theme.orange
        case .notifications: Theme.green
        case .camera: .blue
        }
    }

    var buttonTitle: String {
        switch self {
        case .location: "Allow location"
        case .notifications: "Allow notifications"
        case .camera: "Allow camera"
        }
    }
}

// MARK: - PermissionCard

private struct PermissionCard: View {
    let permission: OnboardingPermission
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: permission.systemImage)
                .font(.title2)
                .foregroundStyle(permission.tint)
                .frame(width: 56, height: 56)
                .background(permission.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(permission.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(permission.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed yet")
    }
}

// MARK: - BudgetSetupView

/// Last onboarding step: set a monthly food budget.
struct BudgetSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var budget = 3000

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set your monthly food budget")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)

            Text("We'll plan quests that help you try new cuisines without overspending.")
                .foregroundStyle(.secondary)

            AmountPresetPicker(presets: [3000, 5000, 8000], selection: $budget)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                SectionCaption("Amount limit")
                CurrencyField(amount: $budget)
            }

            Text("You can change this anytime in Profile.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Start exploring") {
                appState.profile.monthlyBudget = budget
                router.reset()
                appState.enterApp()
            }
            .buttonStyle(.brandPrimary)
        }
        .padding(24)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    OnboardingFlowView()
        .previewEnvironment()
}

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .previewEnvironment()
}

#Preview {
    NavigationStack {
        PermissionsView()
    }
    .previewEnvironment()
}

#Preview {
    NavigationStack {
        BudgetSetupView()
    }
    .previewEnvironment()
}
