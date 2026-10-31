import Foundation

enum InstagramError: LocalizedError {
    case notConnected
    case missingConfig(String)
    case api(String)
    case processingFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "No Instagram account is connected.")
        case let .missingConfig(what): String(localized: "Missing setting: \(what)")
        case let .api(msg): "Instagram API: \(msg)"
        case let .processingFailed(msg): String(localized: "Instagram couldn't process the video: \(msg)")
        case .timeout: String(localized: "Instagram video processing timed out.")
        }
    }
}

/// Instagram Graph API client. Supports two connection types:
/// - `.facebook`: graph.facebook.com, the Instagram account must be linked to a Facebook Page
/// - `.instagram`: graph.instagram.com ("Instagram API with Instagram Login")
/// Both require a Business/Creator account.
struct InstagramAPI {
    var graphVersion: String
    var token: String
    var mode: InstagramLoginMode = .instagram

    static func scopes(for mode: InstagramLoginMode) -> [String] {
        switch mode {
        case .instagram:
            [
                "instagram_business_basic",
                "instagram_business_content_publish",
                "instagram_business_manage_insights",
                "instagram_business_manage_comments",
            ]
        case .facebook:
            [
                "instagram_basic",
                "instagram_content_publish",
                "instagram_manage_insights",
                "instagram_manage_comments",
                "pages_show_list",
                "pages_read_engagement",
                "business_management",
            ]
        }
    }

    private var base: String {
        mode == .facebook ? "https://graph.facebook.com/\(graphVersion)" : "https://graph.instagram.com/\(graphVersion)"
    }

    // MARK: OAuth

    static func authorizeURL(mode: InstagramLoginMode, appId: String, redirectURI: String, graphVersion: String) -> URL? {
        var c: URLComponents?
        switch mode {
        case .instagram:
            c = URLComponents(string: "https://www.instagram.com/oauth/authorize")
            c?.queryItems = [.init(name: "enable_fb_login", value: "0")]
        case .facebook:
            c = URLComponents(string: "https://www.facebook.com/\(graphVersion)/dialog/oauth")
            c?.queryItems = []
        }
        c?.queryItems? += [
            .init(name: "client_id", value: appId),
            .init(name: "redirect_uri", value: redirectURI),
            // With Facebook the token comes back directly in the redirect URL's #fragment; no App Secret needed.
            .init(name: "response_type", value: mode == .facebook ? "token" : "code"),
            .init(name: "scope", value: scopes(for: mode).joined(separator: ",")),
        ]
        return c?.url
    }

    /// Facebook Login: exchanges the authorization code for a long-lived (≈60 day) user token.
    static func exchangeFacebookCode(_ code: String, appId: String, appSecret: String, redirectURI: String, graphVersion: String) async throws -> (token: String, expiresIn: Int) {
        var c = URLComponents(string: "https://graph.facebook.com/\(graphVersion)/oauth/access_token")!
        c.queryItems = [
            .init(name: "client_id", value: appId),
            .init(name: "client_secret", value: appSecret),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code", value: code),
        ]
        let json = try await send(URLRequest(url: c.url!))
        guard let short = json["access_token"] as? String else { throw InstagramError.api(String(localized: "Couldn't get a token")) }
        return try await facebookLongLived(short, appId: appId, appSecret: appSecret, graphVersion: graphVersion)
    }

    /// Exchanges a Facebook user token for a long-lived token. Called with a long-lived token, it extends its expiry.
    static func facebookLongLived(_ token: String, appId: String, appSecret: String, graphVersion: String) async throws -> (token: String, expiresIn: Int) {
        var c = URLComponents(string: "https://graph.facebook.com/\(graphVersion)/oauth/access_token")!
        c.queryItems = [
            .init(name: "grant_type", value: "fb_exchange_token"),
            .init(name: "client_id", value: appId),
            .init(name: "client_secret", value: appSecret),
            .init(name: "fb_exchange_token", value: token),
        ]
        let json = try await send(URLRequest(url: c.url!))
        guard let long = json["access_token"] as? String else { throw InstagramError.api(String(localized: "Couldn't get a long-lived token")) }
        return (long, json["expires_in"] as? Int ?? 5_184_000)
    }

