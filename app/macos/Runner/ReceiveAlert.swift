import AppKit
import ImageIO

// Custom receive card shown while LocalSend is in the background.
// Pure AppKit/ImageIO: no Flutter dependency, so it compiles and renders on its own.
// Design notes and limitations: docs/CUSTOM_ALERT_DESIGN.md

// MARK: - Payload

struct ReceiveAlertPayload: Equatable {
    static let kinds: Set<String> = ["pending", "receiving", "done", "error"]
    static let actions: Set<String> = ["accept", "reject", "copy", "open", "history"]

    let sessionId: String
    let kind: String
    let title: String
    let body: String
    let detail: String
    let previewPath: String?
    let primaryLabel: String
    let primaryAction: String
    let secondaryLabel: String
    let secondaryAction: String
    let dismissLabel: String

    /// Returns nil for a missing session, unknown kind, empty title or unknown action.
    /// An empty label or action hides that button.
    init?(_ arguments: [String: String]) {
        func value(_ key: String) -> String { arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let sessionId = value("sessionId")
        let kind = value("kind")
        let title = value("title")
        let primaryAction = value("primaryAction")
        let secondaryAction = value("secondaryAction")
        guard !sessionId.isEmpty, Self.kinds.contains(kind), !title.isEmpty,
              primaryAction.isEmpty || Self.actions.contains(primaryAction),
              secondaryAction.isEmpty || Self.actions.contains(secondaryAction) else { return nil }
        self.sessionId = sessionId
        self.kind = kind
        self.title = title
        self.body = value("body")
        self.detail = value("detail")
        let previewPath = value("previewPath")
        self.previewPath = previewPath.isEmpty ? nil : previewPath
        self.primaryLabel = value("primaryLabel")
        self.primaryAction = primaryAction
        self.secondaryLabel = value("secondaryLabel")
        self.secondaryAction = secondaryAction
        let dismissLabel = value("dismissLabel")
        self.dismissLabel = dismissLabel.isEmpty ? "Close" : dismissLabel
    }

    var isPending: Bool { kind == "pending" }
}

// MARK: - Style

enum ReceiveAlertStyle {
    static let width: CGFloat = 372
    static let padding: CGFloat = 14
    static let cornerRadius: CGFloat = 14
    static let leadingSize: CGFloat = 44
    static let columnGap: CGFloat = 12
    static let buttonHeight: CGFloat = 24
    static let buttonGap: CGFloat = 8
    static let closeSize: CGFloat = 18

    /// LocalSend teal (#00645A), lifted slightly in dark mode so white text keeps ≥5:1 contrast.
    static func accent(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.04, green: 0.48, blue: 0.43, alpha: 1)
             : NSColor(srgbRed: 0, green: 0.392, blue: 0.353, alpha: 1)
    }

    static func accentText(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.42, green: 0.82, blue: 0.75, alpha: 1)
             : NSColor(srgbRed: 0, green: 0.392, blue: 0.353, alpha: 1)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Thumbnail

enum ReceiveAlertThumbnail {
    /// Decodes a small, orientation-corrected thumbnail without loading the full image.
    static func load(path: String, maxPixelSize: Int = 132) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return squareCropped(image)
    }

    /// Center crop to a square so the tile reads as aspect-fill without distortion.
    static func squareCropped(_ image: CGImage) -> NSImage {
        let side = min(image.width, image.height)
        let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        let cropped = image.cropping(to: rect) ?? image
        return NSImage(cgImage: cropped, size: NSSize(width: side, height: side))
    }

    static func squareCropped(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        return squareCropped(cgImage)
    }
}

// MARK: - Buttons

/// Drawn button: keeps the same colors whether or not the panel is key (system
/// accent bezels turn gray in inactive windows, which is where this card lives).
final class ReceiveAlertButton: NSButton {
    enum Role { case primary, secondary, close }

