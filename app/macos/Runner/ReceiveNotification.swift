import UserNotifications

struct ReceiveNotification {
    let sessionId: String
    let kind: String
    let title: String
    let body: String

    init?(_ arguments: [String: String]) {
        guard let sessionId = arguments["sessionId"], !sessionId.isEmpty,
              let kind = arguments["kind"], ["pending", "done"].contains(kind),
              let title = arguments["title"], !title.isEmpty,
              let body = arguments["body"] else { return nil }
        self.sessionId = sessionId
        self.kind = kind
        self.title = title
        self.body = body
    }

    static func identifier(sessionId: String, kind: String) -> String {
        "localsend-\(kind)-\(sessionId)"
    }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": sessionId, "kind": kind]
        return UNNotificationRequest(identifier: Self.identifier(sessionId: sessionId, kind: kind), content: content, trigger: nil)
    }
}
