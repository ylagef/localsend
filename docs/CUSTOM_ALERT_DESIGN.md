# Custom receive card (macOS)

Replaces the `UserNotifications` banner backend (`ReceiveNotification.swift`, build 2026103102) with a
small LocalSend-owned card shown while the app is in the background. Implementation:
`app/macos/Runner/ReceiveAlert.swift` (AppKit + ImageIO only, no Flutter). Evidence renderer:
`scripts/render-receive-alerts.swift`.

## Why a custom card

The main use is receiving photos from a phone and pasting them immediately. The previous integration opened
the app; the card puts **Copy image** and **Open** next to a real thumbnail, and puts
**Receive/Decline** next to the request without bringing the main window forward.

Sources and where this follows or departs from them:

- [NSPanel `becomesKeyOnlyIfNeeded`](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
  and the `nonactivatingPanel` style: the card is a borderless nonactivating auxiliary panel, shown with
  `orderFrontRegardless()`. LocalSend is never activated and the key window never changes on arrival.
- [HIG Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications):
  concise title, short body, at most two actions with verb labels, no promotional copy. Followed.
- Departure: this is not a system notification. It does not appear in Notification Center, has no
  sound and does not follow Focus / Do Not Disturb or the notification settings. The existing in-app
  opt-in is the only switch.

## Visual decisions

- 372 pt wide, 14 pt radius, top-right of the visible frame of the main screen, stacked downward
  (10 pt gap, newest on top, at most 4; overflow drops the oldest non-pending card, pending cards stay).
- Solid surface (`#FBFBFA` light, `#2B2B2E` dark) with a hairline and the window shadow. No vibrancy:
  it stays legible over any wallpaper and renders identically offscreen.
- 44 pt leading tile: a center-cropped thumbnail for images (decoded with ImageIO at ≤132 px,
  orientation applied, off the main thread), otherwise an SF Symbol on a teal wash
  (orange for errors).
- System type only: title 13 semibold (2 lines, tail truncation), body 12 secondary (1 line, middle
  truncation so file extensions survive), detail 11 tertiary with monospaced digits.
- Buttons are drawn, not system bezels: accent bezels turn gray in inactive windows, which is where
  this card always lives. Primary is LocalSend teal `#00645A` (lifted to `#0A7A6E` in dark) with white
  text (≥5:1); secondary is a neutral fill. Decline is deliberately not red: rejecting loses nothing.
- Feedback replaces the detail line: teal check + message on success, red mark + message on failure.

## Behavior

| Kind | Expiry | Notes |
| --- | --- | --- |
| pending | never | Close hides the card only; the request stays pending in the app. |
| receiving | never | No buttons unless the payload supplies them. |
| done | 12 s | After a successful Copy: 3.5 s so the confirmation can be read. |
| error | 20 s | |

- Hover pauses expiry; leaving restarts it with at least 2.5 s left.
- An action disables both buttons until its completion. Failure re-enables them (retry = press again)
  and never closes the card. Success: `copy` shows feedback, `open`/`history`/`reject` close the card,
  `accept` keeps it until the app sends the next state (falls back to the done expiry).
- Stale results: every `show` for a session bumps a content generation. A completion is applied only if
  the same card object is still registered for that session and its generation is unchanged, so an old
  result never mutates, reveals or closes a replacement card.
- Closing (✕ or Escape when a button has focus) calls only `onClose`, never `onAction`.
- Accessibility: card is an `AXGroup` labeled with title/body/detail; buttons use their visible labels;
  ✕ uses `dismissLabel`; arrival and feedback post `announcementRequested`. Reduce Motion removes the
  slide/fade.

## Public API

```swift
struct ReceiveAlertPayload { init?(_ arguments: [String: String]) }   // keys per contract
@MainActor final class ReceiveAlertController {
    var onAction: ((String, String, String, @escaping (Bool, String) -> Void) -> Void)?  // sessionId, kind, action
    var onClose: ((String, String) -> Void)?                                             // optional
    func show(_ payload: ReceiveAlertPayload)
    func dismiss(sessionId: String)
    func dismissAll()
}
final class ReceiveAlertView: NSView {
    init(payload:onAction:onDismiss:)   // onAction: (action, completion)
    func apply(_:); func setPreviewImage(_:); func finish(success:message:); var fittingSize
}
```

Invalid payloads (empty session/title, unknown kind or action) return nil. An empty label or action
hides that button; an empty `dismissLabel` falls back to "Close" (the lead should always localize it).

## Evidence

Rendered offscreen with real AppKit views, synthetic data, light and dark; no window is created or
shown. Files in `artifacts/evidence/custom-alerts/`: `sheet-light.png`, `sheet-dark.png` and per-state
`pending`, `pending-long`, `receiving`, `done-image`, `done-image-copied`, `done-image-copy-error`,
`done-image-long`, `done-files`, `error` (`-light`/`-dark`). The backdrop and shadow are drawn by the
renderer to approximate the window server; the card pixels are the view's own drawing.

```bash
swiftc -parse-as-library app/macos/Runner/ReceiveAlert.swift scripts/render-receive-alerts.swift -o /tmp/render-receive-alerts && /tmp/render-receive-alerts artifacts/evidence/custom-alerts
```

## Limitations

- Ignores Focus, Do Not Disturb, screen sharing privacy and notification settings; not in
  Notification Center, so a missed card is only recoverable from the app's history.
- Shown on `NSScreen.main` only; the stack does not follow screen changes while visible.
- Hover, click-through without activation, VoiceOver announcements and stacking animation are not
  verified by the offscreen renders; they need a live check in the integrated build.
- Keyboard users reach the buttons only with VoiceOver or full keyboard access focusing the panel; the
  card never takes focus on its own.
