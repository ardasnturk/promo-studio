import Foundation

/// A failure explained for people: what went wrong, what to do about it, and the raw output for the curious.
/// Errors from Claude Code, Remotion, Gemini and Instagram are recognized here; anything else keeps its own message.
struct Problem: Codable, Hashable {
    var code: Code
    var title: String
    var message: String
    /// What fixes it, shown as a button (on the Mac and the phone)
    var fix: Fix?
    /// The original error output
    var details: String?
    /// Step that failed and what it was about, so the fix can run it again
    var kind: JobKind?
    var subject: UUID?
    /// The revision instruction of a failed revision
    var input: String?

    enum Code: String, Codable {
        case claudeMissing, claudeSignedOut, claudeLimit, claudeTurns, claudeNoResult, claude
        case voiceQuota, voiceKey, voice
        case renderCode, render, diskFull, toolMissing
        case instagramSession, instagramRejected, instagramLimit, instagramAccount, instagram
        case offline, template, unknown
    }

    enum Fix: String, Codable {
        /// Run the failed step again
        case retry
        /// Have Claude fix the video code from the render error, then render
        case repair
        /// Produce the video without voiceover
        case withoutVoiceover
        /// Reconnect the Instagram account
        case reconnect
        /// Open the settings (keys, accounts)
        case settings
        /// Open the setup checklist (tools)
        case setup
    }

