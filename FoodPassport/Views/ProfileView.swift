import SwiftUI

// MARK: - ProfileView

/// Profile tab: account summary, lifetime stats and settings.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var plannedVisitReminders = true
    @State private var weeklyChallengeReminder = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var isShowingReminderSheet = false
    @State private var isConfirmingReset = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(spacing: 20) {
                header

                HStack(spacing: 12) {
                    StatTile(value: "\(appState.visits.count)", label: "Visits")
                    StatTile(value: "\(appState.cuisinesTriedCount)", label: "Cuisines", valueColor: Theme.green)
                    StatTile(value: "\(appState.stamps.count)", label: "Stamps")
                }

                VStack(spacing: 0) {
                    Button {
                        router.sheet = .monthlyBudget
                    } label: {
                        SettingsRow(systemImage: "creditcard", title: "Monthly budget") {
                            SettingsValue(appState.profile.monthlyBudget.lkr)
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()
                    SettingsToggleRow(systemImage: "bell", title: "Planned-visit reminders", isOn: $plannedVisitReminders)

                    SettingsDivider()
                    SettingsToggleRow(systemImage: "clock", title: "Weekly challenge reminder", isOn: $weeklyChallengeReminder)

                    if weeklyChallengeReminder {
                        SettingsDivider()
                        Button {
                            isShowingReminderSheet = true
                        } label: {
                            SettingsRow(systemImage: nil, title: "Reminder time", titleColor: .secondary) {
                                SettingsValue(reminderTime.formatted(date: .omitted, time: .shortened))
                            }
                            .background(Color(hex: 0xF6F6F7))
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsDivider()
                    SettingsToggleRow(systemImage: "faceid", title: "Unlock with Face ID", isOn: $appState.isFaceIDEnabled)

                    SettingsDivider()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(systemImage: "location", title: "Location access") {
                            SettingsValue("While Using")
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()
                    NavigationLink(value: AppRoute.about) {
                        SettingsRow(systemImage: "info.circle", title: "About FoodPassport") {
                            SettingsValue(nil)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()
                .animation(.easeInOut(duration: 0.2), value: weeklyChallengeReminder)

                VStack(spacing: 0) {
                    Button {
                        isConfirmingSignOut = true
                    } label: {
                        SettingsRow(systemImage: "rectangle.portrait.and.arrow.right", title: "Sign out") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()
                    Button {
                        isConfirmingReset = true
                    } label: {
                        SettingsRow(systemImage: "trash", title: "Reset all data", titleColor: Theme.destructive) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .appBackground()
        .navigationTitle("Profile")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingReminderSheet) {
            ReminderTimeSheet(time: $reminderTime)
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

    private var header: some View {
        VStack(spacing: 8) {
            InitialsAvatar(initials: appState.profile.initials, size: 96, background: Theme.orange)

            Text(appState.profile.name)
                .font(.title.bold())
                .foregroundStyle(Theme.ink)

            Text("Member since \(appState.profile.memberSince.formatted(.dateTime.month(.abbreviated).year()))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SettingsRow

/// A settings row with an icon, title and trailing accessory (value, chevron, etc.).
struct SettingsRow<Accessory: View>: View {
    let systemImage: String?
    let title: String
    var titleColor: Color = Theme.ink
    let accessory: Accessory

    init(systemImage: String?, title: String, titleColor: Color = Theme.ink, @ViewBuilder accessory: () -> Accessory) {
        self.systemImage = systemImage
        self.title = title
        self.titleColor = titleColor
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 28)

            Text(title)
                .foregroundStyle(titleColor)

            Spacer()

            accessory
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let systemImage: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(Theme.ink)
            }
        }
        .tint(Theme.green)
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }
}

// MARK: - SettingsValue

/// Grey value text followed by a chevron.
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

// MARK: - SettingsDivider

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 60)
    }
}

// MARK: - View

extension View {
    /// White rounded container that groups settings rows.
    func settingsCard() -> some View {
        self
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - MonthlyBudgetSheet

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
                CurrencyField(amount: $amount, background: Color(hex: 0xF6F6F7))
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.brandSecondary)
                Button("Save") {
                    appState.profile.monthlyBudget = amount
                    dismiss()
                }
                .buttonStyle(.brandPrimary)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .onAppear { amount = appState.profile.monthlyBudget }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - ReminderTimeSheet

struct ReminderTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var time: Date
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
                    time = draft
                    dismiss()
                }
                .buttonStyle(.brandPrimary)
            }
        }
        .padding(24)
        .onAppear { draft = time }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - AboutView

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
        Label {
            Text(text)
                .foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.orange)
        }
    }
}

// MARK: - Previews

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
            ReminderTimeSheet(time: .constant(.now))
        }
}

#Preview {
    AboutView()
        .previewInNavigationStack()
}
