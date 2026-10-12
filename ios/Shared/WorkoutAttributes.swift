import ActivityKit
import Foundation

/// The workout Live Activity: the routine's name and start time stay fixed; the exercise, the set and the rest timer change.
/// Compiled into both the app (which starts and updates it) and the widget extension (which draws it).
struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var detail: String        // "Set 2 of 3 · 80 kg × 8"
        var done: Int             // working sets done
        var total: Int
        var restEnd: Date?        // when the rest timer is up, if it runs
    }

    var name: String
    var startedAt: Date
}
