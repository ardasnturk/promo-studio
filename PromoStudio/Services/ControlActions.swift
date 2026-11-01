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
        func analysis(_ p: AppProject) throws -> ProjectAnalysis {
            guard let a = p.analysis else { throw ActionError.failed(String(localized: "The project hasn't been analyzed yet; analyze it first.")) }
            return a
        }
        func created(_ id: UUID?) throws -> (Int, [String: Any]) {
            guard let id else { throw ActionError.failed(String(localized: "Couldn't create the post")) }
            return (202, ["ok": true, "postId": id.uuidString, "jobId": id.uuidString])
        }
        let accepted: (UUID) -> (Int, [String: Any]) = { (202, ["ok": true, "jobId": $0.uuidString]) }

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
            let p = try project(), a = try analysis(p)
            let brief = PostBrief(prompt: try require("prompt"), research: bool("research", true))
            return try created(model.createDirectedPost(projectId: p.id, feature: a.features.first { $0.id == str("featureId") }, seconds: int("seconds", 20), language: str("language"), brief: brief, voiceover: bool("voiceover", model.settings.voiceoverEnabled), style: str("style").flatMap(DirectedStyle.init(rawValue:)) ?? .promo))
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
            return ok
        case "rewriteCaption":
            let p = try post()
            model.rewriteCaption(p.id, instruction: str("instruction") ?? "")
            return accepted(p.id)
        case "render":
            let p = try post()
            model.render(p.id)
            return accepted(p.id)
        case "cancel":
            model.cancel(try uuid("id"))
            return ok
        case "deletePost":
            model.deletePost(try post().id)
            return ok

        // MARK: Posting
        case "publish":
            let p = try post()
            guard p.videoFile != nil else { throw ActionError.failed(String(localized: "Render the video first")) }
            model.queuePublish(p.id)
            return accepted(p.id)
        case "schedule":
            let p = try post()
            guard let at = ISO8601DateFormatter().date(from: try require("at")) else { throw ActionError.missing("at") }
            model.schedule(p.id, at: at)
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
            guard let url = InstagramAPI.authorizeURL(mode: s.loginMode, appId: s.metaAppId, redirectURI: s.redirectURI, graphVersion: s.graphVersion) else {
                throw ActionError.failed(String(localized: "Couldn't create the login URL"))
            }
            return (200, ["ok": true, "mode": s.loginMode.rawValue, "authorizeURL": url.absoluteString, "redirectURI": s.redirectURI])
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
        case "dismissAlert":
            model.alert = nil
            model.notice = nil
            return ok
        default:
            throw ActionError.unknown(name)
        }
    }
}
