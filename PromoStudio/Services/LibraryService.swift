import Foundation

enum LibraryError: LocalizedError {
    case notRemotion(String)
    case noVideo(String)

    var errorDescription: String? {
        switch self {
        case let .notRemotion(path): String(localized: "No Remotion project (package.json + src/Root.tsx) found in \(path).")
        case let .noVideo(msg): String(localized: "Video not found: \(msg)")
        }
    }
}

/// Scans, installs and renders external template libraries (e.g. Promo Templates).
enum LibraryService {
    // MARK: Scanning

    static func scan(_ root: URL, existing: TemplateLibrary? = nil) throws -> TemplateLibrary {
        guard let remotionDir = findRemotionDir(root) else { throw LibraryError.notRemotion(root.path) }
        var lib = existing ?? TemplateLibrary(name: root.lastPathComponent, path: root.path, remotionDir: remotionDir)
        lib.remotionDir = remotionDir
        lib.skills = scanSkills(root)
        lib.compositions = scanCompositions(root.appendingPathComponent(remotionDir).appendingPathComponent("src/Root.tsx"))
        lib.scannedAt = Date()
        return lib
    }

    /// The root itself, or a folder at most two levels below it, with a remotion dependency and src/Root.tsx
    private static func findRemotionDir(_ root: URL) -> String? {
        let fm = FileManager.default
        func isRemotion(_ dir: URL) -> Bool {
            guard let pkg = try? String(contentsOf: dir.appendingPathComponent("package.json"), encoding: .utf8) else { return false }
            return pkg.contains("\"remotion\"") && fm.fileExists(atPath: dir.appendingPathComponent("src/Root.tsx").path)
        }
        if isRemotion(root) { return "." }
        let level1 = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "node_modules" }
        for dir in level1.sorted(by: { $0.path < $1.path }) where isRemotion(dir) { return dir.lastPathComponent }
        for dir in level1 {
            for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where isRemotion(sub) {
                return "\(dir.lastPathComponent)/\(sub.lastPathComponent)"
            }
        }
        return nil
    }

    /// Video skills from the front matter of .claude/skills/*/SKILL.md (excluding Remotion's general skills)
    private static func scanSkills(_ root: URL) -> [LibrarySkill] {
        let dir = root.appendingPathComponent(".claude/skills")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { name -> LibrarySkill? in
            guard !name.hasPrefix("remotion-"),
                  let text = try? String(contentsOf: dir.appendingPathComponent("\(name)/SKILL.md"), encoding: .utf8) else { return nil }
            let front = frontMatter(text)
            return LibrarySkill(
                name: front["name"] ?? name,
                description: front["description"] ?? "",
                argumentHint: front["argument-hint"] ?? ""
            )
        }
    }

    private static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        var out: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            out[key] = value
        }
        return out
    }

    /// <Folder> and <Composition> entries in Root.tsx
    private static func scanCompositions(_ rootTsx: URL) -> [LibraryComposition] {
        guard let text = try? String(contentsOf: rootTsx, encoding: .utf8) else { return [] }
        var result: [LibraryComposition] = []
        var folders: [String] = []
        let token = /<Folder\s+name="([^"]+)"|<\/Folder>|<Composition\b([\s\S]*?)\/>/
        for m in text.matches(of: token) {
            if let folder = m.1 {
                folders.append(String(folder))
            } else if m.0 == "</Folder>" {
                _ = folders.popLast()
            } else if let body = m.2, let id = body.firstMatch(of: /\bid="([^"]+)"/)?.1 {
                result.append(LibraryComposition(id: String(id), folder: folders.joined(separator: "/"), hasSchema: body.contains("schema=")))
            }
        }
        return result
    }

    // MARK: Install and render

    static func ensureInstalled(_ lib: TemplateLibrary, onLine: (@Sendable (String) -> Void)? = nil) async throws {
        let bin = lib.remotionURL.appendingPathComponent("node_modules/.bin/remotion")
        if FileManager.default.isExecutableFile(atPath: bin.path) { return }
        onLine?(String(localized: "\(lib.name): running npm install (may take a few minutes the first time)…"))
        try await ProcessRunner.run("npm", ["install", "--no-audit", "--no-fund"], cwd: lib.remotionURL, onLine: onLine)
    }

    static func entryPoint(_ lib: TemplateLibrary) -> String {
        for candidate in ["src/index.ts", "src/index.tsx", "src/index.js"]
        where FileManager.default.fileExists(atPath: lib.remotionURL.appendingPathComponent(candidate).path) {
            return candidate
        }
        return "src/index.ts"
    }

    /// Renders the composition (with optional props); output is written to the post folder.
    static func render(
        _ lib: TemplateLibrary,
        compositionId: String,
        propsJson: String?,
        postId: UUID,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> (video: String, cover: String) {
        try await ensureInstalled(lib) { onProgress(0, $0) }
        let outDir = Paths.post(postId)
        let video = outDir.appendingPathComponent("video.mp4")
        var args = ["render", entryPoint(lib), compositionId, video.path]
        if let propsJson, !propsJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let propsFile = outDir.appendingPathComponent("props.json")
            try Data(propsJson.utf8).write(to: propsFile)
            args.append("--props=\(propsFile.path)")
        }
        let regex = /(\d+)\/(\d+)/
        let bin = lib.remotionURL.appendingPathComponent("node_modules/.bin/remotion").path
        onProgress(0.02, String(localized: "Starting render: \(compositionId)"))
        try await ProcessRunner.run(bin, args, cwd: lib.remotionURL) { line in
            if let m = line.firstMatch(of: regex), let a = Double(m.1), let b = Double(m.2), b > 0, a <= b {
                onProgress(min(0.95, a / b * 0.95), line.trimmingCharacters(in: .whitespaces))
            }
        }
        guard FileManager.default.fileExists(atPath: video.path) else { throw LibraryError.noVideo(video.path) }
        let cover = try await makeCover(for: video)
        onProgress(1, String(localized: "Done"))
        return (video.lastPathComponent, cover)
    }

    /// Copies the video the skill produced into the post folder and extracts a cover.
    static func importVideo(from path: String, postId: UUID) async throws -> (video: String, cover: String) {
        let src = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: src.path) else { throw LibraryError.noVideo(path) }
        let dest = Paths.post(postId).appendingPathComponent("video.mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return (dest.lastPathComponent, try await makeCover(for: dest))
    }

    private static func makeCover(for video: URL) async throws -> String {
        let cover = video.deletingLastPathComponent().appendingPathComponent("cover.jpg")
        try await AudioService.ffmpeg(["-v", "error", "-y", "-ss", "1.2", "-i", video.path, "-frames:v", "1", "-q:v", "3", cover.path])
        return cover.lastPathComponent
    }
}
