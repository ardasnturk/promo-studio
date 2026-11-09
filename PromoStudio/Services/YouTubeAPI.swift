import AppKit
import CryptoKit
import Foundation
import Network

enum YouTubeError: LocalizedError {
    /// No OAuth client ID or secret in Settings
    case missingClient
    /// The channel isn't connected, or its sign-in was removed
    case notConnected
    /// Google no longer accepts the saved sign-in (revoked, or a week old while the Google app is in Testing)
    case expired
    case signIn(String)
    /// An error from the YouTube API: HTTP status, Google's reason code and message
    case api(status: Int, reason: String?, message: String)
    case uploadIncomplete

    var errorDescription: String? {
        switch self {
        case .missingClient: String(localized: "Enter the Google OAuth client ID and secret in Settings → YouTube.")
        case .notConnected: String(localized: "The YouTube channel isn’t connected. Connect it in Settings → YouTube.")
        case .expired: String(localized: "Google ended the YouTube sign-in. Connect the channel again in Settings → YouTube.")
        case let .signIn(message): String(localized: "The Google sign-in didn’t finish: \(message)")
        case let .api(status, reason, message): "YouTube API (\(status)\(reason.map { ", \($0)" } ?? "")): \(message)"
        case .uploadIncomplete: String(localized: "The upload to YouTube stopped before the whole video was sent.")
        }
    }
}

/// A YouTube channel the app can upload to (its refresh token is in the Keychain).
struct YouTubeChannel: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var handle: String?
    var thumbnailURL: String?

    var label: String { handle.map { "\(title) (\($0))" } ?? title }
}

/// What YouTube reports about an uploaded video's visibility.
struct YouTubeVideoStatus: Hashable {
    var privacy: String
    var publishAt: Date?
    var uploadStatus: String?
    /// Why YouTube rejected or failed the video, when it did
    var problem: String?
}

/// YouTube Data API v3 with an installed-app OAuth client (Google Cloud "Desktop app"). Sign-in runs in the default
/// browser with a one-time listener on 127.0.0.1 (Google doesn't allow sign-in inside an app's web view). Videos go up
/// with Google's resumable upload, so a dropped connection carries on where it stopped.
struct YouTubeAPI {
    var clientId: String
    var clientSecret: String
    var refreshToken: String

    static let scope = "https://www.googleapis.com/auth/youtube"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let api = "https://www.googleapis.com/youtube/v3"

    // MARK: Sign-in

    /// Opens Google's consent page in the browser and waits for its answer. Returns the refresh token and the channels
    /// of the account (the one chosen on the consent page).
    static func signIn(clientId: String, clientSecret: String) async throws -> (refreshToken: String, channels: [YouTubeChannel]) {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw YouTubeError.missingClient }
        let verifier = randomString(48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomString(24)
        let loopback = OAuthLoopback()
        let port = try await loopback.start()
        defer { loopback.stop() }
        let redirect = "http://127.0.0.1:\(port)"
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
        ]
        let consent = auth.url!
        await MainActor.run { _ = NSWorkspace.shared.open(consent) }
        let answer = try await loopback.answer(timeout: 600)
        if let error = answer["error"] { throw YouTubeError.signIn(error) }
        guard answer["state"] == state, let code = answer["code"] else { throw YouTubeError.signIn(String(localized: "Google’s answer didn’t match the request.")) }
        let json = try await tokenRequest([
            "code": code, "client_id": clientId, "client_secret": clientSecret,
            "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = json["refresh_token"] as? String, let access = json["access_token"] as? String else {
            throw YouTubeError.signIn(String(localized: "Google didn’t return a lasting sign-in."))
        }
        await TokenCache.shared.store(access, expiresIn: json["expires_in"] as? Double ?? 3600, for: refresh)
        let client = YouTubeAPI(clientId: clientId, clientSecret: clientSecret, refreshToken: refresh)
        return (refresh, try await client.myChannels())
    }

