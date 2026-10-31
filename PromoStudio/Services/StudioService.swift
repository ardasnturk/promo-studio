import Foundation

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
        let props: [String: Any] = [
            "brand": brand, "lang": post.language ?? "tr", "fps": fps, "durationInFrames": max(30, from), "scenes": scenes,
        ]
        let url = propsFile(post.id)
        try JSONSerialization.data(withJSONObject: props, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        return url
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
    static func render(post: ContentPost, onProgress: @escaping @Sendable (Double, String) -> Void) async throws -> (video: String, cover: String) {
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
        // Cover: the moment the hook scene settles
        let coverFrame = min(Int(1.2 * Double(fps)), Int((post.directed?.storyboard.scenes.first?.durationSec ?? 2) * Double(fps) * 0.6))
        try await ProcessRunner.run(bin, ["still", entry, id, outDir.appendingPathComponent(cover).path, props, "--frame=\(coverFrame)", "--image-format=jpeg"], cwd: Paths.remotion)
        onProgress(1, String(localized: "Done"))
        return (video, cover)
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
