import ActivityKit
import Foundation

/// Starts, updates and ends the workout Live Activity for the page (`{ type: "live", action, json }`). The views live in the
/// widget extension; the Lite project (for free Apple IDs) has none, so there the Live Activity is unavailable.
enum LiveWorkout {
    /// What the page sends: the workout's name and start (ms since 1970), the exercise and set, and the rest timer's end.
    private struct Payload: Decodable {
        var name: String?
        var startedAt: Double?
        var exercise: String?
        var detail: String?
        var done: Int?
        var total: Int?
        var restEnd: Double?
    }

    static var available: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              FileManager.default.fileExists(atPath: plugins.appendingPathComponent("BaselineWidgets.appex").path) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Returns nil when it worked, else the error code for the page.
    @MainActor
    static func run(action: String, json: String?) async -> String? {
        let running = Activity<WorkoutAttributes>.activities
        if action == "end" {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return nil
        }
        guard action == "start" || action == "update" else { return "bad_request" }
        guard available else { return "unavailable" }
        guard let data = json?.data(using: .utf8), let p = try? JSONDecoder().decode(Payload.self, from: data) else { return "bad_request" }
        let state = WorkoutAttributes.ContentState(exercise: p.exercise ?? "", detail: p.detail ?? "", done: p.done ?? 0, total: p.total ?? 0,
                                                   restEnd: p.restEnd.map { Date(timeIntervalSince1970: $0 / 1000) })
        let content = ActivityContent(state: state, staleDate: nil)
        if action == "update", let current = running.first {
            await current.update(content)
            return nil
        }
        // one workout at a time: a new start replaces whatever is still showing
        for a in running { await a.end(nil, dismissalPolicy: .immediate) }
        let attributes = WorkoutAttributes(name: p.name ?? "Workout", startedAt: p.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date())
        do {
            _ = try Activity<WorkoutAttributes>.request(attributes: attributes, content: content, pushType: nil)
            return nil
        } catch {
            log.error("live activity not started: \(error.localizedDescription, privacy: .public)")
            return "failed"
        }
    }
}
