import SwiftUI

/// Shows a saved photo when this device has it, otherwise the existing illustration.
struct VisitPhotoView: View {
    @Environment(AppState.self) private var appState
    let photoID: String?
    let fallbackImage: String
    let cuisine: Cuisine
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                FoodImageView(imageName: fallbackImage, cuisine: cuisine)
            }
        }
        .task(id: photoID) {
            image = nil
            guard let photoID else { return }
            let saved = await appState.mealPhoto(id: photoID)
            if !Task.isCancelled { image = saved }
        }
    }
}

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

private struct SavedMealPhoto: View {
    @Environment(AppState.self) private var appState
    let id: String
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Your saved meal photo")
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                ContentUnavailableView("Photo unavailable on this device", systemImage: "photo",
                    description: Text("Meal photos are saved on the device where the visit was logged."))
                    .foregroundStyle(.white)
            }
        }
        .task(id: id) {
            let saved = await appState.mealPhoto(id: id)
            if !Task.isCancelled {
                image = saved
                isLoading = false
            }
        }
    }
}
