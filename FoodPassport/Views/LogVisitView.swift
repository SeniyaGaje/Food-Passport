import SwiftUI
import AVFoundation
import PhotosUI
import VisionKit

/// "Log your visit" form — dish, cuisine, amount, rating and notes, with meal and receipt scanning.
struct LogVisitView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    let restaurant: Restaurant

    @State private var dish = ""
    @State private var cuisine = ""
    @State private var amount = ""
    @State private var rating = 0
    @State private var notes = ""
    @State private var hasMealPhoto = false
    @State private var isAmountFromReceipt = false
    @State private var isShowingMealCamera = false
    @State private var isShowingReceiptScanner = false

    private var selectedCuisine: Cuisine {
        Cuisine.allCases.first { $0.rawValue.caseInsensitiveCompare(cuisine) == .orderedSame } ?? restaurant.cuisine
    }

    /// The amount typed or scanned, ignoring anything that isn't a digit (e.g. "LKR" or commas).
    private var amountValue: Int? {
        Int(amount.filter(\.isNumber))
    }

    private var canSave: Bool {
        !dish.trimmed.isEmpty && (amountValue ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                restaurantCard

                mealScanArea

                field("Dish") {
                    InputField(placeholder: "What did you eat?", text: $dish)
                }

                field("Cuisine") {
                    InputField(placeholder: "Cuisine type", text: $cuisine)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionCaption("Spent (LKR)")
                        Spacer()
                        Button {
                            isShowingReceiptScanner = true
                        } label: {
                            Label(isAmountFromReceipt ? "Rescan receipt" : "Scan receipt", systemImage: "doc.text.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.orange)
                        }
                    }
                    InputField(placeholder: "Amount spent", text: $amount, prefix: amount.isEmpty ? nil : "LKR")
                        .keyboardType(.numberPad)
                }

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
        .fullScreenCover(isPresented: $isShowingMealCamera) {
            MealCameraView(menu: restaurant.popularDishes.map(\.name)) { prediction in
                dish = prediction.dishName
                cuisine = prediction.cuisine.rawValue
                hasMealPhoto = true
            }
        }
        .fullScreenCover(isPresented: $isShowingReceiptScanner) {
            ReceiptScanView { receipt in
                if let total = receipt.total {
                    amount = "\(total)"
                    isAmountFromReceipt = true
                }
                // Fill in the dish from the receipt if the student hasn't typed or scanned one yet.
                if dish.trimmed.isEmpty, let firstItem = receipt.items.first {
                    dish = firstItem.name
                }
            }
        }
    }

    private func saveVisit() {
        let visit = Visit(
            id: UUID().uuidString,
            dishName: dish.trimmed,
            cuisine: selectedCuisine,
            restaurant: restaurant,
            amount: amountValue ?? 0,
            rating: rating,
            notes: notes.trimmed,
            date: .now,
            // Only a visit logged at the restaurant itself is verified, and only verified visits earn stamps.
            isLocationVerified: appState.isAtRestaurant(restaurant),
            isAutoDetected: hasMealPhoto,
            isFromReceipt: isAmountFromReceipt,
            imageName: restaurant.imageName
        )

        if let stamp = appState.addVisit(visit) {
            router.present(.stampEarned(stamp.cuisine))
        } else {
            router.closeVisitLoggingScreens()
            router.showToast(visit.isLocationVerified ? "Visit logged ✓" : "Visit logged. Stamps need a verified location.")
        }
    }

    private var restaurantCard: some View {
        HStack(spacing: 14) {
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
    }

    @ViewBuilder
    private var mealScanArea: some View {
        if hasMealPhoto {
            // After a scan: confirmation that the dish was filled in, with a way to try again.
            Button {
                isShowingMealCamera = true
            } label: {
                HStack(spacing: 14) {
                    IconTile(systemImage: "checkmark", tint: Theme.green, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meal recognised")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Dish and cuisine filled in below")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Label("Retake", systemImage: "camera")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                }
                .cardStyle(padding: 14)
            }
            .buttonStyle(.pressableCard)
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
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(title)
            content()
        }
    }
}

/// Full-screen camera for photographing a meal. The dish is recognised on the device with Core ML (MobileCLIP).
struct MealCameraView: View {
    private enum Step {
        case camera
        case recognising(UIImage)
        case results(UIImage, [MealPrediction])
        /// Not a dish the app knows, or something went wrong.
        case problem(UIImage?, title: String, message: String)
    }

    private enum CameraStatus {
        case starting
        case running
        /// No camera, e.g. on the simulator.
        case unavailable
        case denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let menu: [String]
    private let recognizer: MealRecognizer
    private let initialPhoto: UIImage?
    private let onConfirm: (MealPrediction) -> Void

    @State private var camera = CameraService()
    @State private var cameraStatus = CameraStatus.starting
    @State private var step = Step.camera
    @State private var isFlashOn = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingResults = false
    @State private var confirmedPrediction: MealPrediction?
    @State private var wantsManualEntry = false

    /// - Parameters:
    ///   - menu: dish names on the restaurant's menu; the recogniser favours them.
    ///   - initialPhoto: a photo to recognise straight away, e.g. in previews.
    init(
        menu: [String] = [],
        recognizer: MealRecognizer = CoreMLMealRecognizer.shared,
        initialPhoto: UIImage? = nil,
        onConfirm: @escaping (MealPrediction) -> Void
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
            // Load the model while the student lines up the photo, so recognition is quick.
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
                    onConfirm: { prediction in
                        confirmedPrediction = prediction
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

    private func takePhoto() {
        Task {
            do {
                recognise(try await camera.takePhoto(withFlash: isFlashOn))
            } catch {
                step = .problem(nil, title: "Couldn't take the photo", message: error.localizedDescription)
            }
        }
    }

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

    private func notAMealMessage(_ lookalike: String) -> String {
        switch lookalike {
        case "Receipt": "It looks like a receipt. Use Scan receipt for the bill, and photograph your plate here."
        case "Unclear photo": "The photo is too dark or blurry. Retake it in better light with your plate in the frame."
        default: "It looks like a \(lookalike.lowercased()). Retake the photo with your plate in the middle of the frame."
        }
    }

    private func retake() {
        selectedPhoto = nil
        confirmedPrediction = nil
        wantsManualEntry = false
        step = .camera
    }

    private func handleResultsDismissed() {
        if let confirmedPrediction {
            onConfirm(confirmedPrediction)
            dismiss()
        } else if wantsManualEntry {
            dismiss()
        } else {
            // Swiped the results away: back to the camera for another try.
            retake()
        }
    }
}

/// Live picture from `CameraService`, filling the viewfinder.
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

/// "We found matches!" — the top three dishes from the on-device recogniser.
struct MealRecognitionSheet: View {
    let photo: UIImage?
    let predictions: [MealPrediction]
    let onConfirm: (MealPrediction) -> Void
    let onEnterManually: () -> Void

    @State private var selectedIndex = 0

    private var selected: MealPrediction {
        predictions[selectedIndex]
    }

    private var isConfident: Bool {
        (predictions.first?.confidence ?? 0) >= MealClassifier.confidentThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        FoodImageView(imageName: nil, cuisine: selected.cuisine)
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
                }
            }

            if !isConfident {
                Label("Not sure about this one. Tap the right dish, or enter it yourself.", systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(predictions.enumerated()), id: \.element.id) { index, prediction in
                Button {
                    selectedIndex = index
                } label: {
                    PredictionRow(prediction: prediction, isSelected: index == selectedIndex)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Suggested cuisine")
                    .foregroundStyle(.secondary)
                Spacer()
                PillLabel(text: selected.cuisine.rawValue, style: .green, font: .subheadline.weight(.semibold))
            }

            Button("Confirm \(selected.label)") {
                onConfirm(selected)
            }
            .buttonStyle(.brandPrimary)

            Button("Not right? Enter manually", action: onEnterManually)
                .buttonStyle(BrandTextButtonStyle(color: .secondary))
        }
        .padding(20)
        .presentationDetents([.fraction(0.75), .large])
        .brandSheetStyle()
    }
}

private struct PredictionRow: View {
    let prediction: MealPrediction
    let isSelected: Bool

    private var percentage: Int {
        Int((prediction.confidence * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
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
        .padding(16)
        .cardBackground(cornerRadius: 16, shadowStrength: 0.4)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.orange : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prediction.label), \(percentage) percent\(prediction.isOnMenu ? ", on the menu" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Reads the total from a photo of a receipt with Vision, on the device, and highlights it on the photo.
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

    /// - Parameter initialImage: a photo to read straight away, e.g. in previews.
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
        // The document scanner needs a real camera, so the simulator only offers the photo library.
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
        SectionCaption("Total detected")

        if let total = receipt.total {
            Text(total.lkr)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.ink)

            if !receipt.isTotalFromTotalLine {
                Label("No TOTAL line was found, so this is the largest amount. Check it before using it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.orange)
            }

            if !receipt.items.isEmpty {
                Text(receipt.items.map { "\($0.name) \($0.price.lkr)" }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button("Use this amount") {
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

    // Actions

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

    private func retake() {
        selectedPhoto = nil
        withAnimation { step = .choosing }
    }
}

/// The receipt photo, with an orange box around the total that Vision found.
private struct ReceiptPhotoView: View {
    let image: UIImage
    /// Vision's normalised coordinates (0–1, origin bottom-left).
    let highlight: CGRect?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if let highlight {
                    GeometryReader { proxy in
                        // Vision measures from the bottom-left corner; SwiftUI from the top-left.
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

/// VisionKit's document scanner: finds the receipt's edges and straightens the photo before Vision reads it.
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

/// "New stamp earned!" pop-up shown after a verified visit adds a new cuisine.
struct StampEarnedPopup: View {
    let cuisine: Cuisine
    let quest: Quest
    let onViewPassport: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the "stamp pressed onto the page" animation when the pop-up appears.
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
                                .symbolEffect(.bounce, value: isStamped)
                            Text(cuisine.rawValue.uppercased())
                                .font(.caption.weight(.heavy))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                    }
                    .shadow(color: Theme.orange.opacity(0.4), radius: 12, y: 6)
            }
            .rotationEffect(.degrees(cuisine.stampTilt))
            .scaleEffect(isStamped || reduceMotion ? 1 : 1.35)
            .opacity(isStamped || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(0.1)) {
                    isStamped = true
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

            ProgressBar(value: quest.cuisineProgress, tint: Theme.orange)
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