    /// Exchanges the authorization code for a 60-day long-lived token.
    static func exchangeCode(_ code: String, appId: String, appSecret: String, redirectURI: String) async throws -> (token: String, expiresIn: Int) {
        var req = URLRequest(url: URL(string: "https://api.instagram.com/oauth/access_token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody([
            "client_id": appId,
            "client_secret": appSecret,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
            "code": code.replacingOccurrences(of: "#_", with: ""),
        ])
        let short = try await send(req)
        guard let shortToken = short["access_token"] as? String else { throw InstagramError.api(String(localized: "Couldn't get a short-lived token")) }

        var c = URLComponents(string: "https://graph.instagram.com/access_token")!
        c.queryItems = [
            .init(name: "grant_type", value: "ig_exchange_token"),
            .init(name: "client_secret", value: appSecret),
            .init(name: "access_token", value: shortToken),
        ]
        let long = try await send(URLRequest(url: c.url!))
        guard let token = long["access_token"] as? String else { throw InstagramError.api(String(localized: "Couldn't get a long-lived token")) }
        return (token, long["expires_in"] as? Int ?? 5_184_000)
    }

    func refreshToken() async throws -> (token: String, expiresIn: Int) {
        var c = URLComponents(string: "https://graph.instagram.com/refresh_access_token")!
        c.queryItems = [.init(name: "grant_type", value: "ig_refresh_token"), .init(name: "access_token", value: token)]
        let json = try await Self.send(URLRequest(url: c.url!))
        guard let t = json["access_token"] as? String else { throw InstagramError.api(String(localized: "Couldn't refresh the token")) }
        return (t, json["expires_in"] as? Int ?? 5_184_000)
    }

    // MARK: Account

    /// All Instagram professional accounts this token can access.
    /// With Facebook Login, the account of every Page the user manages; with Instagram Login, the token's own account.
    func allAccounts() async throws -> [InstagramAccount] {
        var accounts = mode == .facebook ? try await facebookAccounts() : [try await me()]
        for i in accounts.indices { accounts[i].loginMode = mode }
        return accounts
    }

    func me() async throws -> InstagramAccount {
        if mode == .facebook {
            guard let first = try await facebookAccounts().first else { throw InstagramError.api(String(localized: "No account found")) }
            return first
        }
        let json = try await get("me", ["fields": "user_id,username,name,profile_picture_url,followers_count,media_count"])
        guard let userId = (json["user_id"] as? String) ?? (json["id"] as? String),
              let username = json["username"] as? String else { throw InstagramError.api(String(localized: "Couldn't read the profile")) }
        return InstagramAccount(
            userId: userId,
            username: username,
            name: json["name"] as? String,
            profilePictureURL: json["profile_picture_url"] as? String,
            followers: json["followers_count"] as? Int,
            mediaCount: json["media_count"] as? Int
        )
    }

    /// With Facebook Login, Instagram accounts are professional accounts linked to Facebook Pages the user can access.
    /// Pages can belong directly to the user (`me/accounts`) or to a Business portfolio; both are checked.
    private func facebookAccounts() async throws -> [InstagramAccount] {
        let igFields = "name,instagram_business_account{id,username,name,profile_picture_url,followers_count,media_count}"
        var pages = (try await get("me/accounts", ["fields": igFields, "limit": "100"])["data"] as? [[String: Any]]) ?? []

        var businessNames: [String] = []
        let businesses = (try? await get("me/businesses", ["fields": "id,name"]))?["data"] as? [[String: Any]] ?? []
        for b in businesses {
            guard let id = b["id"] as? String else { continue }
            businessNames.append(b["name"] as? String ?? id)
            for edge in ["owned_pages", "client_pages"] {
                if let more = (try? await get("\(id)/\(edge)", ["fields": igFields, "limit": "100"]))?["data"] as? [[String: Any]] {
                    pages += more
                }
            }
        }

        var seen = Set<String>()
        let accounts: [InstagramAccount] = pages.compactMap { page in
            guard let ig = page["instagram_business_account"] as? [String: Any],
                  let id = ig["id"] as? String, seen.insert(id).inserted else { return nil }
            return InstagramAccount(
                userId: id,
                username: ig["username"] as? String ?? "",
                name: (ig["name"] as? String) ?? (page["name"] as? String),
                profilePictureURL: ig["profile_picture_url"] as? String,
                followers: ig["followers_count"] as? Int,
                mediaCount: ig["media_count"] as? Int,
                pageName: page["name"] as? String
            )
        }
        guard !accounts.isEmpty else { throw InstagramError.api(await diagnosis(pages: pages, businesses: businessNames)) }
        return accounts
    }

