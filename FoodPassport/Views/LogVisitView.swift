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
    @State private var mealPhotos: [MealPhoto] = []
    @State private var isSaving = false
    @State private var photoError: String?
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

    /// The first photo that can't prove this visit (reused, old or undated), if any.
    private var photoProblem: PhotoProblem? {
        mealPhotos.lazy.compactMap(\.problem).first
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

                if !mealPhotos.isEmpty { mealPhotosSection }

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
                    if isSaving { ProgressView().tint(.white) } else { Label("Save visit", systemImage: "checkmark.circle.fill") }
                }
                .buttonStyle(.brandPrimary)
                .disabled(!canSave || isSaving)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        // The last GPS fix may be old, so get a fresh one for verifying the visit.
        .onAppear { appState.refreshLocation() }
        .navigationTitle("Log your visit")
        .navigationBarTitleDisplayMode(.large)
        // Keep the total in step with the item prices, unless it was typed or came from a receipt.
        .onChange(of: itemsTotal) { _, newTotal in
            guard !hasTypedTotal && !isAmountFromReceipt else { return }
            amount = newTotal > 0 ? "\(newTotal)" : ""
        }
        .fullScreenCover(isPresented: $isShowingMealCamera) {
            MealCameraView(menu: restaurant.popularDishes.map(\.name)) { dishes, photo, takenAt in
                addScannedDishes(dishes)
                addMealPhoto(photo, takenAt: takenAt)
            }
        }
        .alert("Couldn't save visit", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(photoError ?? "") }
        .fullScreenCover(isPresented: $isShowingReceiptScanner) {
            ReceiptScanView(keepsYourItems: !namedItems.isEmpty) { receipt in
                useReceipt(receipt)
            }
        }
    }

    /// Adds the dishes picked after a meal scan, with the menu price when the restaurant sells them.
    private func addScannedDishes(_ dishes: [MealPrediction]) {
        guard !dishes.isEmpty else { return }
        var newItems: [VisitItemDraft] = []
        for dish in dishes {
            let menuDish = restaurant.popularDishes.first { $0.name.caseInsensitiveCompare(dish.dishName) == .orderedSame }
            let priceText = menuDish.map { "\($0.price)" } ?? ""
            newItems.append(VisitItemDraft(name: dish.dishName, priceText: priceText, cuisine: dish.cuisine,
                                           category: dish.category, isDrink: dish.isDrink, isFromScan: true))
        }

        items = items.filter { !$0.isEmpty } + newItems
        if cuisine.trimmed.isEmpty, let suggested = MealPrediction.suggestedCuisine(in: dishes) {
            cuisine = suggested.rawValue
        }
        hasMealPhoto = true
    }

    /// Keeps the photo with its fingerprint, and checks it's new (not reused or old).
    private func addMealPhoto(_ image: UIImage, takenAt: Date?) {
        let fingerprint = PhotoCheck.fingerprint(of: image)
        let problem = PhotoCheck.problem(fingerprint: fingerprint, takenAt: takenAt,
                                         earlierFingerprints: appState.earlierPhotoFingerprints)
        mealPhotos.append(MealPhoto(image: image, fingerprint: fingerprint, problem: problem))
    }

    /// Fills in prices and the total from a scanned receipt.
    /// Dishes the student already picked keep their names; they only get the receipt's prices.
    private func useReceipt(_ receipt: ReceiptScan) {
        items = VisitItemDraft.applyingReceipt(receipt.items, to: items)
        if let total = receipt.total {
            amount = "\(total)"
            isAmountFromReceipt = true
        }
    }

    /// Saves the visit. Shows the stamp pop-up if it earned one.
    private func saveVisit() {
        var savedItems: [VisitItem] = []
        for item in namedItems {
            savedItems.append(VisitItem(name: item.name.trimmed, price: item.price, cuisine: item.cuisine, category: item.category, isDrink: item.isDrink))
        }

        // A reused or old photo can't prove the student is here now, so the visit isn't verified.
        let isVerified = appState.isAtRestaurant(restaurant) && photoProblem == nil
        var visit = Visit(
            id: UUID().uuidString,
            dishName: savedItems.map(\.name).joined(separator: ", "),
            cuisine: selectedCuisine,
            restaurant: restaurant,
            amount: amountValue ?? 0,
            rating: rating,
            notes: notes.trimmed,
            date: .now,
            // Only visits logged at the restaurant are verified, and only those earn stamps.
            isLocationVerified: isVerified,
            // Only if a saved item still has the name the scanner gave it.
            isAutoDetected: namedItems.contains(where: \.isFromScan),
            isFromReceipt: isAmountFromReceipt,
            imageName: restaurant.imageName,
            items: savedItems
        )
        let fingerprints = mealPhotos.compactMap(\.fingerprint)
        visit.photoFingerprints = fingerprints.isEmpty ? nil : fingerprints

        isSaving = true
        Task {
            do {
                let result = try await appState.saveVisit(visit, photos: mealPhotos.map(\.image))
                if let stamp = result.stamp {
                    router.present(.stampEarned(stamp.cuisine))
                } else {
                    let message = if result.photosWaitingToUpload {
                        "Visit logged. Photos will upload when you're online."
                    } else if visit.isLocationVerified {
                        "Visit logged ✓"
                    } else if photoProblem != nil {
                        "Visit logged. Stamps need a new photo taken here."
                    } else {
                        "Visit logged. Stamps need a verified location."
                    }
                    router.finishLoggingVisit(message: message, budgetUpdate: result.budgetUpdate)
                }
            } catch {
                photoError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private var mealPhotosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption("Meal photos")
            Text("Photos upload when you save. If you're offline, they upload later.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(mealPhotos.enumerated()), id: \.element.id) { index, photo in
                        Image(uiImage: photo.image)
                            .resizable().scaledToFill()
                            .frame(width: 100, height: 100).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                if photo.problem != nil {
                                    RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.gold, lineWidth: 3)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { mealPhotos.removeAll { $0.id == photo.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Remove meal photo \(index + 1)")
                            }
                            .accessibilityLabel(photo.problem.map { "Meal photo \(index + 1). \($0.message)" } ?? "Meal photo \(index + 1)")
                    }
                }
            }
            if let photoProblem {
                Label {
                    Text("\(photoProblem.message) It won't verify this visit, so it can't earn a stamp. Take a new photo here instead.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
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
                let check = appState.locationCheck(for: restaurant)
                if check == .verified {
                    PillLabel(text: check.message, trailingSystemImage: "checkmark", style: .green)
                } else {
                    PillLabel(text: check.message, systemImage: check == .outOfDate ? "location" : "location.slash")
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
        let name = Binding<String>(
            get: { item.wrappedValue.name },
            set: { text in
                item.wrappedValue.name = text
                // A renamed item may no longer match the scan's suggested details.
                item.wrappedValue.cuisine = nil
                item.wrappedValue.category = nil
                item.wrappedValue.isDrink = nil
                item.wrappedValue.isFromScan = false
            }
        )
        // Name and price side by side; one above the other with very large text.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            InputField(placeholder: "Dish or drink", text: name)

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

// Previews

#Preview {
    LogVisitView(restaurant: MockData.campusBites)
        .previewInNavigationStack()
}

/// A meal photo on the form, with its fingerprint and anything that stops it proving the visit.
struct MealPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let fingerprint: String?
    let problem: PhotoProblem?
}
