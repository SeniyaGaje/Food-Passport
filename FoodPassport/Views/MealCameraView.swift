import SwiftUI
import AVFoundation
import PhotosUI

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
    /// The dishes picked, the photo, and when it was taken (nil if a photo from Photos has no date).
    private let onConfirm: ([MealPrediction], UIImage, Date?) -> Void

    @State private var camera = CameraService()
    @State private var cameraStatus = CameraStatus.starting
    @State private var step = Step.camera
    @State private var isFlashOn = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// When the photo being recognised was taken.
    @State private var photoTakenAt: Date?
    @State private var isShowingResults = false
    @State private var confirmedDishes: [MealPrediction] = []
    @State private var wantsManualEntry = false
    @State private var review: MealScanViewModel

    /// `menu` is the restaurant's dishes (they get a boost).
    /// `initialPhoto` is recognised straight away, for previews.
    init(
        menu: [String] = [],
        recognizer: MealRecognizer = CoreMLMealRecognizer.shared,
        initialPhoto: UIImage? = nil,
        onConfirm: @escaping ([MealPrediction], UIImage, Date?) -> Void
    ) {
        self.menu = menu
        self.recognizer = recognizer
        self.initialPhoto = initialPhoto
        self.onConfirm = onConfirm
        _review = State(initialValue: MealScanViewModel(recognizer: recognizer))
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
            review.reject()
        }
        .onChange(of: selectedPhoto) { _, item in
            loadPhoto(item)
        }
        .sheet(isPresented: $isShowingResults, onDismiss: handleResultsDismissed) {
            if case .results(let photo, _) = step {
                MealRecognitionSheet(
                    photo: photo,
                    review: review,
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
                Button("Enter manually", action: finishManualEntry)
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
                let photo = try await camera.takePhoto(withFlash: isFlashOn)
                photoTakenAt = .now
                recognise(photo)
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
                photoTakenAt = PhotoCheck.captureDate(of: data)
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
            await review.scan(photo, menu: menu)
            if let result = review.result {
                step = .results(photo, result.predictions)
                isShowingResults = true
            } else if let message = review.errorMessage {
                step = .problem(photo, title: "Couldn't recognise the photo", message: message)
            }
        }
    }

    /// Clears the photo so the student can try again.
    private func retake() {
        review.reject()
        selectedPhoto = nil
        confirmedDishes = []
        wantsManualEntry = false
        step = .camera
    }

    /// Runs when the results sheet closes, however it was closed.
    private func handleResultsDismissed() {
        if !confirmedDishes.isEmpty {
            if case .results(let photo, _) = step { onConfirm(confirmedDishes, photo, photoTakenAt) }
            dismiss()
        } else if wantsManualEntry {
            finishManualEntry()
        } else {
            // They swiped the results away, so go back to the camera.
            retake()
        }
    }

    /// Keep a valid photo even when the student types the food name themselves.
    private func finishManualEntry() {
        switch step {
        case .results(let photo, _), .problem(let photo?, _, _):
            onConfirm([], photo, photoTakenAt)
        default:
            break
        }
        review.reject()
        dismiss()
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

/// Review each detected item. Its three rows are alternative names, not three foods.
struct MealRecognitionSheet: View {
    let photo: UIImage?
    let review: MealScanViewModel
    let onConfirm: ([MealPrediction]) -> Void
    let onEnterManually: () -> Void

    private var confirmTitle: String {
        let count = review.selectedDishes.count
        return count == 0 ? "Choose at least one item" : (count == 1 ? "Add selected item" : "Add \(count) items")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(review.regions.count > 1 ? "Review your meal" : "Choose your meal")
                    .font(.title2.bold()).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose one name for each item you had. Nothing is selected for you.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let photo {
                    MealRegionPhoto(photo: photo, regions: review.regions.count > 1 ? review.regions : [])
                }
                ForEach(review.regions) { region in
                    VStack(alignment: .leading, spacing: 10) {
                        if review.regions.count > 1 {
                            Text("Item \(region.id)").font(.headline).foregroundStyle(Theme.ink)
                        }
                        if region.isOther {
                            Label("This may be something else. Check the alternatives or enter it yourself.", systemImage: "questionmark.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(region.predictions) { prediction in
                            Button {
                                review.toggle(prediction.label, in: region.id)
                            } label: {
                                PredictionRow(prediction: prediction, isSelected: review.choices[region.id] == prediction.label)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Missing an item? You can scan it separately after adding these.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(confirmTitle) {
                    if let dishes = review.confirm() { onConfirm(dishes) }
                }
                .buttonStyle(.brandPrimary)
                .disabled(review.selectedDishes.isEmpty)
                Button("Enter manually", action: onEnterManually)
                    .buttonStyle(BrandTextButtonStyle(color: .secondary))
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .brandSheetStyle()
        .sensoryFeedback(.selection, trigger: review.choices)
    }
}

private struct MealRegionPhoto: View {
    let photo: UIImage
    let regions: [MealRegion]

    var body: some View {
        Image(uiImage: photo).resizable().scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    ForEach(regions) { region in
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.orange, lineWidth: 2)
                            .overlay(alignment: .topLeading) {
                                Text("\(region.id)").font(.caption.bold()).padding(6)
                                    .foregroundStyle(.white).background(Theme.orange, in: Circle())
                            }
                            .frame(width: region.bounds.width * proxy.size.width, height: region.bounds.height * proxy.size.height)
                            .position(x: region.bounds.midX * proxy.size.width, y: region.bounds.midY * proxy.size.height)
                    }
                }
                .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel(regions.isEmpty ? "Your meal photo" : "Meal photo with \(regions.count) marked items")
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

                Text([prediction.isDrink ? "Drink" : "Food", prediction.category,
                      prediction.cuisine.map { "Suggested cuisine: " + $0.rawValue }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
        .accessibilityLabel([prediction.label, "\(percentage) percent confidence", prediction.isDrink ? "Drink" : "Food",
                             prediction.category, prediction.cuisine.map { "Suggested cuisine: " + $0.rawValue },
                             prediction.isOnMenu ? "On the menu" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(isSelected ? "Double-tap to untick" : "Double-tap to tick")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// Previews

#Preview {
    MealCameraView(recognizer: MockMealRecognizer(), initialPhoto: UIImage(named: "dish_kottu")) { _, _, _ in }
}

#Preview {
    let review = MealScanViewModel(recognizer: MockMealRecognizer())
    Color.black
        .sheet(isPresented: .constant(true)) {
            MealRecognitionSheet(photo: nil, review: review, onConfirm: { _ in }, onEnterManually: {})
                .task { await review.scan(UIImage(), menu: []) }
        }
}
