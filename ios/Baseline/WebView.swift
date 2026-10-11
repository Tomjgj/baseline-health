import SwiftUI
import WebKit
import os

let log = Logger(subsystem: "com.example.baseline", category: "app")

/// Hosts index.html. The page is served from baseline://app/ (a fixed origin, so its localStorage persists),
/// and talks to the native side through the "baseline" message handler.
final class WebController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let health = HealthReader()
    private let scanner = BarcodeScanner()

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
        health.onNewReadings = { [weak self] in
            DispatchQueue.main.async {
                self?.webView.evaluateJavaScript("window.BaselineBridge && window.BaselineBridge.changed && window.BaselineBridge.changed()", completionHandler: nil)
            }
        }
        if let url = URL(string: "baseline://app/index.html") { webView.load(URLRequest(url: url)) }
    }

    // MARK: page loading, logged so a build check can tell the page really rendered

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
    ///   { type: "share", id, filename, text }                       → the share sheet with that file
    ///   { type: "latest", id }                                      → { at, hr: [[time, bpm]], hrv: [[time, ms]] }, the last few hours
    /// and tells the page when the watch has delivered new readings by calling BaselineBridge.changed().
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
        case "share":
            share(id: id, filename: body["filename"] as? String ?? "baseline-export.json", text: body["text"] as? String ?? "")
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
