import AppKit

enum ImageClipboardError: Error {
    case invalidImage
    case clipboardWriteFailed
}

enum ImageClipboard {
    /// Validate before touching the pasteboard. Never copy a file URL as an image.
    static func copyImage(atPath path: String, to pasteboard: NSPasteboard = .general) throws {
        guard let image = NSImage(contentsOfFile: path), image.isValid else {
            throw ImageClipboardError.invalidImage
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw ImageClipboardError.clipboardWriteFailed
        }
    }
}
