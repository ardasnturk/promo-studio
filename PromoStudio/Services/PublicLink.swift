import Foundation
import Network

enum PublicLinkError: LocalizedError {
    case noTunnel(String)

    var errorDescription: String? {
        switch self {
        case let .noTunnel(output): String(localized: "The temporary link for Instagram couldn’t be opened.\n\(output)")
        }
    }
}

/// Instagram's API takes pictures only from a public web address, and videos too when the direct upload fails. For the
/// little time a post is published, a Cloudflare
/// quick tunnel (cloudflared, no account) makes these files reachable at a random trycloudflare.com address; only the
/// files under random paths are served and the tunnel closes right after.
final class PublicLink: @unchecked Sendable {
    static var isInstalled: Bool { ProcessRunner.which("cloudflared") != nil }

    /// Public URL of each file, in order
    private(set) var urls: [URL] = []
    private let files: [String: URL]
    private let queue = DispatchQueue(label: "PublicLink")
    private var listener: NWListener?
    private var process: Process?

    private let paths: [String]

    private init(files: [URL]) {
        paths = files.map { "/\(UUID().uuidString.lowercased())/\($0.lastPathComponent)" }
        self.files = Dictionary(uniqueKeysWithValues: zip(paths, files))
    }

    /// Serves `files` publicly, runs `body` with their URLs, then closes the link.
    static func serving<T>(_ files: [URL], _ body: ([URL]) async throws -> T) async throws -> T {
        let link = PublicLink(files: files)
        defer { link.close() }
        try await link.open()
        return try await body(link.urls)
    }

    private func open() async throws {
        guard let exe = ProcessRunner.which("cloudflared") else { throw ProcessError.notFound("cloudflared") }
        let port = try await startServer()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:\(port)"]
        process.environment = ProcessRunner.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process
        let output = Output()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { output.append(data) }
        }
        try process.run()

        // cloudflared prints the address once the tunnel is registered; DNS takes a few more seconds
        let deadline = Date().addingTimeInterval(45)
        var base: URL?
        while Date() < deadline, process.isRunning {
            if let found = output.address { base = found; break }
            try await Task.sleep(for: .milliseconds(300))
        }
        guard let base else { throw PublicLinkError.noTunnel(output.tail) }
        urls = paths.map { URL(string: base.absoluteString + $0)! }
        // Wait for the address in public DNS (what Instagram's servers resolve). Asking the Mac's own resolver this
        // early would cache "no such host" and the check would fail even after the record exists.
        while Date() < deadline.addingTimeInterval(30) {
            if await Self.isPublished(base.host() ?? "") { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw PublicLinkError.noTunnel(output.tail)
    }

    private static func isPublished(_ host: String) async -> Bool {
        var c = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        c.queryItems = [.init(name: "name", value: host), .init(name: "type", value: "A")]
        var req = URLRequest(url: c.url!)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return !((json["Answer"] as? [Any]) ?? []).isEmpty
    }

    private func close() {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        listener?.cancel()
    }

    // MARK: File server (127.0.0.1 only; cloudflared is its only client)

    private func startServer() async throws -> UInt16 {
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

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, error in
            guard let self else { return conn.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil || buffer.count > 65536 { conn.cancel() } else { receive(conn, buffer: buffer) }
                return
            }
            let request = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            let parts = request.split(separator: "\r\n").first?.split(separator: " ") ?? []
            let method = parts.first.map(String.init) ?? ""
            let path = parts.count > 1 ? String(parts[1]) : ""
            guard ["GET", "HEAD"].contains(method), let file = files[path], let body = try? Data(contentsOf: file, options: .mappedIfSafe) else {
                return respond(conn, "404 Not Found", Data(), type: "text/plain")
            }
            let type = file.pathExtension.lowercased() == "png" ? "image/png" : file.pathExtension.lowercased() == "mp4" ? "video/mp4" : "image/jpeg"
            if let range = Self.byteRange(in: request, size: body.count) {
                let extra = "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)\r\n"
                return respond(conn, "206 Partial Content", body.subdata(in: range), type: type, head: method == "HEAD", extra: extra)
            }
            respond(conn, "200 OK", body, type: type, head: method == "HEAD")
        }
    }

    /// The range of a `Range: bytes=a-b` or `bytes=a-` header, which video fetchers send.
    private static func byteRange(in request: String, size: Int) -> Range<Int>? {
        for line in request.split(separator: "\r\n").dropFirst() where line.lowercased().hasPrefix("range: bytes=") {
            let ends = line.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            guard ends.count == 2, let start = Int(ends[0].trimmingCharacters(in: .whitespaces)), start < size else { return nil }
            let last = Int(ends[1].trimmingCharacters(in: .whitespaces)) ?? size - 1
            return start..<min(last + 1, size)
        }
        return nil
    }

    private func respond(_ conn: NWConnection, _ status: String, _ body: Data, type: String, head: Bool = false, extra: String = "") {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Connection: close\r\n\r\n"
        conn.send(content: Data(header.utf8) + (head ? Data() : body), completion: .contentProcessed { _ in conn.cancel() })
    }
}

private final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        lock.lock()
        text += String(decoding: data, as: UTF8.self)
        lock.unlock()
    }

    var address: URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let r = text.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[r]))
    }

    var tail: String {
        lock.lock()
        defer { lock.unlock() }
        return text.split(separator: "\n").suffix(6).joined(separator: "\n")
    }
}
