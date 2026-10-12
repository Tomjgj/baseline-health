import ActivityKit
import SwiftUI
import WidgetKit

/// A strength workout on the lock screen and in the Dynamic Island: the time (or the rest left), the exercise and set,
/// and how many sets are done. The app starts, updates and ends it as the page logs sets (`{ type: "live" }`).
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            LockScreenView(name: context.attributes.name, startedAt: context.attributes.startedAt, state: context.state)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    } icon: {
                        Image(systemName: Workout.symbol).foregroundStyle(Palette.strain)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Workout.clock(context.state, from: context.attributes.startedAt)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 72, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SetSummary(state: context.state)
                }
            } compactLeading: {
                Image(systemName: Workout.symbol).foregroundStyle(Palette.strain)
            } compactTrailing: {
                Workout.clock(context.state, from: context.attributes.startedAt)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(width: 48)
            } minimal: {
                Image(systemName: Workout.symbol).foregroundStyle(Palette.strain)
            }
            .keylineTint(Palette.strain)
        }
    }
}

enum Workout {
    static let symbol = "figure.strengthtraining.traditional"

    /// Rest left while the rest timer runs, otherwise the time since the start. Both tick on their own.
    @ViewBuilder
    static func clock(_ state: WorkoutAttributes.ContentState, from start: Date) -> some View {
        let now = Date()
        if let end = state.restEnd, end > now {
            Text(timerInterval: now...end, countsDown: true)
                .monospacedDigit().multilineTextAlignment(.trailing).foregroundStyle(Palette.strain)
        } else {
            Text(timerInterval: min(start, now)...Date.distantFuture, countsDown: false)
                .monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}

private struct SetSummary: View {
    let state: WorkoutAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.exercise).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(state.detail).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(state.done) of \(state.total) sets").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(state.done, max(state.total, 1))), total: Double(max(state.total, 1)))
                .tint(Palette.strain)
        }
    }
}

private struct LockScreenView: View {
    let name: String
    let startedAt: Date
    let state: WorkoutAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: Workout.symbol).foregroundStyle(Palette.strain)
                Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if let end = state.restEnd, end > Date() {
                    Text("Rest").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Workout.clock(state, from: startedAt)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 84, alignment: .trailing)
            }
            SetSummary(state: state)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}
