import Foundation
import Security
import UIKit

/// The Claude coach without a server: the person's own Anthropic API key, kept in this iPhone's Keychain, and the same request
/// the coach server makes (server/coach.mjs handleCoach). The model, system prompt and tools come from coach.json, which
/// server/export-config.mjs writes from the server's code, so the two can't drift (CI checks it).
///
/// The page sends `{ type: "coach", id, messages }` and gets the reply as events through BaselineBridge.coach(id, ev), the same
/// objects the server streams as NDJSON: `{ t: "text", v }` while Claude writes, then `{ t: "done", message }` or
/// `{ t: "error", code, message }`. The page never sees the key.
final class Coach {
    /// Hands an event to the page. Set by the web controller; called on the main thread.
    var emit: ((String, [String: Any]) -> Void)?
    private var tasks: [String: Task<Void, Never>] = [:]

    // MARK: requests (main thread)

    func start(id: String, messages: Any?) {
        tasks[id]?.cancel()
        guard let key = CoachKey.read() else {
            emit?(id, Self.failure("server_key", "Add your Anthropic API key in Settings to use the coach."))
            return
        }
        guard let config = Config.shared, let body = Self.body(config, messages: messages) else {
            emit?(id, Self.failure("bad_request", "The conversation is malformed."))
            return
        }
        tasks[id] = Task {
            let ev = await Self.stream(body: body, key: key, fallbackModel: config.model) { text in
                DispatchQueue.main.async { self.emit?(id, ["t": "text", "v": text]) }
            }
            DispatchQueue.main.async {
                self.tasks[id] = nil
                self.emit?(id, ev)
            }
        }
    }

    /// Stops a reply; the running request then ends with `{ t: "error", code: "cancelled" }`.
    func cancel(id: String) {
        tasks[id]?.cancel()
    }

