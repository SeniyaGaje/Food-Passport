import CoreML
import Foundation
import Testing
import UIKit
@testable import FoodPassport

@Suite("Hybrid meal recognition")
@MainActor
struct MealClassifierTests {
    private let classes = [
        MealClass(id: "kottu", name: "Kottu Roti", cuisine: .sriLankan, isDrink: false, menuNames: ["Chicken Kottu"]),
        MealClass(id: "tea", name: "Tea", cuisine: nil, isDrink: true, menuNames: ["Plain Tea", "Milk Tea"]),
        MealClass(id: "coffee", name: "Coffee", cuisine: nil, isDrink: true, menuNames: ["Coffee"]),
        MealClass(id: "other", name: "Other", cuisine: nil, isDrink: false, menuNames: [])
    ]

    private func configuration(threshold: Double = 0.8) -> MealModelConfiguration {
        MealModelConfiguration(schemaVersion: 2, encoder: "MobileCLIP-S0", embeddingCount: 512,
                               confidenceThreshold: threshold, requiresConfirmation: true, classes: classes)
    }

    private func recognition(_ chances: [String: Double], threshold: Double = 0.8) throws -> MealRecognition {
        try MealClassifier.parse(chances, configuration: configuration(threshold: threshold), menu: ["Chicken Kottu"])
    }

    @Test("The top three known classes keep their trained probabilities and menu names")
    func parseResults() throws {
        let result = try recognition(["Kottu Roti": 0.85, "Tea": 0.08, "Coffee": 0.05, "Other": 0.02])
        #expect(result.predictions.map(\.label) == ["Kottu Roti", "Tea", "Coffee"])
        #expect(result.predictions.first?.dishName == "Chicken Kottu")
        #expect(result.predictions.first?.confidence == 0.85)
        #expect(result.predictions.first?.isOnMenu == true)
        #expect(result.isConfident)
    }

    @Test("A calibrated boundary includes the threshold and excludes lower scores", arguments: [0.79, 0.8, 0.81])
    func thresholdBoundary(score: Double) throws {
        let result = try recognition(["Kottu Roti": score, "Tea": 0.05, "Coffee": 0.05, "Other": 0.9 - score])
        #expect(result.isConfident == (score >= 0.8))
    }

    @Test("Other keeps alternatives visible and is never selected automatically")
    func otherNeedsChoice() throws {
        let result = try recognition(["Kottu Roti": 0.03, "Tea": 0.02, "Coffee": 0.01, "Other": 0.94])
        #expect(result.isOther)
        #expect(!result.isConfident)
        #expect(result.predictions.count == 3)
        #expect(!result.predictions.contains { $0.label == "Other" })
    }

    @Test("Confidence is reported separately from the mandatory confirmation policy")
    func confidenceAndConfirmation() throws {
        let result = try recognition(["Kottu Roti": 0.97, "Tea": 0.01, "Coffee": 0.01, "Other": 0.01])
        #expect(result.isConfident)
    }

    @Test("Missing, unknown, negative, non-finite and unnormalised outputs are rejected")
    func invalidOutputs() {
        let invalid: [[String: Double]] = [
            [:], ["Unknown": 1],
            ["Kottu Roti": -0.1, "Tea": 0.5, "Coffee": 0.5, "Other": 0.1],
            ["Kottu Roti": .nan, "Tea": 0, "Coffee": 0, "Other": 0],
            ["Kottu Roti": .infinity, "Tea": 0, "Coffee": 0, "Other": 0],
            ["Kottu Roti": 0.5, "Tea": 0.5, "Coffee": 0.5, "Other": 0.5]
        ]
        for output in invalid {
            #expect(throws: MealRecognitionError.self) { try recognition(output) }
        }
    }

    @Test("Equal scores have a stable ordering")
    func tiedScores() throws {
        let result = try recognition(["Kottu Roti": 0.25, "Tea": 0.25, "Coffee": 0.25, "Other": 0.25])
        #expect(result.predictions.map(\.label) == ["Coffee", "Kottu Roti", "Tea"])
        #expect(!result.isConfident)
    }

    @Test("A broad tea class does not invent which tea was served")
    func menuAmbiguity() {
        let tea = classes[1]
        #expect(tea.menuName(in: ["Plain Tea", "Milk Tea"]) == nil)
        #expect(tea.menuName(in: ["PLAIN TEA"]) == "PLAIN TEA")
    }

    @Test("A confident fake scan fills a draft, and only confirmation returns dishes")
    func confirmFlow() async throws {
        let result = try recognition(["Kottu Roti": 0.9, "Tea": 0.04, "Coffee": 0.03, "Other": 0.03])
        let review = MealScanViewModel(recognizer: MockMealRecognizer(result: result))
        #expect(review.confirm() == nil)
        await review.scan(UIImage(), menu: [])
        #expect(review.selectedDishes.isEmpty)
        review.toggle("Kottu Roti")
        #expect(review.selectedDishes.map(\.label) == ["Kottu Roti"])
        #expect(review.result != nil)
        #expect(review.confirm()?.map(\.label) == ["Kottu Roti"])
        #expect(review.result == nil)
        #expect(review.confirm() == nil)
    }

    @Test("Even a 100 percent scan starts empty and requires a choice")
    func perfectConfidenceNeedsChoice() async throws {
        let result = try recognition(["Kottu Roti": 1, "Tea": 0, "Coffee": 0, "Other": 0])
        let review = MealScanViewModel(recognizer: MockMealRecognizer(result: result))
        await review.scan(UIImage(), menu: [])
        #expect(review.selectedDishes.isEmpty)
        #expect(review.confirm() == nil)
        review.toggle("Kottu Roti")
        #expect(review.confirm()?.first?.label == "Kottu Roti")
    }