    /// Lets go of the sign-in on Google's side too (best effort).
    static func revoke(_ refreshToken: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["token": refreshToken])
        _ = try? await URLSession.shared.data(for: request)
    }

    func myChannels() async throws -> [YouTubeChannel] {
        let json = try await call("GET", "channels?part=snippet&mine=true")
        let items = json["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else {
            throw YouTubeError.api(status: 404, reason: "youtubeSignupRequired", message: String(localized: "This Google account has no YouTube channel."))
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let snippet = item["snippet"] as? [String: Any] else { return nil }
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let thumb = (thumbs?["default"] as? [String: Any])?["url"] as? String
            return YouTubeChannel(id: id, title: snippet["title"] as? String ?? id, handle: snippet["customUrl"] as? String, thumbnailURL: thumb)
        }
    }

    // MARK: Videos

    struct Metadata {
        var title: String
        var description: String
        var tags: [String]
        /// ContentLanguage code of the video's text and voice
        var language: String?
        /// The video shows realistic people or events that were made or changed with AI
        var synthetic: Bool
        /// nil: public right away; a date: private until YouTube publishes it then
        var publishAt: Date?
    }

    /// Uploads the video and returns its ID and the visibility YouTube gave it.
    func upload(_ file: URL, _ meta: Metadata, onStatus: @escaping @Sendable (String) -> Void) async throws -> (id: String, status: YouTubeVideoStatus) {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        onStatus(String(localized: "Starting the upload to YouTube…"))
        var body = Self.body(meta)
        let session: URL
        do {
            session = try await startUpload(body: body, size: data.count)
        } catch let YouTubeError.api(status, _, message) where status == 400 && message.lowercased().contains("language") {
            // A language code YouTube doesn't list: the video goes up without one
            var snippet = body["snippet"] as? [String: Any] ?? [:]
            snippet["defaultLanguage"] = nil
            snippet["defaultAudioLanguage"] = nil
            body["snippet"] = snippet
            session = try await startUpload(body: body, size: data.count)
        }
        let json = try await send(data, to: session, onStatus: onStatus)
        guard let id = json["id"] as? String else { throw YouTubeError.uploadIncomplete }
        return (id, Self.status(of: json))
    }

    /// Sets who can see the video: public now, or private until `publishAt` (YouTube publishes it then), or private.
    func setVisibility(_ videoId: String, privacy: String, publishAt: Date?, synthetic: Bool) async throws -> YouTubeVideoStatus {
        var status = Self.statusBody(privacy: privacy, publishAt: publishAt, synthetic: synthetic)
        if publishAt == nil { status["publishAt"] = nil }
        let json = try await call("PUT", "videos?part=status", body: ["id": videoId, "status": status])
        return Self.status(of: json)
    }

    func videoStatus(_ videoId: String) async throws -> YouTubeVideoStatus? {
        let json = try await call("GET", "videos?part=status&id=\(videoId)")
        return (json["items"] as? [[String: Any]])?.first.map(Self.status(of:))
    }

    /// Views, likes and comments of up to 50 videos (video ID → numbers)
    func statistics(_ ids: [String]) async throws -> [String: PostMetrics] {
        guard !ids.isEmpty else { return [:] }
        let json = try await call("GET", "videos?part=statistics&id=\(ids.prefix(50).joined(separator: ","))")
        var result: [String: PostMetrics] = [:]
        for item in json["items"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, let s = item["statistics"] as? [String: Any] else { continue }
            func n(_ key: String) -> Int? { (s[key] as? String).flatMap(Int.init) ?? s[key] as? Int }
            result[id] = PostMetrics(views: n("viewCount"), likes: n("likeCount"), comments: n("commentCount"))
        }
        return result
    }

    static func watchURL(_ videoId: String) -> URL { URL(string: "https://youtube.com/shorts/\(videoId)")! }
    static func studioURL(_ videoId: String) -> URL { URL(string: "https://studio.youtube.com/video/\(videoId)/edit")! }

    // MARK: Request bodies

    static func body(_ meta: Metadata) -> [String: Any] {
        var snippet: [String: Any] = [
            "title": cleanTitle(meta.title),
            "description": cleanDescription(meta.description),
            "categoryId": "22",
        ]
        let tags = cleanTags(meta.tags)
        if !tags.isEmpty { snippet["tags"] = tags }
        if let code = meta.language.map(youtubeLanguage) {
            snippet["defaultLanguage"] = code
            snippet["defaultAudioLanguage"] = code
        }
        return ["snippet": snippet, "status": statusBody(privacy: meta.publishAt == nil ? "public" : "private", publishAt: meta.publishAt, synthetic: meta.synthetic)]
    }

    /// A status part sent whole: fields left out of an update go back to their defaults
    static func statusBody(privacy: String, publishAt: Date?, synthetic: Bool) -> [String: Any] {
        var status: [String: Any] = [
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": false,
            "containsSyntheticMedia": synthetic,
            "embeddable": true,
            "license": "youtube",
            "publicStatsViewable": true,
        ]
        if let publishAt { status["publishAt"] = ISO8601DateFormatter().string(from: publishAt) }
        return status
    }

    /// At most 100 characters, without < and > (YouTube refuses them)
    static func cleanTitle(_ title: String) -> String {
        let plain = title.replacingOccurrences(of: "\n", with: " ").filter { $0 != "<" && $0 != ">" }
            .trimmingCharacters(in: .whitespaces)
        return plain.count > 100 ? String(plain.prefix(99)).trimmingCharacters(in: .whitespaces) + "…" : plain
    }

    static func cleanDescription(_ text: String) -> String {
        var plain = String(text.filter { $0 != "<" && $0 != ">" })
        while plain.utf8.count > 5000 { plain.removeLast() }
        return plain
    }

    /// Tags without #, at most 500 characters together
    static func cleanTags(_ tags: [String]) -> [String] {
        var result: [String] = [], total = 0
        for tag in tags {
            let t = tag.replacingOccurrences(of: "#", with: "").filter { $0 != "<" && $0 != ">" && $0 != "," }
            guard !t.isEmpty, total + t.count + 1 <= 500 else { continue }
            result.append(t)
            total += t.count + 1
        }
        return result
    }

    /// YouTube lists languages by its own codes
    static func youtubeLanguage(_ code: String) -> String {
        switch code {
        case "zh-Hans": "zh-CN"
        case "pt-BR": "pt"
        default: String(code.split(separator: "-").first ?? Substring(code))
        }
    }

    static func status(of video: [String: Any]) -> YouTubeVideoStatus {
        let s = video["status"] as? [String: Any] ?? [:]
        let publishAt = (s["publishAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) ?? Self.fractional.date(from: $0) }
        let problem = (s["rejectionReason"] as? String) ?? (s["failureReason"] as? String)
        return YouTubeVideoStatus(privacy: s["privacyStatus"] as? String ?? "private", publishAt: publishAt, uploadStatus: s["uploadStatus"] as? String, problem: problem)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Resumable upload

    private func startUpload(body: [String: Any], size: Int) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard let http, http.statusCode == 200, let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
            throw Self.error(status: http?.statusCode ?? 0, data: data)
        }
        return url
    }

    /// Sends the file, and after a dropped connection or a server error asks how much arrived and sends the rest.
    private func send(_ data: Data, to session: URL, onStatus: @escaping @Sendable (String) -> Void) async throws -> [String: Any] {
        var offset = 0
        var lastError: Error = YouTubeError.uploadIncomplete
        for attempt in 0..<5 {
            if attempt > 0 {
                onStatus(String(localized: "The connection to YouTube dropped. Carrying on with the upload…"))
                try await Task.sleep(for: .seconds([0, 3, 10, 30, 60][attempt]))
                switch try await received(session, size: data.count) {
                case let .done(json): return json
                case let .from(next): offset = next
                }
            }
            var request = URLRequest(url: session)
            request.httpMethod = "PUT"
            request.timeoutInterval = 600
            request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            if offset > 0 { request.setValue("bytes \(offset)-\(data.count - 1)/\(data.count)", forHTTPHeaderField: "Content-Range") }
            let progress = UploadProgress(total: data.count, offset: offset, onStatus: onStatus)
            do {
                let (body, response) = try await URLSession.shared.upload(for: request, from: data.subdata(in: offset..<data.count), delegate: progress)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 || status == 201 { return Self.object(body) }
                lastError = Self.error(status: status, data: body)
                // Only a server error is worth another try; anything else is about the request
                guard status >= 500 || status == 308 else { throw lastError }
            } catch let error as URLError {
                lastError = error
            }
        }
        throw lastError
    }

    private enum Received { case done([String: Any]), from(Int) }

    /// Asks the upload session how many bytes it has (Google answers 308 with a Range header).
    private func received(_ session: URL, size: Int) async throws -> Received {
        var request = URLRequest(url: session)
        request.httpMethod = "PUT"
        request.setValue("bytes */\(size)", forHTTPHeaderField: "Content-Range")
        let (body, response) = try await URLSession.shared.upload(for: request, from: Data())
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200, 201: return .done(Self.object(body))
        case 308:
            let range = http?.value(forHTTPHeaderField: "Range") ?? ""
            let last = range.split(separator: "-").last.flatMap { Int($0) }
            return .from(last.map { $0 + 1 } ?? 0)
        case 404, 410: throw YouTubeError.uploadIncomplete
        default: throw Self.error(status: http?.statusCode ?? 0, data: body)
        }
    }

    // MARK: Plumbing

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { await TokenCache.shared.forget(refreshToken) }
            throw Self.error(status: status, data: data)
        }
        return Self.object(data)
    }

    /// A short-lived access token from the refresh token (kept until a minute before it runs out)
    func accessToken() async throws -> String {
        if let cached = await TokenCache.shared.token(for: refreshToken) { return cached }
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw YouTubeError.missingClient }
        let json: [String: Any]
        do {
            json = try await Self.tokenRequest([
                "client_id": clientId, "client_secret": clientSecret,
                "refresh_token": refreshToken, "grant_type": "refresh_token",
            ])
        } catch let YouTubeError.api(_, reason, _) where reason == "invalid_grant" {
            throw YouTubeError.expired
        }
        guard let token = json["access_token"] as? String else { throw YouTubeError.expired }
        await TokenCache.shared.store(token, expiresIn: json["expires_in"] as? Double ?? 3600, for: refreshToken)
        return token
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = object(data)
        guard status == 200 else {
            let reason = json["error"] as? String
            throw YouTubeError.api(status: status, reason: reason, message: json["error_description"] as? String ?? reason ?? String(decoding: data, as: UTF8.self))
        }
        return json
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    }

    private static func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Google's error: {"error": {"code", "message", "errors": [{"reason"}]}}
    static func error(status: Int, data: Data) -> YouTubeError {
        let error = object(data)["error"] as? [String: Any]
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String
        let message = error?["message"] as? String ?? String(decoding: data.prefix(400), as: UTF8.self)
        return .api(status: status, reason: reason, message: message)
    }

    private static func randomString(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Access tokens by refresh token
private actor TokenCache {
    static let shared = TokenCache()
    private var tokens: [String: (token: String, until: Date)] = [:]

    func token(for refresh: String) -> String? {
        guard let t = tokens[refresh], t.until > Date() else { return nil }
        return t.token
    }

    func store(_ token: String, expiresIn: Double, for refresh: String) {
        tokens[refresh] = (token, Date().addingTimeInterval(expiresIn - 60))
    }

    func forget(_ refresh: String) { tokens[refresh] = nil }
}

/// Reports the upload in steps of 10 percent
private final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let total: Int, offset: Int
    private let onStatus: @Sendable (String) -> Void
    private var lastStep = -1

    init(total: Int, offset: Int, onStatus: @escaping @Sendable (String) -> Void) {
        self.total = max(total, 1)
        self.offset = offset
        self.onStatus = onStatus
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let percent = Int(Double(offset + Int(totalBytesSent)) / Double(total) * 100)
        let step = min(percent / 10, 10)
        guard step != lastStep else { return }
        lastStep = step
        onStatus(String(localized: "Uploading to YouTube… \(step * 10)%"))
    }
}

