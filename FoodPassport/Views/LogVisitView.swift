import SwiftUI
import AVFoundation
import PhotosUI
import VisionKit

/// The "Log your visit" form, with meal and receipt scanning.
struct LogVisitView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let restaurant: Restaurant

    @State private var items = [VisitItemDraft()]
    @State private var cuisine = ""
    @State private var amount = ""
    @State private var rating = 0
    @State private var notes = ""
    @State private var hasMealPhoto = false
    @State private var isAmountFromReceipt = false
    /// True once the student types the total themselves, so we stop filling it in for them.
    @State private var hasTypedTotal = false
    @State private var isShowingMealCamera = false
    @State private var isShowingReceiptScanner = false

    /// The cuisine typed in, or the restaurant's cuisine if it doesn't match one we know.
    private var selectedCuisine: Cuisine {
        Cuisine.allCases.first { $0.rawValue.caseInsensitiveCompare(cuisine) == .orderedSame } ?? restaurant.cuisine
    }

    /// The total as a number, ignoring "LKR" and commas.
    private var amountValue: Int? {
        Int(amount.filter(\.isNumber))
    }

    /// The items that have a name (empty rows are ignored).
    private var namedItems: [VisitItemDraft] {
        items.filter { !$0.name.trimmed.isEmpty }
    }

    private var itemsTotal: Int {
        VisitItemDraft.total(of: items)
    }

    /// Save needs at least one item and a total.
    private var canSave: Bool {
        !namedItems.isEmpty && (amountValue ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                restaurantCard

                mealScanArea

                itemsSection

                field("Cuisine") {
                    InputField(placeholder: "Cuisine type", text: $cuisine)
                }

                totalSection

                field("Rating") {
                    StarRatingView(rating: $rating)
                }

                field("Notes (optional)") {
                    InputField(placeholder: "Add details about your experience...", text: $notes, isMultiline: true)
                }

                Button(action: saveVisit) {
                    Label("Save visit", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.brandPrimary)
                .disabled(!canSave)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle("Log your visit")
        .navigationBarTitleDisplayMode(.large)
        // Keep the total in step with the item prices, unless it was typed or came from a receipt.
        .onChange(of: itemsTotal) { _, newTotal in
            guard !hasTypedTotal && !isAmountFromReceipt else { return }
            amount = newTotal > 0 ? "\(newTotal)" : ""
        }
        .fullScreenCover(isPresented: $isShowingMealCamera) {
            MealCameraView(menu: restaurant.popularDishes.map(\.name)) { dishes in
                addScannedDishes(dishes)
            }
        }
        .fullScreenCover(isPresented: $isShowingReceiptScanner) {
            ReceiptScanView { receipt in
                useReceipt(receipt)
            }
        }
    }

    /// Adds the dishes picked after a meal scan, with the menu price when the restaurant sells them.
    private func addScannedDishes(_ dishes: [MealPrediction]) {
        var newItems: [VisitItemDraft] = []
        for dish in dishes {
            let menuDish = restaurant.popularDishes.first { $0.name.caseInsensitiveCompare(dish.dishName) == .orderedSame }
            let priceText = menuDish.map { "\($0.price)" } ?? ""
            newItems.append(VisitItemDraft(name: dish.dishName, priceText: priceText))
        }

        items = VisitItemDraft.adding(newItems, to: items)
        if cuisine.trimmed.isEmpty, let first = dishes.first {
            cuisine = first.cuisine.rawValue
        }
        hasMealPhoto = true
    }

    /// Fills in the items and total from a scanned receipt.
    private func useReceipt(_ receipt: ReceiptScan) {
        // The receipt lists everything that was bought, so its items replace the list.
        if !receipt.items.isEmpty {
            items = receipt.items.map { VisitItemDraft(name: $0.name, priceText: "\($0.price)") }
        }
        if let total = receipt.total {
            amount = "\(total)"
            isAmountFromReceipt = true
        }
    }

    /// Saves the visit. Shows the stamp pop-up if it earned one.
    private func saveVisit() {
        var savedItems: [VisitItem] = []
        for item in namedItems {
            savedItems.append(VisitItem(name: item.name.trimmed, price: item.price))
        }

        let visit = Visit(
            id: UUID().uuidString,
            dishName: savedItems.map(\.name).joined(separator: ", "),
            cuisine: selectedCuisine,
            restaurant: restaurant,
            amount: amountValue ?? 0,
            rating: rating,
            notes: notes.trimmed,
            date: .now,
            // Only visits logged at the restaurant are verified, and only those earn stamps.
            isLocationVerified: appState.isAtRestaurant(restaurant),
            isAutoDetected: hasMealPhoto,
            isFromReceipt: isAmountFromReceipt,
            imageName: restaurant.imageName,
            items: savedItems
        )

        if let stamp = appState.addVisit(visit) {
            router.present(.stampEarned(stamp.cuisine))
        } else {
            router.closeVisitLoggingScreens()
            router.showToast(visit.isLocationVerified ? "Visit logged ✓" : "Visit logged. Stamps need a verified location.")
        }
    }

    // Sections

    private var restaurantCard: some View {
        AdaptiveStack(spacing: 14) {
            FoodImageView(imageName: restaurant.imageName, cuisine: restaurant.cuisine, cornerRadius: 14)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(restaurant.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                if appState.isAtRestaurant(restaurant) {
                    PillLabel(text: "Location verified", trailingSystemImage: "checkmark", style: .green)
                } else {
                    PillLabel(text: "Not at this restaurant", systemImage: "location.slash")
                }
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mealScanArea: some View {
        if hasMealPhoto {
            // After a scan: show it worked, with a button to scan another dish.
            Button {
                isShowingMealCamera = true
            } label: {
                HStack(spacing: 14) {
                    IconTile(systemImage: "checkmark", tint: Theme.green, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meal recognised")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Dishes added below")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label("Scan another", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orangeText)
                }
                .cardStyle(padding: 14)
            }
            .buttonStyle(.pressableCard)
            .accessibilityHint("Opens the camera to add another dish")
        } else {
            Button {
                isShowingMealCamera = true
            } label: {
                VStack(spacing: 12) {
                    IconTile(systemImage: "camera.fill", size: 60)

                    Text("Scan your meal")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    Label("The dish is recognised on your device", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .labelStyle(CompactLabelStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(Theme.orangeTint.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.pressableCard)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the camera")
        }
    }

    /// The list of dishes and drinks, each with its own price.
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption("What did you eat?")

            ForEach($items) { $item in
                itemRow($item)
            }

            Button {
                items.append(VisitItemDraft())
            } label: {
                Label("Add another item", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.orangeText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func itemRow(_ item: Binding<VisitItemDraft>) -> some View {
        // Name and price side by side; one above the other with very large text.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            InputField(placeholder: "Dish or drink", text: item.name)

            HStack(spacing: 4) {
                InputField(placeholder: "LKR", text: item.priceText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 110)
                    .accessibilityLabel("Price of \(item.wrappedValue.name.isEmpty ? "this item" : item.wrappedValue.name)")

                if items.count > 1 {
                    Button {
                        items.removeAll { $0.id == item.wrappedValue.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.wrappedValue.name.isEmpty ? "item" : item.wrappedValue.name)")
                }
            }
        }
    }

    /// The total spent, with the Scan receipt button.
    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionCaption("Total spent (LKR)")
                Spacer()
                Button {
                    isShowingReceiptScanner = true
                } label: {
                    Label(isAmountFromReceipt ? "Rescan receipt" : "Scan receipt", systemImage: "doc.text.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orangeText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityHint("Reads the items and total from a photo of your receipt")
            }

            InputField(placeholder: "Amount spent", text: typedTotal, prefix: amount.isEmpty ? nil : "LKR")
                .keyboardType(.numberPad)

            // e.g. the receipt total includes a service charge, or some prices are missing.
            if itemsTotal > 0 && itemsTotal != amountValue {
                Text("The items add up to \(itemsTotal.lkr).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The total field. Typing in it stops the total being filled in automatically.
    private var typedTotal: Binding<String> {
        Binding(
            get: { amount },
            set: { newValue in
                amount = newValue
                hasTypedTotal = true
            }
        )
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(title)
            content()
        }
    }
}

/// The full-screen camera for photographing a meal. The dish is recognised on the phone.
struct MealCameraView: View {
    private enum Step {
        case camera
        case recognising(UIImage)
        case results(UIImage, [MealPrediction])
        /// Not a dish we know, or something went wrong.
        case problem(UIImage?, title: String, message: String)
    }

    private enum CameraStatus {
        case starting
        case running
        /// No camera (the simulator).
        case unavailable
        case denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let menu: [String]
    private let recognizer: MealRecognizer
    private let initialPhoto: UIImage?
    private let onConfirm: ([MealPrediction]) -> Void

    @State private var camera = CameraService()
    @State private var cameraStatus = CameraStatus.starting
    @State private var step = Step.camera
    @State private var isFlashOn = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingResults = false
    @State private var confirmedDishes: [MealPrediction] = []
    @State private var wantsManualEntry = false

    /// `menu` is the restaurant's dishes (they get a boost).
    /// `initialPhoto` is recognised straight away, for previews.
    init(
        menu: [String] = [],
        recognizer: MealRecognizer = CoreMLMealRecognizer.shared,
        initialPhoto: UIImage? = nil,
        onConfirm: @escaping ([MealPrediction]) -> Void
    ) {
        self.menu = menu
        self.recognizer = recognizer
        self.initialPhoto = initialPhoto
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
                .overlay { viewfinderOverlay }
                .overlay(alignment: .top) { topControls }
                .clipped()

            bottomControls
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .task {
            if let initialPhoto {
                recognise(initialPhoto)
            } else {
                await startCamera()
            }
        }
        .task {
            // Load the model while the student lines up the photo, so it's quick.
            await recognizer.prepare()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: selectedPhoto) { _, item in
            loadPhoto(item)
        }
        .sheet(isPresented: $isShowingResults, onDismiss: handleResultsDismissed) {
            if case .results(let photo, let predictions) = step {
                MealRecognitionSheet(
                    photo: photo,
                    predictions: predictions,
                    onConfirm: { dishes in
                        confirmedDishes = dishes
                        isShowingResults = false
                    },
                    onEnterManually: {
                        wantsManualEntry = true
                        isShowingResults = false
                    }
                )
            }
        }
    }

    // Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        switch step {
        case .camera:
            switch cameraStatus {
            case .running:
                CameraPreview(session: camera.session)
                    .accessibilityLabel("Camera viewfinder")
            case .starting:
                Color.black
            case .unavailable:
                cameraMessage(
                    systemImage: "camera",
                    title: "No camera here",
                    message: "The camera isn't available on this device. Choose a photo of your meal instead."
                )
            case .denied:
                cameraMessage(
                    systemImage: "camera.badge.ellipsis",
                    title: "Camera access is off",
                    message: "Allow camera access in Settings to photograph your meal, or choose a photo instead.",
                    showsSettingsButton: true
                )
            }
        case .recognising(let photo), .results(let photo, _), .problem(let photo?, _, _):
            Color.black
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .accessibilityLabel("Photo of your meal")
        case .problem(nil, _, _):
            Color.black
        }
    }

    @ViewBuilder
    private var viewfinderOverlay: some View {
        switch step {
        case .camera where cameraStatus == .running:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .padding(40)
                .overlay(alignment: .bottom) {
                    Text("Centre your meal in the frame")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 56)
                }
                .allowsHitTesting(false)
        case .recognising:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Recognising your meal…")
                    .font(.headline)
                Label("On your device", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
        case .problem(_, let title, let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retake", action: retake)
                    .buttonStyle(.brandPrimary)
                    .padding(.top, 6)
                Button("Enter manually") { dismiss() }
                    .buttonStyle(BrandTextButtonStyle(color: .secondary))
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        default:
            EmptyView()
        }
    }

    private func cameraMessage(systemImage: String, title: String, message: String, showsSettingsButton: Bool = false) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            if showsSettingsButton {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.headline)
                .foregroundStyle(Theme.orange)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x1C1C1E))
    }

    // Controls

    private var topControls: some View {
        HStack {
            cameraControlButton(systemImage: "xmark", label: "Close") {
                dismiss()
            }
            Spacer()
            if case .camera = step, cameraStatus == .running {
                cameraControlButton(
                    systemImage: isFlashOn ? "bolt.fill" : "bolt.slash.fill",
                    label: isFlashOn ? "Flash on" : "Flash off"
                ) {
                    isFlashOn.toggle()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            Button(action: takePhoto) {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                    }
            }
            .buttonStyle(.plain)
            .opacity(canTakePhoto ? 1 : 0.35)
            .disabled(!canTakePhoto)
            .accessibilityLabel("Take photo")

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Choose from Photos")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
            }
            .disabled(isBusy)
        }
    }

    private var canTakePhoto: Bool {
        if case .camera = step { return cameraStatus == .running }
        return false
    }

    private var isBusy: Bool {
        if case .recognising = step { return true }
        return false
    }

    private func cameraControlButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // Actions

    /// Starts the camera, or explains why it can't.
    private func startCamera() async {
        guard CameraService.isAvailable else {
            cameraStatus = .unavailable
            return
        }
        guard await CameraService.requestAccess() else {
            cameraStatus = .denied
            return
        }
        camera.start()
        cameraStatus = .running
    }

    /// Takes a photo and recognises the meal in it.
    private func takePhoto() {
        Task {
            do {
                recognise(try await camera.takePhoto(withFlash: isFlashOn))
            } catch {
                step = .problem(nil, title: "Couldn't take the photo", message: error.localizedDescription)
            }
        }
    }

    /// Loads the photo chosen from Photos.
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                recognise(photo)
            } else {
                step = .problem(nil, title: "Couldn't open the photo", message: MealRecognitionError.unreadableImage.localizedDescription)
            }
        }
    }

    /// Runs the meal recogniser and shows the results (or the problem).
    private func recognise(_ photo: UIImage) {
        step = .recognising(photo)
        Task {
            do {
                switch try await recognizer.recognize(photo, menu: menu) {
                case .dishes(let predictions) where !predictions.isEmpty:
                    step = .results(photo, predictions)
                    isShowingResults = true
                case .dishes:
                    step = .problem(photo, title: "No dish found", message: "Retake the photo with your plate in the middle of the frame, or enter the dish yourself.")
                case .unknownFood(let lookalike):
                    step = .problem(photo, title: "Not one of our dishes yet",
                                    message: "This looks like \(lookalike == "Drink" ? "a drink" : lookalike.lowercased()), which FoodPassport can't recognise yet. Enter the dish yourself.")
                case .notFood(let lookalike):
                    step = .problem(photo, title: "This doesn't look like a meal", message: notAMealMessage(lookalike))
                }
            } catch {
                step = .problem(photo, title: "Couldn't recognise the photo", message: error.localizedDescription)
            }
        }
    }

    /// What to tell the student when the photo isn't a meal.
    private func notAMealMessage(_ lookalike: String) -> String {
        switch lookalike {
        case "Receipt": "It looks like a receipt. Use Scan receipt for the bill, and photograph your plate here."
        case "Unclear photo": "The photo is too dark or blurry. Retake it in better light with your plate in the frame."
        default: "It looks like a \(lookalike.lowercased()). Retake the photo with your plate in the middle of the frame."
        }
    }

    /// Clears the photo so the student can try again.
    private func retake() {
        selectedPhoto = nil
        confirmedDishes = []
        wantsManualEntry = false
        step = .camera
    }

    /// Runs when the results sheet closes, however it was closed.
    private func handleResultsDismissed() {
        if !confirmedDishes.isEmpty {
            onConfirm(confirmedDishes)
            dismiss()
        } else if wantsManualEntry {
            dismiss()
        } else {
            // They swiped the results away, so go back to the camera.
            retake()
        }
    }
}

/// The live camera picture.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// "We found matches!": the top three dishes for the photo. The student can pick more than one.
struct MealRecognitionSheet: View {
    let photo: UIImage?
    let predictions: [MealPrediction]
    let onConfirm: ([MealPrediction]) -> Void
    let onEnterManually: () -> Void

    /// Positions of the ticked dishes. The most likely one starts ticked.
    @State private var selectedIndexes: Set<Int> = [0]

    /// The ticked dishes, in the order they're listed.
    private var selectedDishes: [MealPrediction] {
        predictions.indices.filter { selectedIndexes.contains($0) }.map { predictions[$0] }
    }

    private var isConfident: Bool {
        (predictions.first?.confidence ?? 0) >= MealClassifier.confidentThreshold
    }

    private var confirmTitle: String {
        switch selectedDishes.count {
        case 0: "Pick at least one dish"
        case 1: "Add \(selectedDishes[0].label)"
        default: "Add \(selectedDishes.count) dishes"
        }
    }

    var body: some View {
        ScrollView {
            sheetContent
                .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.fraction(0.8), .large])
        .brandSheetStyle()
        .sensoryFeedback(.selection, trigger: selectedIndexes)
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        FoodImageView(imageName: nil, cuisine: predictions.first?.cuisine)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Detected on your device", systemImage: "iphone")
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(isConfident ? "We found matches!" : "Is it one of these?")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            Label(
                isConfident ? "Tick every dish you had." : "Not sure about this one. Tick the right dishes, or enter them yourself.",
                systemImage: isConfident ? "checklist" : "questionmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            ForEach(Array(predictions.enumerated()), id: \.element.id) { index, prediction in
                Button {
                    toggle(index)
                } label: {
                    PredictionRow(prediction: prediction, isSelected: selectedIndexes.contains(index))
                }
                .buttonStyle(.plain)
            }

            if let first = selectedDishes.first {
                AdaptiveStack(spacing: 6) {
                    Text("Suggested cuisine")
                        .foregroundStyle(.secondary)
                    Spacer()
                    PillLabel(text: first.cuisine.rawValue, style: .green, font: .subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }

            Button(confirmTitle) {
                onConfirm(selectedDishes)
            }
            .buttonStyle(.brandPrimary)
            .disabled(selectedDishes.isEmpty)

            Button("Not right? Enter manually", action: onEnterManually)
                .buttonStyle(BrandTextButtonStyle(color: .secondary))
        }
    }

    /// Ticks or unticks a dish.
    private func toggle(_ index: Int) {
        if selectedIndexes.contains(index) {
            selectedIndexes.remove(index)
        } else {
            selectedIndexes.insert(index)
        }
    }
}

private struct PredictionRow: View {
    let prediction: MealPrediction
    let isSelected: Bool

    private var percentage: Int {
        Int((prediction.confidence * 100).rounded())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // A tick box, so it's clear more than one dish can be picked.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.orange : Theme.faintInk)

            VStack(alignment: .leading, spacing: 10) {
                AdaptiveStack(spacing: 8) {
                    Text(prediction.label)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if prediction.isOnMenu {
                        PillLabel(text: "On the menu", font: .caption2.weight(.semibold))
                            .fixedSize()
                    }
                    Spacer()
                    Text(verbatim: "\(percentage)%")
                        .font(.headline)
                        .foregroundStyle(isSelected ? Theme.ink : Color.secondary)
                }

                ProgressBar(
                    value: prediction.confidence,
                    tint: isSelected ? Theme.orange : Theme.faintInk,
                    height: 6
                )
            }
        }
        .padding(16)
        .cardBackground(cornerRadius: 16, shadowStrength: 0.4)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.orange : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prediction.label), \(percentage) percent likely\(prediction.isOnMenu ? ", on the menu" : "")")
        .accessibilityHint(isSelected ? "Double-tap to untick" : "Double-tap to tick")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Scans a receipt and shows the total it found, highlighted on the photo.
struct ReceiptScanView: View {
    private enum Step {
        case choosing
        case reading(UIImage)
        case result(UIImage, ReceiptScan)
        case failed(UIImage?, String)
    }

    @Environment(\.dismiss) private var dismiss

    private let scanner: ReceiptScanner
    private let initialImage: UIImage?
    private let onUseReceipt: (ReceiptScan) -> Void

    @State private var step: Step = .choosing
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingDocumentCamera = false

    /// `initialImage` is read straight away, for previews.
    init(
        scanner: ReceiptScanner = VisionReceiptScanner(),
        initialImage: UIImage? = nil,
        onUseReceipt: @escaping (ReceiptScan) -> Void
    ) {
        self.scanner = scanner
        self.initialImage = initialImage
        self.onUseReceipt = onUseReceipt
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 16)

            photoArea
                .padding(.horizontal, 32)

            Spacer(minLength: 16)

            bottomCard
        }
        .background(Color(hex: 0x2A2724).ignoresSafeArea())
        .statusBarHidden()
        .fullScreenCover(isPresented: $isShowingDocumentCamera) {
            DocumentCameraView(
                onScan: { image in
                    isShowingDocumentCamera = false
                    read(image)
                },
                onCancel: { isShowingDocumentCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in
            loadPhoto(item)
        }
        .task {
            if let initialImage {
                read(initialImage)
            }
        }
    }

    // Photo

    @ViewBuilder
    private var photoArea: some View {
        switch step {
        case .choosing:
            instructions(systemImage: "doc.text.viewfinder", title: "Scan your receipt",
                         message: "Photograph the whole receipt, flat and in good light. It's read on your phone and the photo isn't uploaded.")
        case .reading(let image):
            ReceiptPhotoView(image: image, highlight: nil)
                .overlay {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .padding(20)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                }
        case .result(let image, let receipt):
            ReceiptPhotoView(image: image, highlight: receipt.totalBoundingBox)
        case .failed(let image?, _):
            ReceiptPhotoView(image: image, highlight: nil)
        case .failed(nil, _):
            instructions(systemImage: "exclamationmark.triangle", title: "Couldn't open the photo", message: "Try another photo of the receipt.")
        }
    }

    private func instructions(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch step {
            case .choosing:
                choosingButtons

            case .reading:
                SectionCaption("Total detected")
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading receipt…")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 41)

            case .result(_, let receipt):
                resultDetails(for: receipt)

            case .failed(_, let message):
                Text("Couldn't read this receipt")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Retake", action: retake)
                    .buttonStyle(.brandPrimary)
                    .padding(.top, 12)
                Button("Enter the amount myself") { dismiss() }
                    .buttonStyle(BrandTextButtonStyle(color: .secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var choosingButtons: some View {
        // The document scanner needs a real camera, so the simulator only gets Photos.
        if VNDocumentCameraViewController.isSupported {
            Button {
                isShowingDocumentCamera = true
            } label: {
                Label("Scan receipt", systemImage: "doc.viewfinder")
            }
            .buttonStyle(.brandPrimary)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(BrandTextButtonStyle(color: .secondary))
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.brandPrimary)
        }
    }

    @ViewBuilder
    private func resultDetails(for receipt: ReceiptScan) -> some View {
        if let total = receipt.total {
            if !receipt.items.isEmpty {
                SectionCaption(receipt.items.count == 1 ? "1 item found" : "\(receipt.items.count) items found")
                receiptItemList(receipt.items)
                Divider()
                    .padding(.vertical, 6)
            }

            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(total.lkr)
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)

            if !receipt.isTotalFromTotalLine {
                Label("No TOTAL line was found, so this is the largest amount. Check it before using it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.orangeText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The total can be more than the items, e.g. because of a service charge.
            let itemsSum = receipt.items.reduce(0) { $0 + $1.price }
            if !receipt.items.isEmpty && itemsSum != total {
                Text("The items add up to \(itemsSum.lkr). The rest may be tax or a service charge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(receipt.items.isEmpty ? "Use this amount" : "Use these items") {
                onUseReceipt(receipt)
                dismiss()
            }
            .buttonStyle(.brandPrimary)
            .padding(.top, 12)

            Button("Retake", action: retake)
                .buttonStyle(BrandTextButtonStyle(color: .secondary))
        } else {
            Text("No amount found")
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            Text("Retake the photo with the total in view, or type the amount yourself.")
                .foregroundStyle(.secondary)
            Button("Retake", action: retake)
                .buttonStyle(.brandPrimary)
                .padding(.top, 12)
        }
    }

    /// Each item on the receipt with its price. Long receipts scroll, so the buttons stay on screen.
    @ViewBuilder
    private func receiptItemList(_ items: [ReceiptScan.LineItem]) -> some View {
        let list = VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 2) {
                    Text(item.name)
                    Spacer(minLength: 12)
                    Text(item.price.lkr)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .accessibilityElement(children: .combine)
            }
        }

        if items.count > 4 {
            ScrollView {
                list
            }
            .frame(height: 150)
        } else {
            list
        }
    }

    // Actions

    /// Loads the photo chosen from Photos.
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                read(image)
            } else {
                step = .failed(nil, ReceiptScanError.unreadableImage.localizedDescription)
            }
        }
    }

    /// Reads the receipt and shows the total.
    private func read(_ image: UIImage) {
        step = .reading(image)
        Task {
            do {
                let receipt = try await scanner.scan(image)
                withAnimation { step = .result(image, receipt) }
            } catch {
                withAnimation { step = .failed(image, error.localizedDescription) }
            }
        }
    }

    /// Clears the photo so the student can try again.
    private func retake() {
        selectedPhoto = nil
        withAnimation { step = .choosing }
    }
}

/// The receipt photo, with an orange box around the total.
private struct ReceiptPhotoView: View {
    let image: UIImage
    /// Where the total is (Vision uses 0–1, from the bottom-left).
    let highlight: CGRect?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if let highlight {
                    GeometryReader { proxy in
                        // Vision measures from the bottom-left, SwiftUI from the top-left, so flip it.
                        let box = CGRect(
                            x: highlight.minX * proxy.size.width,
                            y: (1 - highlight.maxY) * proxy.size.height,
                            width: highlight.width * proxy.size.width,
                            height: highlight.height * proxy.size.height
                        )
                        .insetBy(dx: -10, dy: -8)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.orange, lineWidth: 3)
                            .background(Theme.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY)
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .accessibilityLabel("Photo of your receipt")
    }
}

/// Apple's document scanner. It finds the receipt's edges and straightens the photo.
struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { return onCancel() }
            onScan(scan.imageOfPage(at: 0))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}

/// The "New stamp earned!" pop-up.
struct StampEarnedPopup: View {
    let cuisine: Cuisine
    let quest: Quest
    let onViewPassport: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Starts the stamping animation when the pop-up appears.
    @State private var isStamped = false

    var body: some View {
        PopupCard {
            ZStack {
                Circle()
                    .strokeBorder(Theme.orange, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(isStamped ? 0 : -40))

                Circle()
                    .fill(Theme.primaryGradient)
                    .frame(width: 122, height: 122)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: cuisine.symbolName)
                                .font(.title.weight(.bold))
                                .symbolEffect(.bounce, value: reduceMotion ? false : isStamped)
                            Text(cuisine.rawValue.uppercased())
                                .font(.caption.weight(.heavy))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(10)
                        // It's artwork with a fixed size, so its text stops growing at large sizes.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                    .shadow(color: Theme.orange.opacity(0.4), radius: 12, y: 6)
            }
            .rotationEffect(.degrees(cuisine.stampTilt))
            .scaleEffect(isStamped || reduceMotion ? 1 : 1.35)
            .opacity(isStamped || reduceMotion ? 1 : 0)
            .onAppear {
                // With Reduce Motion on, the stamp just appears instead of spinning and bouncing in.
                if reduceMotion {
                    isStamped = true
                } else {
                    withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(0.1)) {
                        isStamped = true
                    }
                }
            }
            .sensoryFeedback(.success, trigger: isStamped)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("New stamp earned!")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Quest progress: \(quest.cuisinesTried) of \(quest.targetCuisines) cuisines")
                    .foregroundStyle(.secondary)
            }

            ProgressBar(value: quest.cuisineProgress, tint: Theme.orange, label: "Quest progress")
                .frame(maxWidth: 200)

            VStack(spacing: 10) {
                Button("View passport", action: onViewPassport)
                    .buttonStyle(.brandPrimary)
                Button("Done", action: onDone)
                    .buttonStyle(.brandTinted)
            }
            .padding(.top, 4)
        }
    }
}

// Previews

#Preview {
    LogVisitView(restaurant: MockData.campusBites)
        .previewInNavigationStack()
}

#Preview {
    MealCameraView(recognizer: MockMealRecognizer(), initialPhoto: UIImage(named: "dish_kottu")) { _ in }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            MealRecognitionSheet(photo: nil, predictions: MockData.mealPredictions, onConfirm: { _ in }, onEnterManually: {})
        }
}

#Preview {
    ReceiptScanView(scanner: MockReceiptScanner(), initialImage: UIImage(systemName: "doc.text")) { _ in }
}

#Preview {
    StampEarnedPopup(cuisine: .sriLankan, quest: MockData.activeQuest, onViewPassport: {}, onDone: {})
        .padding()
        .background(Color.black.opacity(0.4))
}
