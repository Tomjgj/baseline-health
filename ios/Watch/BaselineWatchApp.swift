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
                CardioView(type: type, end: { Task { _ = await workout.end(); screen = .home } })
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

    private func discard() {
        if let lift { link.send(["kind": "discard", "id": lift.plan.id], mustArrive: true) }
        workout.discard()
        lift = nil
        screen = .home
    }
}
