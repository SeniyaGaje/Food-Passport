import CoreML
import Foundation
import UIKit
import Vision

/// One thing the recogniser can say a photo shows, with its MobileCLIP text embedding.
/// Made by Tools/make_dish_embeddings.py from Tools/dishes.json and bundled as ML/DishEmbeddings.json.
struct DishLabel: Decodable, Equatable {
    enum Kind: String, Decodable {
        /// A dish the app knows, with a cuisine (e.g. Kottu Roti).
        case dish
        /// Food that isn't one of the app's dishes (e.g. fruit or a drink).
        case otherFood
        /// Not a meal at all (e.g. a receipt or a selfie).
        case notFood
    }

    let id: String
    let name: String
    let cuisine: Cuisine?
    let kind: Kind
    /// Restaurant menu items this label stands for, e.g. "Kottu Roti" and "Chicken Kottu".
    let menuNames: [String]
    /// 512 numbers, length 1.
    let embedding: [Float]

    /// The name this dish has on `menu`, if it's on it.
    func menuName(in menu: [String]) -> String? {
        menu.first { item in menuNames.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }
    }
}

enum MealRecognition: Equatable {
    /// Up to three dishes, most likely first.
    case dishes([MealPrediction])
    /// Food, but not a dish the app knows. Carries what it looks like, e.g. "Drink".
    case unknownFood(String)
    /// Not a meal. Carries what it looks like, e.g. "Receipt".
    case notFood(String)
}

enum MealRecognitionError: LocalizedError {
    case unreadableImage
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be opened. Try another one."
        case .modelUnavailable: "Meal recognition isn't available right now. Enter the dish yourself."
        }
    }
}

/// Recognises the dish in a photo. The views only use this protocol, so previews and tests can use the mock.
protocol MealRecognizer {
    /// Loads the model ahead of time so the first photo is recognised quickly.
    func prepare() async
    /// - Parameter menu: the dishes on the menu of the restaurant being logged, which are favoured.
    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition
}

/// `MealRecognizer` that runs Apple's MobileCLIP-S1 image model with Core ML, entirely on the device.
///
/// MobileCLIP was trained to place photos and their descriptions close together, so the photo's embedding is
/// compared with an embedding of each dish's description. That lets it recognise Sri Lankan dishes such as
/// kottu and string hoppers that ready-made food classifiers (e.g. Food-101) were never trained on.
final class CoreMLMealRecognizer: MealRecognizer {
    /// One copy for the whole app, so the model is loaded only once.
    static let shared = CoreMLMealRecognizer()

    private var visionModel: VNCoreMLModel?
    private var labels: [DishLabel] = []

    func prepare() async {
        _ = try? await loadModel()
    }

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        guard let cgImage = image.cgImage else { throw MealRecognitionError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let model = try await loadModel()

        // Running the model takes a moment, so it happens off the main thread to keep the camera responsive.
        let embedding = try await Task.detached(priority: .userInitiated) {
            try Self.embedding(of: cgImage, orientation: orientation, model: model)
        }.value

        return MealClassifier.classify(embedding: embedding, labels: labels, menu: menu)
    }

    private func loadModel() async throws -> VNCoreMLModel {
        if let visionModel { return visionModel }

        guard let modelURL = Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlmodelc"),
              let labelsURL = Bundle.main.url(forResource: "DishEmbeddings", withExtension: "json")
        else { throw MealRecognitionError.modelUnavailable }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all  // lets Core ML use the Neural Engine
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)

        labels = try JSONDecoder().decode(DishEmbeddingsFile.self, from: Data(contentsOf: labelsURL)).labels
        let visionModel = try VNCoreMLModel(for: model)
        self.visionModel = visionModel
        return visionModel
    }

    /// The photo's MobileCLIP embedding, scaled to length 1.
    nonisolated private static func embedding(
        of image: CGImage,
        orientation: CGImagePropertyOrientation,
        model: VNCoreMLModel
    ) throws -> [Float] {
        let request = VNCoreMLRequest(model: model)
        // Same preparation MobileCLIP was trained with: shortest side scaled to 256, then the centre 256×256.
        request.imageCropAndScaleOption = .centerCrop

        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

        guard let output = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue else {
            throw MealRecognitionError.modelUnavailable
        }
        let values = (0..<output.count).map { output[$0].floatValue }
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        return values.map { $0 / length }
    }

    private struct DishEmbeddingsFile: Decodable {
        let labels: [DishLabel]
    }
}

/// Turns a photo embedding into dish predictions. Separate from Core ML so it can be unit tested.
enum MealClassifier {
    /// CLIP's learned "temperature": similarities (−1…1) are multiplied by 100 before softmax.
    static let logitScale: Float = 100
    /// A meal logged at a restaurant is more likely to be on its menu, so menu dishes count double.
    static let menuBoost = 2.0
    /// Below this, the sheet asks the student to check the dish.
    static let confidentThreshold = 0.4
    /// A non-dish label must be at least this likely before the app says "this isn't a meal".
    static let notMealThreshold = 0.5

    static func classify(embedding: [Float], labels: [DishLabel], menu: [String]) -> MealRecognition {
        guard !labels.isEmpty else { return .notFood("Unclear photo") }

        // Cosine similarity with every label (both have length 1), turned into probabilities with softmax.
        let logits = labels.map { label in
            Double(logitScale * zip(label.embedding, embedding).reduce(0) { $0 + $1.0 * $1.1 })
        }
        var probabilities = softmax(logits)

        // Favour the restaurant's own dishes, then make the probabilities add up to 1 again.
        for (index, label) in labels.enumerated() where label.menuName(in: menu) != nil {
            probabilities[index] *= menuBoost
        }
        let total = probabilities.reduce(0, +)
        probabilities = probabilities.map { $0 / total }

        let ranked = labels.indices.sorted { probabilities[$0] > probabilities[$1] }
        let best = labels[ranked[0]]

        if best.kind != .dish, probabilities[ranked[0]] >= notMealThreshold {
            return best.kind == .otherFood ? .unknownFood(best.name) : .notFood(best.name)
        }

        let predictions = ranked
            .filter { labels[$0].kind == .dish }
            .prefix(3)
            .compactMap { index -> MealPrediction? in
                let label = labels[index]
                guard let cuisine = label.cuisine else { return nil }
                let menuName = label.menuName(in: menu)
                return MealPrediction(
                    label: menuName ?? label.name,
                    dishName: menuName ?? label.name,
                    confidence: probabilities[index],
                    cuisine: cuisine,
                    isOnMenu: menuName != nil
                )
            }
        return .dishes(predictions)
    }

    private static func softmax(_ logits: [Double]) -> [Double] {
        let largest = logits.max() ?? 0
        let exponentials = logits.map { exp($0 - largest) }  // subtracting the largest avoids overflow
        let sum = exponentials.reduce(0, +)
        return exponentials.map { $0 / sum }
    }
}

/// `MealRecognizer` for previews and tests: returns a fixed result without running the model.
struct MockMealRecognizer: MealRecognizer {
    var result: MealRecognition = .dishes(MockData.mealPredictions)

    func prepare() async {}

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        result
    }
}
