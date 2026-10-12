import SwiftUI
import HealthKit

/// A strength workout: swipe for the controls (left), the set (middle) and the exercise list (right), like Apple's Workout app.
struct LiftView: View {
    @ObservedObject var lift: Lift
    @EnvironmentObject var workout: WorkoutManager
    var finish: () -> Void
    var discard: () -> Void
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            ControlsPage(lift: lift, finish: finish, discard: discard).tag(0)
            Group {
                if lift.restEnd != nil { RestPage(lift: lift) } else { SetPage(lift: lift, finish: finish) }
            }.tag(1)
            ExercisesPage(lift: lift, pick: { e, s in lift.select(e, s); lift.restEnd = nil; page = 1 }).tag(2)
        }
        .tabViewStyle(.page)
        .navigationBarBackButtonHidden(true)
    }
}

/// Elapsed time and heart rate, on every workout page.
struct LiveHeader: View {
    @EnvironmentObject var workout: WorkoutManager
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack {
                Text(elapsed(ctx.date)).font(Theme.number(15, .medium)).foregroundStyle(Theme.warn).monospacedDigit()
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill").font(.system(size: 11))
                    Text(workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "–").font(Theme.number(15, .medium)).monospacedDigit()
                }.foregroundStyle(Theme.heart)
            }
        }
    }
    private func elapsed(_ now: Date) -> String {
        guard let s = workout.startDate else { return "0:00" }
        let t = Int(now.timeIntervalSince(s)), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

struct SetPage: View {
    @ObservedObject var lift: Lift
    var finish: () -> Void
    enum Field { case weight, reps }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LiveHeader()
            if lift.finished {
                Spacer()
                Text("All sets done").font(.system(size: 17, weight: .semibold))
                Button("Finish workout", action: finish).buttonStyle(.borderedProminent).tint(Theme.good)
            } else if let ex = lift.exercise {
                Text(ex.name).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(lift.setLabel).font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    field(ex.bw == true && lift.weight == 0 ? "BW" : format(lift.weight), unit: lift.units.name, .weight)
                        .digitalCrownRotation($lift.weight, from: 0, through: 500, by: lift.units.step, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    Text("×").foregroundStyle(.secondary)
                    field("\(Int(lift.reps))", unit: "reps", .reps)
                        .digitalCrownRotation($lift.reps, from: 0, through: 50, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                }
                Spacer(minLength: 2)
                Button { lift.complete() } label: { Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.good)
            }
        }
        .onAppear { focus = .reps }
    }

    private func field(_ text: String, unit: String, _ f: Field) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text).font(Theme.number(30)).monospacedDigit()
            Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 8).stroke(focus == f ? Theme.good : .clear, lineWidth: 2))
        .focusable(true)
        .focused($focus, equals: f)
        .onTapGesture { focus = f }
    }

    private func format(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }
}

struct RestPage: View {
    @ObservedObject var lift: Lift

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, lift.restEnd?.timeIntervalSince(ctx.date) ?? 0)
            VStack(spacing: 6) {
                LiveHeader()
                Ring(value: lift.restTotal > 0 ? left / lift.restTotal : 0, color: Theme.strain, lineWidth: 7) {
                    VStack(spacing: 0) {
                        Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)).font(Theme.number(26)).monospacedDigit()
                        Text("rest").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                if let ex = lift.exercise { Text("Next: \(ex.name)").font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                HStack {
                    Button("−15") { lift.adjustRest(-15) }
                    Button("Skip") { lift.restEnd = nil }.tint(Theme.strain)
                    Button("+15") { lift.adjustRest(15) }
                }
                .font(.system(size: 14, weight: .medium))
            }
            .onChange(of: Int(left)) { _, _ in lift.tickRest() }
        }
    }
}

struct ExercisesPage: View {
    @ObservedObject var lift: Lift
    var pick: (Int, Int) -> Void

    var body: some View {
        List {
            ForEach(Array(lift.plan.exercises.enumerated()), id: \.element.id) { i, ex in
                Button {
                    pick(i, ex.sets.firstIndex(where: { !$0.done }) ?? max(0, ex.sets.count - 1))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.name).font(.system(size: 15, weight: i == lift.ei ? .semibold : .regular)).lineLimit(1)
                            let done = ex.sets.filter { $0.done && $0.t != "W" }.count, all = ex.sets.filter { $0.t != "W" }.count
                            Text("\(done) of \(all) sets").font(.footnote).foregroundStyle(done == all ? Theme.good : .secondary)
                        }
                        Spacer()
                        if ex.sets.allSatisfy(\.done) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good) }
                    }
                }
            }
        }
        .navigationTitle("Exercises")
    }
}

