import Foundation
import UserNotifications

@main
struct ReceiveNotificationSmoke {
    static func main() {
        let fields = ["sessionId": "session-a", "kind": "pending", "title": "Pixel", "body": "Click to review and accept."]
        let payload = ReceiveNotification(fields)!
        let request = payload.request
        precondition(request.identifier == "localsend-pending-session-a")
        precondition(request.content.title == "Pixel")
        precondition(request.content.body == fields["body"])
        precondition(request.content.userInfo["sessionId"] as? String == "session-a")
        precondition(request.content.userInfo["kind"] as? String == "pending")
        precondition(request.trigger == nil)
        precondition(request.content.attachments.isEmpty)
        for field in ["sessionId", "kind", "title", "body"] {
            var invalid = fields
            invalid.removeValue(forKey: field)
            precondition(ReceiveNotification(invalid) == nil)
        }
        var invalid = fields
        invalid["kind"] = "accept"
        precondition(ReceiveNotification(invalid) == nil)
        var done = fields
        done["kind"] = "done"
        precondition(ReceiveNotification(done)!.request.identifier != request.identifier)
        print("PASS: native pending/done payloads, per-session IDs, no attachment or auto-accept action; no notification posted")
    }
}
