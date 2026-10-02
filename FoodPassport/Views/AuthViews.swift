import SwiftUI

// MARK: - AuthHeader

/// Logo, title and subtitle shared by the Sign in and Sign up screens.
struct AuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppLogo(size: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SignInView

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var email = ""
    @State private var password = ""
    @State private var isShowingForgotPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AuthHeader(title: "Welcome back", subtitle: "Sign in to continue your food quest.")

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Email")
                    InputField(placeholder: "you@university.lk", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Password")
                    SecureInputField(placeholder: "Password", text: $password)

                    Button("Forgot password?") { isShowingForgotPassword = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }

                Button("Sign in") {
                    router.reset()
                    appState.enterApp()
                }
                .buttonStyle(.brandPrimary)

                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    NavigationLink("Sign up", value: OnboardingRoute.signUp)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.orange)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingForgotPassword) {
            ForgotPasswordView()
        }
    }
}

// MARK: - SignUpView

struct SignUpView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuthHeader(title: "Create account", subtitle: "Start collecting cuisine stamps around campus.")

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Full name")
                    InputField(placeholder: "John Doe", text: $name)
                        .textContentType(.name)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("University email")
                    InputField(placeholder: "you@university.lk", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Password")
                    SecureInputField(placeholder: "At least 8 characters", text: $password)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption("Confirm password")
                    SecureInputField(placeholder: "Re-enter password", text: $confirmPassword)
                }

                NavigationLink(value: OnboardingRoute.permissions) {
                    Text("Create account")
                }
                .buttonStyle(.brandPrimary)
                .padding(.top, 4)

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(.secondary)
                    NavigationLink("Sign in", value: OnboardingRoute.signIn)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.orange)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ForgotPasswordView

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLinkSent = false

    var body: some View {
        VStack(spacing: 20) {
            if isLinkSent {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.orange)
                    .padding(.top, 8)

                Text("Check your inbox")
                    .font(.title2.bold())

                Text("We've sent a password reset link to \(email.isEmpty ? "your email" : email).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Done") { dismiss() }
                    .buttonStyle(.brandPrimary)
            } else {
                Text("Reset password")
                    .font(.title2.bold())

                Text("Enter the email you signed up with and we'll send you a link to reset your password.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                InputField(placeholder: "you@university.lk", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Send reset link") {
                    withAnimation { isLinkSent = true }
                }
                .buttonStyle(.brandPrimary)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sheetBackground)
    }
}

// MARK: - FaceIDLockView

/// Shown over the app when it returns from the background and "Unlock with Face ID" is on.
struct FaceIDLockView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            AppLogo(size: 80)

            VStack(spacing: 8) {
                Text("FoodPassport is locked")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Your visits and spending stay private. Unlock to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.unlock()
            } label: {
                Image(systemName: "faceid")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.orange)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 104, height: 104)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unlock with Face ID")

            Text("Tap to unlock with Face ID")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Unlock with Face ID") { appState.unlock() }
                .buttonStyle(.brandPrimary)

            Button("Use account password") {
                router.reset()
                router.onboardingPath = [.signIn]
                appState.signOut()
            }
            .buttonStyle(BrandTextButtonStyle(color: .secondary))
        }
        .padding(24)
        .appBackground()
    }
}

// MARK: - Previews

#Preview {
    AuthHeader(title: "Welcome back", subtitle: "Sign in to continue your food quest.")
}

#Preview {
    NavigationStack {
        SignInView()
    }
    .previewEnvironment()
}

#Preview {
    NavigationStack {
        SignUpView()
    }
    .previewEnvironment()
}

#Preview {
    Text("Sign in")
        .sheet(isPresented: .constant(true)) {
            ForgotPasswordView()
        }
}

#Preview {
    FaceIDLockView()
        .previewEnvironment()
}
