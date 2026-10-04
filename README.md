# FoodPassport

A budget-aware food exploration app for university students, built with SwiftUI.
Students set a food quest, find restaurants on a map, log meals, earn cuisine stamps and track their spending.

## Current status

- **UI:** every screen from the Figma prototype is built in SwiftUI with working navigation.
- **Backend:** Firebase Authentication (email and password) and Cloud Firestore store accounts, profiles, budgets,
  bookmarks, visits, stamps and the restaurant list.
- **Not wired up yet:** Face ID, Core ML, Vision, geofencing and notifications. Those screens show sample results,
  and quests, trails and challenges still use sample data.

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
│   └── DatabaseService.swift Reads and writes: Firestore version and a mock for tests
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
