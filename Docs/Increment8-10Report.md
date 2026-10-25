# Increments 8–10: implementation decisions and evidence

Date: 25 October 2026. This is an implementation record for the coursework report; assessment outcomes remain the lecturer's decision.

## Increment 8 — iPad and landscape (C5, LO1)

| Choice | Reason and resulting behaviour |
| --- | --- |
| Universal iPhone/iPad target, iOS 17 minimum | Reuses the same models, services and views across devices. Both landscape directions are supported; iPad also supports upside-down portrait. |
| `NavigationSplitView` at regular horizontal size | A persistent sidebar makes the five destinations visible on a wider display. Compact width uses the familiar tab bar. Width, rather than a device-name check, also supports narrow iPad windows. |
| Shared `AppRouter` | Each destination keeps its route stack when switching between tabs and the sidebar. Notification and widget links use the same routing model. |
| Explore map/list together when the detail area is at least 680 points wide | A student can compare prices and distance while seeing restaurant locations. Both views use the same search, cuisine filter and selected pin. Narrow detail areas and accessibility text sizes stack map and list; compact phones retain their Map/List switch. |
| Native scrolling, adaptive rows and Dynamic Type | Long names and larger text can grow vertically. Navigation and detail content remain usable after rotation. |

The app does not create a separate iPad data model. Account metadata is fetched from Firestore on launch or refresh, and meal photos are fetched from the same account's Storage folder.

## Increment 9 — cloud photos, remote push and widgets (C5)

### Firebase Storage for meal photos

`FirebaseVisitPhotoStore` implements the existing `VisitPhotoStore` protocol. The Firebase configuration selects this implementation; previews and explicitly selected demo mode use the local store.

Photos are resized to a maximum 1600-point side, encoded as JPEG, and uploaded to `users/{uid}/mealPhotos/{UUID}.jpg`. The visit stores IDs, not public download URLs. The Storage SDK authenticates each request and the rules restrict reads, uploads and deletion to that UID. Upload rules require JPEG MIME type, a bounded filename and a maximum 5 MB object. MIME validation does not inspect the actual image bytes.

Uploads complete before a visit receives photo references. If any upload fails, created objects are deleted where possible and cached files are removed; the student's unsaved form keeps its images for retry. Previously viewed photos load from the account's local cache offline. A new device downloads an image on demand. A missing photo offers Retry.

Deleting a visit or resetting visits deletes its images after the metadata deletion succeeds. Failed remote deletions are recorded in an account-specific persistent queue and retried when that account next loads its passport. If the deletion queue itself cannot be written, retry is limited to the current launch. Old photos created by the previous local-only implementation still need the original device; they are not automatically migrated to Storage.

**External setup:** enable the Storage bucket and publish `storage.rules`. Firebase's [current Storage requirements include the Blaze plan](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024). No billing setting was changed by this implementation. The SDK paths and rules were implemented and tested locally; live upload/download using this project's signed-in account still needs a configured bucket and deployed rules.

### Firebase Cloud Messaging / APNs

`PushService` is the SwiftUI application delegate. It assigns the Firebase Messaging delegate, explicitly passes the APNs device token to Messaging, and stores the FCM registration under `users/{uid}/devices/{SHA256(token)}`. The app never prints registration tokens. Automatic token creation is disabled until a signed-in user has allowed notifications. Token refresh updates registration. Account changes invalidate the old token where the network permits; token revocation remains best effort when offline. Stale server registrations should also be pruned by the sending service after FCM reports an invalid token.

`UserNotificationService` remains the single notification-centre delegate for local and remote alerts. Both payloads carry the same allowed destination names (`restaurant`, `logVisit`, `weeklyChallenge`), so a notification tap uses existing navigation. Invalid or incomplete destinations are ignored. Remote payloads should use generic challenge text, without private meal or spending data.

The app entitlement uses development APNs in Debug and production APNs in Release. These are **alert notifications**: no silent-push background work is claimed. No APNs private key, server key or service-account secret is bundled in the app.

