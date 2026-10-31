import Foundation
import Synchronization

enum AudioError: LocalizedError {
    case missingKey
    case tts(String)
    case split(String)
    /// Daily free quota used up; retrying just wastes requests
    case quota(String?)

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "Gemini API key not found (Settings → Voiceover, or GEMINI_API_KEY).")
        case let .tts(msg): "Gemini TTS: \(msg)"
        case let .split(msg): String(localized: "Couldn't split the voiceover: \(msg)")
        case let .quota(wait):
            wait.map { String(localized: "Gemini voiceover quota reached (free plan: 10 requests per model per day); it resets in about \($0). You can produce the video without voiceover, wait for the quota, or enable billing in Google AI Studio.") }
                ?? String(localized: "Gemini voiceover quota reached (free plan: 10 requests per model per day). You can produce the video without voiceover, wait for the quota, or enable billing in Google AI Studio.")
        }
    }
}

/// Generates scene voiceovers and the background beat with Gemini TTS.
enum AudioService {
    /// Key from the Keychain, otherwise GEMINI_API_KEY from the login shell
    static func geminiKey() -> String? {
        if let k = Keychain.get(Keychain.Key.geminiApiKey), !k.isEmpty { return k }
        return envKey
    }

    /// GEMINI_API_KEY from the login shell. Waiting on a process on the main thread re-enters the run loop and
    /// makes SwiftUI run while reading this value, so it is read in the background at launch (`preloadEnvKey`);
    /// if not read yet, the main thread does not wait and gets nil.
    static var envKey: String? {
        if let cached = envKeyCache.withLock({ $0 }) { return cached }
        guard !Thread.isMainThread else { return nil }
        let value = ProcessRunner.loginShellVariable("GEMINI_API_KEY")
        envKeyCache.withLock { $0 = .some(value) }
        return value
    }

    private static let envKeyCache = Mutex<String??>(nil)

    static func preloadEnvKey() {
        Task.detached(priority: .utility) { _ = envKey }
    }

    // MARK: Voiceover

