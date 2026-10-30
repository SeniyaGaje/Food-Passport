import Testing
import Foundation
@testable import FoodPassport

/// Planned-visit and weekly reminders, using fake notifications that remember what was scheduled.
@Suite("Reminders")
@MainActor
struct AppStateReminderTests {

    // A visit time far enough away for its 30-minute reminder.
    private let inTwoHours = Date.now.addingTimeInterval(2 * 60 * 60)

    // Planned visits

    @Test("Planning a visit sets a reminder 30 minutes before it")
    func planVisitWithReminder() async {
        // Notifications are already allowed on the fake phone.
        let app = TestApp(notificationPermission: .allowed)

        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: true)

        #expect(reminderDate == inTwoHours.addingTimeInterval(-30 * 60))
        #expect(app.notifications.scheduledReminders.count == 1)
        // Planned-visit reminders have IDs starting with "visit-".
        #expect(app.notifications.scheduledReminders.first?.id.hasPrefix(LocalReminder.visitReminderIDPrefix) == true)
        #expect(app.appState.plannedVisitRemindersEnabled)
    }

    @Test("The first reminder asks for notification permission")
    func planVisitAsksPermission() async {
        // Permission not asked yet; the fake prompt will say Allow.
        let app = TestApp(notificationPermission: .notDetermined, allowsNotificationsWhenAsked: true)

        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: true)

        #expect(reminderDate != nil)
        #expect(app.notifications.scheduledReminders.count == 1)
    }

    @Test("No reminder when the visit is less than 30 minutes away")
    func visitTooSoon() async {
        let app = TestApp(notificationPermission: .allowed)

        // 20 minutes away: the reminder time (30 minutes before) has already passed.
        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: .now.addingTimeInterval(20 * 60), remind: true)

        #expect(reminderDate == nil)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    @Test("No reminder when Remind me is off")
    func remindMeOff() async {
        let app = TestApp(notificationPermission: .allowed)

        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: false)

        #expect(reminderDate == nil)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    @Test("If notifications were blocked earlier, the student is sent to Settings")
    func notificationsBlocked() async {
        // Notifications were refused earlier, so iOS won't ask again.
        let app = TestApp(notificationPermission: .denied)

        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: true)

        #expect(reminderDate == nil)
        #expect(app.appState.isShowingNotificationSettingsPrompt)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    @Test("Saying no to the permission prompt sets no reminder and doesn't nag")
    func permissionRefused() async {
        // The fake prompt will say Don't Allow.
        let app = TestApp(notificationPermission: .notDetermined, allowsNotificationsWhenAsked: false)

        let reminderDate = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: true)

        #expect(reminderDate == nil)
        // No Settings alert straight after they said no.
        #expect(!app.appState.isShowingNotificationSettingsPrompt)
    }

    @Test("Turning planned-visit reminders off cancels them but keeps the weekly reminder")
    func turnOffPlannedVisitReminders() async {
        let app = TestApp(notificationPermission: .allowed)
        _ = await app.appState.planVisit(to: MockData.campusBites, at: inTwoHours, remind: true)
        await app.appState.setWeeklyChallengeReminder(true)

        await app.appState.setPlannedVisitReminders(false)

        #expect(!app.appState.plannedVisitRemindersEnabled)
        // Only the weekly reminder is left.
        #expect(app.notifications.scheduledReminders.map(\.id) == [LocalReminder.weeklyChallengeID])
    }

    // Weekly challenge

    @Test("The weekly reminder is set for Monday at 9:00 by default")
    func weeklyReminderDefault() async {
        let app = TestApp(notificationPermission: .allowed)

        await app.appState.setWeeklyChallengeReminder(true)

        #expect(app.appState.weeklyChallengeReminderEnabled)
        // Weekday 2 is Monday.
        #expect(app.notifications.scheduledReminders.map(\.schedule) == [.weekly(weekday: 2, hour: 9, minute: 0)])
    }

    @Test("Changing the reminder time moves the weekly reminder and is remembered")
    func changeWeeklyReminderTime() async throws {
        let app = TestApp(notificationPermission: .allowed)
        await app.appState.setWeeklyChallengeReminder(true)
        let sixThirty = try #require(Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now))

        await app.appState.setWeeklyReminderTime(sixThirty)

        // Replaced, not added: there is still only one weekly reminder.
        #expect(app.notifications.scheduledReminders.map(\.schedule) == [.weekly(weekday: 2, hour: 18, minute: 30)])

        // Reopen the app: the new time is remembered.
        let relaunched = TestApp(relaunching: app)
        let time = Calendar.current.dateComponents([.hour, .minute], from: relaunched.appState.weeklyReminderTime)
        #expect(time.hour == 18)
        #expect(time.minute == 30)
    }

    @Test("Turning the weekly reminder off cancels it")
    func turnOffWeeklyReminder() async {
        let app = TestApp(notificationPermission: .allowed)
        await app.appState.setWeeklyChallengeReminder(true)

        await app.appState.setWeeklyChallengeReminder(false)

        #expect(!app.appState.weeklyChallengeReminderEnabled)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    // Onboarding and launch

    @Test("Allowing notifications during onboarding turns on both reminders")
    func allowDuringOnboarding() async {
        let app = TestApp(notificationPermission: .notDetermined, allowsNotificationsWhenAsked: true)

        let isAllowed = await app.appState.allowRemindersDuringOnboarding()

        #expect(isAllowed)
        #expect(app.appState.plannedVisitRemindersEnabled)
        #expect(app.appState.weeklyChallengeReminderEnabled)
        #expect(app.notifications.scheduledReminders.map(\.id) == [LocalReminder.weeklyChallengeID])
    }

    @Test("Refusing notifications during onboarding leaves the reminders off")
    func refuseDuringOnboarding() async {
        let app = TestApp(notificationPermission: .notDetermined, allowsNotificationsWhenAsked: false)

        let isAllowed = await app.appState.allowRemindersDuringOnboarding()

        #expect(!isAllowed)
        #expect(!app.appState.plannedVisitRemindersEnabled)
        #expect(!app.appState.weeklyChallengeReminderEnabled)
        #expect(app.notifications.scheduledReminders.isEmpty)
    }

    @Test("If notifications were turned off in Settings, the reminder switches show off after signing in")
    func switchesFollowSettings() async throws {
        let before = TestApp(notificationPermission: .allowed)
        await before.appState.setWeeklyChallengeReminder(true)

        // Reopen with notifications now turned off in Settings.
        let after = TestApp(notificationPermission: .denied, relaunching: before)
        // Before signing in, the saved switch is still on.
        #expect(after.appState.weeklyChallengeReminderEnabled)

        try await after.signIn()

        #expect(!after.appState.weeklyChallengeReminderEnabled)
        #expect(!after.appState.plannedVisitRemindersEnabled)
    }
}