    /// Tells the user concretely what is missing when the connection fails.
    private func diagnosis(pages: [[String: Any]], businesses: [String]) async -> String {
        let perms = (try? await get("me/permissions", [:]))?["data"] as? [[String: Any]] ?? []
        let granted = Set(perms.filter { $0["status"] as? String == "granted" }.compactMap { $0["permission"] as? String })
        let missing = Self.scopes(for: .facebook).filter { !granted.contains($0) }
        var lines: [String] = []
        if pages.isEmpty {
            lines.append(String(localized: "The token can't see any Facebook Pages."))
            lines.append(String(localized: "During login, at the \"Select Pages\" step, select the Page your Instagram account is linked to. If you have no Facebook Page, create one first and link your Instagram account to it."))
        } else {
            let names = pages.compactMap { $0["name"] as? String }.joined(separator: ", ")
            lines.append(String(localized: "The accessible Pages (\(names)) aren't linked to an Instagram professional account. Link your Instagram account to one of these Pages."))
        }
        if !businesses.isEmpty { lines.append(String(localized: "Business portfolios scanned: \(businesses.joined(separator: ", ")).")) }
        if !missing.isEmpty { lines.append(String(localized: "Permissions not granted: \(missing.joined(separator: ", ")).")) }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Reels posting (resumable upload — the video doesn't need to be at a public URL)

    func publishReel(
        userId: String,
        videoURL: URL,
        caption: String,
        coverOffsetMs: Int? = nil,
        onStatus: @Sendable (String) -> Void = { _ in }
    ) async throws -> (mediaId: String, permalink: String?) {
        onStatus(String(localized: "Creating container…"))
        var params: [String: String] = [
            "media_type": "REELS",
            "upload_type": "resumable",
            "caption": caption,
            "share_to_feed": "true",
        ]
        if let coverOffsetMs { params["thumb_offset"] = String(coverOffsetMs) }
        let container = try await post("\(userId)/media", params)
        guard let containerId = container["id"] as? String else { throw InstagramError.api(String(localized: "No container ID")) }

        onStatus(String(localized: "Uploading video…"))
        let data = try Data(contentsOf: videoURL)
        let uploadURL = (container["uri"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://rupload.facebook.com/ig-api-upload/\(graphVersion)/\(containerId)")!
        var up = URLRequest(url: uploadURL)
        up.httpMethod = "POST"
        up.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        up.setValue("0", forHTTPHeaderField: "offset")
        up.setValue(String(data.count), forHTTPHeaderField: "file_size")
        up.timeoutInterval = 600
        let (upData, upResp) = try await URLSession.shared.upload(for: up, from: data)
        if let http = upResp as? HTTPURLResponse, http.statusCode >= 300 {
            throw InstagramError.api(String(localized: "Upload error (\(http.statusCode)): \(String(decoding: upData, as: UTF8.self))"))
        }

        onStatus(String(localized: "Instagram is processing the video…"))
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            let s = try await get(containerId, ["fields": "status_code,status"])
            switch s["status_code"] as? String {
            case "FINISHED":
                onStatus(String(localized: "Publishing…"))
                let published = try await post("\(userId)/media_publish", ["creation_id": containerId])
                guard let mediaId = published["id"] as? String else { throw InstagramError.api(String(localized: "No media ID")) }
                let info = try? await get(mediaId, ["fields": "permalink"])
                return (mediaId, info?["permalink"] as? String)
            case "ERROR", "EXPIRED":
                throw InstagramError.processingFailed(s["status"] as? String ?? "bilinmeyen")
            default:
                continue
            }
        }
        throw InstagramError.timeout
    }

    // MARK: Insights

    func mediaMetrics(_ mediaId: String) async throws -> PostMetrics {
        var m = PostMetrics()
        if let basic = try? await get(mediaId, ["fields": "like_count,comments_count"]) {
            m.likes = basic["like_count"] as? Int
            m.comments = basic["comments_count"] as? Int
        }
        let insights = try await get("\(mediaId)/insights", ["metric": "views,reach,likes,comments,shares,saved"])
        for item in insights["data"] as? [[String: Any]] ?? [] {
            let value = (item["values"] as? [[String: Any]])?.first?["value"] as? Int
            switch item["name"] as? String {
            case "views": m.views = value
            case "reach": m.reach = value
            case "likes": m.likes = value ?? m.likes
            case "comments": m.comments = value ?? m.comments
            case "shares": m.shares = value
            case "saved": m.saved = value
            default: break
            }
        }
        return m
    }

    // MARK: HTTP

    private func get(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        var c = URLComponents(string: "\(base)/\(path)")!
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "access_token", value: token)]
        return try await Self.send(URLRequest(url: c.url!))
    }

    private func post(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "\(base)/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var p = params
        p["access_token"] = token
        req.httpBody = Self.formBody(p)
        return try await Self.send(req)
    }

    private static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let s = params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        return Data(s.utf8)
    }

    private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = json["error"] as? [String: Any] {
            throw InstagramError.api(err["message"] as? String ?? "\(err)")
        }
        if let err = json["error_message"] as? String { throw InstagramError.api(err) }
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw InstagramError.api("HTTP \(http.statusCode): \(String(decoding: data, as: UTF8.self).prefix(300))")
        }
        return json
    }
}
