import Foundation

/// A box the object detector found, with its label and confidence.
nonisolated struct DetectedMealObject {
    let bounds: CGRect
    let label: String
    let confidence: Double
}

/// Removes duplicate boxes and converts Vision's bottom-left coordinates for the screen.
nonisolated enum MealRegionGeometry {
    // The detector's labels that can be food or drink.
    static let foodObjects: Set<String> = ["cup", "bowl", "pizza", "sandwich", "cake", "donut", "hot dog"]

    static func regions(from objects: [DetectedMealObject]) -> [CGRect] {
        var kept: [CGRect] = []
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        // Most confident boxes first.
        for object in objects.sorted(by: { $0.confidence > $1.confidence }) {
            let box = object.bounds
            // Skip non-food labels, weak guesses and broken boxes.
            guard foodObjects.contains(object.label), object.confidence >= 0.35,
                  [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite),
                  box.width > 0, box.height > 0 else { continue }
            let clipped = box.intersection(unit)
            let area = clipped.width * clipped.height
            // Skip tiny boxes (under 1.5% of the photo).
            guard !clipped.isNull, area >= 0.015 else { continue }
            // A box over 50% overlapping one already kept, or 90% inside it, is a duplicate.
            let duplicate = kept.contains { previous in
                let overlap = previous.intersection(clipped)
                guard !overlap.isNull else { return false }
                let intersection = overlap.width * overlap.height
                let previousArea = previous.width * previous.height
                return intersection / (area + previousArea - intersection) > 0.5
                    || intersection / min(area, previousArea) > 0.9
            }
            if !duplicate { kept.append(clipped) }
            // At most 6 items.
            if kept.count == 6 { break }
        }
        // Flip to top-left coordinates and sort top to bottom, then left to right.
        return kept.map { CGRect(x: $0.minX, y: 1 - $0.maxY, width: $0.width, height: $0.height) }
            .sorted { $0.midY == $1.midY ? $0.minX < $1.minX : $0.midY < $1.midY }
    }

    /// The box in pixels, with a small margin, kept inside the photo.
    static func cropRect(_ box: CGRect, imageSize: CGSize) -> CGRect {
        // A little context helps distinguish a cup or a plate from its contents.
        let expanded = box.insetBy(dx: -0.025, dy: -0.025).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGRect(x: expanded.minX * imageSize.width, y: expanded.minY * imageSize.height,
                      width: expanded.width * imageSize.width, height: expanded.height * imageSize.height)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
