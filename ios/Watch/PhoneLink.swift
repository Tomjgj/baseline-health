import Foundation
import WatchConnectivity
import os

let wlog = Logger(subsystem: "com.example.baseline", category: "watch")

/// The watch side of the link with the iPhone app. The phone sends a context (JSON under "json");
/// the watch sends workout events: start, set, finish, discard.
@MainActor
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var context: WatchContext?
    @Published private(set) var reachable = false
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
        context = ctx
        UserDefaults.standard.set(json, forKey: saved)
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
