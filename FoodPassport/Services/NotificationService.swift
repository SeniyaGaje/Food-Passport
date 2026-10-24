import Foundation
import UserNotifications

enum NotificationPermission: Equatable {
    case notDetermined
    case allowed
    case denied
}

/// Which screen to open when the student taps a notification.
enum NotificationDestination: Equatable {
    case restaurant(id: Restaurant.ID)
    /// The "You've arrived" alert opens Log your visit.
    case logVisit(restaurantID: Restaurant.ID)
    case weeklyChallenge

    /// Saved inside the notification, so we know where to go when it's tapped.
    var userInfo: [String: String] {
        switch self {
        case .restaurant(let id): ["destination": "restaurant", "restaurantID": id]
        case .logVisit(let id): ["destination": "logVisit", "restaurantID": id]
        case .weeklyChallenge: ["destination": "weeklyChallenge"]
        }
    }

    init?(destination: String?, restaurantID: String?) {
        switch destination {
        case "restaurant":
            guard let restaurantID else { return nil }
            self = .restaurant(id: restaurantID)
        case "logVisit":
            guard let restaurantID else { return nil }
            self = .logVisit(restaurantID: restaurantID)
        case "weeklyChallenge":
            self = .weeklyChallenge
        default:
            return nil
        }
    }
}

/// A reminder to schedule on the phone, e.g. "Your visit is in 30 minutes".
struct LocalReminder: Equatable {
    enum Schedule: Equatable {
        /// Show it now (the arrival alert).
        case immediately
        /// Show it once, at this time.
        case once(Date)
        /// Repeat every week. Weekday 1 is Sunday, 2 is Monday.
        case weekly(weekday: Int, hour: Int, minute: Int)
    }

    let id: String
    let title: String
    let body: String
    let schedule: Schedule
    let destination: NotificationDestination

    static let visitReminderIDPrefix = "visit-"
    static let weeklyChallengeID = "weekly-challenge"
    static let arrivalIDPrefix = "arrival-"

    /// The reminder comes 30 minutes before a planned visit.
    static let visitReminderLeadTime: TimeInterval = 30 * 60

    /// "Your visit to Campus Bites is in 30 minutes".
    static func plannedVisit(to restaurant: Restaurant, at visitDate: Date) -> LocalReminder {
        LocalReminder(
            id: "\(visitReminderIDPrefix)\(restaurant.id)-\(Int(visitDate.timeIntervalSince1970))",
            title: "Your visit to \(restaurant.name) is in 30 minutes 🍽️",
            body: "Log it when you arrive to earn your \(restaurant.cuisine.rawValue) stamp.",
            schedule: .once(visitDate.addingTimeInterval(-visitReminderLeadTime)),
            destination: .restaurant(id: restaurant.id)
        )
    }

    /// Sent when the student walks up to a restaurant while the app is closed.
    static func arrival(at restaurant: Restaurant) -> LocalReminder {
        LocalReminder(
            id: "\(arrivalIDPrefix)\(restaurant.id)",
            title: "You've arrived at \(restaurant.name)! 📍",
            body: "Log your visit now to earn a stamp and level up your \(restaurant.cuisine.rawValue) quest.",
            schedule: .immediately,
            destination: .logVisit(restaurantID: restaurant.id)
        )
    }

    /// Every Monday at the time chosen in Profile.
    static func weeklyChallenge(hour: Int, minute: Int) -> LocalReminder {
        LocalReminder(
            id: weeklyChallengeID,
            title: "New weekly challenge! 🌍",
            body: "Try a cuisine you haven't logged yet and earn a new stamp.",
            schedule: .weekly(weekday: 2, hour: hour, minute: minute),
            destination: .weeklyChallenge
        )
    }
}

/// Asks for notification permission and schedules reminders.
/// AppState only uses this protocol, so tests can use the mock instead of real notifications.
protocol NotificationService: AnyObject {
    /// Runs when the student taps one of our notifications.
    var onOpen: ((NotificationDestination) -> Void)? { get set }

    func permission() async -> NotificationPermission

    /// Asks the first time. Returns true if notifications are allowed.
    func requestPermission() async -> Bool

    /// Adds the reminder. One with the same ID is replaced.
    func schedule(_ reminder: LocalReminder) async throws

    func cancelReminders(withIDPrefix prefix: String) async
    func cancelAllReminders()
}

/// Real notifications, using Apple's UserNotifications.
/// It's also the delegate, so it shows banners while the app is open and handles taps.
final class UserNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate {
    var onOpen: ((NotificationDestination) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // Set early, so a tap that opens the app isn't missed.
        center.delegate = self
    }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(_ reminder: LocalReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = reminder.destination.userInfo

        let trigger: UNNotificationTrigger?
        switch reminder.schedule {
        case .immediately:
            trigger = nil
        case .once(let date):
            let dateParts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: dateParts, repeats: false)
        case .weekly(let weekday, let hour, let minute):
            let dateParts = DateComponents(hour: hour, minute: minute, weekday: weekday)
            trigger = UNCalendarNotificationTrigger(dateMatching: dateParts, repeats: true)
        }

        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    func cancelReminders(withIDPrefix prefix: String) async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    // UNUserNotificationCenterDelegate

    /// Show the banner even when the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// The student tapped a notification: tell the app which screen to open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let destinationName = userInfo["destination"] as? String
        let restaurantID = userInfo["restaurantID"] as? String

        Task { @MainActor in
            if let destination = NotificationDestination(destination: destinationName, restaurantID: restaurantID) {
                self.onOpen?(destination)
            }
        }
        completionHandler()
    }
}

/// Fake notifications for previews and tests. Keeps a list of what was scheduled.
final class MockNotificationService: NotificationService {
    var onOpen: ((NotificationDestination) -> Void)?
    var currentPermission: NotificationPermission
    /// What the student taps when asked for permission.
    var allowsWhenAsked: Bool
    private(set) var scheduledReminders: [LocalReminder] = []

    init(permission: NotificationPermission = .notDetermined, allowsWhenAsked: Bool = true) {
        currentPermission = permission
        self.allowsWhenAsked = allowsWhenAsked
    }

    func permission() async -> NotificationPermission {
        currentPermission
    }

    func requestPermission() async -> Bool {
        if currentPermission == .notDetermined {
            currentPermission = allowsWhenAsked ? .allowed : .denied
        }
        return currentPermission == .allowed
    }

    func schedule(_ reminder: LocalReminder) async throws {
        scheduledReminders.removeAll { $0.id == reminder.id }
        scheduledReminders.append(reminder)
    }

    func cancelReminders(withIDPrefix prefix: String) async {
        scheduledReminders.removeAll { $0.id.hasPrefix(prefix) }
    }

    func cancelAllReminders() {
        scheduledReminders = []
    }
}
