import Foundation
import WatchKit

/// A strength workout on the watch: which set is up, the weight and reps for it, the rest timer.
/// It mirrors the phone's workout logger: same exercises and sets, and every completed set goes to the phone.
@MainActor
final class Lift: ObservableObject {
    @Published var plan: Plan
    @Published var ei = 0                // exercise
    @Published var si = 0                // set
    @Published var weight: Double = 0    // in the person's unit
    @Published var reps: Double = 8
    @Published var restEnd: Date?
    @Published var restTotal: Double = 90
    let startedAt: Date
    let units: Units
    private weak var link: PhoneLink?

    init(plan: Plan, units: Units, link: PhoneLink, resumed: Bool) {
        self.plan = plan
        self.units = units
        self.link = link
        self.startedAt = plan.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        moveToNextOpen(from: 0, 0)
        if !resumed {
            link.send(["kind": "start", "id": plan.id, "name": plan.name, "routineId": plan.routineId ?? "",
                       "startedAt": startedAt.timeIntervalSince1970 * 1000, "exercises": Self.encode(plan.exercises)], mustArrive: true)
        }
    }

    static func encode(_ exs: [Ex]) -> [[String: Any]] {
        exs.map { ex in
            ["id": ex.id, "name": ex.name, "rest": ex.rest, "bw": ex.bw ?? false,
             "sets": ex.sets.map { s -> [String: Any] in ["t": s.t, "w": s.w ?? -1, "r": s.r ?? -1, "ph": s.ph ?? -1, "done": s.done] }]
        }
    }

    var exercise: Ex? { plan.exercises.indices.contains(ei) ? plan.exercises[ei] : nil }
    var set: WSet? { exercise.flatMap { $0.sets.indices.contains(si) ? $0.sets[si] : nil } }
    var finished: Bool { plan.exercises.allSatisfy { $0.sets.allSatisfy(\.done) } }
    var doneSets: Int { plan.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && $0.t != "W" }.count } }
    var totalSets: Int { plan.exercises.reduce(0) { $0 + $1.sets.filter { $0.t != "W" }.count } }
    /// "Set 2 of 3" counting working sets; warm-ups are named as such.
    var setLabel: String {
        guard let ex = exercise, let s = set else { return "" }
        if s.t == "W" { return "Warm-up" }
        let work = ex.sets.filter { $0.t != "W" }
        let n = ex.sets[0...si].filter { $0.t != "W" }.count
        return "Set \(n) of \(work.count)"
    }
    var volumeKg: Double {
        plan.exercises.reduce(0) { a, ex in a + ex.sets.filter { $0.done && $0.t != "W" }.reduce(0) { $0 + max(0, $1.w ?? 0) * Double($1.r ?? 0) } }
    }

    /// Point at a set and load its numbers: last time's weight from the plan, else the set above.
    func select(_ e: Int, _ s: Int) {
        ei = e; si = s
        guard let ex = exercise, let st = set else { return }
        let w = st.w ?? ex.sets[0..<s].last(where: { $0.w != nil })?.w ?? 0
        weight = units.show(max(0, w))
        reps = Double(st.r ?? st.ph ?? 8)
    }

    private func moveToNextOpen(from e: Int, _ s: Int) {
        for ex in e..<plan.exercises.count {
            let sets = plan.exercises[ex].sets
            for st in (ex == e ? s : 0)..<sets.count where !sets[st].done { select(ex, st); return }
        }
        // everything done: stay on the last set
        if let last = plan.exercises.indices.last { select(last, max(0, plan.exercises[last].sets.count - 1)) }
    }

    func complete() {
        guard exercise != nil, set != nil else { return }
        let kg = weight > 0 ? (units.kg(weight) * 100).rounded() / 100 : 0
        plan.exercises[ei].sets[si].w = kg
        plan.exercises[ei].sets[si].r = Int(reps)
        plan.exercises[ei].sets[si].done = true
        link?.send(["kind": "set", "id": plan.id, "ex": ei, "set": si, "w": kg, "r": Int(reps), "done": true])
        WKInterfaceDevice.current().play(.success)
        let rest = Double(plan.exercises[ei].rest)
        let (e, s) = (ei, si)
        moveToNextOpen(from: e, s + 1)
        if !finished && rest > 0 { startRest(rest) }
    }

    func startRest(_ seconds: Double) {
        restTotal = seconds
        restEnd = Date().addingTimeInterval(seconds)
    }
    func adjustRest(_ by: Double) {
        guard let end = restEnd else { return }
        restEnd = end.addingTimeInterval(by)
        restTotal = max(restTotal, restEnd!.timeIntervalSinceNow)
        if restEnd! <= Date() { restEnd = nil }
    }
    /// Called every second by the rest view; buzzes when the rest is up.
    func tickRest() {
        guard let end = restEnd, end <= Date() else { return }
        restEnd = nil
        WKInterfaceDevice.current().play(.notification)
    }

    /// The phone changed the same workout (a set ticked there): take its sets, keep our position if it's still open.
    func merge(_ phone: Plan) {
        guard phone.id == plan.id else { return }
        plan.exercises = phone.exercises
        if set?.done ?? true { moveToNextOpen(from: ei, si) }
    }

    func finishEvent(effort: Int, end: Date, hr: (avgHr: Int?, maxHr: Int?, kcal: Int?)) -> [String: Any] {
        var e: [String: Any] = ["kind": "finish", "id": plan.id, "name": plan.name, "routineId": plan.routineId ?? "",
                                "startedAt": startedAt.timeIntervalSince1970 * 1000, "endedAt": end.timeIntervalSince1970 * 1000,
                                "rpe": effort, "exercises": Self.encode(plan.exercises)]
        if let v = hr.avgHr { e["avgHr"] = v }
        if let v = hr.maxHr { e["maxHr"] = v }
        if let v = hr.kcal { e["kcal"] = v }
        return e
    }
}
