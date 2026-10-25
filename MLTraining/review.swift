// Make small contact sheets: swift MLTraining/review.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let images = root.appendingPathComponent("Images")
let output = root.appendingPathComponent("Review")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for folder in try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
    let photos = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { ["jpg", "png"].contains($0.pathExtension) }.sorted { $0.path < $1.path }
    for start in stride(from: 0, to: photos.count, by: 60) {
        let batch = Array(photos[start..<min(start + 60, photos.count)])
        let size = NSSize(width: 1200, height: ceil(Double(batch.count) / 6) * 130)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, photo) in batch.enumerated() {
            let x = (index % 6) * 200
            let y = Int(size.height) - (index / 6 + 1) * 130
            if let thumb = NSImage(contentsOf: photo) {
                let scale = min(190 / thumb.size.width, 100 / thumb.size.height)
                thumb.draw(in: NSRect(x: CGFloat(x) + (200 - thumb.size.width * scale) / 2,
                                     y: CGFloat(y + 25), width: thumb.size.width * scale, height: thumb.size.height * scale))
            }
            (photo.deletingPathExtension().lastPathComponent as NSString).draw(at: NSPoint(x: x + 5, y: y + 5),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(folder.lastPathComponent)-\(start / 60 + 1).png"))
    }
}
print("Contact sheets: \(output.path)")