    /// Generates the scenes' voiceover files (reusing existing ones if text/voice are unchanged),
    /// fills the `audio` fields and fits scene durations to the audio length.
    static func prepareVoiceover(
        post: inout ContentPost,
        voice: String,
        model: String,
        apiKey: String,
        onStatus: @Sendable (String) -> Void
    ) async throws {
        let dir = Paths.post(post.id)
        let indices = post.spec.scenes.indices.filter { !(post.spec.scenes[$0].voiceover ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        guard !indices.isEmpty else { return }
        let lines = indices.map { post.spec.scenes[$0].voiceover!.trimmingCharacters(in: .whitespacesAndNewlines) }
        let signature = "\(voice)|\(model)|" + lines.joined(separator: "\n")
        let files = indices.map { "vo_\($0 + 1).wav" }

        let cached = post.voiceSignature == signature
            && files.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }

        var durations: [Double]
        if cached {
            durations = []
            for f in files { durations.append(try await duration(of: dir.appendingPathComponent(f))) }
        } else {
            // Free quota is ~10 requests per model per day: voice the whole video in one request and split at the silences.
            onStatus(String(localized: "Generating voiceover (Gemini, \(voice))…"))
            let take = dir.appendingPathComponent("vo_take.wav")
            try await synthesize(lines.joined(separator: "\n"), voice: voice, model: model, apiKey: apiKey, to: take)
            do {
                onStatus(String(localized: "Splitting the voiceover into scenes…"))
                durations = try await split(take: take, lines: lines, into: files.map { dir.appendingPathComponent($0) })
            } catch {
                try? FileManager.default.removeItem(at: take)
                // If splitting fails, generate each line with its own request (synthesize fails fast once the quota is used up)
                onStatus(String(localized: "Voicing line by line…"))
                durations = []
                for (line, file) in zip(lines, files) {
                    let raw = dir.appendingPathComponent("raw_\(file)")
                    try await synthesize(line, voice: voice, model: model, apiKey: apiKey, to: raw)
                    durations.append(try await normalize(raw, from: nil, to: nil, into: dir.appendingPathComponent(file)))
                    try? FileManager.default.removeItem(at: raw)
                }
            }
            try? FileManager.default.removeItem(at: take)
            post.voiceSignature = signature
        }

        for (k, i) in indices.enumerated() {
            post.spec.scenes[i].audio = files[k]
            // Don't let the scene end before the audio finishes and the transition (0.4 s) to the next scene starts
            let isLast = i == post.spec.scenes.count - 1
            post.spec.scenes[i].durationSec = max(1.8, (durations[k] + (isLast ? 1.2 : 0.65)) * 10).rounded(.up) / 10
        }
    }

    static func synthesize(_ text: String, voice: String, model: String, apiKey: String, to url: URL) async throws {
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]],
            ],
        ])

        var lastError = ""
        for attempt in 0..<4 {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let part = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["inlineData"] as? [String: Any],
                      let b64 = part["data"] as? String, let pcm = Data(base64Encoded: b64) else {
                    throw AudioError.tts(String(localized: "No audio in the response"))
                }
                var rate = 24000
                if let mime = part["mimeType"] as? String, let r = mime.components(separatedBy: "rate=").last?.split(separator: ";").first, let v = Int(r) { rate = v }
                try wav(pcm16: pcm, rate: rate, channels: 1).write(to: url)
                return
            }
            let body = String(decoding: data, as: UTF8.self)
            lastError = "HTTP \(code): \(body.prefix(300))"
            if code == 429, body.contains("per day") || body.contains("PerDay") {
                throw AudioError.quota(retryHint(body))
            }
            if [429, 500, 503].contains(code), attempt < 3 {
                try await Task.sleep(for: .seconds(5 * (attempt + 1)))
                continue
            }
            break
        }
        throw AudioError.tts(lastError)
    }

    /// "Please retry in 7h47m44.1s" → "7 h 47 min"
    private static func retryHint(_ body: String) -> String? {
        guard let m = body.firstMatch(of: /retry in (?:(\d+)h)?(?:(\d+)m)?/), m.1 != nil || m.2 != nil else { return nil }
        return [m.1.map { String(localized: "\($0) h") }, m.2.map { String(localized: "\($0) min") }].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Splitting (vo_split.py)

    /// Splits a single recording at the silences that best fit the lines' text lengths.
    static func split(take: URL, lines: [String], into outputs: [URL]) async throws -> [Double] {
        let log = try await ffmpeg(["-hide_banner", "-nostats", "-i", take.path, "-af", "silencedetect=noise=-40dB:d=0.22", "-f", "null", "-"])
        let starts = log.matches(of: /silence_start: ([0-9.]+)/).compactMap { Double($0.1) }
        let ends = log.matches(of: /silence_end: ([0-9.]+)/).compactMap { Double($0.1) }
        let silences = Array(zip(starts, ends))
        let length = try await duration(of: take)
        let chars = lines.map { Double(max(4, $0.replacing(/\[[^\]]*\]/, with: "").trimmingCharacters(in: .whitespaces).count)) }

        let start = (silences.first.map { $0.0 < 0.01 } ?? false) ? silences[0].1 : 0
        let end = (silences.last.map { $0.1 > length - 0.05 } ?? false) ? silences.last!.0 : length
        let inner = silences.filter { start + 0.1 < $0.0 && $0.1 < end - 0.1 }
        let n = lines.count, s = inner.count
        guard s >= n - 1 else { throw AudioError.split(String(localized: "fewer pauses than lines")) }
        let rate = (end - start - inner.reduce(0) { $0 + $1.1 - $1.0 }) / chars.reduce(0, +)

        let cut = inner + [(end, end)]
        let startsAfter = [start] + inner.map(\.1)
        func cost(_ k: Int, _ i: Int, _ j: Int) -> Double {
            let a = startsAfter[i], b = cut[j].0
            guard b > a else { return .infinity }
            let speech = b - a - inner[i..<j].reduce(0) { $0 + $1.1 - $1.0 }
            let expected = chars[k] * rate
            let pause = j < s ? cut[j].1 - cut[j].0 : 0
            return abs(speech - expected) / expected - pause
        }
        var dp = Array(repeating: Array(repeating: Double.infinity, count: s + 1), count: n)
        var back = Array(repeating: Array(repeating: -1, count: s + 1), count: n)
        for j in 0...s { dp[0][j] = cost(0, 0, j) }
        if n > 1 {
            for k in 1..<n {
                for j in k...s {
                    for i in (k - 1)..<j where dp[k - 1][i] < .infinity {
                        let c = dp[k - 1][i] + cost(k, i + 1, j)
                        if c < dp[k][j] { dp[k][j] = c; back[k][j] = i }
                    }
                }
            }
        }
        guard dp[n - 1][s] < .infinity else { throw AudioError.split(String(localized: "no suitable split found")) }
        var endsAt: [Int] = []
        var j = s
        for k in stride(from: n - 1, through: 0, by: -1) {
            endsAt.append(j)
            j = back[k][j]
        }
        endsAt.reverse()

        var durations: [Double] = []
        var prev = 0
        for k in 0..<n {
            let a = k == 0 ? start : startsAfter[prev]
            let b = cut[endsAt[k]].0
            prev = endsAt[k] + 1
            let ratio = (b - a) / (chars[k] * rate)
            guard ratio > 0.45, ratio < 2.2 else { throw AudioError.split(String(localized: "line \(k + 1) seems to be split in the wrong place")) }
            durations.append(try await normalize(take, from: max(0, a - 0.04), to: b + 0.08, into: outputs[k]))
        }
        return durations
    }

    /// Trims, normalizes to -16 LUFS, writes 44.1 kHz stereo and returns the duration.
    @discardableResult
    static func normalize(_ input: URL, from: Double?, to: Double?, into output: URL) async throws -> Double {
        var args = ["-v", "error", "-y", "-i", input.path]
        if let from { args += ["-ss", String(format: "%.3f", from)] }
        if let to { args += ["-to", String(format: "%.3f", to)] }
        args += ["-af", "silenceremove=start_periods=1:start_threshold=-45dB,afade=t=in:d=0.02,loudnorm=I=-16:TP=-1.5", "-ar", "44100", "-ac", "2", output.path]
        try await ffmpeg(args)
        return try await duration(of: output)
    }

    static func duration(of url: URL) async throws -> Double {
        let out = try await ffmpeg(["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path], probe: true)
        return Double(out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last ?? "") ?? 0
    }

    /// If ffmpeg is not installed, the one bundled with Remotion is used.
    @discardableResult
    static func ffmpeg(_ args: [String], probe: Bool = false) async throws -> String {
        let tool = probe ? "ffprobe" : "ffmpeg"
        if ProcessRunner.which(tool) != nil { return try await ProcessRunner.run(tool, args) }
        let remotion = Paths.remotion.appendingPathComponent("node_modules/.bin/remotion").path
        return try await ProcessRunner.run(remotion, [tool] + args, cwd: Paths.remotion)
    }

    // MARK: Beat (beat.py)

    /// 120 BPM royalty-free beat: sparse until `drop` seconds, then drums + bass; a hit on the final card at `hit` seconds.
    static func writeBeat(seconds: Double, drop: Double, hit: Double, to url: URL) throws {
        let sr = 44100.0
        let beat = 60.0 / 120
        let n = Int(seconds * sr)
        var mix = [Double](repeating: 0, count: n)
        var rng = SeededRandom(seed: 7)

        func add(_ start: Double, _ samples: [Double], _ gain: Double) {
            let i0 = Int(start * sr)
            for (k, v) in samples.enumerated() where i0 + k >= 0 && i0 + k < n { mix[i0 + k] += v * gain }
        }
        func kick() -> [Double] {
            var out: [Double] = [], phase = 0.0
            for k in 0..<Int(0.35 * sr) {
                let t = Double(k) / sr
                phase += 2 * .pi * (45 + 110 * exp(-t * 28)) / sr
                out.append(sin(phase) * exp(-t * 7.5))
            }
            return out
        }
        func noise(_ dur: Double, _ decay: Double, highPass: Bool = true) -> [Double] {
            var out: [Double] = [], prev = 0.0
            for k in 0..<Int(dur * sr) {
                let x = rng.uniform()
                out.append((highPass ? x - prev : x) * exp(-Double(k) / sr * decay))
                prev = x
            }
            return out
        }

        let kickS = kick(), hat = noise(0.05, 70), clap = noise(0.18, 22).map { $0 * 0.9 }
        let roots = [55.0, 43.65, 65.41, 49.0]
        for b in 0...Int(seconds / beat) {
            let t = Double(b) * beat
            let full = t >= drop
            if full {
                add(t, kickS, 0.9)
                if b % 4 == 1 || b % 4 == 3 { add(t, clap, 0.35) }
                add(t + beat / 4, hat, 0.08)
                add(t + 3 * beat / 4, hat, 0.08)
            }
            add(t + beat / 2, hat, full ? 0.22 : 0.12)
        }
        let eighth = beat / 2
        for e in 0..<Int(seconds / eighth) {
            let t = Double(e) * eighth
            let root = roots[Int(t / (4 * beat)) % 4] * (e % 8 == 6 ? 2 : 1)
            let full = t >= drop
            var samples: [Double] = []
            for k in 0..<Int(eighth * sr) {
                let tt = Double(k) / sr
                let x = (1..<(full ? 6 : 3)).reduce(0.0) { $0 + sin(2 * .pi * root * Double($1) * tt) / Double($1) }
                let env = min(1, tt * 200) * exp(-tt * (full ? 5 : 3))
                let pump = full ? 0.35 + 0.65 * min(1, (tt + Double(e % 2) * eighth) / 0.18) : 1
                samples.append(x * env * pump)
            }
            add(t, samples, full ? 0.32 : 0.2)
        }
        let riseLen = Int(2.0 * sr)
        add(hit - 2, (0..<riseLen).map { rng.uniform() * pow(Double($0) / Double(riseLen), 2) }, 0.25)
        add(hit, noise(1.2, 3.5, highPass: false), 0.3)
        add(hit, kickS, 1.0)

        let maxAbs = mix.map(abs).max() ?? 0
        let peak = maxAbs > 0 ? maxAbs : 1
        var pcm = Data(capacity: n * 4)
        for v in mix {
            var s = Int16(max(-1, min(1, v / peak * 0.89)) * 32767).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        try wav(pcm16: pcm, rate: Int(sr), channels: 2).write(to: url)
    }

    // MARK: Helpers

    static func wav(pcm16 pcm: Data, rate: Int, channels: Int) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + pcm.count)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(channels); u32(rate)
        u32(rate * channels * 2); u16(channels * 2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(pcm.count)
        d.append(pcm)
        return d
    }
}

/// Simple generator for repeatable noise, matching beat.py's character
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func uniform() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 2_000_001) / 1_000_000 - 1
    }
}
