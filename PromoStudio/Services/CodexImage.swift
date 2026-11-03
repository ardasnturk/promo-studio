import Foundation

enum CodexImageError: LocalizedError {
    case noImage(String)

    var errorDescription: String? {
        switch self {
        case let .noImage(reply):
            reply.isEmpty ? String(localized: "Codex didn’t make an image.") : String(localized: "Codex didn’t make an image: \(reply)")
        }
    }
}

/// Edits photos with Codex's image generation (`codex exec`), on the user's ChatGPT plan: no API key, no extra cost.
/// Codex saves what it generates under ~/.codex/generated_images/<thread id>/; the newest file there is the result.
enum CodexImage {
    static var isInstalled: Bool { ProcessRunner.which("codex") != nil }

    /// Edits `photo` per `instruction` and writes the result next to `base` (PNG or JPEG); returns the file written.
    static func edit(photo: URL, name: String, instruction: String, to base: URL) async throws -> URL {
        let prompt = """
        Edit the attached photo of \(name) with image generation. Keep the person's face, identity, skin tone, hair, body and clothing exactly as they are, so they are clearly recognizable; change only this: \(instruction)
        Remove anything in front of the person (microphones, other people, objects) so they stand alone. Photorealistic, portrait orientation (2:3), the head and upper body fully in frame. Generate exactly one image. Don't write files or run commands. Reply with just DONE, or with the reason if you can't make it.
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("codex-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let output = try await ProcessRunner.run(
            "codex",
            ["exec", "--skip-git-repo-check", "--ephemeral", "--json", "--color", "never", "-s", "read-only", "-i", photo.path, "-"],
            cwd: work, stdin: prompt
        )
        var thread: String?
        var reply = ""
        for line in output.split(separator: "\n") {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if event["type"] as? String == "thread.started" { thread = event["thread_id"] as? String }
            if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message", let text = item["text"] as? String {
                reply = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/generated_images/\(thread ?? "-")")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
        guard let newest, let data = try? Data(contentsOf: newest), let saved = PhotoService.normalize(data, to: base) else {
            throw CodexImageError.noImage(reply == "DONE" ? "" : reply)
        }
        return saved
    }
}
