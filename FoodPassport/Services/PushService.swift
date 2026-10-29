import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import CryptoKit
import UserNotifications

/// SwiftUI forwards APNs callbacks here. UserNotificationService handles notification taps.
final class PushService: NSObject, UIApplicationDelegate, MessagingDelegate {
    private var authListener: AuthStateDidChangeListenerHandle?
    private var registeredPath: String?
    private var token: String?
    private var previousUserID: String?
    private var sessionGeneration = 0

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard FirebaseApp.app() != nil else { return true }
        Messaging.messaging().delegate = self
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let userID = user?.uid
            Task { @MainActor in await self?.accountChanged(to: userID) }
        }
        return true
    }

    private func accountChanged(to userID: String?) async {
        sessionGeneration += 1
        let generation = sessionGeneration
        let changedAccount = previousUserID != nil && previousUserID != userID
        previousUserID = userID
        registeredPath = nil
        if userID == nil || changedAccount {
            token = nil
            Messaging.messaging().isAutoInitEnabled = false
            // Invalidating the token also prevents an old account's registration being used.
            try? await Messaging.messaging().deleteToken()
        }
        guard generation == sessionGeneration, userID != nil else { return }
        let permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard permission == .authorized || permission == .provisional else { return }
        Messaging.messaging().isAutoInitEnabled = true
        token = try? await Messaging.messaging().token()
        guard generation == sessionGeneration else { return }
        await saveToken()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
        Task { await accountChanged(to: Auth.auth().currentUser?.uid) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator push still works through simctl; real APNs needs a provisioned device.
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.token = fcmToken
            await self.saveToken()
        }
    }

    private func saveToken() async {
        guard let token, let userID = Auth.auth().currentUser?.uid else { return }
        let id = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let path = "users/\(userID)/devices/\(id)"
        guard registeredPath != path else { return }
        do {
            try await Firestore.firestore().document(path).setData([
                "token": token, "platform": "ios", "updatedAt": FieldValue.serverTimestamp()
            ])
            if Auth.auth().currentUser?.uid == userID { registeredPath = path }
        } catch {
            // Registration retries on the next token refresh or app launch.
        }
    }
}
