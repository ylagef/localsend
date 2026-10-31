import AppKit

@main
struct ReceiveAlertSmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let args = ["sessionId": "one", "kind": "done", "title": "Received", "body": "photo.png",
                    "primaryLabel": "Copy image", "primaryAction": "copy", "dismissLabel": "Dismiss"]
        let now = Date(timeIntervalSince1970: 100)
        precondition(ReceiveAlertController.deadlineAfterFailure(nil, now: now, lifetime: 20) == nil)
        precondition(ReceiveAlertController.deadlineAfterFailure(now.addingTimeInterval(-1), now: now, lifetime: 20) == now.addingTimeInterval(20))
        precondition(ReceiveAlertController.deadlineAfterFailure(now.addingTimeInterval(40), now: now, lifetime: 20) == now.addingTimeInterval(40))
        let payload = ReceiveAlertPayload(args)!
        precondition(ReceiveAlertPayload([:]) == nil)
        precondition(ReceiveAlertPayload(args.merging(["kind": "unknown"]) { _, new in new }) == nil)
        precondition(ReceiveAlertPayload(args.merging(["primaryAction": "delete"]) { _, new in new }) == nil)
        var actions = 0
        var dismissals = 0
        var reply: ((Bool, String) -> Void)?
        let view = ReceiveAlertView(payload: payload, onAction: { action, completion in
            precondition(action == "copy")
            actions += 1
            reply = completion
        }, onDismiss: { dismissals += 1 })
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        let copy = buttons.first { $0.title == "Copy image" }!
        // Dispatch only the local view's target/action. No host pointer or keyboard input.
        _ = copy.target?.perform(copy.action, with: copy)
        precondition(actions == 1 && !copy.isEnabled)
        _ = copy.target?.perform(copy.action, with: copy)
        precondition(actions == 1)
        reply?(false, "Could not copy. Try again.")
        precondition(copy.isEnabled)
        _ = copy.target?.perform(copy.action, with: copy)
        precondition(actions == 2)
        let oldReply = reply!
        let replacement = ReceiveAlertPayload(args.merging(["sessionId": "two", "title": "Replacement"]) { _, new in new })!
        view.apply(replacement)
        oldReply(true, "Old result")
        precondition(view.payload.sessionId == "two" && copy.isEnabled)
        let labels = view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        precondition(!labels.contains("Old result"))
        let close = buttons.first { $0 !== copy && $0.image != nil }!
        _ = close.target?.perform(close.action, with: close)
        precondition(dismissals == 1 && actions == 2)
        print("PASS: payload rejection, local quick action, busy guard, failure retry, stale view result, dismiss without decision; no windows shown")
    }
}