    /// Asks for the key in an alert. `done` gets whether a key is stored afterwards.
    func promptForKey(from view: UIView, retry: Bool = false, done: @escaping (Bool) -> Void) {
        guard var top = view.window?.rootViewController else { done(CoachKey.read() != nil); return }
        while let p = top.presentedViewController { top = p }
        let note = "It stays in this iPhone's Keychain and is only ever sent to Anthropic, with your coach messages."
        let alert = UIAlertController(title: "Anthropic API key",
                                      message: retry ? "That doesn't look like an Anthropic API key; they start with sk-ant-. " + note : note,
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "sk-ant-…"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(CoachKey.read() != nil) })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            let key = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("sk-ant-"), key.count > 20, CoachKey.save(key) {
                done(true)
            } else {
                self.promptForKey(from: view, retry: true, done: done)
            }
        })
        top.present(alert, animated: true)
    }

    // MARK: the request

    /// coach.json: `{"model":…,"system":…,"tools":[…]}` as export-config.mjs writes it.
    struct Config {
        let model: String
        let system: String
        /// The tools exactly as written in the file, so they reach the API byte for byte as the server sends them.
        let toolsJSON: String

        static let shared: Config? = {
            guard let url = Bundle.main.url(forResource: "coach", withExtension: "json"),
                  let text = try? String(contentsOf: url, encoding: .utf8), let data = text.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let model = o["model"] as? String, let system = o["system"] as? String, let tools = o["tools"] as? [Any] else {
                log.error("coach.json is missing or malformed")
                return nil
            }
            // the tools are the last key, so they run from after ,"tools": to the closing brace
            var raw: String?
            if let r = text.range(of: ",\"tools\":", options: .backwards), text.hasSuffix("}") {
                let slice = String(text[r.upperBound..<text.index(before: text.endIndex)])
                if let d = slice.data(using: .utf8), (try? JSONSerialization.jsonObject(with: d)) is [Any] { raw = slice }
            }
            if raw == nil, let d = try? JSONSerialization.data(withJSONObject: tools, options: [.sortedKeys, .withoutEscapingSlashes]) {
                raw = String(data: d, encoding: .utf8)
            }
            guard let toolsJSON = raw else { return nil }
            return Config(model: model, system: system, toolsJSON: toolsJSON)
        }()
    }

    /// The body handleCoach sends, plus "stream": true. `messages` is passed through untouched: a JSON string is spliced in
    /// as it is (byte-stable), an array is serialized.
    static func body(_ config: Config, messages: Any?) -> Data? {
        let messagesJSON: String
        if let s = messages as? String {
            guard let d = s.data(using: .utf8), let a = (try? JSONSerialization.jsonObject(with: d)) as? [Any], !a.isEmpty else { return nil }
            messagesJSON = s
        } else if let a = messages as? [Any], !a.isEmpty, JSONSerialization.isValidJSONObject(a),
                  let d = try? JSONSerialization.data(withJSONObject: a, options: [.withoutEscapingSlashes]), let s = String(data: d, encoding: .utf8) {
            messagesJSON = s
        } else {
            return nil
        }
        let head: [String: Any] = [
            "model": config.model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "medium"],
            // a declined request is re-run on Anthropic's recommended fallback model instead of failing
            "fallbacks": "default",
            "cache_control": ["type": "ephemeral"],
            "system": config.system,
            "stream": true,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: head, options: [.sortedKeys, .withoutEscapingSlashes]),
              var json = String(data: d, encoding: .utf8), json.hasSuffix("}") else { return nil }
        json.removeLast()
        json += ",\"tools\":" + config.toolsJSON + ",\"messages\":" + messagesJSON + "}"
        return json.data(using: .utf8)
    }

    /// Streams one reply and rebuilds the final message from the events, the way the SDK's finalMessage() does.
    /// Text deltas go to `text` as they arrive; the result is the closing done or error event.
    private static func stream(body: Data, key: String, fallbackModel: String, text: @escaping (String) -> Void) async -> [String: Any] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return failure("error", "Bad URL.") }
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                var raw = ""
                for try await line in bytes.lines {
                    raw += line
                    if raw.count > 20_000 { break }
                }
                let error = (raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["error"] as? [String: Any]
                return failure(code(status: status), error?["message"] as? String ?? "Claude answered with HTTP \(status).")
            }

            var message: [String: Any] = [:]
            var blocks: [Int: [String: Any]] = [:]
            var partial: [Int: String] = [:]      // tool input JSON as it streams, by block
            var stopped = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8), let ev = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                switch ev["type"] as? String {
                case "message_start":
                    message = ev["message"] as? [String: Any] ?? [:]
                    for (i, b) in (message["content"] as? [[String: Any]] ?? []).enumerated() { blocks[i] = b }
                case "content_block_start":
                    // every block is kept as it arrives (including types this code doesn't know); deltas below fill it in
                    if let i = ev["index"] as? Int, let b = ev["content_block"] as? [String: Any] { blocks[i] = b }
                case "content_block_delta":
                    guard let i = ev["index"] as? Int, let d = ev["delta"] as? [String: Any], var b = blocks[i] else { break }
                    apply(d, to: &b, partial: &partial[i], text: text)
                    blocks[i] = b
                case "content_block_stop":
                    guard let i = ev["index"] as? Int, let json = partial.removeValue(forKey: i), var b = blocks[i] else { break }
                    // an input cut short (max_tokens) doesn't parse; it stays empty and the page's checks refuse it
                    let parsed = json.isEmpty ? nil : json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                    b["input"] = parsed as? [String: Any] ?? [String: Any]()
                    blocks[i] = b
                case "message_delta":
                    for (k, v) in ev["delta"] as? [String: Any] ?? [:] { message[k] = v }
                    if let u = ev["usage"] as? [String: Any] {
                        var usage = message["usage"] as? [String: Any] ?? [:]
                        for (k, v) in u where !(v is NSNull) { usage[k] = v }
                        message["usage"] = usage
                    }
                case "message_stop":
                    stopped = true
                case "error":
                    let e = ev["error"] as? [String: Any]
                    return failure(code(errorType: e?["type"] as? String), e?["message"] as? String ?? "Something went wrong.")
                default:
                    break // ping, and event types added later
                }
                if stopped { break }
            }
            try Task.checkCancellation()
            guard stopped else { return failure("unreachable", "The connection closed before Claude finished.") }
            let content: [[String: Any]] = blocks.keys.sorted().compactMap { blocks[$0] }
            let final: [String: Any] = [
                "role": "assistant",
                "content": content,
                "stop_reason": message["stop_reason"] ?? NSNull(),
                "stop_details": message["stop_details"] ?? NSNull(),
                "model": message["model"] ?? fallbackModel,
                "usage": message["usage"] ?? [String: Any](),
            ]
            return ["t": "done", "message": final]
        } catch is CancellationError {
            return failure("cancelled", "Stopped.")
        } catch let error as URLError {
            return error.code == .cancelled ? failure("cancelled", "Stopped.") : failure("unreachable", error.localizedDescription)
        } catch {
            return Task.isCancelled ? failure("cancelled", "Stopped.") : failure("error", error.localizedDescription)
        }
    }

    /// Merges one content_block_delta into its block, as the SDK does. Deltas of unknown types are left out.
    private static func apply(_ d: [String: Any], to b: inout [String: Any], partial: inout String?, text: (String) -> Void) {
        switch d["type"] as? String {
        case "text_delta":
            let t = d["text"] as? String ?? ""
            b["text"] = (b["text"] as? String ?? "") + t
            if !t.isEmpty { text(t) }
        case "thinking_delta":
            b["thinking"] = (b["thinking"] as? String ?? "") + (d["thinking"] as? String ?? "")
        case "signature_delta":
            if let s = d["signature"] as? String { b["signature"] = s }
        case "input_json_delta":
            partial = (partial ?? "") + (d["partial_json"] as? String ?? "")
        case "citations_delta":
            if let c = d["citation"] {
                var list = b["citations"] as? [Any] ?? []
                list.append(c)
                b["citations"] = list
            }
        default:
            break
        }
    }

    private static func failure(_ code: String, _ message: String) -> [String: Any] {
        ["t": "error", "code": code, "message": message]
    }

    /// The same codes the server sends, from the HTTP status.
    private static func code(status: Int) -> String {
        switch status {
        case 429: return "rate_limited"
        case 401, 403: return "server_key"
        case 400, 404, 413, 422: return "bad_request"
        case 500...599: return "overloaded"
        default: return "error"
        }
    }

    /// The same codes, from an error event in the stream.
    private static func code(errorType: String?) -> String {
        switch errorType {
        case "rate_limit_error": return "rate_limited"
        case "authentication_error", "permission_error": return "server_key"
        case "invalid_request_error", "request_too_large", "not_found_error": return "bad_request"
        case "overloaded_error", "api_error": return "overloaded"
        default: return "error"
        }
    }
}

/// The person's Anthropic API key, in the Keychain on this iPhone only (not synced, not backed up to other devices).
enum CoachKey {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "baseline.coach",
        kSecAttrAccount as String: "anthropic",
    ]

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) -> Bool {
        delete()
        var q = base
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}
