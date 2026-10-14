import Foundation
import UserNotifications

/// Local reminders the page asks for: the end of a rest timer and a bedtime nudge; and the morning notification.
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

    /// Shows a notification now (the morning "recovery is ready"). Only if the person already allowed notifications:
    /// this runs in the background, where iOS can't ask.
    static func post(key: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }

    /// Asks for permission while the app is open, when the person turns on a notification that comes later in the background.
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in asked = true }
    }
}

/// The page's notification preferences (`{ type: "prefs", json }`), kept here so the app can act on them in the background.
enum Prefs {
    private static let morningKey = "baseline.pref.morning", waterKey = "baseline.pref.waterNudges", notifiedKey = "baseline.morningNotified"

    /// "Your recovery is ready" once last night's sleep reaches Health.
    static var morning: Bool { UserDefaults.standard.bool(forKey: morningKey) }
    /// Kept for the page; the reminders themselves are scheduled by the page with `notify`.
    static var waterNudges: Bool { UserDefaults.standard.bool(forKey: waterKey) }
    /// The day (YYYY-MM-DD) the morning notification last went out.
    static var morningNotified: String? {
        get { UserDefaults.standard.string(forKey: notifiedKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifiedKey) }
    }

    static func save(json: String) {
        guard let data = json.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let on = o["morning"] as? Bool {
            if on && !morning { Notifier.ask() }
            UserDefaults.standard.set(on, forKey: morningKey)
        }
        if let on = o["waterNudges"] as? Bool { UserDefaults.standard.set(on, forKey: waterKey) }
    }
}
