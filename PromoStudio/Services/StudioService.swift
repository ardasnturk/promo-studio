import AppKit

/// Claude-directed videos: the `src/videos/<id>` folder in the Remotion project, props, entry file and render.
/// The kit and its guide live in `RemotionTemplate/src/kit` and `KIT.md`.
enum StudioService {
    static let fps = 30

    static func compositionId(for postId: UUID) -> String {
        "V" + postId.uuidString.replacingOccurrences(of: "-", with: "").prefix(10)
    }

    static func videoDir(_ id: String) -> URL { Paths.remotion.appendingPathComponent("src/videos/\(id)") }
    static func entryFile(_ id: String) -> URL { Paths.remotion.appendingPathComponent("src/entries/\(id).tsx") }
    static func propsFile(_ postId: UUID) -> URL { Paths.remotion.appendingPathComponent("public/posts/\(postId.uuidString)/props.json") }
    static var kitGuide: URL { Paths.remotion.appendingPathComponent("KIT.md") }

    /// A library linked to the project (e.g. Acme ↔ template library): if the Remotion folder has `src/<ProjectName>`.
    static func linkedLibrary(for project: AppProject, in libraries: [TemplateLibrary]) -> (library: TemplateLibrary, folder: String)? {
        let fm = FileManager.default
        for lib in libraries {
            let src = lib.remotionURL.appendingPathComponent("src")
            let match = (try? fm.contentsOfDirectory(atPath: src.path))?.first { $0.caseInsensitiveCompare(project.name) == .orderedSame }
            if let match { return (lib, "src/\(match)") }
        }
        return nil
    }

    /// Copies the library's public images for the project (e.g. public/acme) into the studio; returns the public path.
    static func importLibraryAssets(_ lib: TemplateLibrary, project: AppProject) -> String? {
        let fm = FileManager.default
        let pub = lib.remotionURL.appendingPathComponent("public")
        guard let match = (try? fm.contentsOfDirectory(atPath: pub.path))?.first(where: { $0.caseInsensitiveCompare(project.name) == .orderedSame }) else { return nil }
        let rel = "brands/\(match)"
        let dest = Paths.remotion.appendingPathComponent("public/\(rel)")
        try? fm.removeItem(at: dest)
        Paths.ensure(dest.deletingLastPathComponent())
        guard (try? fm.copyItem(at: pub.appendingPathComponent(match), to: dest)) != nil else { return nil }
        return rel
    }

