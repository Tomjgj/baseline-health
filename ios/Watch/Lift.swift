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
    /// When an exercise was last added or removed here; a context the phone built before it knew is not merged.
    private var lastEdit = Date.distantPast

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
        var out: [[String: Any]] = []
        for ex in exs {
            var sets: [[String: Any]] = []
            for s in ex.sets {
                let w: Double = s.w ?? -1, r: Int = s.r ?? -1, ph: Int = s.ph ?? -1
                sets.append(["t": s.t, "w": w, "r": r, "ph": ph, "done": s.done])
            }
            let bw: Bool = ex.bw ?? false
            out.append(["id": ex.id, "name": ex.name, "rest": ex.rest, "bw": bw, "sets": sets])
        }
        return out
    }

    var exercise: Ex? { plan.exercises.indices.contains(ei) ? plan.exercises[ei] : nil }
    var set: WSet? { exercise.flatMap { $0.sets.indices.contains(si) ? $0.sets[si] : nil } }
    var finished: Bool { plan.exercises.allSatisfy { $0.sets.allSatisfy(\.done) } }
    var doneSets: Int {
        var n = 0
        for ex in plan.exercises { n += ex.sets.filter { $0.done && $0.t != "W" }.count }
        return n
    }
    var totalSets: Int {
        var n = 0
        for ex in plan.exercises { n += ex.sets.filter { $0.t != "W" }.count }
        return n
    }
    /// "Set 2 of 3" counting working sets; warm-ups are named as such.
    var setLabel: String {
        guard let ex = exercise, let s = set else { return "" }
        if s.t == "W" { return "Warm-up" }
        let work = ex.sets.filter { $0.t != "W" }
        let n = ex.sets[0...si].filter { $0.t != "W" }.count
        return "Set \(n) of \(work.count)"
    }
    var volumeKg: Double {
        var total = 0.0
        for ex in plan.exercises {
            for s in ex.sets where s.done && s.t != "W" {
                let w: Double = max(0, s.w ?? 0)
                total += w * Double(s.r ?? 0)
            }
        }
        return total
    }

    /// Point at a set and load its numbers: last time's weight from the plan, else the set above.
    func select(_ e: Int, _ s: Int) {
        ei = e; si = s
        guard let ex = exercise, let st = set else { return }
        let above: Double? = ex.sets[0..<s].last(where: { $0.w != nil })?.w
        let w: Double = st.w ?? above ?? 0
        weight = units.show(max(0, w))
        reps = Double(st.r ?? st.ph ?? 8)
    }

    private func moveToNextOpen(from e: Int, _ s: Int) {
        for ex in min(e, plan.exercises.count)..<plan.exercises.count {
            let sets = plan.exercises[ex].sets
            for st in (ex == e ? min(s, sets.count) : 0)..<sets.count where !sets[st].done { select(ex, st); return }
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
        if phone.exercises.count != plan.exercises.count && Date().timeIntervalSince(lastEdit) < 8 { return }
        plan.exercises = phone.exercises
        if set?.done ?? true { moveToNextOpen(from: ei, si) }
    }

    /// Adds an exercise from the library at the end, with its sets open, and tells the phone.
    func add(_ library: Ex) {
        var ex = library
        for i in ex.sets.indices { ex.sets[i].done = false }
        if ex.sets.isEmpty { ex.sets = [WSet(t: "N", w: nil, r: nil, ph: nil, done: false)] }
        let wasFinished = finished
        plan.exercises.append(ex)
        lastEdit = Date()
        link?.send(["kind": "add", "id": plan.id, "exercise": Self.encode([ex])[0]], mustArrive: true)
        if wasFinished { select(plan.exercises.count - 1, 0) }
    }

    /// Removes an exercise (index before removal) and tells the phone. The last one stays: a workout needs something in it.
    func remove(_ i: Int) {
        guard plan.exercises.indices.contains(i), plan.exercises.count > 1 else { return }
        plan.exercises.remove(at: i)
        lastEdit = Date()
        link?.send(["kind": "remove", "id": plan.id, "ex": i], mustArrive: true)
        if i < ei {
            ei -= 1
        } else if i == ei {
            moveToNextOpen(from: min(i, plan.exercises.count - 1), 0)
        }
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
