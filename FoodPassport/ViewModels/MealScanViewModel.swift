import Observation
import UIKit

/// Holds a scan until the student confirms or rejects it.
@Observable
final class MealScanViewModel {
    // The scan result, and the label chosen for each item (by item ID).
    private(set) var result: MealRecognition?
    private(set) var choices: [Int: String] = [:]

    var selectedLabels: Set<String> { Set(choices.values) }

    // The items to choose for. With no separate items, the whole photo is one item.
    var regions: [MealRegion] {
        guard let result else { return [] }
        return result.regions.isEmpty
            ? [MealRegion(id: 0, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), predictions: result.predictions, isOther: result.isOther)]
            : result.regions
    }
    private(set) var errorMessage: String?
    private(set) var isScanning = false

    private let recognizer: MealRecognizer
    // Bumped by every new scan or reject, so a late result from an old scan is ignored.
    private var scanNumber = 0

    init(recognizer: MealRecognizer = CoreMLMealRecognizer.shared) {
        self.recognizer = recognizer
    }

    // The dish chosen for each item.
    var selectedDishes: [MealPrediction] {
        regions.compactMap { region in
            region.predictions.first { $0.label == choices[region.id] }
        }
    }

    /// Runs the recogniser on a photo. Any earlier scan is cleared first.
    func scan(_ image: UIImage, menu: [String]) async {
        reject()
        let currentScan = scanNumber
        isScanning = true
        do {
            let recognition = try await recognizer.recognize(image, menu: menu)
            guard currentScan == scanNumber else { return }
            result = recognition
        } catch {
            guard currentScan == scanNumber else { return }
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    /// One choice per detected item. Nothing starts selected, even at 100%.
    func toggle(_ label: String, in regionID: Int = 0) {
        guard regions.first(where: { $0.id == regionID })?.predictions.contains(where: { $0.label == label }) == true else { return }
        choices[regionID] = choices[regionID] == label ? nil : label
    }

    /// Confirms the student's choice when the scan needed review.
    func confirm() -> [MealPrediction]? {
        let dishes = selectedDishes
        guard !dishes.isEmpty else { return nil }
        reject()
        return dishes
    }

    /// Clears the scan and its choices.
    func reject() {
        scanNumber += 1
        result = nil
        choices = [:]
        errorMessage = nil
        isScanning = false
    }
}