    let role: Role
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .default
        font = .systemFont(ofSize: 12, weight: role == .primary ? .semibold : .medium)
        if role == .close {
            let config = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold)
            image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            imagePosition = .imageOnly
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        if role == .close { return NSSize(width: ReceiveAlertStyle.closeSize, height: ReceiveAlertStyle.closeSize) }
        let textWidth = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width
        return NSSize(width: max(64, ceil(textWidth) + 24), height: ReceiveAlertStyle.buttonHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let dark = ReceiveAlertStyle.isDark(effectiveAppearance)
        let pressed = isHighlighted
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)

        switch role {
        case .close:
            if hovering || pressed {
                NSColor.labelColor.withAlphaComponent(pressed ? 0.16 : 0.09).setFill()
                NSBezierPath(ovalIn: bounds).fill()
            }
            drawSymbol(tint: NSColor.secondaryLabelColor.withAlphaComponent(alpha))
            return
        case .primary:
            var fill = ReceiveAlertStyle.accent(dark: dark)
            if pressed { fill = fill.blended(withFraction: 0.18, of: .black) ?? fill }
            else if hovering { fill = fill.blended(withFraction: 0.08, of: .white) ?? fill }
            fill.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            drawTitle(color: NSColor.white.withAlphaComponent(alpha))
        case .secondary:
            let base: CGFloat = dark ? 0.12 : 0.07
            NSColor.labelColor.withAlphaComponent((pressed ? base * 2 : hovering ? base * 1.5 : base) * alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            drawTitle(color: NSColor.labelColor.withAlphaComponent(alpha))
        }
    }

