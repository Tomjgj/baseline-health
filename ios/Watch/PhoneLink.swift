import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit
import os

let wlog = Logger(subsystem: "com.example.baseline", category: "watch")

/// The watch side of the link with the iPhone app. The phone sends a context (JSON under "json");
/// the watch sends workout events (start, set, add, remove, finish, discard) and water.
@MainActor
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var context: WatchContext?
    @Published private(set) var reachable = false
    /// Water tapped in on the watch that the phone's context doesn't include yet.
    @Published private(set) var waterAdded: Double = 0
    private var lastWaterTap = Date.distantPast
    private let saved = "baseline.context"

    override init() {
        super.init()
        // the last context, so the watch has something to show before the phone answers
        if let s = UserDefaults.standard.string(forKey: saved) { context = Self.decode(s) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var units: Units { Units(lb: context?.units == "lb") }

    private static func decode(_ json: String) -> WatchContext? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WatchContext.self, from: data)
    }

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["json"] as? String, let ctx = Self.decode(json) else { return }
        let before = context
        context = ctx
        UserDefaults.standard.set(json, forKey: saved)
        // taps the phone has counted come off the optimistic extra; a new day, or a quiet while, clears it
        if before?.day?.date != ctx.day?.date || Date().timeIntervalSince(lastWaterTap) > 10 {
            waterAdded = 0
        } else {
            let counted = (ctx.water?.ml ?? 0) - (before?.water?.ml ?? 0)
            if counted > 0 { waterAdded = max(0, waterAdded - counted) }
        }
        storeGlance()
    }

    // MARK: water

    /// Today's water as shown: the phone's total plus taps it hasn't counted yet.
    var water: (ml: Double, goal: Double, glass: Double)? {
        guard let w = context?.water else { return nil }
        return (w.ml + waterAdded, w.goal, w.glass ?? 250)
    }

    /// One glass, logged on the phone (queued if it's out of reach) and shown here straight away.
    func addGlass() {
        guard let w = water else { return }
        WKInterfaceDevice.current().play(.click)
        waterAdded += w.glass
        lastWaterTap = Date()
        send(["kind": "water", "ml": w.glass, "at": Date().timeIntervalSince1970 * 1000], mustArrive: true)
        storeGlance()
    }

    // MARK: complications

    /// What the complications show, kept in the App Group (none in the Lite project, so then nothing is stored).
    private func storeGlance() {
        guard let ctx = context else { return }
        // built field by field: one long initializer is slow for the type checker
        var g = Glance()
        g.v = 1
        g.at = ctx.at
        g.units = ctx.units == "lb" ? "imperial" : "metric"
        if let d = ctx.day {
            g.date = d.date
            g.recovery = d.recovery.map { Double($0) }
            g.band = d.band
            g.strain = d.strain
            g.strainLo = d.lo
            g.strainHi = d.hi
            g.sleep = d.sleep.map { Double($0) }
            g.asleep = d.asleep.map { Double($0) }
            g.hrv = d.hrv.map { Double($0) }
            g.rhr = d.rhr.map { Double($0) }
        }
        if let w = water { g.water = Glance.Water(ml: w.ml, goal: w.goal) }
        guard g != GlanceStore.load() else { return }
        if GlanceStore.save(g) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Sends a workout event. Start and finish must arrive, so when the phone isn't reachable they're queued
    /// (transferUserInfo); set-by-set updates only go when it is, since the finish carries every set anyway.
    func send(_ event: [String: Any], mustArrive: Bool = false) {
        guard WCSession.isSupported(), let data = try? JSONSerialization.data(withJSONObject: event), let json = String(data: data, encoding: .utf8) else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(["json": json], replyHandler: nil) { _ in if mustArrive { s.transferUserInfo(["json": json]) } }
        } else if mustArrive {
            s.transferUserInfo(["json": json])
        }
    }

    // MARK: WCSessionDelegate (called off the main thread)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext, r = session.isReachable
        Task { @MainActor in self.reachable = r; if !ctx.isEmpty { self.receive(ctx) } }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
