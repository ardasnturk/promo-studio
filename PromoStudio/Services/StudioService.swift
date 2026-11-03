import AppKit

/// Claude-directed videos: the `src/videos/<id>` folder in the Remotion project, props, entry file and render.
/// The kit and its guide live in `RemotionTemplate/src/kit` and `KIT.md`.
enum StudioService {
    static let fps = 30
    /// Length of an image post's composition; the last frame is rendered as the picture
    static let imageFrames = 60

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
            // An uploaded image of the post, or a project image
            if post.uploads?.contains(file) == true {
                let dest = postDir.appendingPathComponent("uploads/\(file)")
                Paths.ensure(dest.deletingLastPathComponent())
                try? fm.removeItem(at: dest)
                return (try? fm.copyItem(at: Paths.post(post.id).appendingPathComponent("uploads/\(file)"), to: dest)) != nil ? "\(postRel)/uploads/\(file)" : nil
            }
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
            // An image is one 2-second scene per slide; each scene's last frame is a picture
            let frames = post.isImage ? imageFrames : max(20, Int(((specScene?.durationSec ?? s.durationSec) * Double(fps)).rounded()))
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
        /// Copies a file of the post folder into the studio; returns its public path
        func publishPostFile(_ file: String) -> String? {
            let dest = postDir.appendingPathComponent(file)
            Paths.ensure(dest.deletingLastPathComponent())
            try? fm.removeItem(at: dest)
            return (try? fm.copyItem(at: Paths.post(post.id).appendingPathComponent(file), to: dest)) != nil ? "\(postRel)/\(file)" : nil
        }
        var logos: [String: String] = [:]
        for (name, file) in logoFiles(post) {
            if let path = publishPostFile(file) { logos[name] = path }
        }
        func photo(_ file: String, cutout: String?) -> [String: String]? {
            guard let path = publishPostFile(file) else { return nil }
            var d = ["photo": path]
            if let cutout, let cut = publishPostFile(cutout) { d["cutout"] = cut }
            return d
        }
        var people: [String: [String: String]] = [:]
        for (name, file, cutout) in peopleFiles(post) { people[name] = photo(file, cutout: cutout) }
        var uploads: [String: [String: String]] = [:]
        for (name, file, cutout) in uploadFiles(post) { uploads[name] = photo(file, cutout: cutout) }
        let size = post.isImage ? (post.directed?.size ?? .portrait).pixels : (width: 1080, height: 1920)
        let props: [String: Any] = [
            "brand": brand, "lang": post.language ?? "tr", "fps": fps, "durationInFrames": post.isImage ? from : max(30, from), "scenes": scenes,
            "logos": logos, "people": people, "uploads": uploads,
            "width": size.width, "height": size.height, "format": post.isImage ? "image" : "video",
        ]
        let url = propsFile(post.id)
        try JSONSerialization.data(withJSONObject: props, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        return url
    }

    // MARK: Real logos

    private static func logoFile(_ logo: StoryLogo) -> String { downloadName("logos", logo.name, logo.url, logo.wiki) }

