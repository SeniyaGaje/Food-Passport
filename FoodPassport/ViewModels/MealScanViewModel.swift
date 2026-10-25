import Observation
import UIKit

/// Holds a scan until the student confirms or rejects it.
@Observable
final class MealScanViewModel {
    private(set) var result: MealRecognition?
    private(set) var selectedLabels: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var isScanning = false

    private let recognizer: MealRecognizer
    private var scanNumber = 0

    init(recognizer: MealRecognizer = CoreMLMealRecognizer.shared) {
        self.recognizer = recognizer
    }

    var selectedDishes: [MealPrediction] {
        result?.predictions.filter { selectedLabels.contains($0.label) } ?? []
    }

    func scan(_ image: UIImage, menu: [String]) async {
        reject()
        let currentScan = scanNumber
        isScanning = true
        do {
            let recognition = try await recognizer.recognize(image, menu: menu)
            guard currentScan == scanNumber else { return }
            result = recognition
            if recognition.canAutoApply, let first = recognition.predictions.first {
                selectedLabels = [first.label]
            }
        } catch {
            guard currentScan == scanNumber else { return }
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    func toggle(_ label: String) {
        guard result?.predictions.contains(where: { $0.label == label }) == true else { return }
        if selectedLabels.contains(label) {
            selectedLabels.remove(label)
        } else {
            selectedLabels.insert(label)
        }
    }

    /// A confident match may fill the draft form; saving the visit stays separate.
    func automaticDraft() -> [MealPrediction]? {
        guard result?.canAutoApply == true else { return nil }
        return confirm()
    }

    /// Confirms the student's choice when the scan needed review.
    func confirm() -> [MealPrediction]? {
        let dishes = selectedDishes
        guard !dishes.isEmpty else { return nil }
        reject()
        return dishes
    }

    func reject() {
        scanNumber += 1
        result = nil
        selectedLabels = []
        errorMessage = nil
        isScanning = false
    }
}
