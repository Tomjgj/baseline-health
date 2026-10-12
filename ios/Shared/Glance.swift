import Foundation
import SwiftUI

/// Today at a glance, for the widgets, the Live Activity's neighbours on the lock screen and the watch complications.
/// On the iPhone the page sends it as JSON (`{ type: "widget", json }`); on the watch the app builds it from the phone's context.
/// Every number is optional: a day without a watch night has no recovery, and a fresh install has nothing at all.
struct Glance: Codable, Equatable {
    var v: Int?
    var at: String?               // when the page built it, local "YYYY-MM-DDTHH:MM:SS"
    var date: String?             // the day the scores belong to, "YYYY-MM-DD"
    var units: String?            // "metric" | "imperial"
    var recovery: Double?         // 0...100
    var band: String?             // high | mid | low
    var strain: Double?           // 0...21
    var strainLo: Double?
    var strainHi: Double?
    var sleep: Double?            // score 0...100
    var asleep: Double?           // minutes
    var hrv: Double?
    var rhr: Double?
    var water: Water?
    var next: Next?

    struct Water: Codable, Equatable { var ml: Double; var goal: Double }
    struct Next: Codable, Equatable { var name: String; var time: String? }

    static func decode(_ json: String) -> Glance? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Glance.self, from: data)
    }

    var imperial: Bool { units == "imperial" }

    /// How old the scores are, said the way the app says it; nil when they're today's.
    func age(now: Date = Date()) -> String? {
        guard let date, let day = Self.dayFormat.date(from: date) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return nil
        case 1: return "Yesterday"
        case 2...6: return Self.weekdayFormat.string(from: day)
        default: return Self.shortDateFormat.string(from: day)
        }
    }

    var recoveryText: String { recovery.map { "\(Int($0.rounded()))%" } ?? "–" }
    var strainText: String { strain.map { String(format: "%.1f", $0) } ?? "–" }
    var sleepText: String { sleep.map { "\(Int($0.rounded()))" } ?? "–" }
    var asleepText: String? {
        guard let m = asleep, m > 0 else { return nil }
        let t = Int(m.rounded())
        return "\(t / 60)h \(String(format: "%02d", t % 60))m"
    }
    var strainTargetText: String? {
        guard let lo = strainLo, let hi = strainHi else { return nil }
        return "\(Int(lo.rounded()))–\(Int(hi.rounded()))"
    }
    var waterText: String? {
        guard let w = water else { return nil }
        return Self.waterText(ml: w.ml, goal: w.goal, imperial: imperial)
    }

    /// "1.2 L of 2.5 L", or "41 of 85 fl oz".
    static func waterText(ml: Double, goal: Double, imperial: Bool) -> String {
        if imperial {
            let oz = { (v: Double) in Int((v / 29.5735).rounded()) }
            return goal > 0 ? "\(oz(ml)) of \(oz(goal)) fl oz" : "\(oz(ml)) fl oz"
        }
        let l = { (v: Double) in String(format: "%.1f", v / 1000) }
        return goal > 0 ? "\(l(ml)) L of \(l(goal)) L" : "\(l(ml)) L"
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let weekdayFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()
    private static let shortDateFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()
}

/// The latest glance, kept in the App Group's defaults so the widgets (a separate process) can read it.
/// Without an App Group (the Lite project, for free Apple IDs) there is nowhere to share it, so nothing is stored.
enum GlanceStore {
    private static let key = "baseline.glance"

    static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "BaselineAppGroup") as? String, !group.isEmpty,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
        return UserDefaults(suiteName: group)
    }

    /// Stores the JSON as it came; returns false when there's no App Group.
    @discardableResult
    static func save(json: String) -> Bool {
        guard let d = defaults else { return false }
        d.set(json, forKey: key)
        return true
    }

    @discardableResult
    static func save(_ glance: Glance) -> Bool {
        guard let data = try? JSONEncoder().encode(glance), let json = String(data: data, encoding: .utf8) else { return false }
        return save(json: json)
    }

    static func load() -> Glance? {
        defaults?.string(forKey: key).flatMap(Glance.decode)
    }
}

/// The data colours, as the page draws them.
enum Palette {
    static let strain = Color(red: 0x3B / 255, green: 0x8D / 255, blue: 0xEB / 255)
    static let sleep = Color(red: 0x8F / 255, green: 0x7B / 255, blue: 0xF0 / 255)
    static let water = Color(red: 0x3A / 255, green: 0xAE / 255, blue: 0xE0 / 255)
    static let hrv = Color(red: 0x1A / 255, green: 0xA3 / 255, blue: 0x94 / 255)
    static let heart = Color(red: 0xE0 / 255, green: 0x52 / 255, blue: 0x6E / 255)
    static let high = Color(red: 0x2E / 255, green: 0xA8 / 255, blue: 0x66 / 255)
    static let mid = Color(red: 0xB8 / 255, green: 0x89 / 255, blue: 0x0F / 255)
    static let low = Color(red: 0xE5 / 255, green: 0x53 / 255, blue: 0x4B / 255)
    static let background = Color(red: 7 / 255, green: 8 / 255, blue: 11 / 255)

    static func recovery(_ band: String?) -> Color {
        switch band { case "high": return high; case "mid": return mid; case "low": return low; default: return .gray }
    }
}
