import SwiftUI

/// Shows a saved photo when this device has it, otherwise the existing illustration.
struct VisitPhotoView: View {
    @Environment(AppState.self) private var appState
    let photoID: String?
    let fallbackImage: String
    let cuisine: Cuisine
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                FoodImageView(imageName: fallbackImage, cuisine: cuisine)
            }
        }
        .overlay { if isLoading { ProgressView().padding(6).background(.regularMaterial, in: Circle()) } }
        .task(id: photoID) {
            image = nil
            guard let photoID else { return }
            isLoading = true
            defer { isLoading = false }
            let saved = await appState.mealPhoto(id: photoID)
            if !Task.isCancelled { image = saved }
        }
    }
}

/// Full-screen gallery of a visit's photos; swipe between them.
struct VisitPhotoGallery: View {
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    let startingAt: Int
    @State private var selected = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    SavedMealPhoto(id: id).tag(index)
                }
            }
            .tabViewStyle(.page)
            .background(.black)
            .navigationTitle("Photo \(selected + 1) of \(ids.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { selected = min(max(startingAt, 0), max(ids.count - 1, 0)) }
    }
}

/// One saved photo, loaded by its ID, with Retry if it can't load.
private struct SavedMealPhoto: View {
    @Environment(AppState.self) private var appState
    let id: String
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var retry = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Your saved meal photo")
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                ContentUnavailableView {
                    Label("Photo unavailable", systemImage: "photo")
                } description: {
                    Text("Connect to the internet and retry. Older photos saved only on another device cannot be downloaded.")
                } actions: {
                    Button("Retry") { retry += 1 }.buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            }
        }
        .task(id: "\(id)-\(retry)") {
            isLoading = true
            let saved = await appState.mealPhoto(id: id)
            if !Task.isCancelled {
                image = saved
                isLoading = false
            }
        }
    }
}