    private static func downloadName(_ folder: String, _ name: String, _ url: String?, _ wiki: String?) -> String {
        let slug = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        // Stable across launches (hashValue isn't), so a changed source downloads again
        let source = [url, wiki].compactMap { $0 }.joined(separator: "|")
        let hash = source.utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return "\(folder)/\(slug.isEmpty ? "photo" : slug)-\(hash % 100_000)"
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
            var sources = [logo.url].compactMap { $0.flatMap(URL.init(string:)) }
            if let wiki = logo.wiki, let image = await wikipediaImage(wiki) { sources.append(image) }
            for url in sources where url.scheme == "https" || url.scheme == "http" {
                guard let (data, resp) = try? await fetch(url), (resp as? HTTPURLResponse)?.statusCode == 200,
                      let ext = imageExtension(data, response: resp) else { continue }
                try? data.write(to: dir.appendingPathComponent(((logoFile(logo) as NSString).lastPathComponent) + "." + ext))
                break
            }
        }
    }

    // MARK: Real people

    private static func personFile(_ person: StoryPerson) -> String { downloadName("people", person.name, person.url, person.wiki) }

    /// Photos of the storyboard's people the video uses: name → photo and its cut-out (if Vision found the person).
    /// The Codex-edited photo when there is one and the user didn't choose the original.
    static func peopleFiles(_ post: ContentPost) -> [(String, String, String?)] {
        (post.directed?.storyboard.people ?? []).compactMap { person in
            let photos = personPhotos(post, person)
            if person.useOriginal != true, let edited = photos.edited { return (person.name, edited.photo, edited.cutout) }
            return photos.original.map { (person.name, $0.photo, $0.cutout) }
        }
    }

    /// The downloaded photo of a person and its Codex edit (for the current instruction), each with its cut-out; paths in the post folder.
    static func personPhotos(_ post: ContentPost, _ person: StoryPerson) -> (original: (photo: String, cutout: String?)?, edited: (photo: String, cutout: String?)?) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.post(post.id).appendingPathComponent("people").path)) ?? []
        func find(_ base: String) -> (photo: String, cutout: String?)? {
            guard let photo = files.first(where: { ($0 as NSString).deletingPathExtension == base }) else { return nil }
            return ("people/\(photo)", files.contains("\(base)-cut.png") ? "people/\(base)-cut.png" : nil)
        }
        let base = (personFile(person) as NSString).lastPathComponent
        return (find(base), editedBase(person).flatMap(find))
    }

    /// File name of a person's edit; it changes with the instruction, so a new instruction makes a new edit
    private static func editedBase(_ person: StoryPerson) -> String? {
        guard let edit = person.edit?.trimmingCharacters(in: .whitespacesAndNewlines), !edit.isEmpty else { return nil }
        let hash = edit.utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return ((personFile(person) as NSString).lastPathComponent) + "-edit-\(hash % 100_000)"
    }

    /// Has Codex edit the person's downloaded photo per their instruction and cuts the result out.
    static func editPerson(_ post: ContentPost, _ person: StoryPerson) async throws {
        guard let original = personPhotos(post, person).original, let base = editedBase(person), let edit = person.edit else { return }
        let dir = Paths.post(post.id).appendingPathComponent("people")
        let saved = try await CodexImage.edit(photo: Paths.post(post.id).appendingPathComponent(original.photo), name: person.name, instruction: edit, to: dir.appendingPathComponent(base))
        _ = await PhotoService.cutout(saved, to: dir.appendingPathComponent("\(base)-cut.png"))
    }

    /// Downloads a photo of each person in the storyboard and cuts them out of the background.
    /// Ones that can't be found are skipped (the video shows them without a photo).
    static func downloadPeople(_ post: ContentPost) async {
        let dir = Paths.ensure(Paths.post(post.id).appendingPathComponent("people"))
        for person in post.directed?.storyboard.people ?? [] where personPhotos(post, person).original == nil {
            var sources = [person.url].compactMap { $0.flatMap(URL.init(string:)) }
            if let wiki = person.wiki, let image = await wikipediaImage(wiki) { sources.append(image) }
            let base = dir.appendingPathComponent((personFile(person) as NSString).lastPathComponent)
            for url in sources where url.scheme == "https" || url.scheme == "http" {
                guard let (data, resp) = try? await fetch(url), (resp as? HTTPURLResponse)?.statusCode == 200,
                      let saved = PhotoService.normalize(data, to: base) else { continue }
                _ = await PhotoService.cutout(saved, to: URL(fileURLWithPath: base.path + "-cut.png"))
                break
            }
        }
    }

    // MARK: Uploaded images

    /// Images the user added to the post: name → file and its cut-out
    static func uploadFiles(_ post: ContentPost) -> [(String, String, String?)] {
        let dir = Paths.post(post.id).appendingPathComponent("uploads")
        return (post.uploads ?? []).compactMap { name in
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) else { return nil }
            let cut = "\((name as NSString).deletingPathExtension)-cut.png"
            return (name, "uploads/\(name)", FileManager.default.fileExists(atPath: dir.appendingPathComponent(cut).path) ? "uploads/\(cut)" : nil)
        }
    }

    /// Saves an image the user added into the post's uploads (resized and upright) and makes its cut-out; returns its file name.
    static func addUpload(_ data: Data, to postId: UUID) async -> String? {
        let dir = Paths.ensure(Paths.post(postId).appendingPathComponent("uploads"))
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var n = 1
        while existing.contains(where: { ($0 as NSString).deletingPathExtension == "image-\(n)" }) { n += 1 }
        guard let saved = PhotoService.normalize(data, to: dir.appendingPathComponent("image-\(n)")) else { return nil }
        _ = await PhotoService.cutout(saved, to: dir.appendingPathComponent("image-\(n)-cut.png"))
        return saved.lastPathComponent
    }

    private static func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url, timeoutInterval: 20)
        // Some hosts (e.g. Wikimedia) refuse requests without a user agent
        req.setValue("PromoStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: req)
    }

    /// Lead image of an English Wikipedia article: for clubs, leagues and brands their crest or logo, for people their photo.
    /// Without one, the image Wikidata has for the article's item (P18, on Wikimedia Commons).
    private static func wikipediaImage(_ title: String) async -> URL? {
        let path = title.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])),
              let api = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
              let (data, resp) = try? await fetch(api), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let image = (json["originalimage"] as? [String: Any])?["source"] ?? (json["thumbnail"] as? [String: Any])?["source"]
        if let url = (image as? String).flatMap(URL.init(string:)) { return url }
        guard let item = json["wikibase_item"] as? String else { return nil }
        return await wikidataImage(item)
    }

    private static func wikidataImage(_ item: String) async -> URL? {
        guard let api = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(item).json"),
              let (data, resp) = try? await fetch(api), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entity = (json["entities"] as? [String: Any])?[item] as? [String: Any],
              let claims = (entity["claims"] as? [String: Any])?["P18"] as? [[String: Any]],
              let file = ((claims.first?["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"] as? String,
              let name = file.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) else { return nil }
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(name)?width=1800")
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
              return {fps: p.fps, durationInFrames: p.durationInFrames, width: p.width ?? 1080, height: p.height ?? 1920};
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

    /// Renders an image post's picture (its last frame) into the post folder; it is also the post's cover.
    /// Renders the last frame of each scene: the picture, or a carousel's slides in order. Returns the files written.
    static func renderImage(post: ContentPost, onProgress: @escaping @Sendable (Double, String) -> Void) async throws -> [String] {
        guard let directed = post.directed else { throw StudioError.noStoryboard }
        let id = directed.compositionId
        guard hasCode(id) else { throw StudioError.noCode }
        try writeEntry(id)
        let count = max(1, directed.storyboard.scenes.count)
        let fm = FileManager.default
        // Slides of an earlier, longer carousel would linger
        for file in (try? fm.contentsOfDirectory(atPath: Paths.post(post.id).path)) ?? [] where file.hasPrefix("image") && file.hasSuffix(".jpg") {
            try? fm.removeItem(at: Paths.post(post.id).appendingPathComponent(file))
        }
        var images: [String] = []
        for i in 0..<count {
            let image = i == 0 ? "image.jpg" : "image-\(i + 1).jpg"
            let out = Paths.post(post.id).appendingPathComponent(image)
            onProgress(0.1 + 0.9 * Double(i) / Double(count), count > 1 ? String(localized: "Rendering slide \(i + 1) of \(count)…") : String(localized: "Rendering the image…"))
            try await ProcessRunner.run(
                Paths.remotion.appendingPathComponent("node_modules/.bin/remotion").path,
                ["still", "src/entries/\(id).tsx", id, out.path, "--props=\(propsFile(post.id).path)", "--frame=\(imageFrames * (i + 1) - 1)", "--image-format=jpeg", "--jpeg-quality=95"],
                cwd: Paths.remotion
            )
            guard fm.fileExists(atPath: out.path) else { throw RemotionError.noOutput }
            images.append(image)
        }
        onProgress(1, String(localized: "Done"))
        return images
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
