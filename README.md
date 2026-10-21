# FoodPassport

A budget-aware food exploration app for university students, built with SwiftUI.
Students set a food quest, find restaurants on a map, log meals, earn cuisine stamps and track their spending.

## Requirements

- Xcode 26 or later
- iOS 17.0+ (iPhone)

## Running

1. Open `FoodPassport.xcodeproj`.
2. Select the **FoodPassport** scheme and an iPhone simulator.
3. Press **Run** (⌘R). Run the unit tests with **Test** (⌘U).

Without `GoogleService-Info.plist` the app runs on mock data (any email and password signs in).
To use the real backend, follow **Firebase setup** below.

Demo flow: Get started → Create account → Before we begin → Start exploring → Explore → Campus Bites → Get directions →
Start (arrival banner appears) → tap banner → Scan your meal / Scan receipt → Save visit → Done → Budget update → See updated plan.

The Face ID lock screen appears when the app returns from the background while "Unlock with Face ID" is on in Profile.

## Trying Face ID and notifications in the simulator

- **Face ID:** in the Simulator menu choose **Features → Face ID → Enrolled**. Turn on "Unlock with Face ID" in Profile,
  then use **Features → Face ID → Matching Face** (or **Non-matching Face**) when the prompt appears.
- **Lock screen:** with Face ID on, press ⇧⌘H to go home, then reopen FoodPassport.
- **Reminders:** allow notifications during onboarding, or turn a reminder on in Profile. Plan a visit at least
  30 minutes ahead with "Remind me" on. Notifications show even while the app is open.

## Trying geofencing in the simulator

The simulator starts in California, so first move it to campus: **Features → Location → Custom Location…**
and enter latitude `6.9028`, longitude `79.8598`. Allow location during onboarding.

- **Arrival alert:** open Campus Bites → **Get directions** → **Start**, then set the custom location to
  `6.9010`, `79.8624` (Campus Bites). The "You've arrived" banner appears and the route card switches to
  **Log your visit**.
- **With the app closed:** choose **Always** when iOS asks to change location access, press ⇧⌘H, then move the
  location to Campus Bites. A notification appears; tapping it opens Log your visit.
- From Terminal: `xcrun simctl location booted set 6.9010,79.8624`

## Trying receipt scanning in the simulator

The simulator has no camera, so add a receipt photo to its Photos app first: drag an image file onto the
Simulator window, or run `xcrun simctl addmedia booted path/to/receipt.jpg`. Then go to Log your visit →
Scan receipt → **Choose from Photos**. On a real iPhone, **Scan receipt** opens the document scanner.

## Demo at NIBM Colombo (viva)

**NIBM Canteen** is a sample restaurant placed on the NIBM building on Vidya Mawatha (6.9063905, 79.8708285,
from OpenStreetMap). Its 100 m geofence covers the whole building, so the arrival alert and location-verified
visits can be shown live on a real iPhone on campus.

- The first debug run on a phone uploads it to Firestore (`restaurants/nibm-canteen`) alongside the other restaurants.
- Opening the app inside NIBM shows "You've arrived at NIBM Canteen!". **Get directions → Start** shows it again on demand.
- To move it (e.g. to the exact viva room), edit `latitude` and `longitude` on that Firestore document and reopen the app.
- Simulator backup: **Features → Location → Custom Location…** `6.90635`, `79.87080`.

## Firebase setup

1. In the [Firebase console](https://console.firebase.google.com), create a project.
2. Add an **iOS** app with the bundle ID `com.seniyagajadeera.FoodPassport`, then download `GoogleService-Info.plist`.
3. Put `GoogleService-Info.plist` in the `FoodPassport/` folder, next to `FoodPassportApp.swift`.
   It is listed in `.gitignore`, so it is not committed.
4. **Authentication → Sign-in method:** enable **Email/Password**.
5. **Firestore Database:** create a database in production mode, then paste the contents of
   [`firestore.rules`](firestore.rules) into the **Rules** tab and publish.
6. Run the app and create an account. On the first run, a debug build uploads the sample restaurants
   to the `restaurants` collection.

Firestore layout:

```
restaurants/{restaurantID}          shared restaurant list
users/{userID}                      profile: name, email, monthly budget, bookmarks
users/{userID}/visits/{visitID}     logged visits
users/{userID}/stamps/{cuisine}     one stamp per cuisine
```

## Project structure

The app follows MVVM with one file per screen area:

```
FoodPassport/
├── FoodPassportApp.swift     App entry point and root view (onboarding / tabs / Face ID lock)
├── Assets.xcassets           App icon, accent colour, photos
├── Models/
│   ├── Models.swift          Data types (Restaurant, Visit, Quest, Stamp, …)
│   └── MockData.swift        Sample data for previews, tests and the first Firestore upload
├── ViewModels/
│   └── AppState.swift        Session and data state, plus navigation (tabs, routes, pop-ups)
├── Services/
│   ├── AuthService.swift     Sign up / sign in: Firebase Auth version and a mock for tests
│   ├── DatabaseService.swift Reads and writes: Firestore version and a mock for tests
│   ├── BiometricService.swift      Face ID / Touch ID: LocalAuthentication version and a mock
│   ├── NotificationService.swift   Reminders: UserNotifications version and a mock
│   ├── LocationService.swift       Location and geofences: Core Location version and a mock
│   └── ReceiptScanner.swift        Receipt reading: Vision text recognition, the receipt parser, and a mock
├── Views/
│   ├── MainTabView.swift     Tab bar, screen routing, pop-up and toast hosts
│   ├── OnboardingViews.swift Welcome, permissions, budget setup
│   ├── AuthViews.swift       Sign in, sign up, forgot password, Face ID lock
│   ├── HomeView.swift        Dashboard
│   ├── ExploreView.swift     Map / list of restaurants
│   ├── PlaceDetailView.swift Place detail, plan visit, directions
│   ├── LogVisitView.swift    Log a visit, meal camera, recognition, receipt scan, stamp earned
│   ├── PassportView.swift    Stamps and challenges
│   ├── QuestViews.swift      Quest detail/editor, food trail, weekly challenge, budget pop-ups
│   ├── HistoryView.swift     Visit history and visit detail
│   └── ProfileView.swift     Profile, settings, budget and reminder sheets, about
└── Utilities/
    ├── Theme.swift           Colours, button styles, card style, small extensions
    └── Components.swift      Reusable UI pieces (headers, chips, fields, pins, rows, …)
FoodPassportTests/            Swift Testing unit tests
```

Each file is split into `// MARK: -` sections, so use the Xcode jump bar to find a specific view.
The project uses Xcode folder-synced groups, so any file added inside `FoodPassport/` is picked up automatically.

## Photos

Food photos come from the Figma prototype and live in `Assets.xcassets`:
`welcome_hero`, `restaurant_campus_bites`, `restaurant_spice_route`, `restaurant_dragon_wok`,
`restaurant_hoppers_hut`, `restaurant_pasta_corner`, `dish_kottu`, `dish_masala_dosa`, `dish_butter_chicken`.
To change a photo, replace the image in that set. Any missing photo falls back to a cuisine-coloured placeholder.

The meal camera and receipt scanner show placeholders until the camera is connected.
