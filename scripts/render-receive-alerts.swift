import AppKit
import ImageIO

// Renders ReceiveAlertView fixtures offscreen to PNG. Never creates, orders or focuses a window
// and never activates the app.
//
//   swiftc -parse-as-library app/macos/Runner/ReceiveAlert.swift scripts/render-receive-alerts.swift \
//     -o /tmp/render-receive-alerts && /tmp/render-receive-alerts artifacts/evidence/custom-alerts

@main
struct RenderReceiveAlerts {
    struct Fixture {
        let name: String
        let payload: [String: String]
        var preview = false
        var feedback: (Bool, String)?
    }

    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "artifacts/evidence/custom-alerts")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let photo = output.appendingPathComponent("fixture-photo.png")
        try writeSyntheticPhoto(to: photo)

        let photoName = "PXL_20261031_142233871.jpg"
        var fixtures: [Fixture] = [
            Fixture(name: "pending", payload: [
                "sessionId": "s1", "kind": "pending", "title": "Pixel 8 Pro wants to send a photo",
                "body": photoName, "detail": "3.4 MB",
                "primaryLabel": "Receive", "primaryAction": "accept",
                "secondaryLabel": "Decline", "secondaryAction": "reject", "dismissLabel": "Close",
            ]),
            Fixture(name: "pending-long", payload: [
                "sessionId": "s2", "kind": "pending",
                "title": "Yeray’s Pixel 9 Pro XL (work profile, living room) wants to send 12 files",
                "body": "Screenshot_2026-10-31-14-22-33-871_com.google.android.apps.photos.editor.final-version.png",
                "detail": "12 files · 148.2 MB",
                "primaryLabel": "Receive", "primaryAction": "accept",
                "secondaryLabel": "Decline", "secondaryAction": "reject", "dismissLabel": "Close",
            ]),
            Fixture(name: "receiving", payload: [
                "sessionId": "s3", "kind": "receiving", "title": "Receiving from Pixel 8 Pro",
                "body": "IMG_4471.HEIC and 4 more", "detail": "2 of 5 · 12.4 MB of 31 MB", "dismissLabel": "Close",
            ]),
            Fixture(name: "done-image", payload: imageDone(photoName, path: photo.path), preview: true),
            Fixture(name: "done-image-copied", payload: imageDone(photoName, path: photo.path), preview: true,
                    feedback: (true, "Copied to clipboard")),
            Fixture(name: "done-image-copy-error", payload: imageDone(photoName, path: photo.path), preview: true,
                    feedback: (false, "Couldn’t copy the image. Try again.")),
            Fixture(name: "done-image-long", payload: [
                "sessionId": "s5", "kind": "done",
                "title": "Received from Yeray’s Pixel 9 Pro XL (work profile, living room)",
                "body": "Screenshot_2026-10-31-14-22-33-871_com.google.android.apps.photos.editor.final-version.png",
                "detail": "8.1 MB", "previewPath": photo.path,
                "primaryLabel": "Copy image", "primaryAction": "copy",
                "secondaryLabel": "Open", "secondaryAction": "open", "dismissLabel": "Close",
            ], preview: true),
            Fixture(name: "done-files", payload: [
                "sessionId": "s6", "kind": "done", "title": "Received 5 files from Pixel 8 Pro",
                "body": "IMG_4471.HEIC, notes.pdf and 3 more", "detail": "31 MB",
                "primaryLabel": "Open", "primaryAction": "open",
                "secondaryLabel": "History", "secondaryAction": "history", "dismissLabel": "Close",
            ]),
            Fixture(name: "error", payload: [
                "sessionId": "s7", "kind": "error", "title": "Transfer from Pixel 8 Pro failed",
                "body": "The connection was lost after 2 of 5 files.", "detail": "",
                "primaryLabel": "History", "primaryAction": "history", "dismissLabel": "Close",
            ]),
        ]

        // Use the shipped Spanish strings for the user-facing review fixtures.
        let localeData = try Data(contentsOf: URL(fileURLWithPath: "app/assets/i18n/es-ES.json"))
        let locale = try JSONSerialization.jsonObject(with: localeData) as! [String: Any]
        let es = ((locale["settingsTab"] as! [String: Any])["general"] as! [String: Any]).compactMapValues { $0 as? String }
        fixtures.append(Fixture(name: "pending-es", payload: [
            "sessionId": "es-pending", "kind": "pending",
            "title": es["notificationPendingTitle"]!.replacingOccurrences(of: "{alias}", with: "Pixel 8 Pro"),
            "body": photoName, "detail": "3.4 MB",
            "primaryLabel": es["alertAccept"]!, "primaryAction": "accept",
            "secondaryLabel": es["alertReject"]!, "secondaryAction": "reject", "dismissLabel": es["alertDismiss"]!,
        ]))
        var spanishDone = [
            "sessionId": "es-done", "kind": "done",
            "title": es["alertDoneSingleTitle"]!.replacingOccurrences(of: "{alias}", with: "Pixel 8 Pro"),
            "body": photoName, "detail": "3.4 MB", "previewPath": photo.path,
            "primaryLabel": es["alertCopy"]!, "primaryAction": "copy",
            "secondaryLabel": es["alertOpen"]!, "secondaryAction": "open", "dismissLabel": es["alertDismiss"]!,
        ]
        fixtures.append(Fixture(name: "done-image-es", payload: spanishDone, preview: true))
        spanishDone["sessionId"] = "es-copied"
        fixtures.append(Fixture(name: "done-image-copied-es", payload: spanishDone, preview: true, feedback: (true, es["alertCopied"]!)))

        var sheets: [String: [(String, NSBitmapImageRep)]] = [:]
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let appearance = NSAppearance(named: appearance) else { continue }
            for fixture in fixtures {
                guard let payload = ReceiveAlertPayload(fixture.payload) else {
                    fatalError("Invalid fixture payload \(fixture.name)")
                }
                let view = ReceiveAlertView(payload: payload, onAction: { _, _ in }, onDismiss: {})
                view.appearance = appearance
                view.apply(payload)
                if fixture.preview {
                    guard let thumbnail = ReceiveAlertThumbnail.load(path: photo.path) else { fatalError("Thumbnail failed") }
                    let pixels = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? 0
                    precondition(pixels <= 132, "Preview was not downsampled: \(pixels)px")
                    view.setPreviewImage(thumbnail)
                }
                if let (success, message) = fixture.feedback { view.finish(success: success, message: message) }
                let rep = composite(view, appearance: appearance, dark: appearanceName == "dark")
                let file = output.appendingPathComponent("\(fixture.name)-\(appearanceName).png")
                try rep.representation(using: .png, properties: [:])!.write(to: file)
                sheets[appearanceName, default: []].append((fixture.name, rep))
                print("wrote \(file.path) \(Int(view.frame.width))x\(Int(view.frame.height))pt")
            }
        }
        for (name, reps) in sheets {
            let sheet = contactSheet(reps.map(\.1), dark: name == "dark")
            let file = output.appendingPathComponent("sheet-\(name).png")
            try sheet.representation(using: .png, properties: [:])!.write(to: file)
            print("wrote \(file.path)")
        }
    }

    static func imageDone(_ name: String, path: String) -> [String: String] {
        [
            "sessionId": "s4", "kind": "done", "title": "Received from Pixel 8 Pro",
            "body": name, "detail": "3.4 MB", "previewPath": path,
            "primaryLabel": "Copy image", "primaryAction": "copy",
            "secondaryLabel": "Open", "secondaryAction": "open", "dismissLabel": "Close",
        ]
    }

    static let scale: CGFloat = 2
    static let margin: CGFloat = 28

    /// The card bitmap on a neutral backdrop with a soft shadow approximating the window shadow.
    static func composite(_ view: ReceiveAlertView, appearance: NSAppearance, dark: Bool) -> NSBitmapImageRep {
        view.setFrameSize(view.fittingSize)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let cardRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                                       pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        cardRep.size = view.bounds.size
        appearance.performAsCurrentDrawingAppearance {
            // Draws only what the view paints, keeping the rounded corners transparent.
            view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(bitmapImageRep: cardRep)!)
        }

        let size = NSSize(width: view.bounds.width + margin * 2, height: view.bounds.height + margin * 2)
        return draw(size: size) {
            backdrop(NSRect(origin: .zero, size: size), dark: dark)
            let cardRect = NSRect(x: margin, y: margin, width: view.bounds.width, height: view.bounds.height)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowBlurRadius = 18
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.18)
            shadow.set()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: cardRect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).fill()
            NSGraphicsContext.restoreGraphicsState()
            // Offscreen AppKit fills the view's full bounds behind it; the real panel is
            // non-opaque with a clear background, so clip to the card shape it draws.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14).addClip()
            cardRep.draw(in: cardRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func contactSheet(_ reps: [NSBitmapImageRep], dark: Bool) -> NSBitmapImageRep {
        let width = reps.map(\.size.width).max() ?? 0
        let height = reps.map(\.size.height).reduce(0, +)
        return draw(size: NSSize(width: width, height: height)) {
            backdrop(NSRect(x: 0, y: 0, width: width, height: height), dark: dark)
            var y = height
            for rep in reps {
                y -= rep.size.height
                rep.draw(in: NSRect(x: 0, y: y, width: rep.size.width, height: rep.size.height))
            }
        }
    }

    static func backdrop(_ rect: NSRect, dark: Bool) {
        let colors = dark
            ? [NSColor(srgbRed: 0.11, green: 0.13, blue: 0.17, alpha: 1), NSColor(srgbRed: 0.18, green: 0.16, blue: 0.22, alpha: 1)]
            : [NSColor(srgbRed: 0.80, green: 0.86, blue: 0.92, alpha: 1), NSColor(srgbRed: 0.92, green: 0.88, blue: 0.86, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: rect, angle: -30)
    }

    static func draw(size: NSSize, _ body: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// A large synthetic "photo" (sky, hills, sun) so the preview path exercises real downsampling.
    static func writeSyntheticPhoto(to url: URL) throws {
        let size = NSSize(width: 2016, height: 1512)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.72, blue: 0.48, alpha: 1),
                            NSColor(srgbRed: 0.42, green: 0.62, blue: 0.86, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1180, y: 640, width: 300, height: 300)).fill()
        for (index, color) in [NSColor(srgbRed: 0.27, green: 0.45, blue: 0.38, alpha: 1),
                               NSColor(srgbRed: 0.16, green: 0.32, blue: 0.27, alpha: 1)].enumerated() {
            let path = NSBezierPath()
            let base = CGFloat(560 - index * 220)
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 0, y: base))
            path.curve(to: NSPoint(x: size.width, y: base - 80), controlPoint1: NSPoint(x: 600, y: base + 260),
                       controlPoint2: NSPoint(x: 1300, y: base - 240))
            path.line(to: NSPoint(x: size.width, y: 0))
            path.close()
            color.setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