    private func drawTitle(color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (title as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: 6, y: (bounds.height - size.height) / 2, width: bounds.width - 12, height: size.height)
        (title as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawSymbol(tint: NSColor) {
        guard let image else { return }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let origin = NSPoint(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2)
        tinted.draw(in: NSRect(origin: origin, size: image.size))
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        if role == .close { NSBezierPath(ovalIn: bounds).fill() }
        else { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    }
}

// MARK: - View

/// Pure card view. Usable offscreen: set `appearance`, call `layoutSubtreeIfNeeded()`
/// and draw with `displayIgnoringOpacity(_:in:)`. Its size is fixed width, height from content.
final class ReceiveAlertView: NSView {
    typealias ActionHandler = (_ action: String, _ completion: @escaping (Bool, String) -> Void) -> Void

    private(set) var payload: ReceiveAlertPayload
    var onAction: ActionHandler
    var onDismiss: () -> Void
    var onHoverChange: ((Bool) -> Void)?

    private let leadingView = NSImageView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let bodyField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let primaryButton = ReceiveAlertButton(role: .primary)
    private let secondaryButton = ReceiveAlertButton(role: .secondary)
    private let closeButton = ReceiveAlertButton(role: .close)
    private var previewImage: NSImage?
    private var status: (success: Bool, message: String)?
    private var busy = false
    /// Bumped on every payload change, so a completion from older content is ignored.
    private var generation = 0
    private var trackingArea: NSTrackingArea?

    init(payload: ReceiveAlertPayload, onAction: @escaping ActionHandler, onDismiss: @escaping () -> Void) {
        self.payload = payload
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init(frame: NSRect(x: 0, y: 0, width: ReceiveAlertStyle.width, height: 96))
        setUp()
        apply(payload)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setUp() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        leadingView.imageScaling = .scaleProportionallyUpOrDown
        leadingView.wantsLayer = true
        leadingView.layer?.cornerRadius = 9
        leadingView.layer?.masksToBounds = true

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byWordWrapping
        titleField.cell?.truncatesLastVisibleLine = true

        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .secondaryLabelColor
        bodyField.lineBreakMode = .byTruncatingMiddle   // keeps file extensions visible
        bodyField.maximumNumberOfLines = 1

        detailField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .tertiaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.maximumNumberOfLines = 1

        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.setAccessibilityElement(false)

        for field in [titleField, bodyField, detailField] {
            field.isSelectable = false
            field.allowsDefaultTighteningForTruncation = true
        }

        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryPressed)
        closeButton.target = self
        closeButton.action = #selector(closePressed)

        [leadingView, titleField, bodyField, detailField, statusIcon, secondaryButton, primaryButton, closeButton].forEach(addSubview)
    }

    // MARK: Content

    /// Replaces the content in place. Any in-flight action result for the old content is dropped.
    func apply(_ payload: ReceiveAlertPayload) {
        let previewChanged = payload.previewPath != self.payload.previewPath
        self.payload = payload
        generation += 1
        busy = false
        status = nil
        if previewChanged { previewImage = nil }

        titleField.stringValue = payload.title
        bodyField.stringValue = payload.body
        bodyField.toolTip = payload.body.isEmpty ? nil : payload.body
        detailField.stringValue = payload.detail
        configure(primaryButton, label: payload.primaryLabel, action: payload.primaryAction)
        configure(secondaryButton, label: payload.secondaryLabel, action: payload.secondaryAction)
        closeButton.toolTip = payload.dismissLabel
        closeButton.setAccessibilityLabel(payload.dismissLabel)
        setAccessibilityLabel([payload.title, payload.body, payload.detail].filter { !$0.isEmpty }.joined(separator: ", "))
        updateLeading()
        updateState()
        loadPreviewIfNeeded()
    }

    /// Supplies an already decoded preview (used by offscreen rendering and tests).
    func setPreviewImage(_ image: NSImage?) {
        previewImage = image.map { ReceiveAlertThumbnail.squareCropped($0) }
        updateLeading()
    }

    private func configure(_ button: ReceiveAlertButton, label: String, action: String) {
        let visible = !label.isEmpty && !action.isEmpty
        button.isHidden = !visible
        button.title = label
        button.setAccessibilityLabel(label)
        button.invalidateIntrinsicContentSize()
    }

    private func loadPreviewIfNeeded() {
        guard previewImage == nil, let path = payload.previewPath else { return }
        let expected = generation
        let scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        let pixels = Int(ReceiveAlertStyle.leadingSize * scale * 1.5)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ReceiveAlertThumbnail.load(path: path, maxPixelSize: pixels)
            DispatchQueue.main.async {
                guard let self, self.generation == expected, self.payload.previewPath == path else { return }
                self.setPreviewImage(image)
            }
        }
    }

    private func updateLeading() {
        let dark = ReceiveAlertStyle.isDark(effectiveAppearance)
        if let previewImage {
            leadingView.image = previewImage
            leadingView.imageScaling = .scaleAxesIndependently
            leadingView.contentTintColor = nil
            leadingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
            leadingView.setAccessibilityElement(false)
            needsLayout = true
            needsDisplay = true
            return
        }
        let symbol: String
        let tint: NSColor
        switch payload.kind {
        case "pending": symbol = "arrow.down"; tint = ReceiveAlertStyle.accentText(dark: dark)
        case "receiving": symbol = "arrow.down.circle"; tint = ReceiveAlertStyle.accentText(dark: dark)
        case "error": symbol = "exclamationmark.triangle"; tint = .systemOrange
        default: symbol = "checkmark"; tint = ReceiveAlertStyle.accentText(dark: dark)
        }
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        leadingView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        leadingView.imageScaling = .scaleNone
        leadingView.contentTintColor = tint
        let wash = payload.kind == "error" ? NSColor.systemOrange : ReceiveAlertStyle.accent(dark: dark)
        leadingView.layer?.backgroundColor = wash.withAlphaComponent(dark ? 0.22 : 0.11).cgColor
        leadingView.setAccessibilityElement(false)
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLeading()
        updateState()
    }

    private func updateState() {
        let dark = ReceiveAlertStyle.isDark(effectiveAppearance)
        primaryButton.isEnabled = !busy
        secondaryButton.isEnabled = !busy
        if let status {
            let symbol = status.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            statusIcon.contentTintColor = status.success ? ReceiveAlertStyle.accentText(dark: dark) : .systemRed
            statusIcon.isHidden = false
            detailField.stringValue = status.message
            detailField.font = .systemFont(ofSize: 11, weight: .medium)
            detailField.textColor = status.success ? ReceiveAlertStyle.accentText(dark: dark) : .systemRed
        } else {
            statusIcon.isHidden = true
            detailField.stringValue = payload.detail
            detailField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            detailField.textColor = .tertiaryLabelColor
        }
        detailField.isHidden = detailField.stringValue.isEmpty
        needsLayout = true
    }

    // MARK: Actions

    @objc private func primaryPressed() { perform(payload.primaryAction) }
    @objc private func secondaryPressed() { perform(payload.secondaryAction) }
    @objc private func closePressed() { onDismiss() }

    override func cancelOperation(_ sender: Any?) { onDismiss() }

    private func perform(_ action: String) {
        guard !busy, ReceiveAlertPayload.actions.contains(action) else { return }
        busy = true
        status = nil
        updateState()
        let expected = generation
        onAction(action) { [weak self] success, message in
            let finish = {
                guard let self, self.generation == expected else { return }
                self.finish(success: success, message: message)
            }
            if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
        }
    }

    /// Shows feedback without leaving the card; on failure the buttons stay usable for retry.
    func finish(success: Bool, message: String) {
        busy = false
        status = message.isEmpty ? nil : (success, message)
        updateState()
        if !message.isEmpty {
            NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
                .announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    /// Test hook: the generation that a completion must match.
    var contentGeneration: Int { generation }

    // MARK: Layout

    private var textX: CGFloat { ReceiveAlertStyle.padding + ReceiveAlertStyle.leadingSize + ReceiveAlertStyle.columnGap }
    private var textWidth: CGFloat { ReceiveAlertStyle.width - textX - ReceiveAlertStyle.padding - ReceiveAlertStyle.closeSize - 6 }

    private func height(of field: NSTextField, width: CGFloat) -> CGFloat {
        guard !field.isHidden, !field.stringValue.isEmpty, let cell = field.cell else { return 0 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height)
    }

    private var hasButtons: Bool { !primaryButton.isHidden || !secondaryButton.isHidden }

    /// Height for the current content at the fixed card width.
    var fittingHeight: CGFloat {
        let p = ReceiveAlertStyle.padding
        var y = p - 1
        y += height(of: titleField, width: textWidth)
        let body = height(of: bodyField, width: textWidth)
        if body > 0 { y += 1 + body }
        let detail = height(of: detailField, width: textWidth)
        if detail > 0 { y += 2 + detail }
        if hasButtons { y += 10 + ReceiveAlertStyle.buttonHeight }
        return ceil(max(y + p, p * 2 + ReceiveAlertStyle.leadingSize))
    }

    override var fittingSize: NSSize { NSSize(width: ReceiveAlertStyle.width, height: fittingHeight) }
    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let p = ReceiveAlertStyle.padding
        leadingView.frame = NSRect(x: p, y: p, width: ReceiveAlertStyle.leadingSize, height: ReceiveAlertStyle.leadingSize)
        closeButton.frame = NSRect(x: bounds.width - p - ReceiveAlertStyle.closeSize + 4, y: p - 4,
                                   width: ReceiveAlertStyle.closeSize, height: ReceiveAlertStyle.closeSize)

        var y = p - 1
        let titleHeight = height(of: titleField, width: textWidth)
        titleField.frame = NSRect(x: textX, y: y, width: textWidth, height: titleHeight)
        y += titleHeight
        let bodyHeight = height(of: bodyField, width: textWidth)
        bodyField.isHidden = bodyField.stringValue.isEmpty
        if bodyHeight > 0 { y += 1; bodyField.frame = NSRect(x: textX, y: y, width: textWidth, height: bodyHeight); y += bodyHeight }
        let detailHeight = height(of: detailField, width: textWidth)
        if detailHeight > 0 {
            y += 2
            var detailX = textX
            if !statusIcon.isHidden {
                statusIcon.frame = NSRect(x: textX, y: y + (detailHeight - 13) / 2, width: 13, height: 13)
                detailX += 17
            }
            detailField.frame = NSRect(x: detailX, y: y, width: textX + textWidth - detailX, height: detailHeight)
            y += detailHeight
        }

        if hasButtons {
            y = max(y + 10, p + ReceiveAlertStyle.leadingSize - ReceiveAlertStyle.buttonHeight + 10)
            var right = bounds.width - p
            let maxWidth = (bounds.width - textX - p - ReceiveAlertStyle.buttonGap) / 2
            for button in [primaryButton, secondaryButton] where !button.isHidden {
                let width = min(button.intrinsicContentSize.width, maxWidth)
                button.frame = NSRect(x: right - width, y: y, width: width, height: ReceiveAlertStyle.buttonHeight)
                right -= width + ReceiveAlertStyle.buttonGap
            }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dark = ReceiveAlertStyle.isDark(effectiveAppearance)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: ReceiveAlertStyle.cornerRadius, yRadius: ReceiveAlertStyle.cornerRadius)
        (dark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
              : NSColor(srgbRed: 0.985, green: 0.985, blue: 0.98, alpha: 1)).setFill()
        shape.fill()
        (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.09)).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

// MARK: - Panel

/// Borderless, nonactivating auxiliary panel. It never activates LocalSend; it only becomes
/// key if a view needs it (none do), so clicks act without stealing focus.
final class ReceiveAlertPanel: NSPanel {
    init(contentView view: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        worksWhenModal = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isMovable = false
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class ReceiveAlertController {
    typealias ActionCallback = (_ sessionId: String, _ kind: String, _ action: String,
                                _ completion: @escaping (Bool, String) -> Void) -> Void

    /// Called for accept/reject/copy/open/history. Call completion exactly once, on any thread.
    var onAction: ActionCallback?
    /// Optional: the user closed a card. Closing never accepts or rejects.
    var onClose: ((_ sessionId: String, _ kind: String) -> Void)?

    /// Auto-close delays. Pending and receiving cards never expire.
    var doneLifetime: TimeInterval = 12
    var errorLifetime: TimeInterval = 20
    var feedbackLifetime: TimeInterval = 3.5
    let maxVisibleCards = 4

    private final class Card {
        let panel: ReceiveAlertPanel
        let view: ReceiveAlertView
        var hovering = false
        var timer: Timer?
        var deadline: Date?
        init(panel: ReceiveAlertPanel, view: ReceiveAlertView) { self.panel = panel; self.view = view }
    }

    private var cards: [String: Card] = [:]
    private var order: [String] = []   // newest first

    init() {}

    func show(_ payload: ReceiveAlertPayload) {
        if let card = cards[payload.sessionId] {
            card.view.apply(payload)
            resize(card)
            scheduleExpiry(card, kind: payload.kind)
            layoutStack(animated: true)
            announce(payload)
            return
        }
        let view = ReceiveAlertView(payload: payload, onAction: { _, _ in }, onDismiss: {})
        let card = Card(panel: ReceiveAlertPanel(contentView: view), view: view)
        wire(card, sessionId: payload.sessionId)
        cards[payload.sessionId] = card
        order.insert(payload.sessionId, at: 0)
        trimOverflow()
        resize(card)
        layoutStack(animated: false, newSessionId: payload.sessionId)
        present(card)
        scheduleExpiry(card, kind: payload.kind)
        announce(payload)
    }

    func dismiss(sessionId: String) {
        guard let card = cards.removeValue(forKey: sessionId) else { return }
        order.removeAll { $0 == sessionId }
        card.timer?.invalidate()
        card.view.onHoverChange = nil
        fadeOut(card.panel)
        layoutStack(animated: true)
    }

    func dismissAll() { order.forEach(dismiss(sessionId:)) }

    var visibleSessionIds: [String] { order }

    // MARK: Wiring

    private func wire(_ card: Card, sessionId: String) {
        card.view.onDismiss = { [weak self, weak card] in
            guard let self, let card, self.cards[sessionId] === card else { return }
            let kind = card.view.payload.kind
            self.dismiss(sessionId: sessionId)
            self.onClose?(sessionId, kind)
        }
        card.view.onHoverChange = { [weak self, weak card] hovering in
            guard let self, let card else { return }
            card.hovering = hovering
            if hovering { card.timer?.invalidate() } else { self.resumeExpiry(card) }
        }
        card.view.onAction = { [weak self, weak card] action, viewCompletion in
            guard let self, let card, self.cards[sessionId] === card else { return }
            let kind = card.view.payload.kind
            guard let onAction = self.onAction else {
                viewCompletion(false, "")
                return
            }
            let generation = card.view.contentGeneration
            card.timer?.invalidate()
            onAction(sessionId, kind, action) { [weak self, weak card] success, message in
                DispatchQueue.main.async {
                    // A replaced or dismissed card must never be mutated or revealed by an old result.
                    guard let self, let card, self.cards[sessionId] === card,
                          card.view.contentGeneration == generation else { return }
                    viewCompletion(success, message)
                    self.handleResult(card, sessionId: sessionId, action: action, success: success)
                }
            }
        }
    }

    private func handleResult(_ card: Card, sessionId: String, action: String, success: Bool) {
        guard success else {
            card.deadline = Self.deadlineAfterFailure(card.deadline, now: Date(), lifetime: errorLifetime)
            resumeExpiry(card)   // leave a full retry window, even if the old deadline expired
            return
        }
        switch action {
        case "copy":
            card.deadline = Date().addingTimeInterval(feedbackLifetime)
            resumeExpiry(card)
        case "open", "history", "reject":
            dismiss(sessionId: sessionId)
        default:   // accept: keep until the app sends the next state, as a done card would
            card.deadline = Date().addingTimeInterval(doneLifetime)
            resumeExpiry(card)
        }
    }

    // MARK: Expiry

    static func deadlineAfterFailure(_ deadline: Date?, now: Date, lifetime: TimeInterval) -> Date? {
        guard let deadline else { return nil } // pending decisions never expire
        return max(deadline, now.addingTimeInterval(lifetime))
    }

    private func scheduleExpiry(_ card: Card, kind: String) {
        card.timer?.invalidate()
        switch kind {
        case "done": card.deadline = Date().addingTimeInterval(doneLifetime)
        case "error": card.deadline = Date().addingTimeInterval(errorLifetime)
        default: card.deadline = nil
        }
        resumeExpiry(card)
    }

    private func resumeExpiry(_ card: Card) {
        card.timer?.invalidate()
        guard !card.hovering, let deadline = card.deadline else { return }
        let delay = max(deadline.timeIntervalSinceNow, 2.5)   // leave time to read after hover
        let sessionId = card.view.payload.sessionId
        let identity = ObjectIdentifier(card)
        card.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let card = self.cards[sessionId], ObjectIdentifier(card) == identity, !card.hovering else { return }
                self.dismiss(sessionId: sessionId)
            }
        }
    }

    // MARK: Presentation

    private func trimOverflow() {
        while order.count > maxVisibleCards,
              let oldest = order.last(where: { cards[$0]?.view.payload.isPending == false }) {
            dismiss(sessionId: oldest)
        }
    }

    private func resize(_ card: Card) {
        card.view.layoutSubtreeIfNeeded()
        let size = card.view.fittingSize
        card.view.setFrameSize(size)
        var frame = card.panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        card.panel.setFrame(frame, display: true)
    }

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    private func layoutStack(animated: Bool, newSessionId: String? = nil) {
        guard let visible = screen?.visibleFrame else { return }
        var top = visible.maxY - 12
        for sessionId in order {
            guard let card = cards[sessionId] else { continue }
            let size = card.panel.frame.size
            let frame = NSRect(x: visible.maxX - size.width - 12, y: top - size.height, width: size.width, height: size.height)
            if animated && sessionId != newSessionId && !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    card.panel.animator().setFrame(frame, display: true)
                }
            } else {
                card.panel.setFrame(frame, display: true)
            }
            top -= size.height + 10
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// orderFrontRegardless shows the panel without activating LocalSend or changing the key window.
    private func present(_ card: Card) {
        let target = card.panel.frame
        if reduceMotion {
            card.panel.alphaValue = 1
            card.panel.orderFrontRegardless()
            return
        }
        card.panel.alphaValue = 0
        card.panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        card.panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            card.panel.animator().alphaValue = 1
            card.panel.animator().setFrame(target, display: true)
        }
    }

    private func fadeOut(_ panel: ReceiveAlertPanel) {
        guard !reduceMotion else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func announce(_ payload: ReceiveAlertPayload) {
        let text = [payload.title, payload.body].filter { !$0.isEmpty }.joined(separator: ". ")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}
