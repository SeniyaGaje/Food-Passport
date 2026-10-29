import SwiftUI
import PhotosUI
import VisionKit

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
    /// True when the student already picked their dishes, so the receipt only adds prices.
    private let keepsYourItems: Bool
    private let onUseReceipt: (ReceiptScan) -> Void

    @State private var step: Step = .choosing
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingDocumentCamera = false

    /// `initialImage` is read straight away, for previews.
    init(
        scanner: ReceiptScanner = VisionReceiptScanner(),
        initialImage: UIImage? = nil,
        keepsYourItems: Bool = false,
        onUseReceipt: @escaping (ReceiptScan) -> Void
    ) {
        self.scanner = scanner
        self.initialImage = initialImage
        self.keepsYourItems = keepsYourItems
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

            if keepsYourItems && !receipt.items.isEmpty {
                Label("Your dishes stay as they are. Their prices and the total come from this receipt.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(useButtonTitle(for: receipt)) {
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

    private func useButtonTitle(for receipt: ReceiptScan) -> String {
        if receipt.items.isEmpty {
            return "Use this amount"
        }
        return keepsYourItems ? "Add these prices" : "Use these items"
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

// Previews

#Preview {
    ReceiptScanView(scanner: MockReceiptScanner(), initialImage: UIImage(systemName: "doc.text")) { _ in }
}
