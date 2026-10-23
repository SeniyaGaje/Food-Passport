import SwiftUI

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

struct WelcomeView: View {
    /// The app name grows with the student's text size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40

    /// Colours of the header band; the photo fades into the lower one.
    private let headerTop = Color(light: 0xFFC9A6, dark: 0x2B1B12)
    private let headerBottom = Color(light: 0xFCE3D4, dark: 0x1A1513)

    var body: some View {
        // The photo fills the whole screen on every iPhone; the header and buttons sit on top of it.
        FoodImageView(imageName: "welcome_hero", cuisine: .sriLankan)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                header
            }
            .overlay(alignment: .bottom) {
                buttons
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                AppLogo(size: 84)

                Text("FoodPassport")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("Every new cuisine is a new stamp")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .padding(.horizontal, Theme.screenMargin)
            .background {
                LinearGradient(colors: [headerTop, headerBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            }

            // The text sits on a solid band; below it the band fades into the photo instead of a hard edge.
            LinearGradient(colors: [headerBottom, headerBottom.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
                .allowsHitTesting(false)
        }
    }

    private var buttons: some View {
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
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, 80)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// "Before we begin" — explains each permission before it is requested.
struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    /// The student's answer for each permission asked so far: true if allowed.
    @State private var answers: [OnboardingPermission: Bool] = [:]

    private var nextPermission: OnboardingPermission? {
        OnboardingPermission.allCases.first { answers[$0] == nil }
    }

    var body: some View {
        // Scrolls on smaller iPhones or with large text; the buttons stay pinned at the bottom.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before we begin")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("FoodPassport works best with these permissions. You can change them anytime in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(OnboardingPermission.allCases) { permission in
                    PermissionCard(permission: permission, isGranted: answers[permission] == true)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if let nextPermission {
                    Button(nextPermission.buttonTitle) { ask(for: nextPermission) }
                        .buttonStyle(.brandPrimary)

                    Button("Continue") { router.onboardingPath.append(.budgetSetup) }
                        .buttonStyle(BrandTextButtonStyle(color: .secondary))
                } else {
                    Button("Continue") { router.onboardingPath.append(.budgetSetup) }
                        .buttonStyle(.brandPrimary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask(for permission: OnboardingPermission) {
        switch permission {
        case .notifications:
            Task {
                let isAllowed = await appState.allowRemindersDuringOnboarding()
                withAnimation { answers[.notifications] = isAllowed }
            }
        case .location:
            Task {
                let isAllowed = await appState.requestLocationPermission()
                withAnimation { answers[.location] = isAllowed }
            }
        case .camera:
            // UI only for now: the system prompt is added with the camera feature.
            withAnimation { answers[permission] = true }
        }
    }
}

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

private struct PermissionCard: View {
    let permission: OnboardingPermission
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(systemImage: permission.systemImage, tint: permission.tint, size: 52)

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
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.green.opacity(isGranted ? 0.6 : 0), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.25), value: isGranted)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed yet")
    }
}

/// Last onboarding step: set a monthly food budget.
struct BudgetSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var budget = 3000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Set your monthly food budget")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("We'll plan quests that help you try new cuisines without overspending.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AmountPresetPicker(presets: [3000, 5000, 8000], selection: $budget)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Amount limit")
                    CurrencyField(amount: $budget)
                }

                Label("You can change this anytime in Profile.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.updateMonthlyBudget(budget)
                router.reset()
                appState.enterApp()
            } label: {
                Label("Start exploring", systemImage: "arrow.right")
            }
            .buttonStyle(.brandPrimary)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: budget)
    }
}

// Previews

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
