import AppKit
import Foundation

@main
struct ClipboardSmokeTest {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 0.5), atX: 0, y: 0)
        bitmap.setColor(.blue, atX: 1, y: 1)
        let source = directory.appendingPathComponent("received.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        try ImageClipboard.copyImage(atPath: source.path, to: board)
        try FileManager.default.removeItem(at: source)
        guard let copied = board.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let pixels = copied.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
              pixels.pixelsWide == 2, pixels.pixelsHigh == 2,
              let red = pixels.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB),
              abs(red.redComponent - 1) < 0.02, abs(red.alphaComponent - 0.5) < 0.02,
              !(board.types ?? []).contains(.fileURL) else {
            fatalError("Image content, pixels or alpha did not survive the native clipboard round-trip")
        }
        let jpeg = directory.appendingPathComponent("received.jpg")
        try bitmap.representation(using: .jpeg, properties: [:])!.write(to: jpeg)
        try ImageClipboard.copyImage(atPath: jpeg.path, to: board)
        precondition(board.readObjects(forClasses: [NSImage.self])?.isEmpty == false)
        precondition(!(board.types ?? []).contains(.fileURL))
        // An invalid or missing file must not replace the existing pasteboard.
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let changeCount = board.changeCount
        for path in [invalid.path, directory.appendingPathComponent("missing.png").path] {
            do {
                try ImageClipboard.copyImage(atPath: path, to: board)
                fatalError("Invalid images must fail")
            } catch ImageClipboardError.invalidImage {
                precondition(board.changeCount == changeCount)
            }
        }
        print("PASS: native PNG/JPEG image content, alpha, source deletion, no file URL, invalid and missing files; private pasteboard only")
    }
}