    /// Recognizes the error; `kind` is the job it came from (an unrecognized error is described by the step that failed).
    init(_ error: Error, kind: JobKind = .other) {
        let raw = error.localizedDescription
        self.init(code: .unknown, title: Self.stepTitle(kind), message: Self.firstLine(raw), fix: .retry, details: raw)
        let text = raw.lowercased()

        if let e = error as? InstagramError {
            classify(instagram: e, text: text)
        } else if let e = error as? AudioError {
            switch e {
            case .quota:
                set(.voiceQuota, String(localized: "Voiceover quota used up"), raw, .withoutVoiceover)
            case .missingKey:
                set(.voiceKey, String(localized: "No voiceover key"), String(localized: "Add a Gemini API key in Settings → Voiceover, or produce the video without voiceover."), .settings)
            case .tts, .split:
                set(.voice, String(localized: "The voiceover couldn’t be made"), String(localized: "Gemini didn’t return usable audio. Try again, or produce the video without voiceover."), .retry)
            }
        } else if let e = error as? ProcessError, case let .notFound(tool) = e {
            if tool == "claude" {
                set(.claudeMissing, String(localized: "Claude Code isn’t installed"), String(localized: "Install Claude Code and sign in; the setup checklist shows how."), .setup)
            } else {
                set(.toolMissing, String(localized: "\(tool) isn’t installed"), String(localized: "Promo Studio needs \(tool) for this step; the setup checklist shows how to install it."), .setup)
            }
        } else if error is ClaudeCodeError || text.contains("claude code") {
            classify(claude: text)
        } else if let e = error as? ProcessError, case let .failed(command, _, _) = e, command.contains("remotion") {
            classify(render: text)
        } else if error is RemotionError {
            set(.render, String(localized: "The video couldn’t be rendered"), Self.firstLine(raw), .retry)
        } else if error is LibraryError {
            set(.template, String(localized: "The template couldn’t make the video"), Self.firstLine(raw), .retry)
        } else if let e = error as? URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed].contains(e.code) {
                set(.offline, String(localized: "No internet connection"), String(localized: "The Mac couldn’t reach the server. Check the connection and try again."), .retry)
            }
        }
        if Self.matches(text, ["no space left", "enospc"]) {
            set(.diskFull, String(localized: "The disk is full"), String(localized: "Free up some space on the Mac, then try again."), .retry)
        }
    }

    /// A message that is already meant for people (no recognizable error behind it)
    init(message: String, title: String = String(localized: "Something went wrong"), code: Code = .unknown, fix: Fix? = nil) {
        self.init(code: code, title: title, message: message, fix: fix, details: nil)
    }

    init(code: Code, title: String, message: String, fix: Fix?, details: String?) {
        self.code = code
        self.title = title
        self.message = message
        self.fix = fix
        self.details = details
    }

    private mutating func set(_ code: Code, _ title: String, _ message: String, _ fix: Fix?) {
        self.code = code
        self.title = title
        self.message = message
        self.fix = fix
    }

    private mutating func classify(claude text: String) {
        if Self.matches(text, ["not logged in", "please run /login", "invalid api key", "authentication_error", "oauth token has expired", "credit balance is too low"]) {
            set(.claudeSignedOut, String(localized: "Claude Code isn’t signed in"), String(localized: "Run claude auth login in Terminal on the Mac, then try again."), .setup)
        } else if Self.matches(text, ["usage limit", "rate limit", "rate_limit", "limit reached", "overloaded"]) || text.contains(/\b(429|529)\b/) {
            // The CLI says "Claude AI usage limit reached|<reset time as a Unix timestamp>", or "resets 5pm"
            let epoch = text.firstMatch(of: /limit reached\|([0-9]{10})/).flatMap { TimeInterval(String($0.1)) }
            let reset = epoch.map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) }
                ?? text.firstMatch(of: /resets? (?:at )?([0-9]{1,2}(?::[0-9]{2})?\s?(?:am|pm)?)/).map { String($0.1) }
            set(.claudeLimit, String(localized: "Claude’s usage limit is reached"),
                reset.map { String(localized: "Claude can work again after \($0). Try again then.") } ?? String(localized: "Claude is busy or the usage limit is reached. Try again in a while."), .retry)
        } else if Self.matches(text, ["max_turns", "max turns", "maximum number of turns"]) {
            set(.claudeTurns, String(localized: "Claude ran out of steps"), String(localized: "The job was bigger than Claude’s step budget. Try again; the work done so far is kept where possible."), .retry)
        } else if text.contains("didn't return a structured result") || text.contains("didn’t return a structured result") {
            set(.claudeNoResult, String(localized: "Claude stopped without an answer"), String(localized: "Claude finished but didn’t return a result. Trying again usually works."), .retry)
        } else {
            set(.claude, String(localized: "Claude Code ran into an error"), message, .retry)
        }
    }

    private mutating func classify(render text: String) {
        // An error in the video's own code (TypeScript, a React error in a scene) is something Claude can fix
        if Self.matches(text, ["src/videos/", "typeerror", "referenceerror", "syntaxerror", "is not defined", "cannot read propert", "error: src/", "is not a function", "module not found", "can't resolve"]) {
            set(.renderCode, String(localized: "The video code has an error"), String(localized: "Rendering stopped on an error in the video’s code. Claude can fix it and render again."), .repair)
        } else if Self.matches(text, ["timeout", "timed out", "delayrender"]) {
            set(.render, String(localized: "Rendering timed out"), String(localized: "An image or font took too long to load. Try again."), .retry)
        } else {
            set(.render, String(localized: "The video couldn’t be rendered"), String(localized: "Remotion stopped with an error. Try again, or have Claude look at it."), .repair)
        }
    }

    private mutating func classify(instagram e: InstagramError, text: String) {
        switch e {
        case .notConnected:
            set(.instagramAccount, String(localized: "No Instagram account"), String(localized: "Connect an Instagram account, or pick one for this post."), .settings)
        case .missingConfig:
            set(.instagramAccount, String(localized: "Instagram isn’t set up"), message, .settings)
        case let .graph(msg, code, subcode):
            // https://developers.facebook.com/docs/graph-api/guides/error-handling
            if code == 190 || [458, 459, 460, 463, 464, 467].contains(subcode ?? 0) {
                set(.instagramSession, String(localized: "The Instagram session has expired"), String(localized: "Sign in to the account again; the post stays as it is."), .reconnect)
            } else if [4, 17, 32, 613].contains(code ?? 0) || subcode == 2207042 {
                set(.instagramLimit, String(localized: "Instagram’s limit is reached"), String(localized: "Instagram allows only so many posts and requests a day. Try again later."), .retry)
            } else if code == 10 || code == 200 || (code ?? 0) >= 200 && (code ?? 0) < 300 {
                set(.instagramAccount, String(localized: "Instagram didn’t allow it"), String(localized: "The account hasn’t granted posting permission, or isn’t a Business or Creator account. Reconnect it and allow publishing."), .reconnect)
            } else if [2207026, 2207053, 2207004, 2207005].contains(subcode ?? 0) {
                set(.instagramRejected, String(localized: "Instagram didn’t accept the video"), String(localized: "Instagram rejected the file (length, size or format). Render it again and retry."), .retry)
            } else {
                set(.instagram, String(localized: "Instagram returned an error"), msg, .retry)
            }
        case .processingFailed:
            set(.instagramRejected, String(localized: "Instagram couldn’t process the video"), String(localized: "Instagram took the upload but couldn’t process it. Retrying usually works; if not, render the video again."), .retry)
        case .timeout:
            set(.instagram, String(localized: "Instagram is taking too long"), String(localized: "Instagram didn’t finish processing in 10 minutes. Try again later."), .retry)
        case .api:
            if Self.matches(text, ["access token", "session has expired", "error validating"]) {
                set(.instagramSession, String(localized: "The Instagram session has expired"), String(localized: "Sign in to the account again; the post stays as it is."), .reconnect)
            } else {
                set(.instagram, String(localized: "Instagram returned an error"), message, .retry)
            }
        }
    }

    private static func stepTitle(_ kind: JobKind) -> String {
        switch kind {
        case .analyze: String(localized: "The project couldn’t be analyzed")
        case .script, .storyboard: String(localized: "The storyboard couldn’t be written")
        case .produce: String(localized: "The video couldn’t be produced")
        case .revise: String(localized: "The revision couldn’t be made")
        case .render: String(localized: "The video couldn’t be rendered")
        case .caption: String(localized: "The caption couldn’t be written")
        case .translate: String(localized: "The translation couldn’t be made")
        case .generate: String(localized: "The template couldn’t make the video")
        case .ideas: String(localized: "The ideas couldn’t be found")
        case .capture: String(localized: "The screens couldn’t be captured")
        case .publish: String(localized: "The post couldn’t be published")
        case .other: String(localized: "Something went wrong")
        }
    }

    private static func matches(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// The first meaningful line, without tool noise, at a readable length
    static func firstLine(_ raw: String) -> String {
        let line = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("{") && !$0.hasPrefix("at ") } ?? raw
        return line.count > 240 ? String(line.prefix(240)) + "…" : line
    }
}
