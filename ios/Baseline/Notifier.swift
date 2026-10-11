import UserNotifications

/// Local reminders the page asks for: the end of a rest timer and a bedtime nudge.
/// Each has a key, so scheduling it again replaces the earlier one. They only show while the app isn't open;
/// when it is, the page shows its own message.
enum Notifier {
    private static var asked = false

    static func schedule(key: String, at: Date, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [key])
        let interval = at.timeIntervalSinceNow
        guard interval > 1 else { return }
        let add = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
        }
        if asked { add(); return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            asked = true
            if ok { add() }
        }
    }

    static func cancel(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [key])
    }
}
