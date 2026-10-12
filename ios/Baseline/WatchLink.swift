import Foundation
import WatchConnectivity

/// The iPhone side of the link with the watch app. The page's context goes to the watch as JSON; workout events from
/// the watch go to the page. Events that arrive before the page is ready are kept (also across launches) and handed over
/// once it is.
final class WatchLink: NSObject, WCSessionDelegate {
    /// Hands a watch event (JSON) to the page. Set by the web controller.
    var deliver: ((String) -> Void)?
    private var pageReady = false
    private let key = "baseline.watchPending"
    private var pending: [String] { get { UserDefaults.standard.stringArray(forKey: key) ?? [] } set { UserDefaults.standard.set(newValue, forKey: key) } }

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// The page's latest context. Sent as application context (the watch always gets the newest one) and, when the
    /// watch app is open, as a message too so it updates straight away.
    func send(context json: String) {
        markReady()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(["json": json])
        if s.isReachable { s.sendMessage(["json": json], replyHandler: nil, errorHandler: nil) }
    }

    private func markReady() {
        guard !pageReady else { return }
        pageReady = true
        let queued = pending
        pending = []
        queued.forEach { deliver?($0) }
    }

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["json"] as? String else { return }
        DispatchQueue.main.async {
            if self.pageReady, let deliver = self.deliver { deliver(json) } else { self.pending.append(json) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
}
