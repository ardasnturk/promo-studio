import Foundation

enum ProcessError: LocalizedError {
    case failed(command: String, code: Int32, output: String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, code, output):
            let tail = output.split(separator: "\n").suffix(12).joined(separator: "\n")
            return String(localized: "\(command) failed (code \(code)):\n\(tail)")
        case let .notFound(tool):
            return String(localized: "\(tool) not found. Make sure it's installed and on your PATH.")
        }
    }
}

/// GUI apps don't inherit the user's shell PATH; the login shell PATH is used for claude/npx/xcrun.
enum ProcessRunner {
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let shellPath = (try? captureLoginShellPath()) ?? ""
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var parts = shellPath.split(separator: ":").map(String.init)
        for e in extras where !parts.contains(e) { parts.append(e) }
        env["PATH"] = parts.joined(separator: ":")
        env["FORCE_COLOR"] = "0"
        env["NO_COLOR"] = "1"
        return env
    }()

    private static func captureLoginShellPath() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "printf '__PATH__%s' \"$PATH\""]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let r = out.range(of: "__PATH__") else { return "" }
        return String(out[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads an environment variable defined in the user's login shell (e.g. GEMINI_API_KEY in ~/.zshrc).
    static func loginShellVariable(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "printf '__VAL__%s' \"${\(name)}\""]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let r = out.range(of: "__VAL__") else { return nil }
        let value = String(out[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func which(_ tool: String) -> String? {
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let path = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Runs the command, forwarding output line by line via `onLine`. The process is terminated if the task is cancelled.
    @discardableResult
    static func run(
        _ tool: String,
        _ args: [String],
        cwd: URL? = nil,
        stdin: String? = nil,
        extraEnvironment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let exe = tool.hasPrefix("/") ? tool : which(tool) else { throw ProcessError.notFound(tool) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.environment = environment.merging(extraEnvironment) { _, new in new }
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = outPipe
        let inPipe = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

        let buffer = OutputBuffer(onLine: onLine)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { buffer.append(data) }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                process.terminationHandler = { p in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    let rest = outPipe.fileHandleForReading.readDataToEndOfFile()
                    if !rest.isEmpty { buffer.append(rest) }
                    let output = buffer.finish()
                    if p.terminationStatus == 0 {
                        cont.resume(returning: output)
                    } else {
                        let cmd = ([tool] + args.prefix(3)).joined(separator: " ")
                        cont.resume(throwing: ProcessError.failed(command: cmd, code: p.terminationStatus, output: output))
                    }
                }
                do {
                    try process.run()
                    if let stdin {
                        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                        try? inPipe.fileHandleForWriting.close()
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var all = Data()
    private var pending = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ data: Data) {
        lock.lock()
        all.append(data)
        pending += String(decoding: data, as: UTF8.self)
        // Remotion writes progress with \r; treat both as line endings.
        var lines: [String] = []
        while let idx = pending.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            lines.append(String(pending[..<idx]))
            pending = String(pending[pending.index(after: idx)...])
        }
        lock.unlock()
        for l in lines where !l.isEmpty { onLine?(l) }
    }

    func finish() -> String {
        lock.lock(); defer { lock.unlock() }
        if !pending.isEmpty { onLine?(pending); pending = "" }
        return String(decoding: all, as: UTF8.self)
    }
}