**External setup and limitation:** real-device delivery needs Apple Developer membership with Push Notifications provisioning and an APNs key uploaded in Firebase; follow the [Firebase Apple-platform setup](https://firebase.google.com/docs/cloud-messaging/ios/get-started). The current environment does not establish that these credentials exist. Simulator injection exercises iOS display/routing, but does not prove FCM delivery, APNs credentials, device-token registration or delivery while a real device is offline.

### WidgetKit and App Group

A separate `FoodPassportWidgets` extension provides a small/medium Home Screen quest widget and circular/rectangular accessory budget widgets. Both targets declare `group.com.seniyagajadeera.FoodPassport`.

The app writes a small, atomic JSON snapshot into the App Group container and requests timeline reloads after visits, budget changes and quest changes. The extension reads this snapshot without loading Firebase, the classifier or meal photos. This keeps extension work small and makes widgets useful without a connection. iOS controls the final refresh schedule.

The quest widget uses saved quest choices and progress calculated from real visits. The budget widget shows this calendar month's spending divided by the monthly budget, with remaining money clamped at zero. The gauge fills at 100% for overspending; it does not display an invalid value above the gauge's range. A month rollover clears last month's spending, and an expired quest no longer appears active. If there is no active quest, the widget asks the student to create one.

Sign-out overwrites the shared snapshot with an empty one. WidgetKit controls when the rendered widget is refreshed; the app requests a reload rather than promising an immediate screen update. Face ID locking also hides personal widget values until unlocking. Widget views are marked privacy-sensitive. The snapshot contains no account email, images, tokens or credentials. Widget links open Passport or the budget editor through the app's authenticated root view.

**Signing requirement:** register the App Group and enable it for both app identifiers in the developer account. Both targets use the same team. Simulator builds verify code and the extension bundle; a physical-device widget installation and signed archive require matching provisioning profiles.

Saved quests now live in `users/{uid}/quests/active`; their displayed progress and the bundled trail/challenge templates are calculated from the student's visits. Shared Firestore quest/trail/challenge collections have explicit read-only rules for future admin-authored content. The app currently uses its bundled trail/challenge templates; it does not claim to download those shared catalogues.

## Increment 10 — polish and hardening (C5)

| State or safeguard | Implementation and reason |
| --- | --- |
| Initial loading | Launch progress remains visible until session data is loaded. |
| Refresh loading and failure | All five main screens support refresh; a common status strip shows loading or a Retry action. A failed refresh preserves the last complete passport rather than partially replacing it. |
| Offline | `NWPathMonitor` supplies a shared connectivity hint. The banner explains cached data, on-device scanning and the connection required for new photo uploads. Every request still handles its own failures because connectivity alone cannot prove service availability. |
| Saving | Existing visit-save progress stays visible during photo upload; the common status strip reports background metadata syncing. Errors are presented with Retry. Failed metadata operations can retry during the current session, and reset/sign-out invalidate old retry operations so a deleted visit cannot reappear. Firestore itself supplies its persistent offline write queue. |
| Empty data | Explore has an empty-catalogue state and refresh action, search has no-results states, Home/Passport offer quest creation, and History retains its first-visit action. Home charts now use actual visits and show an empty cuisine state. |
| Photo failure | The gallery offers Retry and explains that older local-only images may be unavailable on another device. |
| Feedback | Tab/sidebar selections and successful visit/stamp actions use system haptics. Short transitions retain Reduce Motion support. Existing camera and form feedback is retained. |
| Account isolation | Photo paths, local caches, widget clearing, notification registration and Firestore rules are scoped to the signed-in user. Pending photo saves cannot restore a visit after sign-out/reset. |
| Shared catalogue writes | `restaurants` write rule is `if false`. The debug client uploader was removed, so a debug app cannot bypass catalogue ownership. Shared quests, trails and challenges also reject client writes. Owner subcollections have explicit rules, including quest and device-token validation. |

`firestore.rules`, `storage.rules` and `firebase.json` are the deployable configuration. They have not been published to the live Firebase project: the local Firebase CLI reports no authenticated accounts. Sign in with `npx firebase-tools login` before the deployment command below. Restaurant maintenance now belongs in the Firebase console or a trusted Admin SDK process.

## Verification

- The new Swift checks passed: cloud-photo download/cache/rollback/deletion retry, shared widget snapshots, month rollover, Face ID privacy, quest persistence, deep links and refresh errors.
- All 12 Firestore/Storage emulator tests passed, including denial of signed-in restaurant writes and cross-account image access.
- Final iPad Pro 11-inch (M5), iOS 27 Simulator run: **both UI tests passed** for landscape side-by-side map/list geometry, portrait rotation and notification permission. Screenshots: [landscape](Evidence/iPad-landscape.png), [portrait](Evidence/iPad-portrait.png).
- Final iPhone 18 Pro / iOS 27 Simulator full suite: **182 tests passed, zero failures** (including parameterised test cases and two UI checks). [Machine-readable summary](Evidence/SwiftTests.json).
- Updated phone layout screenshots: [landscape](Evidence/iPhone-landscape.png), [portrait](Evidence/iPhone-portrait.png). The notification permission UI check also passed.
- After authorising notifications through Profile, `xcrun simctl push` accepted the weekly challenge payload for `com.seniyagajadeera.FoodPassport` and reported “Notification sent”. The foreground challenge banner was visually verified: [Simulator push screenshot](Evidence/Simulator-push.png). This verifies Simulator injection; it is not an FCM/APNs end-to-end delivery test. Notification destination parsing and routing use the existing tested paths.
- The signed Simulator app and extension shared the declared App Group. A real snapshot was found in its shared container with the demo account's quest and monthly spending. Widget-gallery placement on a physical device remains unverified.

No commit is made by this increment.

## Reproducing setup and checks

1. Open `FoodPassport.xcodeproj`, select FoodPassport and choose an iPhone or iPad Simulator. The Debug launch argument `--demo` uses sample data without connecting to Firebase.
2. For Firebase, supply the local `GoogleService-Info.plist`, enable Email/Password authentication and create the Storage bucket. Use an authenticated Firebase CLI to publish:

   ```sh
   npx firebase-tools deploy --project foodpassport-6fc9c --only firestore:rules,storage
   ```

   Check the project ID before publishing to another project. Deployment is a separate operation; emulator success does not publish rules.
3. Enable Push Notifications and App Groups in Signing & Capabilities, register the App Group for both identifiers, and upload the APNs key to Firebase → Project settings → Cloud Messaging. Never add that private key to this repository.
4. Allow notifications in the app. For a Simulator demo, select its explicit device UUID:

   ```sh
   xcrun simctl push DEVICE_UUID com.seniyagajadeera.FoodPassport PushSamples/weekly-challenge.apns
   xcrun simctl push DEVICE_UUID com.seniyagajadeera.FoodPassport PushSamples/restaurant.apns
   ```

   Tap the alert to verify its destination. For a live FCM test, use Firebase's notification composer and a provisioned physical device's registration from that user's `devices` collection; add the same destination fields as custom data. Never copy a token into a report screenshot.
5. Add **My food quest** from the Home Screen widget gallery. Add **Food budget** to a supported Lock Screen accessory slot. Create a quest and log a visit, then check the snapshot and widget after iOS refreshes it.
6. Run Swift and UI tests with Xcode Test or:

   ```sh
   xcodebuild test -project FoodPassport.xcodeproj -scheme FoodPassport \
     -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO
   xcodebuild test -project FoodPassport.xcodeproj -scheme FoodPassport \
     -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
     -only-testing:FoodPassportUITests -parallel-testing-enabled NO
   ```

7. For rule checks, install Node.js and Java 21+, then:

   ```sh
   cd FirebaseTests
   npm ci
   npm test
   ```

   Tests use `demo-foodpassport` and the local Firestore/Storage emulators, without production data or credentials. They cover shared writes, anonymous access, owner isolation, quest validation, token ownership and upload limits.

## Primary references

- [Apple: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Apple: Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: Linking widget scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [Firebase: Upload files on Apple platforms](https://firebase.google.com/docs/storage/ios/upload-files)
- [Firebase: Storage rules](https://firebase.google.com/docs/storage/security)
- [Firebase: Cloud Messaging setup for Apple apps](https://firebase.google.com/docs/cloud-messaging/ios/get-started)
- [Firebase: Storage billing requirements](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
