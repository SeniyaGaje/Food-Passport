# FoodPassport

A budget-aware food exploration app for university students, built with SwiftUI.
Students set a food quest, find restaurants on a map, log meals, earn cuisine stamps and track their spending.

## Requirements

- Xcode 26 or later
- iOS 17.0+ (iPhone and iPad)

## Running

1. Open `FoodPassport.xcodeproj`.
2. Select the **FoodPassport** scheme and an iPhone or iPad simulator.
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

The receipt screen lists every item with its price, then the total. If you've already added your dishes (for example
with Scan your meal), the receipt only fills in their prices and the total: your dish names stay as they are. Each dish
is matched to the receipt line that shares the most words with it ("Kottu Roti" gets the price of "CHICKEN KOTTU").
With no dishes added yet, the receipt's items are used instead.

## Meal recognition and photos

Log your visit → **Scan your meal** takes a camera photo or chooses one from Photos.
All recognition runs on the device:

1. **YOLOv3-tiny** locates common food and drink objects, such as cups, bowls and cake.
2. When multiple objects are found, each region is classified separately using Apple's frozen
   **MobileCLIP-S0** encoder and our **Create ML Components logistic regression classifier**.
3. Each item gets three alternative names. **Nothing starts selected, even at 100% confidence.**
   Choose one name for each item you had, then tap **Add selected items**.
4. The editable form receives those items. **Save visit** is always required to persist the visit.

The catalogue includes Sri Lankan foods, familiar meals, coffee, tea, **Cake & Dessert** (including
chocolate cakes, cheesecake and cupcakes), and Other. Suggestions show food/drink type, category and
suggested cuisine where one applies. These extra details are catalogue mappings, not separate
ingredient or nutrition predictions. A broad Tea result does not distinguish plain tea from milk tea.

The object detector can miss small or overlapping items. If fewer than two separate regions are found,
the app shows three guesses for the whole photo. Scan a missing item separately when needed.

Meal photos are cached privately in **Application Support**, separately for each account. Firebase-enabled builds also upload them to that account's private Storage folder.
Visit history, recent activity and stamp details show the saved photo, and **Your meal photos** opens
a full-size gallery. Photos also survive reopening the app. Choosing manual entry keeps a valid photo.
Deleting a visit or resetting its data removes the associated photos after the database deletion succeeds.

With Firebase configured, resized meal photos upload to the signed-in account's Firebase Storage folder.
Other devices download them on demand, and previously viewed photos remain cached offline.
A failed upload keeps the visit form open for retry. Older local-only photos still need their original device.
Without Firebase, the app uses the local store.

See [the increments 8–10 report](Docs/Increment8-10Report.md) for iPad layout decisions, cloud setup,
push limitations, widgets, rule tests and verification evidence.

See [MLTraining/README.md](MLTraining/README.md) for training steps and limits,
[MLTraining/EvaluationReport.md](MLTraining/EvaluationReport.md) for measured results, and
[CREDITS.md](CREDITS.md) for model and dataset credits.

The Simulator has no camera. Add a food photo to its Photos app, then use **Choose from Photos**.

## Demo at NIBM Colombo (viva)

**NIBM Canteen** is a sample restaurant placed on the NIBM building on Vidya Mawatha (6.9063905, 79.8708285,
from OpenStreetMap). Its 100 m geofence covers the whole building, so the arrival alert and location-verified
visits can be shown live on a real iPhone on campus.

- Add or maintain `restaurants/nibm-canteen` in the Firebase console. Client restaurant writes are disabled.
- Opening the app inside NIBM shows "You've arrived at NIBM Canteen!". **Get directions → Start** shows it again on demand.
- To move it (e.g. to the exact viva room), edit `latitude` and `longitude` on that Firestore document and reopen the app.
- Simulator backup: **Features → Location → Custom Location…** `6.90635`, `79.87080`.

## Demo at home: Ratmalana Tea Kade

**Ratmalana Tea Kade** is a sample tea shop in the middle of Chakkindarama Road, Ratmalana (6.8231622, 79.8728517,
from OpenStreetMap). The road is 362 m long, so a visit logged almost anywhere on it is location verified (within
150 m), and the arrival alert fires within 100 m. It sells tea, coffee and short eats, which is handy for trying
drink recognition.

