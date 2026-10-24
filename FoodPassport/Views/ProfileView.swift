import SwiftUI

/// The Profile tab: the student's details, totals and settings.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    /// Saved on the phone. FoodPassportApp reads it to switch the app to dark mode.
    @AppStorage(AppearanceSetting.darkModeKey) private var isDarkModeOn = false

    @State private var isShowingReminderSheet = false
    @State private var isConfirmingReset = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header

                HStack(spacing: Theme.Spacing.s) {
                    StatTile(value: "\(appState.visits.count)", label: "Visits", systemImage: "fork.knife")
                    StatTile(value: "\(appState.cuisinesTriedCount)", label: "Cuisines", systemImage: "globe.asia.australia.fill", valueColor: Theme.green)
                    StatTile(value: "\(appState.stamps.count)", label: "Stamps", systemImage: "seal.fill")
                }

                settingsSection("Budget") {
                    Button {
                        router.sheet = .monthlyBudget
                    } label: {
                        SettingsRow(systemImage: "creditcard.fill", tint: Theme.orange, title: "Monthly budget") {
                            SettingsValue(appState.profile.monthlyBudget.lkr)
                        }
                    }
                    .buttonStyle(.plain)
                }

                settingsSection("Reminders") {
                    SettingsToggleRow(
                        systemImage: "bell.fill",
                        tint: .red,
                        title: "Planned visits",
                        isOn: asyncBinding(appState.plannedVisitRemindersEnabled, set: appState.setPlannedVisitReminders)
                    )

                    SettingsDivider()
                    SettingsToggleRow(
                        systemImage: "clock.fill",
                        tint: .purple,
                        title: "Weekly challenge",
                        isOn: asyncBinding(appState.weeklyChallengeReminderEnabled, set: appState.setWeeklyChallengeReminder)
                    )

                    if appState.weeklyChallengeReminderEnabled {
                        SettingsDivider()
                        Button {
                            isShowingReminderSheet = true
                        } label: {
                            SettingsRow(systemImage: nil, title: "Reminder time", titleColor: .secondary) {
                                SettingsValue(appState.weeklyReminderTime.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: appState.weeklyChallengeReminderEnabled)

                settingsSection("Privacy & display") {
                    SettingsToggleRow(
                        systemImage: appState.biometryKind.systemImage,
                        tint: Theme.green,
                        title: "Unlock with \(appState.biometryKind.name)",
                        isOn: asyncBinding(appState.isFaceIDEnabled, set: appState.setFaceIDEnabled)
                    )

                    SettingsDivider()
                    SettingsToggleRow(
                        systemImage: isDarkModeOn ? "moon.fill" : "sun.max.fill",
                        tint: .indigo,
                        title: "Dark mode",
                        isOn: $isDarkModeOn
                    )

                    SettingsDivider()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(systemImage: "location.fill", tint: .blue, title: "Location access") {
                            SettingsValue(appState.locationPermission.label)
                        }
                    }
                    .buttonStyle(.plain)
                }

                settingsSection(nil) {
                    NavigationLink(value: AppRoute.about) {
                        SettingsRow(systemImage: "info", tint: Theme.mutedInk, title: "About FoodPassport") {
                            SettingsValue(nil)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()
                    Button {
                        isConfirmingSignOut = true
                    } label: {
                        SettingsRow(systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.mutedInk, title: "Sign out") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()
                    Button {
                        isConfirmingReset = true
                    } label: {
                        SettingsRow(systemImage: "trash.fill", tint: Theme.destructive, title: "Reset all data", titleColor: Theme.destructive) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("Profile")
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: isDarkModeOn)
        .sheet(isPresented: $isShowingReminderSheet) {
            ReminderTimeSheet(time: appState.weeklyReminderTime) { newTime in
                Task { await appState.setWeeklyReminderTime(newTime) }
            }
        }
        .alert("Reset All Data?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                appState.resetAllData()
            }
        } message: {
            Text("This will permanently delete all your visits, stamps, and quest progress.")
        }
        .alert("Sign Out?", isPresented: $isConfirmingSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                router.reset()
                appState.signOut()
            }
        } message: {
            Text("You'll need to sign in again to see your passport.")
        }
    }

    /// A card of settings rows, with an optional heading.
    private func settingsSection<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title {
                SectionCaption(title)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content()
            }
            .settingsCard()
        }
    }

    /// For switches that need to ask first (Face ID or notifications).
    /// The switch only stays on if AppState says yes.
    private func asyncBinding(_ value: Bool, set: @escaping (Bool) async -> Void) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in Task { await set(newValue) } }
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            InitialsAvatar(initials: appState.profile.initials, size: 92, background: Theme.orange, foreground: .white)
                .padding(5)
                .overlay { Circle().strokeBorder(Theme.primaryGradient, lineWidth: 2.5) }
                .shadow(color: Theme.orange.opacity(0.25), radius: 14, y: 6)
                .padding(.bottom, 4)

            Text(appState.profile.name)
                .font(.title.bold())
                .foregroundStyle(Theme.ink)

            Label("Member since \(appState.profile.memberSince.formatted(.dateTime.month(.abbreviated).year()))", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A settings row: coloured icon, title, and something on the right (like a value).
struct SettingsRow<Accessory: View>: View {
    let systemImage: String?
    var tint: Color = Theme.mutedInk
    let title: String
    var titleColor: Color = Theme.ink
    let accessory: Accessory

    init(
        systemImage: String?,
        tint: Color = Theme.mutedInk,
        title: String,
        titleColor: Color = Theme.ink,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.titleColor = titleColor
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                IconTile(systemImage: systemImage, tint: tint, size: 30, isFilled: true)
            } else {
                // Empty space, so the title lines up with rows that have an icon.
                Color.clear
                    .frame(width: 30, height: 30)
            }

            Text(title)
                .foregroundStyle(titleColor)

            Spacer(minLength: 8)

            accessory
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    let systemImage: String
    var tint: Color = Theme.mutedInk
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                IconTile(systemImage: systemImage, tint: tint, size: 30, isFilled: true)
                Text(title)
                    .foregroundStyle(Theme.ink)
            }
        }
        .tint(Theme.green)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }
}