struct ControlsPage: View {
    @ObservedObject var lift: Lift
    @EnvironmentObject var workout: WorkoutManager
    var finish: () -> Void
    var discard: () -> Void
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 8) {
            Text(lift.plan.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text("\(lift.doneSets) of \(lift.totalSets) sets").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                control(workout.paused ? "Resume" : "Pause", workout.paused ? "play.fill" : "pause.fill", Theme.warn) { workout.togglePause() }
                control("End", "xmark", Theme.crit) { lift.doneSets > 0 ? finish() : (confirmDiscard = true) }
            }
        }
        .confirmationDialog("No sets logged yet", isPresented: $confirmDiscard) {
            Button("Discard workout", role: .destructive, action: discard)
            Button("Keep going", role: .cancel) {}
        }
    }

    private func control(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) { Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44) }
                .tint(color)
            Text(title).font(.footnote)
        }
    }
}

/// After a strength workout: the numbers, how hard it felt, then save (to Baseline on the phone and to Health).
struct SummaryView: View {
    @ObservedObject var lift: Lift
    @EnvironmentObject var workout: WorkoutManager
    @EnvironmentObject var link: PhoneLink
    var done: () -> Void
    @State private var effort: Double = 7
    @State private var saving = false
    @State private var end = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout complete").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.good)
                Text(lift.plan.name).font(.system(size: 18, weight: .semibold))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { stat(duration, "time"); stat("\(lift.doneSets)", "sets") }
                    GridRow {
                        stat("\(Int((lift.units.show(lift.volumeKg)).rounded()))", "\(lift.units.name) volume")
                        stat(workout.avgHeartRate > 0 ? "\(Int(workout.avgHeartRate))" : "–", "avg bpm", Theme.heart)
                    }
                }
                Text("How hard was it?").font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                HStack {
                    Text("\(Int(effort))").font(Theme.number(30)).monospacedDigit()
                    Text(effortWord).font(.footnote).foregroundStyle(.secondary)
                }
                .focusable(true)
                .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                Button { save() } label: { Text(saving ? "Saving…" : "Save").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.good).disabled(saving)
            }
        }
    }

    private var duration: String { let m = Int(end.timeIntervalSince(lift.startedAt) / 60); return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min" }
    private var effortWord: String { effort <= 3 ? "easy" : effort <= 6 ? "moderate" : effort <= 8 ? "hard" : "all-out" }

    private func stat(_ v: String, _ k: String, _ c: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Theme.number(20)).foregroundStyle(c).monospacedDigit()
            Text(k).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func save() {
        saving = true
        Task {
            let hr = await workout.end()
            link.send(lift.finishEvent(effort: Int(effort), end: end, hr: hr), mustArrive: true)
            done()
        }
    }
}

/// A cardio workout: time, heart rate, energy and distance, saved to Health; the phone picks it up on its next sync.
struct CardioView: View {
    let type: HKWorkoutActivityTypeName
    @EnvironmentObject var workout: WorkoutManager
    var end: () -> Void

    init(type: HKWorkoutActivityType, end: @escaping () -> Void) { self.type = HKWorkoutActivityTypeName(type); self.end = end }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiveHeader()
            Text(type.name).font(.system(size: 16, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(workout.kcal))").font(Theme.number(30)).monospacedDigit()
                Text("kcal").font(.footnote).foregroundStyle(.secondary)
            }
            if workout.meters > 0 {
                Text(String(format: "%.2f km", workout.meters / 1000)).font(Theme.number(20)).foregroundStyle(Theme.strain)
            }
            Spacer(minLength: 2)
            HStack {
                Button { workout.togglePause() } label: { Image(systemName: workout.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity) }.tint(Theme.warn)
                Button(action: end) { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(Theme.crit)
            }
        }
    }
}

struct HKWorkoutActivityTypeName {
    let name: String
    init(_ t: HKWorkoutActivityType) {
        switch t { case .running: name = "Run"; case .walking: name = "Walk"; case .cycling: name = "Ride"; default: name = "Workout" }
    }
}
