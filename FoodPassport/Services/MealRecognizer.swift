import CoreML
import CoreImage
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
    var category: String? = nil

    var isOther: Bool { id == "other" }

    // The restaurant's own name for this dish, if exactly one menu item matches.
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
    let requiresConfirmation: Bool
    let classes: [MealClass]

    // Reads FoodModel.json from the app and checks it.
    static func load(from bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "FoodModel", withExtension: "json") else {
            throw MealRecognitionError.modelUnavailable
        }
        let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    // Checks the file matches the model the app expects, so a wrong file is never used.
    func validate() throws {
        guard schemaVersion == 2, requiresConfirmation, encoder == "MobileCLIP-S0", embeddingCount == 512,
              confidenceThreshold.isFinite, (0...1).contains(confidenceThreshold),
              classes.count >= 2, classes.filter(\.isOther).count == 1,
              Set(classes.map(\.name)).count == classes.count,
              Set(classes.map(\.id)).count == classes.count,
              classes.allSatisfy({ !$0.name.isEmpty && !$0.id.isEmpty }) else {
            throw MealRecognitionError.modelUnavailable
        }
    }
}

/// What the recogniser found: three suggestions for the whole photo, plus one entry per detected item.
struct MealRecognition: Equatable {
    let predictions: [MealPrediction]
    let topLabel: String
    let confidence: Double
    let isOther: Bool
    let isConfident: Bool
    var regions: [MealRegion] = []
}

/// A separate object in the photo, with three alternative names for that object.
struct MealRegion: Identifiable, Equatable {
    let id: Int
    /// Normalised coordinates from the top-left of the upright photo.
    let bounds: CGRect
    let predictions: [MealPrediction]
    let isOther: Bool
}

/// Problems shown to the student, with what to do next.
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

/// The meal recogniser. Screens use this protocol, so tests can use the mock instead.
protocol MealRecognizer {
    func prepare() async
    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition
}

/// MobileCLIP describes the image; our trained classifier names the meal.
final class CoreMLMealRecognizer: MealRecognizer {
    // One shared recogniser, so the models load only once.
    static let shared = CoreMLMealRecognizer()

    private var models: LoadedModels?
    private var loadingTask: Task<LoadedModels, Error>?

    // The three Core ML models and the label catalogue, loaded together.
    private struct LoadedModels {
        let encoder: VNCoreMLModel
        let classifier: MLModel
        let detector: VNCoreMLModel
        let configuration: MealModelConfiguration
    }

    // Loads the models early (e.g. when the camera opens), so the first scan is quicker.
    func prepare() async {
        _ = try? await loadModels()
    }

