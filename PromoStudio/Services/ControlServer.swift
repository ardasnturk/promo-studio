import AppKit
import Foundation
import Network

/// Token-protected control API that only runs on 127.0.0.1 (Remote Code relays it to the iPhone).
/// Contract: docs/CONTROL_API.md
@MainActor
final class ControlServer {
    static let version = 1
    static var infoFile: URL { Paths.root.appendingPathComponent("control.json") }

    private weak var model: AppModel?
    private var listener: NWListener?
    private let token: String
    private let queue = DispatchQueue(label: "promostudio.control")
    /// Open SSE connections
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private(set) var revision = 0
    private var changePending = false
    private var lastJobSent: [UUID: Date] = [:]
    private var pingTimer: Timer?

    init(model: AppModel) {
        self.model = model
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token = bytes.map { String(format: "%02x", $0) }.joined()
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: params) else { return }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            Task { @MainActor in self?.writeInfo(port: Int(port)) }
        }
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .main)
            Task { @MainActor in self?.receive(conn, buffer: Data()) }
        }
        listener.start(queue: queue)
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.broadcast("ping", [:]) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: ControlServer.infoFile)
        }
    }

    private func writeInfo(port: Int) {
        let info: [String: Any] = ["version": Self.version, "port": port, "token": token, "pid": ProcessInfo.processInfo.processIdentifier]
        guard let data = try? JSONSerialization.data(withJSONObject: info) else { return }
        let url = Self.infoFile
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    // MARK: Events (called by AppModel)

    /// Data changed: clients receive `changed` at most twice per second.
    func dataChanged() {
        revision += 1
        guard !changePending else { return }
        changePending = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            changePending = false
            broadcast("changed", ["revision": revision])
        }
    }

    func jobChanged(_ id: UUID, _ job: JobState?) {
        guard let job else {
            lastJobSent[id] = nil
            broadcast("jobEnded", ["id": id.uuidString])
            return
        }
        if let last = lastJobSent[id], Date().timeIntervalSince(last) < 0.25 { return }
        lastJobSent[id] = Date()
        var payload: [String: Any] = ["id": id.uuidString, "message": job.message]
        payload.merge(Self.timing(job)) { _, new in new }
        if let p = job.progress { payload["progress"] = p }
        broadcast("job", payload)
    }

    /// `kind`, `startedAt` and `estimatedEnd` (ISO 8601) of a job, for the remaining time on the phone
    static func timing(_ job: JobState) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var out: [String: Any] = ["kind": job.kind.rawValue, "startedAt": iso.string(from: job.startedAt)]
        if let end = job.estimatedEnd { out["estimatedEnd"] = iso.string(from: end) }
        return out
    }

    /// A job ended. `notice` says what is worth telling the user: videoReady, storyboardReady,
    /// published or failed (nil: nothing, e.g. a rewritten caption). Remote Code turns it into a notification.
    func jobFinished(_ id: UUID, kind: JobKind, notice: String?, title: String, postId: UUID?, error: String?) {
        var payload: [String: Any] = ["id": id.uuidString, "kind": kind.rawValue, "title": title]
        if let notice { payload["notice"] = notice }
        if let postId { payload["postId"] = postId.uuidString }
        if let error { payload["error"] = error }
        broadcast("finished", payload)
    }

    func alertShown(title: String, message: String) {
        broadcast("alert", ["title": title, "message": message])
    }

    private func broadcast(_ event: String, _ data: [String: Any]) {
        guard !streams.isEmpty, let json = try? JSONSerialization.data(withJSONObject: data) else { return }
        let chunk = Data("event: \(event)\ndata: ".utf8) + json + Data("\n\n".utf8)
        for (key, conn) in streams {
            conn.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if error != nil { Task { @MainActor in self?.streams[key] = nil } }
            })
        }
    }

    // MARK: HTTP

    private struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = Self.parse(buffer) {
                    await self.handle(request, conn)
                } else if error != nil || isComplete || buffer.count > 8 << 20 {
                    conn.cancel()
                } else {
                    self.receive(conn, buffer: buffer)
                }
            }
        }
    }

    /// Returns the request once the headers and Content-Length bytes of body have arrived.
    private static func parse(_ buffer: Data) -> Request? {
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        let target = String(parts[1])
        let comps = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] { query[item.name] = item.value }
        return Request(method: String(parts[0]), path: comps?.path ?? target, query: query, headers: headers, body: Data(body.prefix(length)))
    }

    private func handle(_ req: Request, _ conn: NWConnection) async {
        guard req.headers["authorization"] == "Bearer \(token)" else {
            return send(conn, status: 401, json: ["error": String(localized: "Unauthorized")])
        }
        guard let model else { return send(conn, status: 503, json: ["error": String(localized: "Promo Studio isn't ready")]) }
        switch (req.method, req.path) {
        case ("GET", "/v1/state"):
            send(conn, status: 200, body: stateJSON(model), type: "application/json")
        case ("GET", "/v1/events"):
            openStream(conn)
        case ("GET", let p) where p.hasPrefix("/v1/media/"):
            serveMedia(String(p.dropFirst("/v1/media/".count)), range: req.headers["range"], conn)
        case ("POST", let p) where p.hasPrefix("/v1/actions/"):
            let body = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]
            do {
                let (status, result) = try await ControlActions.perform(String(p.dropFirst("/v1/actions/".count)), body: body, model: model)
                send(conn, status: status, json: result)
            } catch {
                send(conn, status: 400, json: ["error": error.localizedDescription])
            }
        default:
            send(conn, status: 404, json: ["error": String(localized: "Unknown endpoint: \(req.method) \(req.path)")])
        }
    }

    private func openStream(_ conn: NWConnection) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        let key = ObjectIdentifier(conn)
        streams[key] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: Task { @MainActor in self?.streams[key] = nil }
            default: break
            }
        }
        conn.send(content: Data(head.utf8) + Data("event: changed\ndata: {\"revision\": \(revision)}\n\n".utf8), completion: .idempotent)
    }

    private func serveMedia(_ rel: String, range: String?, _ conn: NWConnection) {
        let parts = rel.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains(where: { $0.isEmpty }) else {
            return send(conn, status: 400, json: ["error": String(localized: "Invalid path")])
        }
        let url: URL?
        switch parts.first {
        case "posts" where parts.count == 3 && UUID(uuidString: parts[1]) != nil:
            url = Paths.post(UUID(uuidString: parts[1])!).appendingPathComponent(parts[2])
        case "projects" where parts.count == 4 && parts[2] == "assets" && UUID(uuidString: parts[1]) != nil:
            url = Paths.projectAssets(UUID(uuidString: parts[1])!).appendingPathComponent(parts[3])
        default:
            url = nil
        }
        guard let url, let handle = try? FileHandle(forReadingFrom: url), let size = try? handle.seekToEnd() else {
            return send(conn, status: 404, json: ["error": String(localized: "File not found")])
        }
        defer { try? handle.close() }
        let type = switch url.pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        default: "application/octet-stream"
        }
        var start: UInt64 = 0, end: UInt64 = size == 0 ? 0 : size - 1
        var partial = false
        if let range, let m = range.firstMatch(of: /bytes=(\d*)-(\d*)/) {
            if let a = UInt64(m.1) { start = a }
            if let b = UInt64(m.2) { end = min(b, end) }
            partial = true
        }
        guard start <= end || size == 0 else {
            return send(conn, status: 416, body: Data(), type: type, extra: ["Content-Range": "bytes */\(size)"])
        }
        try? handle.seek(toOffset: start)
        let data = (size == 0 ? Data() : (try? handle.read(upToCount: Int(end - start + 1))) ?? Data())
        var extra = ["Accept-Ranges": "bytes"]
        if partial { extra["Content-Range"] = "bytes \(start)-\(end)/\(size)" }
        send(conn, status: partial ? 206 : 200, body: data, type: type, extra: extra)
    }

    private func send(_ conn: NWConnection, status: Int, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        send(conn, status: status, body: data, type: "application/json")
    }

    private func send(_ conn: NWConnection, status: Int, body: Data, type: String, extra: [String: String] = [:]) {
        let reason = [200: "OK", 202: "Accepted", 206: "Partial Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 416: "Range Not Satisfiable", 503: "Service Unavailable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: Status

    private func stateJSON(_ model: AppModel) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func object<T: Encodable>(_ value: T) -> Any {
            (try? encoder.encode(value)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        }
        let projects: [Any] = model.data.projects.map { p in
            var d = object(p) as? [String: Any] ?? [:]
            d["logo"] = p.logoFile.map { "/v1/media/projects/\(p.id.uuidString)/assets/\($0)" } ?? NSNull()
            return d
        }
        let posts: [Any] = model.data.posts.sorted { $0.createdAt > $1.createdAt }.map { post in
            var d = object(post) as? [String: Any] ?? [:]
            d["media"] = [
                "video": post.videoFile.map { "/v1/media/posts/\(post.id.uuidString)/\($0)" } ?? NSNull(),
                "cover": post.coverFile.map { "/v1/media/posts/\(post.id.uuidString)/\($0)" } ?? NSNull(),
            ]
            return d
        }
        var jobs: [String: Any] = [:]
        for (id, job) in model.jobs {
            var j: [String: Any] = ["message": job.message, "log": Array(job.log.suffix(20))]
            if let p = job.progress { j["progress"] = p }
            j.merge(Self.timing(job)) { _, new in new }
            jobs[id.uuidString] = j
        }
        let s = model.settings
        let state: [String: Any] = [
            "version": Self.version,
            "revision": revision,
            "projects": projects,
            "posts": posts,
            "accounts": object(model.data.accounts),
            "libraries": model.data.libraries.map { ["id": $0.id.uuidString, "name": $0.name, "skills": $0.skills.map { ["name": $0.name, "description": $0.description] }] },
            "jobs": jobs,
            "alert": model.alert ?? model.notice ?? NSNull(),
            "settings": [
                "loginMode": s.loginMode.rawValue, "metaAppId": s.metaAppId,
                "hasAppSecret": !(Keychain.get(Keychain.Key.metaAppSecret) ?? "").isEmpty,
                "contentLanguage": s.contentLanguage, "voiceoverEnabled": s.voiceoverEnabled,
                "defaultTheme": s.defaultTheme.rawValue, "maxHashtags": s.maxHashtags,
            ],
            "languages": ContentLanguage.all.map { ["id": $0.id, "label": $0.label] },
            "themes": VideoTheme.allCases.map { ["id": $0.rawValue, "label": $0.label] },
        ]
        return (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8)
    }
}