- Add or maintain `restaurants/ratmalana-tea-kade` in the Firebase console. Debug builds do not upload restaurants.
- The Explore map opens on the places within 3 km of the student, so on Chakkindarama Road it shows the tea kade.
- To move it, edit `latitude` and `longitude` on that Firestore document and reopen the app.
- Simulator: **Features → Location → Custom Location…** `6.82316`, `79.87285`.

## Firebase setup

1. In the [Firebase console](https://console.firebase.google.com), create a project.
2. Add an **iOS** app with the bundle ID `com.seniyagajadeera.FoodPassport`, then download `GoogleService-Info.plist`.
3. Put `GoogleService-Info.plist` in the `FoodPassport/` folder, next to `FoodPassportApp.swift`.
   It is listed in `.gitignore`, so it is not committed.
4. **Authentication → Sign-in method:** enable **Email/Password**.
5. **Firestore Database:** create a database in production mode, then paste the contents of
   [`firestore.rules`](firestore.rules) into the **Rules** tab and publish.
6. Create restaurant documents in the Firebase console or a trusted Admin SDK tool; the app cannot write the shared catalogue.
7. Enable **Storage** on Blaze and publish [`storage.rules`](storage.rules). Photos use private account paths.
8. Follow [the increment report](Docs/Increment8-10Report.md) for APNs, App Group signing, widgets and rule deployment.
9. Run the app and create an account. Use the Debug launch argument `--demo` for a sample-data demonstration without Firebase.

Firestore layout:

```
restaurants/{restaurantID}          shared restaurant list
users/{userID}                      profile: name, email, monthly budget, bookmarks
users/{userID}/visits/{visitID}     logged visits
users/{userID}/stamps/{cuisine}     one stamp per cuisine
users/{userID}/quests/active        saved quest settings
users/{userID}/devices/{tokenHash}  private FCM registration
Storage: users/{userID}/mealPhotos/{UUID}.jpg
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
│   ├── AppState.swift        Session and data state, plus navigation (tabs, routes, pop-ups)
│   └── MealScanViewModel.swift  Scan review, selection, confirmation and rejection
├── Services/
│   ├── AuthService.swift     Sign up / sign in: Firebase Auth version and a mock for tests
│   ├── DatabaseService.swift Reads and writes: Firestore version and a mock for tests
│   ├── BiometricService.swift      Face ID / Touch ID: LocalAuthentication version and a mock
│   ├── NotificationService.swift   Reminders: UserNotifications version and a mock
│   ├── LocationService.swift       Location and geofences: Core Location version and a mock
│   ├── ReceiptScanner.swift        Receipt reading: Vision text recognition, the receipt parser, and a mock
│   ├── MealRecognizer.swift        Meal recognition: MobileCLIP + trained classifier, result parsing, and a mock
│   └── CameraService.swift         The back camera (AVFoundation)
├── ML/
│   ├── MobileCLIPImageEncoder.mlpackage   Apple's frozen MobileCLIP-S0 image encoder
│   ├── FoodClassifier.mlpackage    Food classifier trained with Create ML Components
│   ├── FoodModel.json              Catalogue, categories and confirmation policy
│   ├── MealObjectDetector.mlmodel  YOLOv3-tiny food/drink object detector
│   └── MobileCLIP-LICENSE.txt      Apple's licence for the model
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
MLTraining/                  Dataset collection, review, splitting, training, evaluation and credits
```

Each file holds a screen area and its smaller views; use the Xcode jump bar to find a specific view.
The project uses Xcode folder-synced groups, so any file added inside `FoodPassport/` is picked up automatically.

## Photos

Restaurant and dish photos are real photos from Wikimedia Commons, resized to 1,400–1,600 px wide for iPhone and iPad; the welcome screen photo is the one from the Figma prototype. They live in `Assets.xcassets`:
`welcome_hero`, `restaurant_campus_bites`, `restaurant_spice_route`, `restaurant_dragon_wok`,
`restaurant_hoppers_hut`, `restaurant_pasta_corner`, `restaurant_nibm_canteen`, `restaurant_ratmalana_tea_kade`,
`dish_kottu`, `dish_masala_dosa`, `dish_butter_chicken`. The Commons photos' authors and licences are in
[`PHOTO_CREDITS.md`](PHOTO_CREDITS.md); the licences allow reuse as long as the authors are credited.
To change a photo, replace the image in that set. Any missing photo falls back to a cuisine-coloured placeholder.
