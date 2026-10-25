import CoreML
import Foundation
import UIKit
import Vision

/// Something the recogniser can say a photo shows, e.g. "Kottu Roti" or "Receipt".
/// Loaded from ML/DishEmbeddings.json, which Tools/make_dish_embeddings.py creates.
struct DishLabel: Decodable, Equatable {
    enum Kind: String, Decodable {
        /// A dish the app knows, e.g. Kottu Roti.
        case dish
        /// A drink the app knows, e.g. Plain Tea or Iced Coffee. Some drinks have no cuisine.
        case drink
        /// Food that isn't one of our dishes, e.g. fruit.
        case otherFood
        /// Not food at all, e.g. a receipt or a selfie.
        case notFood

        /// Dishes and drinks can be added to a visit; the other kinds can't.
        var isMenuItem: Bool {
            self == .dish || self == .drink
        }
    }

    let id: String
    let name: String
    let cuisine: Cuisine?
    let kind: Kind
    /// Menu names this dish goes by, e.g. "Kottu Roti" and "Chicken Kottu".
    let menuNames: [String]
    /// 512 numbers that describe the dish (made by MobileCLIP from its description).
    let embedding: [Float]

    /// What this dish is called on the restaurant's menu, or nil if it isn't on it.
    func menuName(in menu: [String]) -> String? {
        for item in menu {
            for name in menuNames where name.caseInsensitiveCompare(item) == .orderedSame {
                return item
            }
        }
        return nil
    }
}

enum MealRecognition: Equatable {
    /// Up to three dishes or drinks, most likely first.
    case dishes([MealPrediction])
    /// Food, but not one we know, e.g. "Fruit".
    case unknownFood(String)
    /// Not a meal, e.g. "Receipt".
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

/// Recognises the dish in a photo.
/// Screens use this protocol, so previews and tests can swap in the mock.
protocol MealRecognizer {
    /// Loads the model early so the first photo is quick.
    func prepare() async
    /// `menu` is the restaurant's dishes; they get a boost because they're more likely.
    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition
}

/// Recognises meals with Apple's MobileCLIP model (Core ML), all on the phone.
/// MobileCLIP turns a photo into 512 numbers. We compare those with the numbers for each
/// dish description, so it can recognise local dishes like kottu that normal food models don't know.
final class CoreMLMealRecognizer: MealRecognizer {
    /// One shared copy, so the model is only loaded once.
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

        // Running the model takes a moment, so do it in the background to keep the camera smooth.
        let embedding = try await Task.detached(priority: .userInitiated) {
            try Self.embedding(of: cgImage, orientation: orientation, model: model)
        }.value

        return MealClassifier.classify(embedding: embedding, labels: labels, menu: menu)
    }

    /// Loads the model and the dish labels the first time, then reuses them.
    private func loadModel() async throws -> VNCoreMLModel {
        if let visionModel { return visionModel }

        guard let modelURL = Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlmodelc"),
              let labelsURL = Bundle.main.url(forResource: "DishEmbeddings", withExtension: "json")
        else { throw MealRecognitionError.modelUnavailable }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all  // allows the Neural Engine, which is fastest
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)

        labels = try JSONDecoder().decode(DishEmbeddingsFile.self, from: Data(contentsOf: labelsURL)).labels
        let visionModel = try VNCoreMLModel(for: model)
        self.visionModel = visionModel
        return visionModel
    }

    /// Runs the model on the photo and returns its 512 numbers.
    nonisolated private static func embedding(
        of image: CGImage,
        orientation: CGImagePropertyOrientation,
        model: VNCoreMLModel
    ) throws -> [Float] {
        let request = VNCoreMLRequest(model: model)
        // Crop the middle square of the photo, the same way MobileCLIP was trained.
        request.imageCropAndScaleOption = .centerCrop

        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

        let observation = request.results?.first as? VNCoreMLFeatureValueObservation
        guard let output = observation?.featureValue.multiArrayValue else {
            throw MealRecognitionError.modelUnavailable
        }

        var values: [Float] = []
        for index in 0..<output.count {
            values.append(output[index].floatValue)
        }

        // Scale the numbers to length 1, like the dish embeddings, so they can be compared.
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        return values.map { $0 / length }
    }

    private struct DishEmbeddingsFile: Decodable {
        let labels: [DishLabel]
    }
}

/// Works out which dish a photo shows from its 512 numbers.
/// It doesn't need Core ML, so it's easy to unit test.
enum MealClassifier {
    /// MobileCLIP's setting: similarities are multiplied by 100 before turning them into chances.
    static let logitScale: Float = 100
    /// Dishes on the restaurant's menu count double.
    static let menuBoost = 2.0
    /// Below this chance, the screen asks the student to check the dish.
    static let confidentThreshold = 0.4
    /// Only say "this isn't a meal" when we're at least this sure.
    static let notMealThreshold = 0.5

    static func classify(embedding: [Float], labels: [DishLabel], menu: [String]) -> MealRecognition {
        guard !labels.isEmpty else { return .notFood("Unclear photo") }

        // How similar the photo is to each label, turned into chances that add up to 1.
        let scores = labels.map { Double(logitScale * dotProduct(embedding, $0.embedding)) }
        var chances = softmax(scores)

        // Boost the restaurant's own dishes, then make the chances add up to 1 again.
        for (index, label) in labels.enumerated() where label.menuName(in: menu) != nil {
            chances[index] *= menuBoost
        }
        let total = chances.reduce(0, +)
        chances = chances.map { $0 / total }

        // Label positions, most likely first.
        let ranked = labels.indices.sorted { chances[$0] > chances[$1] }
        let best = labels[ranked[0]]

        // The photo is most likely not one of our dishes or drinks, and we're fairly sure.
        if !best.kind.isMenuItem && chances[ranked[0]] >= notMealThreshold {
            if best.kind == .otherFood {
                return .unknownFood(best.name)
            }
            return .notFood(best.name)
        }

        // Otherwise suggest the top three dishes and drinks.
        var predictions: [MealPrediction] = []
        let topItems = ranked.filter { labels[$0].kind.isMenuItem }.prefix(3)
        for index in topItems {
            let label = labels[index]
            // Every dish has a cuisine; only drinks may leave it out.
            if label.kind == .dish && label.cuisine == nil { continue }

            let menuName = label.menuName(in: menu)
            predictions.append(MealPrediction(
                label: menuName ?? label.name,
                dishName: menuName ?? label.name,
                confidence: chances[index],
                cuisine: label.cuisine,
                isOnMenu: menuName != nil,
                isDrink: label.kind == .drink
            ))
        }
        return .dishes(predictions)
    }

    /// How alike two lists of numbers are (1 means the same, 0 means unrelated).
    private static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for (x, y) in zip(a, b) {
            sum += x * y
        }
        return sum
    }

    /// Turns scores into chances between 0 and 1 that add up to 1.
    private static func softmax(_ scores: [Double]) -> [Double] {
        let largest = scores.max() ?? 0
        let exponentials = scores.map { exp($0 - largest) }  // subtracting the largest stops overflow
        let sum = exponentials.reduce(0, +)
        return exponentials.map { $0 / sum }
    }
}

/// Fake recogniser for previews and tests. Returns a fixed result without running the model.
struct MockMealRecognizer: MealRecognizer {
    var result: MealRecognition = .dishes(MockData.mealPredictions)

    func prepare() async {}

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        result
    }
}
