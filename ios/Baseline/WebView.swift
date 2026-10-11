import SwiftUI
import WebKit

/// Hosts index.html. The page is served from baseline://app/ (a fixed origin, so its localStorage persists),
/// and talks to the native side through the "baseline" message handler.
final class WebController: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView
    private let health = HealthReader()

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
        if let url = URL(string: "baseline://app/index.html") { webView.load(URLRequest(url: url)) }
    }

    func foreground() {
        webView.evaluateJavaScript("window.BaselineBridge && window.BaselineBridge.foreground()", completionHandler: nil)
    }

    /// The page asks: { type: "sync", id, from: "YYYY-MM-DD", to: "YYYY-MM-DD" }.
    /// The app answers by calling BaselineBridge.receive({ id, ok, payload | error }).
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
        guard (body["type"] as? String) == "sync", let from = body["from"] as? String, let to = body["to"] as? String else {
            reply(["id": id, "ok": false, "error": "unknown_request"])
            return
        }
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
