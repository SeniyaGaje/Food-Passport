import Foundation
import Testing
import UIKit
@testable import FoodPassport

/// Photos with more than one item: detected boxes, cropping and one choice per item.
@Suite("Multiple meal items")
@MainActor
struct MealRegionTests {
    @Test("Food boxes are kept while overlapping duplicates and unrelated objects are removed")
    func objectBoxes() {
        let cup = CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)
        let cake = CGRect(x: 0.6, y: 0.3, width: 0.25, height: 0.3)
        // A cup, a duplicate box over it, a cake, a person and a weak pizza guess.
        let boxes = MealRegionGeometry.regions(from: [
            DetectedMealObject(bounds: cup, label: "cup", confidence: 0.9),
            DetectedMealObject(bounds: cup, label: "bowl", confidence: 0.7),
            DetectedMealObject(bounds: cake, label: "cake", confidence: 0.85),
            DetectedMealObject(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), label: "person", confidence: 0.99),
            DetectedMealObject(bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), label: "pizza", confidence: 0.1)
        ])
        // Only the cup and the cake survive.
        #expect(boxes.count == 2)
        // Vision's bottom-left y (0.2 + 0.3) becomes a top-left y of 0.5.
        #expect(boxes.contains { abs($0.minY - 0.5) < 0.001 && abs($0.minX - 0.1) < 0.001 })
    }

    @Test("Invalid boxes are ignored and crops stay inside the image")
    func invalidAndClippedBoxes() {
        // A zero-size box is ignored.
        #expect(MealRegionGeometry.regions(from: [DetectedMealObject(bounds: .zero, label: "cup", confidence: 1)]).isEmpty)
        // A box covering the whole photo is cropped to exactly the photo.
        let rect = MealRegionGeometry.cropRect(CGRect(x: 0, y: 0, width: 1, height: 1), imageSize: CGSize(width: 600, height: 400))
        #expect(rect == CGRect(x: 0, y: 0, width: 600, height: 400))
    }

    @Test("Each detected object gets one independent choice, even when both are the same food")
    func independentChoices() async {
        // Two fake items that both offer cake and tea.
        let cake = MealPrediction(label: "Cake & Dessert", dishName: "Cake & Dessert", confidence: 1, cuisine: nil, category: "Dessert")
        let tea = MealPrediction(label: "Tea", dishName: "Tea", confidence: 0, cuisine: nil, isDrink: true, category: "Drink")
        let result = MealRecognition(predictions: [cake, tea], topLabel: cake.label, confidence: 1, isOther: false,
                                     isConfident: true, regions: [
            MealRegion(id: 1, bounds: CGRect(x: 0, y: 0, width: 0.4, height: 0.4), predictions: [cake, tea], isOther: false),
            MealRegion(id: 2, bounds: CGRect(x: 0.5, y: 0, width: 0.4, height: 0.4), predictions: [cake, tea], isOther: false)
        ])
        let review = MealScanViewModel(recognizer: MockMealRecognizer(result: result))
        await review.scan(UIImage(), menu: [])
        // Nothing is selected for the student.
        #expect(review.selectedDishes.isEmpty)
        // Picking tea after cake in the same item replaces the choice.
        review.toggle(cake.label, in: 1)
        review.toggle(tea.label, in: 1)
        #expect(review.selectedDishes.map(\.label) == ["Tea"])
        // Choose cake for both items: two separate cakes.
        review.toggle(cake.label, in: 1)
        review.toggle(cake.label, in: 2)
        #expect(review.confirm()?.map(\.label) == [cake.label, cake.label])
    }

    @Test("The real pipeline finds separate drink and cake regions and offers the correct names")
    func realCoffeeAndCake() async throws {
        // A real photo of coffee and cake, bundled with the tests.
        let bundle = Bundle(for: MealFixtureMarker.self)
        let url = try #require(bundle.url(forResource: "coffee-and-cake", withExtension: "jpg"))
        let image = try #require(UIImage(contentsOfFile: url.path))
        // Run the real models (detector, MobileCLIP and the classifier).
        let result = try await CoreMLMealRecognizer.shared.recognize(image, menu: [])
        // Two separate items were found.
        #expect(result.regions.count == 2)
        let drink = try #require(result.regions.first { $0.predictions.first?.isDrink == true })
        let dessert = try #require(result.regions.first { $0.predictions.first?.category == "Dessert" })
        #expect(drink.id != dessert.id)
        #expect(drink.predictions.contains { $0.label == "Coffee" })
        #expect(dessert.predictions.contains { $0.label == "Cake & Dessert" })
        // The review still starts with nothing selected.
        let review = MealScanViewModel(recognizer: MockMealRecognizer(result: result))
        await review.scan(image, menu: [])
        #expect(review.selectedDishes.isEmpty)
        review.toggle("Coffee", in: drink.id)
        review.toggle("Cake & Dessert", in: dessert.id)
        #expect(Set(review.confirm()?.map(\.label) ?? []) == ["Coffee", "Cake & Dessert"])
    }

}


private final class MealFixtureMarker: NSObject {}
