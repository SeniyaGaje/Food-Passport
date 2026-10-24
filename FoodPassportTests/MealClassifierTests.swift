import Testing
import Foundation
@testable import FoodPassport

/// The meal classifier is tested without the Core ML model: a photo "embedding" is passed in directly.
/// With one-number embeddings, each label's similarity to the photo is simply its own number,
/// so the tests can choose exactly how alike the photo and each label are.
@Suite("Meal recognition")
@MainActor
struct MealClassifierTests {

    private func label(
        _ name: String,
        similarity: Float,
        cuisine: Cuisine? = .sriLankan,
        kind: DishLabel.Kind = .dish,
        menuNames: [String] = []
    ) -> DishLabel {
        DishLabel(id: name.lowercased(), name: name, cuisine: cuisine, kind: kind, menuNames: menuNames, embedding: [similarity])
    }

    private let photo: [Float] = [1]

    private func dishes(_ result: MealRecognition) -> [MealPrediction]? {
        if case .dishes(let predictions) = result { return predictions }
        return nil
    }

    @Test("The closest dish comes first, with the most confidence")
    func closestDishFirst() throws {
        let labels = [
            label("Fried Rice", similarity: 0.7, cuisine: .chinese),
            label("Kottu Roti", similarity: 0.9),
            label("String Hoppers", similarity: 0.8),
        ]

        let predictions = try #require(dishes(MealClassifier.classify(embedding: photo, labels: labels, menu: [])))

        #expect(predictions.map(\.label) == ["Kottu Roti", "String Hoppers", "Fried Rice"])
        #expect(predictions[0].confidence > MealClassifier.confidentThreshold)
        #expect(predictions[0].cuisine == .sriLankan)
        #expect(predictions.map(\.confidence) == predictions.map(\.confidence).sorted(by: >))
        // Every label is a dish here, so the three chances add up to 100%.
        #expect(abs(predictions.map(\.confidence).reduce(0, +) - 1) < 0.0001)
    }

    @Test("At most three dishes are suggested")
    func topThreeOnly() throws {
        let labels = (0..<6).map { label("Dish \($0)", similarity: 0.5 + Float($0) / 100) }

        let predictions = try #require(dishes(MealClassifier.classify(embedding: photo, labels: labels, menu: [])))

        #expect(predictions.count == 3)
        #expect(predictions[0].label == "Dish 5")
    }

    @Test("A dish on the restaurant's menu is favoured and shown with the menu's name")
    func menuBoost() throws {
        let labels = [
            label("Kottu Roti", similarity: 0.8, menuNames: ["Kottu Roti", "Chicken Kottu"]),
            label("Hoppers", similarity: 0.8, menuNames: ["Egg Hoppers", "Plain Hoppers (3)"]),
        ]

        let predictions = try #require(dishes(MealClassifier.classify(embedding: photo, labels: labels, menu: ["Egg Hoppers", "Pol Roti"])))

        // Equally likely from the photo alone, so the menu boost (×2) decides: 2/3 against 1/3.
        #expect(predictions[0].label == "Egg Hoppers")
        #expect(predictions[0].dishName == "Egg Hoppers")
        #expect(predictions[0].isOnMenu)
        #expect(abs(predictions[0].confidence - 2.0 / 3.0) < 0.0001)
        #expect(!predictions[1].isOnMenu)
    }

    @Test("Menu names are matched ignoring capital letters")
    func menuNameMatching() {
        let kottu = label("Kottu Roti", similarity: 1, menuNames: ["Kottu Roti", "Chicken Kottu"])

        #expect(kottu.menuName(in: ["Rice & Curry", "chicken kottu"]) == "chicken kottu")
        #expect(kottu.menuName(in: ["Rice & Curry"]) == nil)
    }

    @Test("A photo of a receipt is reported as not a meal")
    func notFood() {
        let labels = [
            label("Receipt", similarity: 0.9, cuisine: nil, kind: .notFood),
            label("Kottu Roti", similarity: 0.6),
        ]

        #expect(MealClassifier.classify(embedding: photo, labels: labels, menu: []) == .notFood("Receipt"))
    }

    @Test("Food the app doesn't know, such as a drink, is reported as unknown food")
    func unknownFood() {
        let labels = [
            label("Drink", similarity: 0.9, cuisine: nil, kind: .otherFood),
            label("Kottu Roti", similarity: 0.6),
        ]

        #expect(MealClassifier.classify(embedding: photo, labels: labels, menu: []) == .unknownFood("Drink"))
    }

    @Test("When the app is unsure a photo isn't a meal, it still suggests dishes")
    func unsureNonMealFallsBackToDishes() throws {
        // The receipt is the single best match, but only about 45% likely, under the 50% needed to say "not a meal".
        let labels = [
            label("Receipt", similarity: 0.5, cuisine: nil, kind: .notFood),
            label("Kottu Roti", similarity: 0.495),
            label("String Hoppers", similarity: 0.495),
        ]

        let predictions = try #require(dishes(MealClassifier.classify(embedding: photo, labels: labels, menu: [])))

        #expect(Set(predictions.map(\.label)) == ["Kottu Roti", "String Hoppers"])
        #expect(predictions.allSatisfy { $0.confidence < MealClassifier.confidentThreshold })
    }

    @Test("With no labels loaded, the photo is reported as unclear")
    func noLabels() {
        #expect(MealClassifier.classify(embedding: photo, labels: [], menu: []) == .notFood("Unclear photo"))
    }

    // The bundled data file

    @Test("The bundled dish embeddings are complete and valid")
    func bundledEmbeddings() throws {
        let labels = try loadBundledLabels()

        #expect(labels.count >= 50)
        #expect(Set(labels.map(\.id)).count == labels.count, "Every label needs its own ID")

        for label in labels {
            #expect(label.embedding.count == 512, "\(label.name) has the wrong number of values")
            let length = sqrt(label.embedding.reduce(0) { $0 + $1 * $1 })
            #expect(abs(length - 1) < 0.001, "\(label.name) isn't length 1")
            if label.kind == .dish {
                #expect(label.cuisine != nil, "\(label.name) is a dish without a cuisine")
            }
        }
        #expect(labels.contains { $0.kind == .notFood && $0.name == "Receipt" })
    }

    @Test("A photo matching a dish's description exactly is recognised as that dish")
    func everyDishRecognisesItself() throws {
        let labels = try loadBundledLabels()

        for dish in labels where dish.kind == .dish {
            let predictions = dishes(MealClassifier.classify(embedding: dish.embedding, labels: labels, menu: []))
            #expect(predictions?.first?.label == dish.name, "\(dish.name) wasn't the top match for itself")
        }
    }

    private func loadBundledLabels() throws -> [DishLabel] {
        struct EmbeddingsFile: Decodable {
            let labels: [DishLabel]
        }
        // The tests run inside the app, so the app's bundle holds the file.
        let url = try #require(Bundle.main.url(forResource: "DishEmbeddings", withExtension: "json"))
        return try JSONDecoder().decode(EmbeddingsFile.self, from: Data(contentsOf: url)).labels
    }
}
