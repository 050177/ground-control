import Foundation

struct SessionUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    /// Last model seen in this session (e.g. "anthropic/claude-sonnet-4.6").
    var model: String?

    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }

    var estimatedCostUSD: Double? {
        guard let model else { return nil }
        guard let rate = ModelPricing.rate(for: model) else { return nil }
        let input  = Double(inputTokens)       / 1_000_000 * rate.input
        let output = Double(outputTokens)      / 1_000_000 * rate.output
        let cread  = Double(cacheReadTokens)   / 1_000_000 * rate.cacheRead
        let cwrite = Double(cacheWriteTokens)  / 1_000_000 * rate.cacheWrite
        return input + output + cread + cwrite
    }

    var tokenLabel: String {
        let k = totalTokens
        if k == 0 { return "" }
        if k < 1_000 { return "\(k) tok" }
        if k < 1_000_000 { return String(format: "%.1fk tok", Double(k) / 1_000) }
        return String(format: "%.2fM tok", Double(k) / 1_000_000)
    }

    var costLabel: String? {
        guard let c = estimatedCostUSD else { return nil }
        if c < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", c)
    }

    /// Short model name for display — strips provider prefix, e.g.
    /// "anthropic/claude-sonnet-4.6" → "sonnet-4.6"
    var shortModel: String? {
        guard let model else { return nil }
        // Strip known provider prefixes
        let prefixes = ["anthropic/claude-", "anthropic/", "openrouter/anthropic/claude-",
                        "openrouter/anthropic/", "openrouter/"]
        for prefix in prefixes {
            if model.lowercased().hasPrefix(prefix) {
                return String(model.dropFirst(prefix.count))
            }
        }
        // Unknown provider — show last path component
        return model.split(separator: "/").last.map(String.init) ?? model
    }
}

// MARK: - Per-model pricing ($ per million tokens)

private struct PricingRate {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
}

private enum ModelPricing {
    static func rate(for model: String) -> PricingRate? {
        let m = model.lowercased()
        if m.contains("claude-opus-4") || m.contains("claude-opus-4-") {
            return PricingRate(input: 15, output: 75, cacheRead: 1.50, cacheWrite: 18.75)
        }
        if m.contains("sonnet-4") || m.contains("sonnet-3-7") || m.contains("sonnet-3.7") {
            return PricingRate(input: 3, output: 15, cacheRead: 0.30, cacheWrite: 3.75)
        }
        if m.contains("haiku-4") || m.contains("haiku-3-5") || m.contains("haiku-3.5") {
            return PricingRate(input: 0.80, output: 4, cacheRead: 0.08, cacheWrite: 1.0)
        }
        if m.contains("haiku") {
            return PricingRate(input: 0.25, output: 1.25, cacheRead: 0.03, cacheWrite: 0.30)
        }
        if m.contains("sonnet") {
            return PricingRate(input: 3, output: 15, cacheRead: 0.30, cacheWrite: 3.75)
        }
        if m.contains("opus") {
            return PricingRate(input: 15, output: 75, cacheRead: 1.50, cacheWrite: 18.75)
        }
        return nil  // OpenRouter non-Anthropic or unknown — no cost estimate
    }
}

// MARK: - Transcript reading

enum TranscriptReader {

    /// Read cumulative token usage and current model from a session JSONL file.
    /// Safe to call on a background thread.
    static func readUsage(path: String) -> SessionUsage {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return SessionUsage() }
        var usage = SessionUsage()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let msg = json["message"] as? [String: Any] else { continue }
            if let model = msg["model"] as? String, !model.isEmpty {
                usage.model = model
            }
            if let u = msg["usage"] as? [String: Any] {
                usage.inputTokens      += u["input_tokens"]                as? Int ?? 0
                usage.outputTokens     += u["output_tokens"]               as? Int ?? 0
                usage.cacheReadTokens  += u["cache_read_input_tokens"]     as? Int ?? 0
                usage.cacheWriteTokens += u["cache_creation_input_tokens"] as? Int ?? 0
            }
        }
        return usage
    }

    /// Export a session JSONL as human-readable markdown.
    static func exportMarkdown(path: String, label: String) -> String {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "# \(label) — Session Export\n\nTranscript not found."
        }
        var lines = ["# \(label) — Session Export", ""]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            switch json["type"] as? String {
            case "user":
                guard let msg = json["message"] as? [String: Any] else { continue }
                let content: String
                if let s = msg["content"] as? String {
                    content = s
                } else if let arr = msg["content"] as? [[String: Any]] {
                    content = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else { continue }
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                lines += ["---", "**You**", "", content, ""]
            case "assistant":
                guard let msg = json["message"] as? [String: Any],
                      let arr = msg["content"] as? [[String: Any]] else { continue }
                let text = arr.compactMap { item -> String? in
                    guard item["type"] as? String == "text" else { return nil }
                    return item["text"] as? String
                }.joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                lines += ["**Claude**", "", text, ""]
            default: continue
            }
        }
        return lines.joined(separator: "\n")
    }
}
