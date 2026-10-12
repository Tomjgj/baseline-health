import SwiftUI
import WebKit
import WidgetKit
import os

let log = Logger(subsystem: "com.example.baseline", category: "app")

/// Hosts index.html. The page is served from baseline://app/ (a fixed origin, so its localStorage persists),
/// and talks to the native side through the "baseline" message handler.
final class WebController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let health = HealthReader.shared
    private let scanner = BarcodeScanner()
    private let watch = WatchLink()
    private let coach = Coach()
    /// The page has loaded, so it can be told about new Health data.
    private var loaded = false

    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "baseline")
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "baseline")
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 7 / 255, green: 8 / 255, blue: 11 / 255, alpha: 1)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        watch.deliver = { [weak self] json in
            self?.webView.callAsyncJavaScript("window.BaselineBridge && window.BaselineBridge.fromWatch && window.BaselineBridge.fromWatch(JSON.parse(json))", arguments: ["json": json], in: nil, in: .page, completionHandler: nil)
        }
        health.onNewReadings = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.loaded else { return }
                self.webView.evaluateJavaScript("window.BaselineBridge && window.BaselineBridge.changed && window.BaselineBridge.changed()", completionHandler: nil)
            }
        }
        coach.emit = { [weak self] id, ev in
            self?.webView.callAsyncJavaScript("window.BaselineBridge && window.BaselineBridge.coach && window.BaselineBridge.coach(id, ev)", arguments: ["id": id, "ev": ev], in: nil, in: .page, completionHandler: nil)
        }
        if let url = URL(string: "baseline://app/index.html") { webView.load(URLRequest(url: url)) }
    }

    // MARK: page loading, logged so a build check can tell the page really rendered

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        // the app draws its first screen a moment after load
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            webView.evaluateJavaScript("document.title + ' | ' + (document.querySelector('#view .view') ? 'rendered' : 'empty')") { result, _ in
                log.notice("page: \(String(describing: result ?? "no result"), privacy: .public)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("page failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("page failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func foreground() {
        webView.evaluateJavaScript("window.BaselineBridge && window.BaselineBridge.foreground()", completionHandler: nil)
    }

    /// The page asks, and the app answers by calling BaselineBridge.receive({ id, ok, payload | error }):
    ///   { type: "sync", id, from: "YYYY-MM-DD", to: "YYYY-MM-DD" }  → a baseline.health/1 payload
    ///   { type: "scan", id }                                        → { code } from the camera
    ///   { type: "food", id, path }                                  → { text } from Open Food Facts (path starts with /)
    ///   { type: "notify", id, key, at: ms since 1970, title, body } and { type: "unnotify", id, key } → local reminders
    ///   { type: "watch", id, json }                                 → the context for the watch app (WatchLink)
    ///   { type: "share", id, filename, text }                       → the share sheet with that file
    ///   { type: "latest", id }                                      → { at, hr: [[time, bpm]], hrv: [[time, ms]] }, the last few hours
    ///   { type: "water", id, ml, at: "YYYY-MM-DDTHH:MM" }           → saved to Health as dietary water, tagged with id; { saved }
    ///   { type: "unwater", id }                                     → deletes the sample saved with that id; { saved }
    ///     (both tag with `key` instead of `id` when the page sends one)
    ///   { type: "widget", id, json }                                → today's glance for the widgets (Glance in ios/Shared)
    ///   { type: "live", id, action: "start" | "update" | "end", json } → the workout Live Activity; error "unavailable" without one
    ///   { type: "prefs", id, json: { morning, waterNudges } }       → kept for the morning notification
    ///   { type: "coachKey", id, action: "status" | "prompt" | "clear" } → { set }; the key itself never reaches the page
    ///   { type: "coachCancel", id }                                 → stops the coach reply with that id
    ///   { type: "haptic", id, kind: "light" | "medium" | "success" } → a tap from the Taptic Engine, no answer
    ///   { type: "coach", id, messages }                             → no answer here: the reply streams through
    ///     BaselineBridge.coach(id, { t: "text", v } … then { t: "done", message } or { t: "error", code, message }) (Coach)
    /// Requests that only hand something over get an ok reply too, except haptic and coach.
    /// The app tells the page about new Health data (watch readings, sleep, workouts, water) by calling BaselineBridge.changed().
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
        switch body["type"] as? String {
        case "scan":
            log.notice("scan request")
            scanner.scan(from: webView) { outcome in
                switch outcome {
                case .code(let code): self.reply(["id": id, "ok": true, "payload": ["code": code]])
                case .cancelled: self.reply(["id": id, "ok": false, "error": "cancelled"])
                case .denied: self.reply(["id": id, "ok": false, "error": "camera_denied"])
                case .unavailable: self.reply(["id": id, "ok": false, "error": "scan_unavailable"])
                }
            }
            return
        case "food":
            fetchFood(id: id, path: body["path"] as? String ?? "")
            return
        case "notify":
            if let key = body["key"] as? String, let at = body["at"] as? Double {
                Notifier.schedule(key: key, at: Date(timeIntervalSince1970: at / 1000), title: body["title"] as? String ?? "Baseline", body: body["body"] as? String ?? "")
            }
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "unnotify":
            if let key = body["key"] as? String { Notifier.cancel(key: key) }
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "watch":
            if let json = body["json"] as? String { watch.send(context: json) }
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "share":
            share(id: id, filename: body["filename"] as? String ?? "baseline-export.json", text: body["text"] as? String ?? "")
            return
        case "haptic":
            // fire and forget: the page doesn't wait for an answer
            switch body["kind"] as? String {
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            return
        case "water":
            let key = body["key"] as? String ?? id
            let ml = body["ml"] as? Double ?? 0
            let at = (body["at"] as? String).flatMap(Self.localTime) ?? Date()
            Task {
                let saved = await health.saveWater(key: key, ml: ml, at: at)
                await MainActor.run { self.reply(["id": id, "ok": true, "payload": ["saved": saved]]) }
            }
            return
        case "unwater":
            let key = body["key"] as? String ?? id
            Task {
                let saved = await health.deleteWater(key: key)
                await MainActor.run { self.reply(["id": id, "ok": true, "payload": ["saved": saved]]) }
            }
            return
        case "widget":
            if let json = body["json"] as? String, GlanceStore.save(json: json) { WidgetCenter.shared.reloadAllTimelines() }
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "live":
            let action = body["action"] as? String ?? "", json = body["json"] as? String
            Task { @MainActor in
                if let code = await LiveWorkout.run(action: action, json: json) {
                    self.reply(["id": id, "ok": false, "error": code])
                } else {
                    self.reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
                }
            }
            return
        case "prefs":
            if let json = body["json"] as? String { Prefs.save(json: json) }
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "coach":
            coach.start(id: id, messages: body["messages"])
            return
        case "coachCancel":
            coach.cancel(id: id)
            reply(["id": id, "ok": true, "payload": [:] as [String: Any]])
            return
        case "coachKey":
            switch body["action"] as? String {
            case "prompt":
                coach.promptForKey(from: webView) { set in self.reply(["id": id, "ok": true, "payload": ["set": set]]) }
            case "clear":
                CoachKey.delete()
                reply(["id": id, "ok": true, "payload": ["set": false]])
            default:
                reply(["id": id, "ok": true, "payload": ["set": CoachKey.read() != nil]])
            }
            return
        case "latest":
            Task {
                do {
                    let payload = try await health.latest()
                    await MainActor.run { self.reply(["id": id, "ok": true, "payload": payload]) }
                } catch let error as HealthReader.Failure {
                    await MainActor.run { self.reply(["id": id, "ok": false, "error": error.code]) }
                } catch {
                    await MainActor.run { self.reply(["id": id, "ok": false, "error": "sync-failed"]) }
                }
            }
            return
        default:
            break
        }
        guard (body["type"] as? String) == "sync", let from = body["from"] as? String, let to = body["to"] as? String else {
            reply(["id": id, "ok": false, "error": "unknown_request"])
            return
        }
        log.notice("sync request \(from, privacy: .public) to \(to, privacy: .public)")
        Task {
            do {
                let payload = try await health.payload(from: from, to: to)
                await MainActor.run { self.reply(["id": id, "ok": true, "payload": payload]) }
            } catch let error as HealthReader.Failure {
                await MainActor.run { self.reply(["id": id, "ok": false, "error": error.code]) }
            } catch {
                await MainActor.run { self.reply(["id": id, "ok": false, "error": "sync-failed"]) }
            }
        }
    }

    /// Hands a file to the share sheet (Save to Files, AirDrop, Mail…). Replies once the sheet closes.
    private func share(id: String, filename: String, text: String) {
        let safe = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "baseline-export.json" : safe)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil, var top = webView.window?.rootViewController else {
            reply(["id": id, "ok": false, "error": "share_failed"])
            return
        }
        while let p = top.presentedViewController { top = p }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = webView
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            self.reply(completed ? ["id": id, "ok": true, "payload": ["saved": true]] : ["id": id, "ok": false, "error": "cancelled"])
        }
        top.present(sheet, animated: true)
    }

    /// Food lookups go through the app rather than the page, so they don't depend on the web view's cross-origin rules.
    /// Only Open Food Facts is reachable this way.
    private func fetchFood(id: String, path: String) {
        guard path.hasPrefix("/"), let url = URL(string: "https://world.openfoodfacts.org" + path) else {
            reply(["id": id, "ok": false, "error": "bad_request"])
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Baseline/1.0 (iPhone; personal use)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async {
                if let text, error == nil, status == 200 || status == 404 {
                    self.reply(["id": id, "ok": true, "payload": ["status": status, "text": text]])
                } else {
                    self.reply(["id": id, "ok": false, "error": "offline"])
                }
            }
        }.resume()
    }

    /// The page's local wall-clock times, "YYYY-MM-DDTHH:MM" (seconds optional).
    private static func localTime(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = text.count > 16 ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd'T'HH:mm"
        return f.date(from: String(text.prefix(19)))
    }

    private func reply(_ message: [String: Any]) {
        // callAsyncJavaScript passes the dictionary as a real JS object, so nothing needs escaping
        webView.callAsyncJavaScript("window.BaselineBridge && window.BaselineBridge.receive(msg)", arguments: ["msg": message], in: nil, in: .page, completionHandler: nil)
    }
}

struct WebView: UIViewRepresentable {
    let controller: WebController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Serves files from the app bundle under baseline://app/.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let name = url.path.isEmpty || url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let ext = (name as NSString).pathExtension
        guard let file = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: ext),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = ext == "html" ? "text/html" : ext == "js" ? "text/javascript" : ext == "css" ? "text/css" : "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
