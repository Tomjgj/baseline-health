import SwiftUI
import HealthKit

@main
struct BaselineWatchApp: App {
    @StateObject private var link = PhoneLink()
    @StateObject private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(link)
                .environmentObject(workout)
                .tint(Theme.good)
        }
    }
}

/// What's on screen: home, a strength workout, a cardio workout, or the summary after one.
enum Screen: Equatable {
    case home
    case lift
    case cardio(HKWorkoutActivityType)
    case summary
}

struct RootView: View {
    @EnvironmentObject var link: PhoneLink
    @EnvironmentObject var workout: WorkoutManager
    @State private var screen: Screen = .home
    @State private var lift: Lift?

    var body: some View {
        Group {
            switch screen {
            case .home:
                HomeView(startLift: startLift, startCardio: { type in
                    Task { await workout.start(type, outdoor: type != .traditionalStrengthTraining && type != .other) }
                    screen = .cardio(type)
                })
            case .lift:
                if let lift { LiftView(lift: lift, finish: { screen = .summary }, discard: discard) } else { ProgressView() }
            case .cardio(let type):
                CardioView(type: type, end: { Task { await endCardio(type) } })
            case .summary:
                if let lift { SummaryView(lift: lift, done: { self.lift = nil; screen = .home }) }
            }
        }
        // a workout the phone finished or discarded ends here too
        .onChange(of: link.context?.draft) { _, draft in
            guard screen == .lift, let lift else { return }
            if let draft { lift.merge(draft) }
        }
    }

    private func startLift(_ plan: Plan, resumed: Bool) {
        lift = Lift(plan: plan, units: link.units, link: link, resumed: resumed)
        Task { await workout.start(.traditionalStrengthTraining) }
        screen = .lift
    }

    /// Ends a cardio session and tells the phone, which logs it (and, with saving on, finds the same workout in Health and merges them).
    private func endCardio(_ type: HKWorkoutActivityType) async {
        let started = workout.startDate ?? Date(), meters = workout.meters
        let r = await workout.end()
        let name: String = switch type { case .running: "Running"; case .walking: "Walking"; case .cycling: "Cycling"; default: "Workout" }
        var event: [String: Any] = ["kind": "cardio", "id": "wc" + UUID().uuidString.prefix(8).lowercased(), "type": name,
                                    "startedAt": started.timeIntervalSince1970 * 1000, "endedAt": Date().timeIntervalSince1970 * 1000]
        if meters > 0 { event["km"] = meters / 1000 }
        if let v = r.avgHr { event["avgHr"] = v }
        if let v = r.maxHr { event["maxHr"] = v }
        if let v = r.kcal { event["kcal"] = v }
        link.send(event, mustArrive: true)
        screen = .home
    }

    private func discard() {
        if let lift { link.send(["kind": "discard", "id": lift.plan.id], mustArrive: true) }
        workout.discard()
        lift = nil
        screen = .home
    }
}
