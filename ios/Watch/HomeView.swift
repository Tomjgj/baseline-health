import SwiftUI
import HealthKit

/// Two pages, like the phone's Today and Train: the day's scores, then what to train.
struct HomeView: View {
    @EnvironmentObject var link: PhoneLink
    var startLift: (Plan, Bool) -> Void
    var startCardio: (HKWorkoutActivityType) -> Void

    var body: some View {
        TabView {
            TodayPage()
            TrainPage(startLift: startLift, startCardio: startCardio)
        }
        .tabViewStyle(.verticalPage)
        .onAppear { wlog.notice("watch: home rendered") }
    }
}

struct TodayPage: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                scores
                if let w = link.water { water(w) }
            }
        }
        .navigationTitle("Today")
    }

    private var scores: some View {
        let day = link.context?.day
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                score(value: Double(day?.recovery ?? 0) / 100, color: Theme.band(day?.band),
                      text: day?.recovery.map { "\($0)%" } ?? "–", label: "Recovery")
                score(value: (day?.strain ?? 0) / 21, color: Theme.strain, target: strainTarget(day),
                      text: day?.strain.map { String(format: "%.1f", $0) } ?? "–", label: "Strain")
                score(value: Double(day?.sleep ?? 0) / 100, color: Theme.sleep,
                      text: day?.sleep.map(String.init) ?? "–", label: "Sleep")
            }
            if let d = day {
                HStack(spacing: 10) {
                    if let hrv = d.hrv { stat("\(hrv)", "ms HRV", Theme.hrv) }
                    if let rhr = d.rhr { stat("\(rhr)", "bpm rest", Theme.heart) }
                }
                if let lo = d.lo, let hi = d.hi {
                    Text("Strain target \(Int(lo))–\(Int(hi))").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Open Baseline on your iPhone to bring today’s scores here.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Today's water against the goal, and a button that logs one glass on the phone.
    private func water(_ w: (ml: Double, goal: Double, glass: Double)) -> some View {
        Card {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").font(.system(size: 13)).foregroundStyle(Theme.water)
                Text(Glance.waterText(ml: w.ml, goal: w.goal, imperial: link.units.lb))
                    .font(Theme.number(15, .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            ProgressView(value: min(w.ml, max(w.goal, 1)), total: max(w.goal, 1)).tint(Theme.water)
            Button { link.addGlass() } label: {
                Text("+ Glass").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .tint(Theme.water)
        }
    }

    private func strainTarget(_ d: WatchContext.Day?) -> ClosedRange<Double>? {
        guard let lo = d?.lo, let hi = d?.hi, hi >= lo else { return nil }
        return (lo / 21)...(hi / 21)
    }

    private func score(value: Double, color: Color, target: ClosedRange<Double>? = nil, text: String, label: String) -> some View {
        VStack(spacing: 4) {
            Ring(value: value, color: color, lineWidth: 5, target: target) {
                Text(text).font(Theme.number(text.count > 3 ? 13 : 15)).minimumScaleFactor(0.7)
            }
            .frame(width: 50, height: 50)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ v: String, _ k: String, _ c: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(v).font(Theme.number(17)).foregroundStyle(c)
            Text(k).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct TrainPage: View {
    @EnvironmentObject var link: PhoneLink
    var startLift: (Plan, Bool) -> Void
    var startCardio: (HKWorkoutActivityType) -> Void

    var body: some View {
        let ctx = link.context
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let draft = ctx?.draft {
                    planCard(draft, label: "In progress on iPhone", action: "Continue", resumed: true)
                } else if let next = ctx?.next {
                    planCard(next, label: next.why ?? "Suggested", action: "Start", resumed: false)
                }
                if let tired = ctx?.tired, !tired.isEmpty {
                    Text("Still recovering: \(tired.prefix(3).joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                let others = (ctx?.routines ?? []).filter { $0.routineId != ctx?.next?.routineId }
                if ctx?.draft == nil, !others.isEmpty {
                    Text("Routines").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(others) { p in
                        Button { startLift(fresh(p), false) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 15, weight: .medium))
                                Text("\(p.exercises.count) exercises\(p.minutes.map { " · \($0) min" } ?? "")").font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Cardio").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    cardio("Run", "figure.run", .running)
                    cardio("Walk", "figure.walk", .walking)
                    cardio("Ride", "figure.outdoor.cycle", .cycling)
                    cardio("Other", "heart", .other)
                }
            }
        }
        .navigationTitle("Train")
    }

    /// A routine from the list starts as a new workout with its own id.
    private func fresh(_ p: Plan) -> Plan {
        var x = p
        x.id = "w" + UUID().uuidString.prefix(8).lowercased()
        x.startedAt = nil
        return x
    }

    private func planCard(_ p: Plan, label: String, action: String, resumed: Bool) -> some View {
        Card {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.good)
            Text(p.name).font(.system(size: 18, weight: .semibold))
            Text(p.exercises.prefix(3).map(\.name).joined(separator: ", ") + (p.exercises.count > 3 ? " +\(p.exercises.count - 3)" : ""))
                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            Button(action) { startLift(resumed ? p : fresh(p), resumed) }
                .buttonStyle(.borderedProminent).tint(Theme.good).padding(.top, 4)
        }
    }

    private func cardio(_ name: String, _ symbol: String, _ type: HKWorkoutActivityType) -> some View {
        Button { startCardio(type) } label: {
            VStack(spacing: 2) { Image(systemName: symbol).font(.system(size: 18)); Text(name).font(.system(size: 13, weight: .medium)) }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tint(Theme.strain)
    }
}
