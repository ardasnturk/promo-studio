import Foundation

/// `POST /v1/actions/<name>` operations of the control API (docs/CONTROL_API.md). Calls into AppModel.
@MainActor
enum ControlActions {
    enum ActionError: LocalizedError {
        case missing(String)
        case notFound(String)
        case unknown(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case let .missing(field): String(localized: "Missing field: \(field)")
            case let .notFound(what): String(localized: "\(what) not found")
            case let .unknown(name): String(localized: "Unknown action: \(name)")
            case let .failed(message): message
            }
        }
    }

    static func perform(_ name: String, body: [String: Any], model: AppModel) async throws -> (Int, [String: Any]) {
        let ok: (Int, [String: Any]) = (200, ["ok": true])
        func str(_ key: String) -> String? { (body[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        func require(_ key: String) throws -> String {
            guard let v = str(key), !v.isEmpty else { throw ActionError.missing(key) }
            return v
        }
        func uuid(_ key: String) throws -> UUID {
            guard let id = UUID(uuidString: try require(key)) else { throw ActionError.missing(key) }
            return id
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { body[key] as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { (body[key] as? NSNumber)?.intValue ?? fallback }
        func project() throws -> AppProject {
            let id = try uuid("projectId")
            guard let p = model.project(id) else { throw ActionError.notFound(String(localized: "Project")) }
            return p
        }
        func post() throws -> ContentPost {
            let id = try uuid("postId")
            guard let p = model.post(id) else { throw ActionError.notFound(String(localized: "Post")) }
            return p
        }
        func optionalProject() throws -> AppProject? {
            guard let raw = str("projectId"), !raw.isEmpty else { return nil }
            return try project()
        }
        /// Instagram account chosen for a post (nil: the project's; "-": not to Instagram)
        func accountId() throws -> String? {
            guard let id = str("accountId"), !id.isEmpty else { return nil }
            if id == AppModel.noInstagram { return id }
            guard model.account(id) != nil else { throw ActionError.notFound(String(localized: "Account")) }
            return id
        }
        func analysis(_ p: AppProject) throws -> ProjectAnalysis {
            guard let a = p.analysis else { throw ActionError.failed(String(localized: "The project hasn't been analyzed yet; analyze it first.")) }
            return a
        }
        func created(_ id: UUID?) throws -> (Int, [String: Any]) {
            guard let id else { throw ActionError.failed(String(localized: "Couldn't create the post")) }
            return (202, ["ok": true, "postId": id.uuidString, "jobId": id.uuidString])
        }
        let accepted: (UUID) -> (Int, [String: Any]) = { (202, ["ok": true, "jobId": $0.uuidString]) }
        let placement = str("placement").flatMap(PostPlacement.init(rawValue:))
        /// `plan`: {runAt, autoApprove?, autoPublish?}, to make the post at that time instead of now
        func plan() throws -> CreationPlan? {
            guard let plan = body["plan"] as? [String: Any] else { return nil }
            guard let at = (plan["runAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) else { throw ActionError.missing("runAt") }
            return CreationPlan(runAt: at, autoApprove: plan["autoApprove"] as? Bool ?? false, autoPublish: plan["autoPublish"] as? Bool ?? false)
        }

        switch name {
        // MARK: Production
        case "createPost":
            let p = try project(), a = try analysis(p)
            let feature = a.features.first { $0.id == str("featureId") }
            let suggestion = a.suggestions.first { $0.id == str("suggestionId") }
            let theme = str("theme").flatMap(VideoTheme.init(rawValue:)) ?? suggestion?.theme ?? model.settings.defaultTheme
            return try created(model.createPost(projectId: p.id, feature: feature, suggestion: suggestion, theme: theme, seconds: int("seconds", 15), notes: str("notes") ?? "", autoRender: bool("autoRender", true), language: str("language")))
        case "createScriptPost":
            let p = try project(), a = try analysis(p)
            let brief = PostBrief(prompt: try require("prompt"), research: bool("research", true))
            let theme = str("theme").flatMap(VideoTheme.init(rawValue:)) ?? model.settings.defaultTheme
            return try created(model.createPost(projectId: p.id, feature: a.features.first { $0.id == str("featureId") }, suggestion: nil, theme: theme, seconds: int("seconds", 15), notes: "", autoRender: false, language: str("language"), brief: brief))
        case "createDirectedPost":
            // Without projectId: a standalone video (always free-form). format "image": an image post of `size`.
            // uploads: IDs from uploadImage, images for Claude to look at and use
            let p = try optionalProject(), a = try p.map(analysis)
            let uploads = try (body["uploads"] as? [String] ?? []).map { id in
                guard let data = UploadStaging.take(id) else { throw ActionError.notFound(String(localized: "Uploaded image")) }
                return data
            }
            let prompt = str("prompt").flatMap { $0.isEmpty ? nil : $0 } ?? (uploads.isEmpty ? nil : String(localized: "Make it from my images."))
            guard let prompt else { throw ActionError.missing("prompt") }
            let brief = PostBrief(prompt: prompt, research: bool("research", true))
            let image = str("format") == "image" ? str("size").flatMap(ImageSize.init(rawValue:)) ?? .portrait : nil
            let id = model.createDirectedPost(projectId: p?.id, feature: a?.features.first { $0.id == str("featureId") }, seconds: int("seconds", 20), language: str("language"), brief: brief, voiceover: bool("voiceover", model.settings.voiceoverEnabled), style: str("style").flatMap(DirectedStyle.init(rawValue:)) ?? .promo, accountId: try accountId(), image: image, slides: int("slides", 1), uploads: uploads, plan: try plan())
            if let id, let placement { model.setPlacement(placement, forPost: id) }
            return try created(id)
        case "uploadImage":
            // An image for a new post, sent ahead (base64, at most a few MB); returns its uploadId
            guard let raw = body["data"] as? String, let data = Data(base64Encoded: raw), !data.isEmpty else { throw ActionError.missing("data") }
            return (200, ["ok": true, "uploadId": try UploadStaging.put(data)])
        case "produce":
            let p = try post()
            guard p.directed != nil else { throw ActionError.failed(String(localized: "This post isn't a promo film")) }
            model.produce(p.id, voiceover: bool("voiceover", true))
            return accepted(p.id)
        case "revise":
            let p = try post(), instruction = try require("instruction")
            if p.directed != nil {
                model.reviseDirected(p.id, instruction: instruction, renderAfter: bool("renderAfter", true))
            } else {
                model.reviseScript(p.id, instruction: instruction, renderAfter: bool("renderAfter", false))
            }
            return accepted(p.id)
        case "restoreRevision":
            let p = try post(), rid = try uuid("revisionId")
            model.restoreRevision(p.id, revisionId: rid)
            return ok
        case "updatePost":
            let p = try post()
            var board: Storyboard?
            if let raw = body["storyboard"] {
                let data = try JSONSerialization.data(withJSONObject: raw)
                board = try JSONDecoder().decode(Storyboard.self, from: data)
            }
            model.updatePost(p.id) { q in
                if let v = str("title") { q.title = v }
                if let v = body["caption"] as? String { q.caption = v }
                if let v = body["hashtags"] as? [String] { q.hashtags = v.map { $0.replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty } }
                if let v = body["altText"] as? String { q.altText = v }
                if let board { q.directed?.storyboard = board }
            }
            // accountId: an account's userId, or "" / null for the project's account
            if body.keys.contains("accountId") {
                model.setAccount(try accountId(), forPost: p.id)
            }
            if let v = body["youtubeTitle"] as? String { model.updatePost(p.id) { $0.youtubeTitle = v } }
            // youtubeChannelId: a channel's ID, "" for not to YouTube, null for the default in Settings
            if body.keys.contains("youtubeChannelId") {
                let id = body["youtubeChannelId"] as? String
                if let id, !id.isEmpty, model.channel(id) == nil { throw ActionError.notFound(String(localized: "Channel")) }
                model.setYouTubeChannel(id, forPost: p.id)
            }
            return ok
        case "writeYouTubeTitle":
            let p = try post()
            model.writeYouTubeTitle(p.id)
            return accepted(p.id)
        case "forgetYouTubeUpload":
            model.forgetYouTubeUpload(try post().id)
            return ok
        case "rewriteCaption":
            let p = try post()
            model.rewriteCaption(p.id, instruction: str("instruction") ?? "")
            return accepted(p.id)
        case "render":
            let p = try post()
            model.render(p.id)
            return accepted(p.id)
        case "setCover":
            let p = try post()
            guard p.videoFile != nil else { throw ActionError.failed(String(localized: "Render the video first")) }
            guard let sec = (body["sec"] as? NSNumber)?.doubleValue, sec >= 0 else { throw ActionError.missing("sec") }
            await model.setCover(p.id, at: sec)
            return ok
        case "cancel":
            model.cancel(try uuid("id"))
            return ok
        case "updatePlan":
            let p = try post()
            guard p.isPlanned else { throw ActionError.failed(String(localized: "This post has already started")) }
            var runAt: Date?
            if let at = str("runAt") {
                guard let date = ISO8601DateFormatter().date(from: at) else { throw ActionError.missing("runAt") }
                runAt = date
            }
            model.updatePlan(p.id, request: str("request"), runAt: runAt, autoApprove: body["autoApprove"] as? Bool, autoPublish: body["autoPublish"] as? Bool)
            if let placement { model.setPlacement(placement, forPost: p.id) }
            return ok
        case "startPlan":
            let p = try post()
            guard p.isPlanned else { throw ActionError.failed(String(localized: "This post has already started")) }
            model.startPlan(p.id)
            return accepted(p.id)
        case "deletePost":
            model.deletePost(try post().id)
            return ok

        // MARK: Posting
        case "publish":
            // placement: "feed" (a Reel, photo or carousel) or "story"; left out, the post's own
            let p = try post()
            if p.isImage {
                guard !p.imageFiles.isEmpty else { throw ActionError.failed(String(localized: "Create the image first")) }
                guard PublicLink.isInstalled else { throw ActionError.failed(String(localized: "Posting pictures needs cloudflared on the Mac: install it from the setup checklist.")) }
            } else {
                guard p.videoFile != nil else { throw ActionError.failed(String(localized: "Render the video first")) }
            }
            if let placement = str("placement").flatMap(PostPlacement.init(rawValue:)) { model.setPlacement(placement, forPost: p.id) }
            model.queuePublish(p.id)
            return accepted(p.id)
        case "schedule":
            let p = try post()
            guard let at = ISO8601DateFormatter().date(from: try require("at")) else { throw ActionError.missing("at") }
            if let placement = str("placement").flatMap(PostPlacement.init(rawValue:)) { model.setPlacement(placement, forPost: p.id) }
            model.schedule(p.id, at: at)
            return ok
        case "setPlacement":
            let p = try post()
            guard let placement = PostPlacement(rawValue: try require("placement")) else { throw ActionError.missing("placement") }
            model.setPlacement(placement, forPost: p.id)
            return ok
        case "unschedule":
            model.unschedule(try post().id)
            return ok
        case "refreshMetrics":
            model.refreshMetrics()
            return ok

        // MARK: Projects and accounts
        case "analyze":
            let p = try project()
            model.analyze(p.id)
            return accepted(p.id)
        case "setAccount":
            let p = try project()
            model.setAccount(str("accountId"), for: p.id)
            return ok
        case "loginInfo":
            let s = model.settings
            guard !s.metaAppId.isEmpty else { throw ActionError.failed(String(localized: "No Meta App ID is set in Promo Studio on the Mac (Account & Settings).")) }
            guard let url = InstagramAPI.authorizeURL(mode: s.loginMode, appId: s.metaAppId, redirectURI: s.redirectURI, graphVersion: s.graphVersion, configId: s.facebookConfigId) else {
                throw ActionError.failed(String(localized: "Couldn't create the login URL"))
            }
            // Unified Login (configuration ID) returns a ?code= like Instagram login, so clients handle it the same way
            let callbackMode = s.loginMode == .facebook && s.facebookConfigId.isEmpty ? "facebook" : "instagram"
            return (200, ["ok": true, "mode": callbackMode, "authorizeURL": url.absoluteString, "redirectURI": s.redirectURI])
        case "connectToken":
            let token = try require("token")
            let expires = (body["expiresIn"] as? NSNumber)?.intValue
            Task { await model.connect(withToken: token, expiresIn: expires) }
            return (202, ["ok": true])
        case "connectCode":
            let code = try require("code")
            Task { await model.connect(withCode: code) }
            return (202, ["ok": true])
        case "refreshAccounts":
            Task { await model.refreshAccounts() }
            return (202, ["ok": true])
        case "disconnect":
            model.disconnect(try require("accountId"))
            return ok
        // MARK: Template libraries
        case "generateFromSkill":
            let id = try uuid("libraryId")
            guard let lib = model.library(id) else { throw ActionError.notFound(String(localized: "Library")) }
            let skill = try require("skill")
            guard lib.skills.contains(where: { $0.name == skill }) else { throw ActionError.notFound(String(localized: "Template")) }
            let post = model.generateFromSkill(libraryId: id, skill: skill, request: str("request") ?? "", projectId: try optionalProject()?.id, accountId: try accountId(), plan: try plan())
            if let post, let placement { model.setPlacement(placement, forPost: post) }
            return try created(post)
        case "generateIdeas":
            let id = try uuid("libraryId")
            guard model.library(id) != nil else { throw ActionError.notFound(String(localized: "Library")) }
            model.generateIdeas(libraryId: id, focus: str("focus") ?? "")
            return accepted(id)
        case "createTemplate":
            let id = try uuid("libraryId")
            guard model.library(id) != nil else { throw ActionError.notFound(String(localized: "Library")) }
            model.createTemplate(libraryId: id, prompt: try require("prompt"))
            return accepted(id)
        // MARK: Fixing failures
        case "fix":
            // The fix of the post's (or the alert's) failure: retry, repair or withoutVoiceover
            guard let fix = str("fix").flatMap(Problem.Fix.init(rawValue:)) else { throw ActionError.missing("fix") }
            let p = try post()
            var problem = p.problem ?? Problem(message: p.lastError ?? "")
            problem.subject = p.id
            model.apply(fix, to: problem)
            return accepted(p.id)
        case "setPersonPhoto":
            // Which photo of a person the video uses: the downloaded one (useOriginal) or Codex's edit
            let p = try post(), name = try require("name")
            guard p.directed?.storyboard.people?.contains(where: { $0.name == name }) == true else { throw ActionError.notFound(name) }
            model.setUseOriginalPhoto(bool("useOriginal", false), name: name, postId: p.id)
            return ok
        case "editPersonPhoto":
            // Codex edits the person's photo again; `instruction` (optional) replaces Claude's
            let p = try post(), name = try require("name")
            guard p.directed?.storyboard.people?.contains(where: { $0.name == name }) == true else { throw ActionError.notFound(name) }
            guard CodexImage.isInstalled else { throw ActionError.failed(String(localized: "Codex isn’t installed on the Mac. Install it and sign in with your ChatGPT account to edit photos.")) }
            model.editPersonPhoto(name: name, postId: p.id, instruction: str("instruction"))
            return accepted(p.id)
        case "checkHealth":
            await model.refreshRequirements()
            return ok
        case "dismissAlert":
            model.alert = nil
            model.notice = nil
            return ok
        default:
            throw ActionError.unknown(name)
        }
    }
}

/// Images the phone sends before the post exists (one request each, to stay under the relay's message size).
/// They wait in a folder until createDirectedPost takes them; leftovers older than a day are removed.
enum UploadStaging {
    private static var dir: URL { Paths.ensure(Paths.root.appendingPathComponent("uploads")) }

    static func put(_ data: Data) throws -> String {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let url = dir.appendingPathComponent(name)
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, date.timeIntervalSinceNow < -86400 {
                try? fm.removeItem(at: url)
            }
        }
        let id = UUID().uuidString
        try data.write(to: dir.appendingPathComponent(id))
        return id
    }

    static func take(_ id: String) -> Data? {
        guard UUID(uuidString: id) != nil else { return nil }
        let url = dir.appendingPathComponent(id)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }
}
