import Foundation

/// What the phone sends the watch: today's scores, the workouts to offer, and a workout in progress on the phone.
/// The page builds it (Watch.context in index.html) and the iPhone app forwards it as JSON.
struct WatchContext: Codable {
    var v: Int
    var at: String
    var units: String              // "kg" or "lb"
    var day: Day?
    var next: Plan?
    var routines: [Plan]
    var draft: Plan?
    var tired: [String]?           // muscles still recovering, most tired first
    var water: Water?              // today's water (missing in contexts from older versions of the page, like library)
    var library: [Ex]?             // exercises that can be added to a running workout
    var healthWrite: Bool?         // save workouts to Apple Health (the phone's Settings switch; off when missing)

    struct Water: Codable {
        var ml: Double
        var goal: Double
        var glass: Double?         // what one tap on "+ Glass" adds
    }

    struct Day: Codable {
        var date: String
        var recovery: Int?
        var band: String?          // high | mid | low
        var strain: Double?
        var lo: Double?
        var hi: Double?
        var sleep: Int?
        var asleep: Int?           // minutes
        var hrv: Int?
        var rhr: Int?
    }
}

struct Plan: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var why: String?               // "Planned · 18:00", "Suggested", "In progress on iPhone"
    var routineId: String?
    var startedAt: Double?         // ms since 1970, for a workout already running
    var minutes: Int?
    var exercises: [Ex]
}

struct Ex: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var rest: Int                  // seconds
    var bw: Bool?
    var sets: [WSet]
}

struct WSet: Codable, Equatable {
    var t: String                  // N normal, W warm-up, D drop, F failure
    var w: Double?                 // kg; nil = not set
    var r: Int?                    // reps done
    var ph: Int?                   // reps aimed for
    var done: Bool
}

/// Weights are stored in kilograms; the watch shows the person's unit.
struct Units {
    var lb: Bool
    func show(_ kg: Double) -> Double { lb ? (kg * 2.20462 * 2).rounded() / 2 : (kg * 4).rounded() / 4 }
    func kg(_ shown: Double) -> Double { lb ? shown / 2.20462 : shown }
    var step: Double { lb ? 5 : 2.5 }
    var name: String { lb ? "lb" : "kg" }
    func text(_ kg: Double?) -> String {
        guard let kg, kg > 0 else { return "BW" }
        let v = show(kg)
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