    /// Copies the project's images and the post's audio into public/ and writes props.json.
    /// `post.spec.scenes` must be synced with the storyboard and have its voiceover ready.
    @discardableResult
    static func writeProps(post: ContentPost, project: AppProject, storeLabel: String?) throws -> URL {
        guard let board = post.directed?.storyboard else { throw StudioError.noStoryboard }
        let fm = FileManager.default
        let projRel = "projects/\(project.id.uuidString)"
        let postRel = "posts/\(post.id.uuidString)"
        let projDir = Paths.ensure(Paths.remotion.appendingPathComponent("public/\(projRel)"))
        let postDir = Paths.ensure(Paths.remotion.appendingPathComponent("public/\(postRel)"))
        let assetDir = Paths.projectAssets(project.id)

        func publish(_ file: String) -> String? {
            let src = assetDir.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { return nil }
            let dest = projDir.appendingPathComponent(file)
            if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: src, to: dest) }
            return "\(projRel)/\(file)"
        }

        var from = 0
        var scenes: [[String: Any]] = []
        for (i, s) in board.scenes.enumerated() {
            let specScene = post.spec.scenes.indices.contains(i) ? post.spec.scenes[i] : nil
            let frames = max(20, Int(((specScene?.durationSec ?? s.durationSec) * Double(fps)).rounded()))
            var scene: [String: Any] = [
                "from": from, "durationInFrames": frames, "text": s.text, "visual": s.visual,
                "assets": (s.assets ?? []).compactMap(publish),
            ]
            if let audio = specScene?.audio {
                let src = Paths.post(post.id).appendingPathComponent(audio)
                let dest = postDir.appendingPathComponent(audio)
                try? fm.removeItem(at: dest)
                if (try? fm.copyItem(at: src, to: dest)) != nil { scene["audio"] = "\(postRel)/\(audio)" }
            }
            scenes.append(scene)
            from += frames
        }
        var brand: [String: Any] = [
            "appName": post.spec.brand.appName, "primary": post.spec.brand.primary,
            "accent": post.spec.brand.accent, "background": post.spec.brand.background,
        ]
        if let label = storeLabel { brand["storeLabel"] = label }
        if let logo = project.logoFile, let path = publish(logo) { brand["logo"] = path }
        var logos: [String: String] = [:]
        for (name, file) in logoFiles(post) {
            let dest = postDir.appendingPathComponent(file)
            Paths.ensure(dest.deletingLastPathComponent())
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: Paths.post(post.id).appendingPathComponent(file), to: dest)) != nil { logos[name] = "\(postRel)/\(file)" }
        }
        let props: [String: Any] = [
            "brand": brand, "lang": post.language ?? "tr", "fps": fps, "durationInFrames": max(30, from), "scenes": scenes,
            "logos": logos,
        ]
        let url = propsFile(post.id)
        try JSONSerialization.data(withJSONObject: props, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        return url
    }

    // MARK: Real logos

    private static func logoFile(_ logo: StoryLogo) -> String {
        let slug = logo.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        // Stable across launches (hashValue isn't), so a changed URL downloads again
        let hash = logo.url.utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return "logos/\(slug.isEmpty ? "logo" : slug)-\(hash % 100_000)"
    }

    /// Downloaded logos of the storyboard: name → file in the post folder.
    static func logoFiles(_ post: ContentPost) -> [(String, String)] {
        let dir = Paths.post(post.id)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("logos").path)) ?? []
        return (post.directed?.storyboard.logos ?? []).compactMap { logo in
            let base = (logoFile(logo) as NSString).lastPathComponent
            return files.first { ($0 as NSString).deletingPathExtension == base }.map { (logo.name, "logos/\($0)") }
        }
    }

    /// Downloads the storyboard's logos into the post folder; ones that fail or aren't images are skipped (the video uses a Badge).
    static func downloadLogos(_ post: ContentPost) async {
        let dir = Paths.ensure(Paths.post(post.id).appendingPathComponent("logos"))
        let have = Set(logoFiles(post).map(\.0))
        for logo in post.directed?.storyboard.logos ?? [] where !have.contains(logo.name) {
            guard let url = URL(string: logo.url), url.scheme == "https" || url.scheme == "http" else { continue }
            var req = URLRequest(url: url, timeoutInterval: 20)
            // Some hosts (e.g. Wikimedia) refuse requests without a user agent
            req.setValue("PromoStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200, let ext = imageExtension(data, response: resp) else { continue }
            try? data.write(to: dir.appendingPathComponent(((logoFile(logo) as NSString).lastPathComponent) + "." + ext))
        }
    }

    private static func imageExtension(_ data: Data, response: URLResponse) -> String? {
        let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        if head.contains("<svg") { return "svg" }
        guard NSImage(data: data) != nil else { return nil }
        switch response.mimeType {
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        default: return data.starts(with: [0xFF, 0xD8]) ? "jpg" : "png"
        }
    }

    // MARK: Cover

    /// Cover frame: the settled moment of the scene the director picked (the hook if none).
    static func coverFrame(_ post: ContentPost) -> Int {
        // Same timing as writeProps: the voiceover-fitted duration, else the storyboard's
        let board = post.directed?.storyboard.scenes ?? []
        let durations = board.indices.map { i in
            let sec = (post.spec.scenes.indices.contains(i) ? post.spec.scenes[i].durationSec : nil) ?? board[i].durationSec
            return max(20, Int((sec * Double(fps)).rounded()))
        }
        guard !durations.isEmpty else { return Int(1.2 * Double(fps)) }
        let index = min(max(post.directed?.storyboard.coverScene ?? 0, 0), durations.count - 1)
        let start = durations.prefix(index).reduce(0, +)
        let into = index == 0 ? min(Int(1.2 * Double(fps)), Int(Double(durations[0]) * 0.6)) : Int(Double(durations[index]) * 0.6)
        return start + into
    }

    /// Entry file that registers only this video; an error in one video does not break rendering the others.
    static func writeEntry(_ id: String) throws {
        let entry = """
        // Generated by Promo Studio; do not edit.
        import React from 'react';
        import {Composition, registerRoot} from 'remotion';
        import type {StudioProps} from '../kit';
        import {Video} from '../videos/\(id)/Video';

        const Root: React.FC = () => (
          <Composition
            id="\(id)"
            component={Video as unknown as React.FC<Record<string, unknown>>}
            width={1080}
            height={1920}
            fps={\(fps)}
            durationInFrames={300}
            calculateMetadata={({props}) => {
              const p = props as unknown as StudioProps;
              return {fps: p.fps, durationInFrames: p.durationInFrames};
            }}
          />
        );

        registerRoot(Root);

        """
        Paths.ensure(entryFile(id).deletingLastPathComponent())
        try entry.write(to: entryFile(id), atomically: true, encoding: .utf8)
    }

    static func hasCode(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: videoDir(id).appendingPathComponent("Video.tsx").path)
    }

    /// Renders the video and cover into the post folder.
    static func render(post: ContentPost, onProgress: @escaping @Sendable (Double, String) -> Void) async throws -> (video: String, cover: String, coverSec: Double) {
        guard let directed = post.directed else { throw StudioError.noStoryboard }
        let id = directed.compositionId
        guard hasCode(id) else { throw StudioError.noCode }
        try writeEntry(id)
        let fm = FileManager.default
        let outDir = Paths.post(post.id)
        let video = "video.mp4", cover = "cover.jpg"
        let bin = Paths.remotion.appendingPathComponent("node_modules/.bin/remotion").path
        let entry = "src/entries/\(id).tsx"
        let props = "--props=\(propsFile(post.id).path)"
        onProgress(0.02, String(localized: "Starting render…"))
        let regex = /(\d+)\/(\d+)/
        try await ProcessRunner.run(bin, ["render", entry, id, outDir.appendingPathComponent(video).path, props], cwd: Paths.remotion) { line in
            if let m = line.firstMatch(of: regex), let a = Double(m.1), let b = Double(m.2), b > 0, a <= b {
                onProgress(min(0.95, a / b * 0.95), line.trimmingCharacters(in: .whitespaces))
            }
        }
        guard fm.fileExists(atPath: outDir.appendingPathComponent(video).path) else { throw RemotionError.noOutput }
        onProgress(0.97, String(localized: "Creating cover image…"))
        let frame = coverFrame(post)
        try await ProcessRunner.run(bin, ["still", entry, id, outDir.appendingPathComponent(cover).path, props, "--frame=\(frame)", "--image-format=jpeg"], cwd: Paths.remotion)
        onProgress(1, String(localized: "Done"))
        return (video, cover, Double(frame) / Double(fps))
    }

    // MARK: Code versions

    /// Takes a snapshot of the video code into the post folder; returns its name.
    static func snapshotCode(_ id: String, postId: UUID) -> String? {
        guard hasCode(id) else { return nil }
        let name = "v\(Int(Date().timeIntervalSince1970))"
        let dest = Paths.ensure(Paths.post(postId).appendingPathComponent("code")).appendingPathComponent(name)
        return (try? FileManager.default.copyItem(at: videoDir(id), to: dest)) != nil ? name : nil
    }

    static func restoreCode(_ name: String, id: String, postId: UUID) throws {
        let src = Paths.post(postId).appendingPathComponent("code/\(name)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { throw StudioError.noCode }
        try? fm.removeItem(at: videoDir(id))
        Paths.ensure(videoDir(id).deletingLastPathComponent())
        try fm.copyItem(at: src, to: videoDir(id))
    }

    /// When a post is deleted, cleans up its code, entry file and public copies in the studio.
    static func remove(postId: UUID, id: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: videoDir(id))
        try? fm.removeItem(at: entryFile(id))
        try? fm.removeItem(at: propsFile(postId).deletingLastPathComponent())
    }
}

enum StudioError: LocalizedError {
    case noStoryboard, noCode

    var errorDescription: String? {
        switch self {
        case .noStoryboard: String(localized: "This post has no storyboard.")
        case .noCode: String(localized: "The video code hasn't been written yet. Approve the storyboard and produce the video first.")
        }
    }
}
