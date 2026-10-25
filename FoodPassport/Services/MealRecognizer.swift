import CoreML
import Foundation
import UIKit
import Vision

/// One label learned from the training photos.
struct MealClass: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let cuisine: Cuisine?
    let isDrink: Bool
    let menuNames: [String]

    var isOther: Bool { id == "other" }

    func menuName(in menu: [String]) -> String? {
        let matches = menu.filter { item in menuNames.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }
        // A general "Tea" result cannot tell plain tea from milk tea.
        return matches.count == 1 ? matches.first : nil
    }
}

/// Exported with the classifier, including its measured confidence threshold.
struct MealModelConfiguration: Codable, Equatable {
    let schemaVersion: Int
    let encoder: String
    let embeddingCount: Int
    let confidenceThreshold: Double
    let autoApplyEnabled: Bool
    let classes: [MealClass]

    static func load(from bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "FoodModel", withExtension: "json") else {
            throw MealRecognitionError.modelUnavailable
        }
        let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    func validate() throws {
        guard schemaVersion == 1, encoder == "MobileCLIP-S0", embeddingCount == 512,
              confidenceThreshold.isFinite, (0...1).contains(confidenceThreshold),
              classes.count >= 2, classes.filter(\.isOther).count == 1,
              Set(classes.map(\.name)).count == classes.count,
              Set(classes.map(\.id)).count == classes.count,
              classes.allSatisfy({ !$0.name.isEmpty && !$0.id.isEmpty }) else {
            throw MealRecognitionError.modelUnavailable
        }
    }
}

struct MealRecognition: Equatable {
    let predictions: [MealPrediction]
    let topLabel: String
    let confidence: Double
    let isOther: Bool
    /// Allows filling the editable visit form. It never saves a visit.
    let canAutoApply: Bool
}

enum MealRecognitionError: LocalizedError {
    case unreadableImage
    case modelUnavailable
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be opened. Try another one."
        case .modelUnavailable: "Meal recognition isn't available right now. Enter the dish yourself."
        case .invalidOutput: "The meal couldn't be recognised. Try another photo or enter it yourself."
        }
    }
}

protocol MealRecognizer {
    func prepare() async
    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition
}

/// MobileCLIP describes the image; our trained classifier names the meal.
final class CoreMLMealRecognizer: MealRecognizer {
    static let shared = CoreMLMealRecognizer()

    private var models: LoadedModels?
    private var loadingTask: Task<LoadedModels, Error>?

    private struct LoadedModels {
        let encoder: VNCoreMLModel
        let classifier: MLModel
        let configuration: MealModelConfiguration
    }

    func prepare() async {
        _ = try? await loadModels()
    }

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        guard let cgImage = image.cgImage else { throw MealRecognitionError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let loaded = try await loadModels()
        let encoder = loaded.encoder
        let classifier = loaded.classifier
        // Model work stays off the main thread, so the camera remains responsive.
        let probabilities = try await Task.detached(priority: .userInitiated) {
            let request = VNCoreMLRequest(model: encoder)
            request.imageCropAndScaleOption = .centerCrop
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
                  let embedding = observation.featureValue.shapedArrayValue(of: Float.self),
                  embedding.scalarCount == 512, embedding.scalars.allSatisfy(\.isFinite) else {
                throw MealRecognitionError.invalidOutput
            }
            let features = MLShapedArray<Float>(scalars: embedding.scalars, shape: [512])
            let input = try MLDictionaryFeatureProvider(dictionary: ["features": MLMultiArray(features)])
            let output = try classifier.prediction(from: input)
            guard let values = output.featureValue(for: "targetProbability"), values.type == .dictionary else {
                throw MealRecognitionError.invalidOutput
            }
            var probabilities: [String: Double] = [:]
            for (key, value) in values.dictionaryValue {
                guard let label = key as? String else { throw MealRecognitionError.invalidOutput }
                probabilities[label] = value.doubleValue
            }
            return probabilities
        }.value
        return try MealClassifier.parse(probabilities, configuration: loaded.configuration, menu: menu)
    }

    private func loadModels() async throws -> LoadedModels {
        if let models { return models }
        if let loadingTask { return try await loadingTask.value }
        let task = Task { () throws -> LoadedModels in
            let configuration = try MealModelConfiguration.load()
            guard let encoderURL = Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlmodelc"),
                  let classifierURL = Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc") else {
                throw MealRecognitionError.modelUnavailable
            }
            let compute = MLModelConfiguration()
            #if targetEnvironment(simulator)
            compute.computeUnits = .cpuOnly
            #else
            compute.computeUnits = .all
            #endif
            let encoder = try await MLModel.load(contentsOf: encoderURL, configuration: compute)
            let classifier = try await MLModel.load(contentsOf: classifierURL, configuration: compute)
            guard Set(classifier.modelDescription.classLabels as? [String] ?? []) == Set(configuration.classes.map(\.name)),
                  classifier.modelDescription.inputDescriptionsByName["features"]?.multiArrayConstraint?.shape == [512] else {
                throw MealRecognitionError.modelUnavailable
            }
            return LoadedModels(encoder: try VNCoreMLModel(for: encoder), classifier: classifier, configuration: configuration)
        }
        loadingTask = task
        do {
            let loaded = try await task.value
            models = loaded
            loadingTask = nil
            return loaded
        } catch {
            loadingTask = nil
            throw error
        }
    }
}

/// Keeps the trained probabilities unchanged, so the measured threshold still applies.
enum MealClassifier {
    static func parse(_ probabilities: [String: Double], configuration: MealModelConfiguration, menu: [String]) throws -> MealRecognition {
        try configuration.validate()
        guard Set(probabilities.keys) == Set(configuration.classes.map(\.name)),
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(probabilities.values.reduce(0, +) - 1) < 0.01 else {
            throw MealRecognitionError.invalidOutput
        }
        let ranked = configuration.classes.sorted {
            let first = probabilities[$0.name]!
            let second = probabilities[$1.name]!
            return first == second ? $0.name < $1.name : first > second
        }
        let best = ranked[0]
        let confidence = probabilities[best.name]!
        let predictions = ranked.filter { !$0.isOther }.prefix(3).map { label in
            let menuName = label.menuName(in: menu)
            return MealPrediction(label: label.name, dishName: menuName ?? label.name,
                                  confidence: probabilities[label.name]!, cuisine: label.cuisine,
                                  isOnMenu: menuName != nil, isDrink: label.isDrink)
        }
        return MealRecognition(predictions: predictions, topLabel: best.name, confidence: confidence,
                               isOther: best.isOther,
                               canAutoApply: configuration.autoApplyEnabled && !best.isOther && confidence >= configuration.confidenceThreshold)
    }
}

struct MockMealRecognizer: MealRecognizer {
    var result = MealRecognition(predictions: MockData.mealPredictions, topLabel: "Kottu Roti", confidence: 0.87,
                                 isOther: false, canAutoApply: true)
    var error: MealRecognitionError?

    func prepare() async {}

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        if let error { throw error }
        return result
    }
}