    /// Finds the dishes in a photo: the whole photo first, then each item if there are two or more.
    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        guard let cgImage = image.cgImage else { throw MealRecognitionError.unreadableImage }
        // Vision needs to know which way up the photo is.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let loaded = try await loadModels()
        let encoder = loaded.encoder
        let classifier = loaded.classifier
        let detector = loaded.detector
        // The heavy work runs off the main thread, so the screen stays smooth.
        let analysis = try await Task.detached(priority: .userInitiated) {
            let upright: CGImage
            if orientation == .up {
                upright = cgImage
            } else {
                let oriented = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientation.rawValue))
                // Keep an 8-bit image; a floating-point render changes the detector's input.
                guard let rotated = CIContext(options: [.cacheIntermediates: false]).createCGImage(
                    oriented, from: oriented.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                    throw MealRecognitionError.unreadableImage
                }
                upright = rotated
            }
            // Step 1: classify the whole photo.
            let whole = try Self.probabilities(for: upright, encoder: encoder, classifier: classifier)
            // Step 2: YOLOv3-tiny finds separate food and drink items.
            let request = VNCoreMLRequest(model: detector)
            request.imageCropAndScaleOption = .scaleFit
            try VNImageRequestHandler(cgImage: upright).perform([request])
            let objects = (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { observation -> DetectedMealObject? in
                guard let label = observation.labels.first else { return nil }
                return DetectedMealObject(bounds: observation.boundingBox, label: label.identifier, confidence: Double(label.confidence))
            }
            // Keep only food boxes, without duplicates.
            let boxes = MealRegionGeometry.regions(from: objects)
            var crops: [(CGRect, [String: Double])] = []
            // Step 3: with two or more items, crop and classify each one.
            if boxes.count >= 2 {
                for box in boxes {
                    let rect = MealRegionGeometry.cropRect(box, imageSize: CGSize(width: upright.width, height: upright.height))
                    if let crop = upright.cropping(to: rect) {
                        crops.append((box, try Self.probabilities(for: crop, encoder: encoder, classifier: classifier)))
                    }
                }
            }
            return (whole, crops)
        }.value
        // Turn the scores into the top-three suggestions, for the whole photo and each item.
        var result = try MealClassifier.parse(analysis.0, configuration: loaded.configuration, menu: menu)
        for (index, crop) in analysis.1.enumerated() {
            let item = try MealClassifier.parse(crop.1, configuration: loaded.configuration, menu: menu)
            result.regions.append(MealRegion(id: index + 1, bounds: crop.0, predictions: item.predictions, isOther: item.isOther))
        }
        return result
    }

    /// MobileCLIP turns the image into 512 numbers; the trained classifier turns those into a score per label.
    nonisolated private static func probabilities(for image: CGImage, encoder: VNCoreMLModel, classifier: MLModel) throws -> [String: Double] {
        let request = VNCoreMLRequest(model: encoder)
        // Crop the centre, exactly as in training.
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
              let embedding = observation.featureValue.shapedArrayValue(of: Float.self),
              embedding.scalarCount == 512, embedding.scalars.allSatisfy(\.isFinite) else {
            throw MealRecognitionError.invalidOutput
        }
        // Feed the 512 numbers into the classifier's "features" input.
        let features = MLShapedArray<Float>(scalars: embedding.scalars, shape: [512])
        let input = try MLDictionaryFeatureProvider(dictionary: ["features": MLMultiArray(features)])
        let output = try classifier.prediction(from: input)
        // Its output is a probability for every label.
        guard let values = output.featureValue(for: "targetProbability"), values.type == .dictionary else {
            throw MealRecognitionError.invalidOutput
        }
        var probabilities: [String: Double] = [:]
        for (key, value) in values.dictionaryValue {
            guard let label = key as? String else { throw MealRecognitionError.invalidOutput }
            probabilities[label] = value.doubleValue
        }
        return probabilities
    }

    /// Loads the three models once. Callers that arrive while loading wait for the same task.
    private func loadModels() async throws -> LoadedModels {
        if let models { return models }
        if let loadingTask { return try await loadingTask.value }
        let task = Task { () throws -> LoadedModels in
            let configuration = try MealModelConfiguration.load()
            guard let encoderURL = Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlmodelc"),
                  let classifierURL = Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc"),
                  let detectorURL = Bundle.main.url(forResource: "MealObjectDetector", withExtension: "mlmodelc") else {
                throw MealRecognitionError.modelUnavailable
            }
            let compute = MLModelConfiguration()
            // The Simulator has no Neural Engine, so it uses the CPU; a phone uses everything.
            #if targetEnvironment(simulator)
            compute.computeUnits = .cpuOnly
            #else
            compute.computeUnits = .all
            #endif
            let encoder = try await MLModel.load(contentsOf: encoderURL, configuration: compute)
            let classifier = try await MLModel.load(contentsOf: classifierURL, configuration: compute)
            let detector = try await MLModel.load(contentsOf: detectorURL, configuration: compute)
            // The classifier's labels must match FoodModel.json, and its input must be 512 numbers.
            guard Set(classifier.modelDescription.classLabels as? [String] ?? []) == Set(configuration.classes.map(\.name)),
                  classifier.modelDescription.inputDescriptionsByName["features"]?.multiArrayConstraint?.shape == [512] else {
                throw MealRecognitionError.modelUnavailable
            }
            return LoadedModels(encoder: try VNCoreMLModel(for: encoder), classifier: classifier, detector: try VNCoreMLModel(for: detector), configuration: configuration)
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
        // Every label needs a valid score, and the scores must add up to 1.
        guard Set(probabilities.keys) == Set(configuration.classes.map(\.name)),
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(probabilities.values.reduce(0, +) - 1) < 0.01 else {
            throw MealRecognitionError.invalidOutput
        }
        // Rank the labels by score; ties are broken alphabetically.
        let ranked = configuration.classes.sorted {
            let first = probabilities[$0.name]!
            let second = probabilities[$1.name]!
            return first == second ? $0.name < $1.name : first > second
        }
        let best = ranked[0]
        let confidence = probabilities[best.name]!
        // The top three real dishes (never Other), using the restaurant's menu name if it has one.
        let predictions = ranked.filter { !$0.isOther }.prefix(3).map { label in
            let menuName = label.menuName(in: menu)
            return MealPrediction(label: label.name, dishName: menuName ?? label.name,
                                  confidence: probabilities[label.name]!, cuisine: label.cuisine,
                                  isOnMenu: menuName != nil, isDrink: label.isDrink, category: label.category)
        }
        // isConfident is only used for the evaluation; the student always chooses.
        return MealRecognition(predictions: predictions, topLabel: best.name, confidence: confidence,
                               isOther: best.isOther,
                               isConfident: !best.isOther && confidence >= configuration.confidenceThreshold)
    }
}

/// A fake recogniser for previews and tests, with a fixed result or error.
struct MockMealRecognizer: MealRecognizer {
    var result = MealRecognition(predictions: MockData.mealPredictions, topLabel: "Kottu Roti", confidence: 0.87,
                                 isOther: false, isConfident: true)
    var error: MealRecognitionError?

    func prepare() async {}

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        if let error { throw error }
        return result
    }
}
