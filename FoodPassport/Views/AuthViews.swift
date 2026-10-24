import SwiftUI

/// The logo and title at the top of Sign in and Sign up.
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

/// A red error message under a form.
struct FormErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(Theme.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var email = ""
    @State private var password = ""
    @State private var isShowingForgotPassword = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?

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

                if let errorMessage {
                    FormErrorText(message: errorMessage)
                }

                Button(action: signIn) {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel("Signing in")
                    } else {
                        Text("Sign in")
                    }
                }
                .buttonStyle(.brandPrimary)
                .disabled(isSigningIn || email.trimmed.isEmpty || password.isEmpty)

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

    /// Signs in, or shows what went wrong.
    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                try await appState.signIn(email: email.trimmed, password: password)
                router.reset()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

struct SignUpView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?

    /// Checks the form before sending it to Firebase, so simple mistakes show straight away.
    private var validationMessage: String? {
        if name.trimmed.isEmpty { return "Enter your full name." }
        if !email.trimmed.contains("@") { return "Enter a valid email address." }
        if password.count < 8 { return "Password must be at least 8 characters." }
        if password != confirmPassword { return "Passwords don't match." }
        return nil
    }

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

                if let errorMessage {
                    FormErrorText(message: errorMessage)
                }

                Button(action: createAccount) {
                    if isCreatingAccount {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel("Creating account")
                    } else {
                        Text("Create account")
                    }
                }
                .buttonStyle(.brandPrimary)
                .disabled(isCreatingAccount)
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

    /// Checks the form, creates the account, then moves on to permissions.
    private func createAccount() {
        if let validationMessage {
            errorMessage = validationMessage
            return
        }

        isCreatingAccount = true
        errorMessage = nil

        Task {
            do {
                try await appState.signUp(name: name.trimmed, email: email.trimmed, password: password)
                router.onboardingPath.append(.permissions)
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreatingAccount = false
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLinkSent = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if isLinkSent {
                PopupIcon(systemImage: "envelope.badge.fill")
                    .padding(.top, 8)

                Text("Check your inbox")
                    .font(.title2.bold())

                Text("We've sent a password reset link to \(email.isEmpty ? "your email" : email).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Done") { dismiss() }
                    .buttonStyle(.brandPrimary)
            } else {
                PopupIcon(systemImage: "key.fill")
                    .padding(.top, 8)

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

                if let errorMessage {
                    FormErrorText(message: errorMessage)
                }

                Button("Send reset link", action: sendResetLink)
                    .buttonStyle(.brandPrimary)
                    .disabled(isSending || email.trimmed.isEmpty)
            }
        }
        .padding(24)
        .fittedSheetHeight()
        .brandSheetStyle()
    }

    /// Emails a password reset link.
    private func sendResetLink() {
        isSending = true
        errorMessage = nil

        Task {
            do {
                try await appState.sendPasswordReset(email: email.trimmed)
                withAnimation { isLinkSent = true }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

/// Covers the app when it opens, if "Unlock with Face ID" is on.
struct FaceIDLockView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    /// Face ID pops up by itself once each time the app opens.
    /// After that the student taps to try again, so cancelling doesn't keep bringing it back.
    @State private var hasPromptedAutomatically = false
    @State private var isAuthenticating = false

    var body: some View {
        let biometryName = appState.biometryKind.name

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

            Button(action: unlock) {
                Image(systemName: appState.biometryKind.systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.orange)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 104, height: 104)
                    .surfaceBackground(Circle(), shadowStrength: 1.5)
            }
            .buttonStyle(.plain)
            .disabled(isAuthenticating)
            .accessibilityLabel("Unlock with \(biometryName)")

            if let lockMessage = appState.lockMessage {
                FormErrorText(message: lockMessage)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tap to unlock with \(biometryName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Unlock with \(biometryName)", action: unlock)
                .buttonStyle(.brandPrimary)
                .disabled(isAuthenticating)

            Button("Use account password") {
                router.reset()
                router.onboardingPath = [.signIn]
                appState.signOut()
            }
            .buttonStyle(BrandTextButtonStyle(color: .secondary))
        }
        .padding(24)
        .appBackground()
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active where !hasPromptedAutomatically:
                hasPromptedAutomatically = true
                unlock()
            case .background:
                hasPromptedAutomatically = false
            default:
                break
            }
        }
    }

    /// Shows the Face ID prompt.
    private func unlock() {
        isAuthenticating = true
        Task {
            await appState.unlockWithBiometrics()
            isAuthenticating = false
        }
    }
}

// Previews

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