/// Listens on 127.0.0.1 for the browser coming back from Google's consent page with `?code=…&state=…`.
final class OAuthLoopback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "OAuthLoopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return conn.cancel() }
            conn.start(queue: queue)
            receive(conn, buffer: Data())
        }
        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    resumed = true
                    cont.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// The query of the first request that carries a code or an error
    func answer(timeout: TimeInterval) async throws -> [String: String] {
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(YouTubeError.signIn(String(localized: "No answer from Google in time."))))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    if let result = self.result { return cont.resume(with: result) }
                    self.continuation = cont
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        listener?.cancel()
    }

    /// Runs on `queue`
    private func finish(_ result: Result<[String: String], Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, error in
            guard let self else { return conn.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil || buffer.count > 65536 { conn.cancel() } else { receive(conn, buffer: buffer) }
                return
            }
            let line = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).split(separator: "\r\n").first ?? ""
            let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
            var query: [String: String] = [:]
            for item in items { query[item.name] = item.value ?? "" }
            guard query["code"] != nil || query["error"] != nil else {
                return respond(conn, "404 Not Found", "")
            }
            let ok = query["code"] != nil
            let title = ok ? String(localized: "Promo Studio is connected to YouTube.") : String(localized: "The YouTube connection was cancelled.")
            let page = """
            <!doctype html><meta charset="utf-8"><title>Promo Studio</title>
            <body style="font:16px -apple-system,system-ui;display:grid;place-items:center;height:90vh;text-align:center;color:#222">
            <div><h2>\(title)</h2><p>\(String(localized: "You can close this tab and go back to Promo Studio."))</p></div>
            """
            respond(conn, "200 OK", page)
            finish(.success(query))
        }
    }

    private func respond(_ conn: NWConnection, _ status: String, _ body: String) {
        let data = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in conn.cancel() })
    }
}
