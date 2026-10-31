import Foundation

enum RemotionError: LocalizedError {
    case templateMissing
    case noOutput

    var errorDescription: String? {
        switch self {
        case .templateMissing: String(localized: "Remotion template not found in the app bundle.")
        case .noOutput: String(localized: "The render finished, but no video file was created.")
        }
    }
}

/// Installs the bundled Remotion template into Application Support and renders videos.
enum RemotionService {
    private static let syncedFiles = ["package.json", "package-lock.json", "tsconfig.json", "remotion.config.ts", "KIT.md"]
    /// Videos and entry files Claude wrote under src/ are preserved during sync
    private static let preservedSourceDirs: Set<String> = ["videos", "entries"]

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.remotion.appendingPathComponent("node_modules/.bin/remotion").path)
    }

    /// Updates the template sources; runs `npm install` if dependencies are missing or changed.
    static func prepare(onLine: (@Sendable (String) -> Void)? = nil) async throws {
        guard let bundled = Bundle.main.url(forResource: "RemotionTemplate", withExtension: nil) else {
            // When running outside the bundle (e.g. command-line tests), continue with the installed template
            if isInstalled { return }
            throw RemotionError.templateMissing
        }
        let fm = FileManager.default
        let dest = Paths.ensure(Paths.remotion)
        let oldPackage = try? Data(contentsOf: dest.appendingPathComponent("package.json"))
        for item in syncedFiles {
            let target = dest.appendingPathComponent(item)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: bundled.appendingPathComponent(item), to: target)
        }
        let src = Paths.ensure(dest.appendingPathComponent("src"))
        for item in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] where !preservedSourceDirs.contains(item) {
            try? fm.removeItem(at: src.appendingPathComponent(item))
        }
        for item in try fm.contentsOfDirectory(atPath: bundled.appendingPathComponent("src").path) where !preservedSourceDirs.contains(item) {
            try fm.copyItem(at: bundled.appendingPathComponent("src/\(item)"), to: src.appendingPathComponent(item))
        }
        Paths.ensure(dest.appendingPathComponent("public/jobs"))
        let newPackage = try? Data(contentsOf: dest.appendingPathComponent("package.json"))
        if !isInstalled || oldPackage != newPackage {
            onLine?(String(localized: "Running npm install (first setup may take a few minutes)…"))
            try await ProcessRunner.run("npm", ["install", "--no-audit", "--no-fund"], cwd: dest, onLine: onLine)
        }
    }

    /// Renders the video and cover image. Returns file names in the post folder.
    static func render(
        post: ContentPost,
        project: AppProject,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> (video: String, cover: String) {
        // Sync template sources every time (cheap); npm install only runs when dependencies change
        try await prepare { onProgress(0, $0) }

        let fm = FileManager.default
        let jobRel = "jobs/\(post.id.uuidString)"
        let jobDir = Paths.remotion.appendingPathComponent("public/\(jobRel)")
        try? fm.removeItem(at: jobDir)
        Paths.ensure(jobDir)

        // Copy scene images into the job folder and rewrite their paths relative to public/
        var spec = post.spec
        let assetDir = Paths.projectAssets(project.id)
        for i in spec.scenes.indices {
            guard let img = spec.scenes[i].image, !img.isEmpty else { continue }
            let src = assetDir.appendingPathComponent(img)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: jobDir.appendingPathComponent(img))
                spec.scenes[i].image = "\(jobRel)/\(img)"
            } else {
                spec.scenes[i].image = nil
            }
        }
        // Voiceover and music live in the post folder
        let postDir = Paths.post(post.id)
        for i in spec.scenes.indices {
            guard let audio = spec.scenes[i].audio else { continue }
            let src = postDir.appendingPathComponent(audio)
            if fm.fileExists(atPath: src.path), (try? fm.copyItem(at: src, to: jobDir.appendingPathComponent(audio))) != nil {
                spec.scenes[i].audio = "\(jobRel)/\(audio)"
            } else {
                spec.scenes[i].audio = nil
            }
        }
        if let music = spec.music {
            let src = postDir.appendingPathComponent(music)
            if fm.fileExists(atPath: src.path), (try? fm.copyItem(at: src, to: jobDir.appendingPathComponent(music))) != nil {
                spec.music = "\(jobRel)/\(music)"
            } else {
                spec.music = nil
            }
        }
        if let logo = project.logoFile {
            try? fm.copyItem(at: assetDir.appendingPathComponent(logo), to: jobDir.appendingPathComponent(logo))
            spec.brand.logo = "\(jobRel)/\(logo)"
        } else {
            spec.brand.logo = nil
        }

        let propsURL = jobDir.appendingPathComponent("props.json")
        try JSONEncoder().encode(spec).write(to: propsURL)

        let outDir = Paths.post(post.id)
        let video = "video.mp4"
        let cover = "cover.jpg"
        let bin = Paths.remotion.appendingPathComponent("node_modules/.bin/remotion").path

        onProgress(0.02, String(localized: "Starting render…"))
        let regex = /(\d+)\/(\d+)/
        try await ProcessRunner.run(
            bin,
            ["render", "src/index.ts", "AppPromo", outDir.appendingPathComponent(video).path, "--props=\(propsURL.path)"],
            cwd: Paths.remotion
        ) { line in
            if let m = line.firstMatch(of: regex), let a = Double(m.1), let b = Double(m.2), b > 0, a <= b {
                onProgress(min(0.95, a / b * 0.95), line.trimmingCharacters(in: .whitespaces))
            }
        }
        guard fm.fileExists(atPath: outDir.appendingPathComponent(video).path) else { throw RemotionError.noOutput }

        onProgress(0.97, String(localized: "Creating cover image…"))
        // Cover: the frame where the first scene's hook text has fully settled
        let fps = Double(spec.fps ?? 30)
        let coverFrame = Int(min(1.2, (spec.scenes.first?.durationSec ?? 2) * 0.6) * fps)
        try await ProcessRunner.run(
            bin,
            ["still", "src/index.ts", "AppPromo", outDir.appendingPathComponent(cover).path, "--props=\(propsURL.path)", "--frame=\(coverFrame)", "--image-format=jpeg"],
            cwd: Paths.remotion
        )
        try? fm.removeItem(at: jobDir)
        onProgress(1, String(localized: "Done"))
        return (video, cover)
    }
}
