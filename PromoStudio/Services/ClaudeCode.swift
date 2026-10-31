import Foundation

enum ClaudeCodeError: LocalizedError {
    case noResult(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .noResult(out): String(localized: "Claude Code didn't return a structured result.\n\(out.suffix(400))")
        case let .failed(msg): String(localized: "Claude Code error: \(msg)")
        }
    }
}

/// Manages `claude -p` (headless Claude Code) calls. Output is structured with a JSON Schema.
struct ClaudeCode {
    var model: String = ""

    func structured<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        schema: [String: Any],
        cwd: URL,
        tools: [String] = [],
        additionalDirectories: [URL] = [],
        maxTurns: Int = 6,
        onActivity: (@Sendable (String) -> Void)? = nil
    ) async throws -> T {
        let schemaData = try JSONSerialization.data(withJSONObject: schema)
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--json-schema", String(decoding: schemaData, as: UTF8.self),
            "--max-turns", String(maxTurns),
        ]
        if !model.isEmpty { args += ["--model", model] }
        // Only explicitly allowed (read-only) tools can be used; others are denied in -p mode.
        if !tools.isEmpty { args += ["--allowedTools", tools.joined(separator: ",")] }
        for dir in additionalDirectories { args += ["--add-dir", dir.path] }

        let output = try await ProcessRunner.run("claude", args, cwd: cwd, stdin: prompt) { line in
            if let activity = Self.describe(line) { onActivity?(activity) }
        }

        for line in output.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "result" else { continue }
            if obj["is_error"] as? Bool == true {
                throw ClaudeCodeError.failed(obj["result"] as? String ?? obj["subtype"] as? String ?? "bilinmeyen")
            }
            guard let structured = obj["structured_output"] else { throw ClaudeCodeError.noResult(output) }
            let json = try JSONSerialization.data(withJSONObject: structured)
            return try JSONDecoder().decode(T.self, from: json)
        }
        throw ClaudeCodeError.noResult(output)
    }

    /// Extracts a short activity text to show the user from stream-json events.
    private static func describe(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
        for block in content where block["type"] as? String == "tool_use" {
            let name = block["name"] as? String ?? String(localized: "tool")
            let input = block["input"] as? [String: Any] ?? [:]
            let detail = (input["file_path"] ?? input["pattern"] ?? input["path"] ?? input["command"]) as? String
            if name == "StructuredOutput" { return String(localized: "Compiling the result…") }
            return detail.map { "\(name): \(($0 as NSString).lastPathComponent)" } ?? name
        }
        return nil
    }
}