    @Test("Low confidence and Other start empty and need the student's choice", arguments: [false, true])
    func uncertainFlow(other: Bool) async throws {
        let output = other
            ? ["Kottu Roti": 0.04, "Tea": 0.03, "Coffee": 0.03, "Other": 0.9]
            : ["Kottu Roti": 0.5, "Tea": 0.2, "Coffee": 0.2, "Other": 0.1]
        let review = MealScanViewModel(recognizer: MockMealRecognizer(result: try recognition(output)))
        await review.scan(UIImage(), menu: [])
        #expect(review.selectedDishes.isEmpty)
        #expect(review.confirm() == nil)
        review.toggle("Tea")
        review.toggle("Unknown")
        #expect(review.selectedDishes.map(\.label) == ["Tea"])
        #expect(review.confirm()?.first?.isDrink == true)
    }

    @Test("Rejecting a scan discards its suggestions and selection")
    func rejectFlow() async {
        let review = MealScanViewModel(recognizer: MockMealRecognizer())
        await review.scan(UIImage(), menu: [])
        review.reject()
        #expect(review.result == nil)
        #expect(review.selectedDishes.isEmpty)
        #expect(review.confirm() == nil)
    }

    @Test("A failed rescan clears the earlier prediction")
    func failedScan() async {
        let review = MealScanViewModel(recognizer: MockMealRecognizer(error: .unreadableImage))
        await review.scan(UIImage(), menu: [])
        #expect(review.errorMessage != nil)
        #expect(review.result == nil)
        #expect(!review.isScanning)
        #expect(review.confirm() == nil)
    }

    @Test("Closing review during inference cannot bring an old result back")
    func rejectPendingScan() async {
        let recognizer = SuspendedMealRecognizer()
        let review = MealScanViewModel(recognizer: recognizer)
        let task = Task { await review.scan(UIImage(), menu: []) }
        await recognizer.waitUntilStarted()
        review.reject()
        recognizer.finish()
        await task.value
        #expect(review.result == nil)
        #expect(review.selectedDishes.isEmpty)
        #expect(!review.isScanning)
    }

    @Test("The catalogue agrees with the exported classifier and both model interfaces")
    func bundledModelContract() throws {
        let configuration = try MealModelConfiguration.load()
        let url = try #require(Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc"))
        let compute = MLModelConfiguration()
        compute.computeUnits = .cpuOnly
        let classifier = try MLModel(contentsOf: url, configuration: compute)
        #expect(Set(classifier.modelDescription.classLabels as? [String] ?? []) == Set(configuration.classes.map(\.name)))
        #expect(classifier.modelDescription.inputDescriptionsByName["features"]?.multiArrayConstraint?.shape == [512])
        #expect(classifier.modelDescription.predictedFeatureName == "target")
        #expect(classifier.modelDescription.predictedProbabilitiesName == "targetProbability")
        let encoderURL = try #require(Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlmodelc"))
        let encoder = try MLModel(contentsOf: encoderURL, configuration: compute)
        #expect(encoder.modelDescription.inputDescriptionsByName["image"]?.imageConstraint?.pixelsWide == 256)
        #expect(encoder.modelDescription.inputDescriptionsByName["image"]?.imageConstraint?.pixelsHigh == 256)
        #expect(encoder.modelDescription.outputDescriptionsByName["final_emb_1"]?.multiArrayConstraint?.shape == [1, 512])
    }

    @Test("The real model recognises unseen app photos among its three suggestions", arguments: [
        ("dish_kottu", "Kottu Roti"), ("dish_masala_dosa", "Dosa"),
        ("restaurant_hoppers_hut", "Hoppers"), ("restaurant_ratmalana_tea_kade", "Tea")
    ])
    func unseenAppPhotos(asset: String, expected: String) async throws {
        let photo = try #require(UIImage(named: asset))
        let result = try await CoreMLMealRecognizer.shared.recognize(photo, menu: [])
        #expect(result.predictions.contains { $0.label == expected }, "\(asset): \(result.predictions.map(\.label))")
        #expect(result.predictions.allSatisfy { (0...1).contains($0.confidence) })
        if result.isConfident { #expect(result.topLabel == expected) }
    }

    @Test("An unreadable image fails without suggesting a meal")
    func unreadablePhoto() async {
        await #expect(throws: MealRecognitionError.self) {
            try await CoreMLMealRecognizer.shared.recognize(UIImage(), menu: [])
        }
    }

    @Test("Food determines the cuisine ahead of a drink")
    func suggestedCuisine() {
        let coffee = MealPrediction(label: "Coffee", dishName: "Coffee", confidence: 0.8, cuisine: nil, isDrink: true)
        let kottu = MealPrediction(label: "Kottu Roti", dishName: "Kottu Roti", confidence: 0.7, cuisine: .sriLankan)
        #expect(MealPrediction.suggestedCuisine(in: [coffee, kottu]) == .sriLankan)
        #expect(MealPrediction.suggestedCuisine(in: [coffee]) == nil)
    }
}

/// Lets the test close the screen while a photo is still being processed.
@MainActor
private final class SuspendedMealRecognizer: MealRecognizer {
    private var pending: CheckedContinuation<MealRecognition, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func prepare() async {}

    func recognize(_ image: UIImage, menu: [String]) async throws -> MealRecognition {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        pending?.resume(returning: MockMealRecognizer().result)
        pending = nil
    }
}