/// Grey text with a ">" arrow.
struct SettingsValue: View {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            if let text {
                Text(text)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 60)
    }
}

extension View {
    /// The card that holds a group of settings rows.
    func settingsCard() -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardBackground()
    }
}

struct MonthlyBudgetSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 3000

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Monthly budget")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)

            Divider()

            AmountPresetPicker(presets: [3000, 5000, 8000], selection: $amount)

            VStack(alignment: .leading, spacing: 8) {
                SectionCaption("Amount limit")
                CurrencyField(amount: $amount, background: Theme.insetFill)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.brandSecondary)
                Button("Save") {
                    appState.updateMonthlyBudget(amount)
                    dismiss()
                }
                .buttonStyle(.brandPrimary)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .onAppear { amount = appState.profile.monthlyBudget }
        .fittedSheetHeight()
        .brandSheetStyle()
    }
}

struct ReminderTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let time: Date
    let onSave: (Date) -> Void
    @State private var draft = Date.now

    var body: some View {
        VStack(spacing: 16) {
            Text("Reminder time")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Divider()

            DatePicker("Reminder time", selection: $draft, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.brandSecondary)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.brandPrimary)
            }
        }
        .padding(24)
        .onAppear { draft = time }
        .fittedSheetHeight()
        .brandSheetStyle()
    }
}

struct AboutView: View {
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AppLogo(size: 96)
                    .padding(.top, 16)

                VStack(spacing: 4) {
                    Text("FoodPassport")
                        .font(.title.bold())
                        .foregroundStyle(Theme.ink)
                    Text("Version \(appVersion)")
                        .foregroundStyle(.secondary)
                }

                Text("FoodPassport turns food exploration into a budget-friendly challenge for university students. Discover new cuisines around campus, earn stamps for verified visits and keep your monthly food spending on track.")
                    .foregroundStyle(Theme.ink)
                    .cardStyle(padding: 20)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow("map", "Find affordable food spots near campus")
                    featureRow("checkmark.seal", "Earn stamps for location-verified visits")
                    featureRow("chart.bar", "Track spending against your budget")
                    featureRow("lock.shield", "Meal and receipt scanning runs on your device")
                }
                .cardStyle(padding: 20)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, size: 36)
            Text(text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Previews

#Preview {
    ProfileView()
        .previewInNavigationStack()
}

#Preview {
    VStack(spacing: 0) {
        SettingsRow(systemImage: "creditcard", title: "Monthly budget") { SettingsValue("LKR 3,000") }
        SettingsDivider()
        SettingsToggleRow(systemImage: "bell", title: "Planned-visit reminders", isOn: .constant(true))
    }
    .settingsCard()
    .padding()
    .appBackground()
}

#Preview {
    Text("Profile")
        .sheet(isPresented: .constant(true)) {
            MonthlyBudgetSheet()
        }
        .previewEnvironment()
}

#Preview {
    Text("Profile")
        .sheet(isPresented: .constant(true)) {
            ReminderTimeSheet(time: .now) { _ in }
        }
}

#Preview {
    AboutView()
        .previewInNavigationStack()
}
