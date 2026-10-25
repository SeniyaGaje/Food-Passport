// Train the small classifier: swift MLTraining/train_model.swift
import Foundation
import CoreML
import CreateMLComponents
import Vision
import ImageIO
import CryptoKit

struct Photo {
    let label: String
    let file: String
    let split: String
    let hash: String
}

struct EmbeddedPhoto: Codable {
    let values: [Float]
    let mirroredValues: [Float]?
}

struct EmbeddingCache: Codable {
    let encoderHash: String
    let photos: [String: EmbeddedPhoto]
}

struct ScoredPhoto: Codable {
    let label: String
    let file: String
    let split: String
    let prediction: String
    let confidence: Double
    let probabilities: [String: Double]
}

enum TrainingError: Error {
    case invalidEmbedding(String)
    case invalidExport
}

// CSV fields may contain quoted commas and new lines in photo credits.
func readCSV(_ text: String) -> [[String: String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let chars = Array(text)
    var index = 0
    while index < chars.count {
        let char = chars[index]
        if char == "\"" {
            if quoted && index + 1 < chars.count && chars[index + 1] == "\"" {
                field.append("\"")
                index += 1
            } else {
                quoted.toggle()
            }
        } else if char == "," && !quoted {
            row.append(field)
            field = ""
        } else if (char == "\n" || char == "\r\n") && !quoted {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else if char != "\r" || quoted {
            field.append(char)
        }
        index += 1
    }
    if !field.isEmpty || !row.isEmpty { rows.append(row + [field]) }
    guard let headings = rows.first else { return [] }
    return rows.dropFirst().filter { $0.count == headings.count }.map { Dictionary(uniqueKeysWithValues: zip(headings, $0)) }
}

func embedding(at url: URL, mirrored: Bool, model: VNCoreMLModel) throws -> [Float] {
    let request = VNCoreMLRequest(model: model)
    request.imageCropAndScaleOption = .centerCrop
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw TrainingError.invalidEmbedding(url.lastPathComponent)
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
    // Flipping the EXIF orientation mirrors the displayed image without re-encoding it.
    let mirrors: [CGImagePropertyOrientation: CGImagePropertyOrientation] = [
        .up: .upMirrored, .upMirrored: .up, .down: .downMirrored, .downMirrored: .down,
        .left: .rightMirrored, .rightMirrored: .left, .right: .leftMirrored, .leftMirrored: .right
    ]
    try VNImageRequestHandler(cgImage: image, orientation: mirrored ? mirrors[orientation]! : orientation).perform([request])
    guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
          let array = observation.featureValue.shapedArrayValue(of: Float.self),
          array.scalarCount == 512, array.scalars.allSatisfy(\.isFinite) else {
        throw TrainingError.invalidEmbedding(url.lastPathComponent)
    }
    return array.scalars
}

func accuracy(_ photos: [ScoredPhoto]) -> Double {
    guard !photos.isEmpty else { return 0 }
    return Double(photos.filter { $0.label == $0.prediction }.count) / Double(photos.count)
}

func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

func writeJSON(_ value: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appML = root.deletingLastPathComponent().appendingPathComponent("FoodPassport/ML")
let cacheFolder = root.appendingPathComponent(".cache")
try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
let csv = try String(contentsOf: root.appendingPathComponent("split.csv"), encoding: .utf8)
let photos = readCSV(csv).map { Photo(label: $0["label"]!, file: $0["file"]!, split: $0["split"]!, hash: $0["sha256"]!) }
guard !photos.isEmpty else { fatalError("Run split_dataset.py first") }
let labels = Set(photos.map(\.label))
let sortedLabels = labels.sorted()
let modelURL = appML.appendingPathComponent("MobileCLIPImageEncoder.mlpackage")
let compute = MLModelConfiguration()
// CPU also works on Macs and Simulators without a usable Neural Engine context.
compute.computeUnits = .cpuOnly
let compiledEncoder = try MLModel.compileModel(at: modelURL)
defer { try? FileManager.default.removeItem(at: compiledEncoder) }
let encoder = try VNCoreMLModel(for: MLModel(contentsOf: compiledEncoder, configuration: compute))
let cacheURL = cacheFolder.appendingPathComponent("s0-embeddings.json")
var encoderHasher = SHA256()
for file in ["Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"] {
    encoderHasher.update(data: try Data(contentsOf: modelURL.appendingPathComponent(file)))
}
let encoderHash = encoderHasher.finalize().map { String(format: "%02x", $0) }.joined()
let savedCache = try? JSONDecoder().decode(EmbeddingCache.self, from: Data(contentsOf: cacheURL))
var cache = savedCache?.encoderHash == encoderHash ? savedCache!.photos : [:]
var training: [AnnotatedFeature<MLShapedArray<Float>, String>] = []
var validation: [AnnotatedFeature<MLShapedArray<Float>, String>] = []
for (index, photo) in photos.enumerated() {
    if cache[photo.hash] == nil || (photo.split == "train" && cache[photo.hash]?.mirroredValues == nil) {
        let url = root.appendingPathComponent(photo.file)
        let values = try autoreleasepool { try embedding(at: url, mirrored: false, model: encoder) }
        let mirror = photo.split == "train" ? try autoreleasepool { try embedding(at: url, mirrored: true, model: encoder) } : nil
        cache[photo.hash] = EmbeddedPhoto(values: values, mirroredValues: mirror)
    }
    let sample = cache[photo.hash]!
    let feature = AnnotatedFeature(feature: MLShapedArray<Float>(scalars: sample.values, shape: [512]), annotation: photo.label)
    if photo.split == "train" {
        training.append(feature)
        training.append(AnnotatedFeature(feature: MLShapedArray<Float>(scalars: sample.mirroredValues!, shape: [512]), annotation: photo.label))
    } else if photo.split == "validation" {
        validation.append(feature)
    }
    if index % 25 == 0 {
        print("Embedded \(index + 1)/\(photos.count)")
        try JSONEncoder().encode(EmbeddingCache(encoderHash: encoderHash, photos: cache)).write(to: cacheURL)
        fflush(stdout)
    }
}
try JSONEncoder().encode(EmbeddingCache(encoderHash: encoderHash, photos: cache)).write(to: cacheURL)

var options = LogisticRegressionClassifier<Float, String>.Configuration()
options.maximumIterations = 500
options.l2Penalty = 0.01
let estimator = LogisticRegressionClassifier<Float, String>(labels: labels, configuration: options)
print("Training on \(training.count) examples, including mirrored copies")
fflush(stdout)
let trained = try await estimator.fitted(to: training, validateOn: validation)
let classifierURL = appML.appendingPathComponent("FoodClassifier.mlpackage")
try? FileManager.default.removeItem(at: classifierURL)
try trained.export(to: classifierURL)

// Evaluate the exported model, so these scores describe what the app actually runs.
let compiledClassifier = try MLModel.compileModel(at: classifierURL)
defer { try? FileManager.default.removeItem(at: compiledClassifier) }
let classifier = try MLModel(contentsOf: compiledClassifier, configuration: compute)
guard classifier.modelDescription.inputDescriptionsByName["features"]?.multiArrayConstraint?.shape == [512],
      Set(classifier.modelDescription.classLabels as? [String] ?? []) == labels else { throw TrainingError.invalidExport }
var scores: [ScoredPhoto] = []
for photo in photos {
    let values = MLShapedArray<Float>(scalars: cache[photo.hash]!.values, shape: [512])
    let result = try classifier.prediction(from: MLDictionaryFeatureProvider(dictionary: ["features": MLMultiArray(values)]))
    let probabilities = Dictionary(uniqueKeysWithValues: result.featureValue(for: "targetProbability")!.dictionaryValue.map { ($0.key as! String, $0.value.doubleValue) })
    let best = probabilities.max { $0.value < $1.value }!
    scores.append(ScoredPhoto(label: photo.label, file: photo.file, split: photo.split, prediction: best.key,
                              confidence: best.value, probabilities: probabilities))
}
let validationScores = scores.filter { $0.split == "validation" }
let validationKnown = validationScores.filter { $0.prediction != "Other" }
let thresholds = Set([0.0] + validationKnown.map(\.confidence)).sorted()
let threshold = thresholds.first { candidate in
    let accepted = validationKnown.filter { $0.confidence >= candidate }
    return accepted.count >= 5 && accuracy(accepted) >= 0.95
}
var catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("training_catalogue.json"))) as! [String: Any]
let entries = (catalogue["classes"] as! [[String: Any]]).map { entry in
    entry.filter { ["id", "name", "cuisine", "isDrink", "menuNames", "category"].contains($0.key) }
}
try writeJSON([
    "schemaVersion": 2, "encoder": "MobileCLIP-S0", "embeddingCount": 512,
    "confidenceThreshold": threshold ?? 1.0, "requiresConfirmation": true,
    "classes": entries
], to: appML.appendingPathComponent("FoodModel.json"))
try JSONEncoder().encode(scores).write(to: root.appendingPathComponent("evaluation_predictions.json"))

var report = "# Food classifier evaluation\n\n"
report += "Frozen Apple MobileCLIP-S0 image encoder + Create ML Components logistic regression. Only the classifier was trained on these photos.\n\n"
report += "Split seed: 38. Existing author assignments are preserved when extending the dataset. Authors stay in one split across every class. Only training images have mirrored copies. Validation selects the stopping point and confidence threshold; test photos are used only for final evaluation.\n\n"
report += "| Split | Original photos | Top-1 accuracy |\n|---|---:|---:|\n"
for split in ["train", "validation", "test"] {
    let selected = scores.filter { $0.split == split }
    report += "| \(split) | \(selected.count) | \(percent(accuracy(selected))) |\n"
}
report += "\nTraining examples with augmentation: \(training.count). Maximum iterations: 500; L2 penalty: 0.01.\n\n"
report += "## Confidence calibration\n\n"
if let threshold {
    report += "Lowest observed validation threshold reaching at least 95% precision with at least five accepted examples: **\(String(format: "%.6f", threshold))**. All results require an explicit choice, including 100% confidence. The threshold is retained for evaluation only.\n\n"
    report += "| Split | Accepted known predictions | Precision | Coverage (all photos) |\n|---|---:|---:|---:|\n"
    for split in ["validation", "test"] {
        let all = scores.filter { $0.split == split }
        let accepted = all.filter { $0.prediction != "Other" && $0.confidence >= threshold }
        report += "| \(split) | \(accepted.count) | \(accepted.isEmpty ? "N/A" : percent(accuracy(accepted))) | \(percent(Double(accepted.count) / Double(all.count))) |\n"
    }
} else {
    report += "No validation threshold met 95% precision with five accepted examples. Users choose and confirm every result at every confidence level.\n"
}
let test = scores.filter { $0.split == "test" }
report += "\n## Test precision and recall\n\n| Class | Train | Validation | Test | Precision | Recall |\n|---|---:|---:|---:|---:|---:|\n"
for label in sortedLabels {
    let tp = test.filter { $0.label == label && $0.prediction == label }.count
    let predicted = test.filter { $0.prediction == label }.count
    let actual = test.filter { $0.label == label }.count
    let counts = ["train", "validation", "test"].map { split in scores.filter { $0.label == label && $0.split == split }.count }
    report += "| \(label) | \(counts[0]) | \(counts[1]) | \(counts[2]) | \(predicted == 0 ? "N/A" : percent(Double(tp) / Double(predicted))) | \(percent(Double(tp) / Double(actual))) |\n"
}
report += "\n## Test confusion matrix\n\nRows are actual labels; columns are predicted labels.\n\n| Actual / predicted | " + sortedLabels.joined(separator: " | ") + " |\n|---|" + sortedLabels.map { _ in "---:" }.joined(separator: "|") + "|\n"
for label in sortedLabels {
    report += "| \(label) | " + sortedLabels.map { prediction in String(test.filter { $0.label == label && $0.prediction == prediction }.count) }.joined(separator: " | ") + " |\n"
}
report += "\n## Limits\n\nThis is a small web-photo dataset, not a claim of real-world accuracy. A few photos per held-out class give wide uncertainty. Similar dishes, mixed plates, lighting, and unseen drinks can confuse it. Other covers varied everyday scenes and unsupported foods, but cannot cover every unknown image. Confidence is a model score, not a guarantee. Every prediction needs a label confirmation, and every visit needs an explicit Save visit action.\n\n"
report += "Dropped classes with fewer than ten usable photos: \(catalogue["droppedClasses"] ?? [:]).\n"
try report.write(to: root.appendingPathComponent("EvaluationReport.md"), atomically: true, encoding: .utf8)
print(report)
