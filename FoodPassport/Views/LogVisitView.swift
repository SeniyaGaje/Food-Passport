import SwiftUI

// MARK: - LogVisitView

/// "Log your visit" form — dish, cuisine, amount, rating and notes, with meal and receipt scanning.
struct LogVisitView: View {
    @Environment(AppRouter.self) private var router

    let restaurant: Restaurant

    @State private var dish = ""
    @State private var cuisine = ""
    @State private var amount = ""
    @State private var rating = 0
    @State private var notes = ""
    @State private var hasMealPhoto = false
    @State private var isShowingMealCamera = false
    @State private var isShowingReceiptScanner = false

    private var selectedCuisine: Cuisine {
        Cuisine.allCases.first { $0.rawValue.caseInsensitiveCompare(cuisine) == .orderedSame } ?? restaurant.cuisine
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
                            Label("Scan receipt", systemImage: "doc.text.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
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

                Button("Save visit") {
                    router.present(.stampEarned(selectedCuisine))
                }
                .buttonStyle(.brandPrimary)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle("Log your visit")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $isShowingMealCamera) {
            MealCameraView { prediction in
                dish = prediction.dishName
                cuisine = prediction.cuisine.rawValue
                hasMealPhoto = true
            }
        }
        .fullScreenCover(isPresented: $isShowingReceiptScanner) {
            ReceiptScanView(receipt: MockData.sampleReceipt) { total in
                amount = "\(total)"
            }
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
                PillLabel(text: "Location verified", trailingSystemImage: "checkmark")
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var mealScanArea: some View {
        if hasMealPhoto {
            FoodImageView(imageName: "dish_kottu", cuisine: selectedCuisine, cornerRadius: 20)
                .frame(height: 180)
                .overlay(alignment: .topLeading) {
                    PillLabel(text: "Auto-detected", systemImage: "sparkles", style: .orange)
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        isShowingMealCamera = true
                    } label: {
                        Label("Retake", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
        } else {
            Button {
                isShowingMealCamera = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 64)
                        .background(Color(hex: 0xE8E8EA), in: Circle())

                    Text("Scan your meal")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    Text("The dish is recognised on your device")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.systemGray4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(title)
            content()
        }
    }
}

// MARK: - MealCameraView

/// Full-screen camera for photographing a meal. Shows a placeholder viewfinder until the camera is wired up.
struct MealCameraView: View {
    @Environment(\.dismiss) private var dismiss

    let onConfirm: (MealPrediction) -> Void

    @State private var isShowingResults = false
    @State private var isFlashOn = false
    @State private var confirmedPrediction: MealPrediction?
    @State private var wantsManualEntry = false

    var body: some View {
        VStack(spacing: 0) {
            FoodImageView(imageName: "camera_preview_meal", cuisine: .sriLankan)
                .overlay { viewfinderFrame }
                .overlay(alignment: .top) { topControls }

            VStack(spacing: 16) {
                Button {
                    isShowingResults = true
                } label: {
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
                .accessibilityLabel("Take photo")

                Button("Choose from Photos") {
                    isShowingResults = true
                }
                .font(.headline)
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .sheet(isPresented: $isShowingResults, onDismiss: handleResultsDismissed) {
            MealRecognitionSheet(
                predictions: MockData.mealPredictions,
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

    private var topControls: some View {
        HStack {
            cameraControlButton(systemImage: "xmark", label: "Close") {
                dismiss()
            }
            Spacer()
            cameraControlButton(systemImage: isFlashOn ? "bolt.fill" : "bolt.slash.fill", label: "Flash") {
                isFlashOn.toggle()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var viewfinderFrame: some View {
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

    private func handleResultsDismissed() {
        if let confirmedPrediction {
            onConfirm(confirmedPrediction)
            dismiss()
        } else if wantsManualEntry {
            dismiss()
        }
    }
}

// MARK: - MealRecognitionSheet

/// "We found matches!" — top three dish predictions from the on-device model.
struct MealRecognitionSheet: View {
    let predictions: [MealPrediction]
    let onConfirm: (MealPrediction) -> Void
    let onEnterManually: () -> Void

    @State private var selectedIndex = 0

    private var selected: MealPrediction {
        predictions[selectedIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                FoodImageView(imageName: "camera_preview_meal", cuisine: selected.cuisine, cornerRadius: 14)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Detected on your device", systemImage: "iphone")
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("We found matches!")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                }
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
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - PredictionRow

private struct PredictionRow: View {
    let prediction: MealPrediction
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(prediction.label)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(verbatim: "\(Int(prediction.confidence * 100))%")
                    .font(.headline)
                    .foregroundStyle(isSelected ? Theme.ink : Color.secondary)
            }

            ProgressBar(
                value: prediction.confidence,
                tint: isSelected ? Theme.ink : Color(hex: 0xC7C7CC),
                height: 6
            )
        }
        .padding(16)
        .background(Color(hex: 0xF2F2F4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.orange : .clear, lineWidth: 2)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - ReceiptScanView

/// Full-screen receipt scanner showing the detected total.
struct ReceiptScanView: View {
    @Environment(\.dismiss) private var dismiss

    let receipt: ReceiptScan
    let onUseAmount: (Int) -> Void

    @State private var isReading = false

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

            ReceiptPaperView(receipt: receipt, highlightsTotal: !isReading)
                .padding(.horizontal, 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        .padding(.horizontal, 32)
                        .padding(.vertical, -16)
                }

            Spacer(minLength: 16)

            resultCard
        }
        .background(Color(hex: 0x2A2724).ignoresSafeArea())
        .statusBarHidden()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption("Total detected")

            if isReading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading receipt…")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 41)
            } else {
                Text(receipt.total.lkr)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            Button("Use this amount") {
                onUseAmount(receipt.total)
                dismiss()
            }
            .buttonStyle(.brandPrimary)
            .disabled(isReading)
            .padding(.top, 12)

            Button("Retake") { rescan() }
                .buttonStyle(BrandTextButtonStyle(color: .secondary))
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func rescan() {
        isReading = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { isReading = false }
        }
    }
}

// MARK: - ReceiptPaperView

private struct ReceiptPaperView: View {
    let receipt: ReceiptScan
    let highlightsTotal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(receipt.restaurantName)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)

            Text(receipt.timestamp)
                .frame(maxWidth: .infinity)

            DashedDivider()

            ForEach(receipt.items) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(item.price.lkr)
                }
            }

            DashedDivider()

            HStack {
                Text("TOTAL")
                Spacer()
                Text(receipt.total.lkr)
            }
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.orange.opacity(highlightsTotal ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.orange, lineWidth: highlightsTotal ? 2.5 : 0)
            }
            .animation(.easeInOut, value: highlightsTotal)
        }
        .font(.system(.subheadline, design: .monospaced))
        .foregroundStyle(Color(hex: 0x2B2B2B))
        .padding(22)
        .background(Color(hex: 0xFAFAF7))
        .rotationEffect(.degrees(-1.5))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - DashedDivider

private struct DashedDivider: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .frame(height: 1)
    }
}

// MARK: - StampEarnedPopup

/// "New stamp earned!" pop-up shown after a verified visit adds a new cuisine.
struct StampEarnedPopup: View {
    let cuisine: Cuisine
    let quest: Quest
    let onViewPassport: () -> Void
    let onDone: () -> Void

    var body: some View {
        PopupCard {
            ZStack {
                Circle()
                    .strokeBorder(Theme.orange, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                    .frame(width: 150, height: 150)

                Circle()
                    .fill(Theme.orange)
                    .frame(width: 122, height: 122)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: cuisine.symbolName)
                                .font(.title.weight(.bold))
                            Text(cuisine.rawValue.uppercased())
                                .font(.caption.weight(.heavy))
                        }
                        .foregroundStyle(.white)
                    }
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("New stamp earned!")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Quest progress: \(quest.cuisinesTried) of \(quest.targetCuisines) cuisines")
                    .foregroundStyle(.secondary)
            }

            ProgressBar(value: quest.cuisineProgress)
                .frame(width: 180)

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

// MARK: - Previews

#Preview {
    LogVisitView(restaurant: MockData.campusBites)
        .previewInNavigationStack()
}

#Preview {
    MealCameraView { _ in }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            MealRecognitionSheet(predictions: MockData.mealPredictions, onConfirm: { _ in }, onEnterManually: {})
        }
}

#Preview {
    ReceiptScanView(receipt: MockData.sampleReceipt) { _ in }
}

#Preview {
    StampEarnedPopup(cuisine: .sriLankan, quest: MockData.activeQuest, onViewPassport: {}, onDone: {})
        .padding()
        .background(Color.black.opacity(0.4))
}
