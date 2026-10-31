import Foundation

struct AppProject: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var folderPath: String
    var createdAt = Date()
    var analysis: ProjectAnalysis?
    var analyzedAt: Date?
    var assets: [ProjectAsset] = []
    /// Logo file in the project's asset folder
    var logoFile: String?
    /// Recipe for capturing screens in every language from the iOS Simulator (extracted by Claude Code)
    var captureRecipe: CaptureRecipe?
    /// Instagram account this project's content is shared to (InstagramAccount.userId)
    var accountId: String?

    var folderURL: URL { URL(fileURLWithPath: folderPath) }
}

/// Recipe for launching the app in the simulator with demo data in the requested language and capturing specific screens.
struct CaptureRecipe: Codable, Hashable {
    var bundleId: String
    /// Folder where build commands run (relative to the project root)
    var buildDirectory: String
    /// Command to run before xcodebuild (e.g. "xcodegen generate"); empty if none
    var prebuildCommand: String
    /// .xcodeproj or .xcworkspace (relative to buildDirectory)
    var projectFile: String
    var scheme: String
    /// Arguments passed on every launch (demo data etc.); language arguments are added by Promo Studio
    var launchArguments: [String]
    var shots: [Shot]
    /// Claude's notes (unreachable screens etc.)
    var notes: String

    struct Shot: Codable, Hashable, Identifiable {
        var id: String
        var label: String
        /// File name of the existing image this screen will be the localized version of
        var assetFile: String
        /// Deep link to open after launch; empty if none
        var url: String
        /// Extra arguments for this screen only
        var extraArguments: [String]
        /// Time to wait for the screen to settle (s)
        var waitSeconds: Double
        /// Elements to tap in order after launch (accessibility identifier or visible text)
        var taps: [String]?
    }
}

struct ProjectAnalysis: Codable, Hashable {
    var appName: String
    var tagline: String
    var summary: String
    var category: String
    var targetAudience: String
    var platforms: [String]
    var tone: String
    var brandColors: BrandColors
    var features: [AppFeature]
    var suggestions: [ContentSuggestion]
    var screenshots: [ScreenshotCandidate]
    var logoPath: String?
    var storeURL: String?
}

struct BrandColors: Codable, Hashable {
    var primary: String
    var accent: String
    var background: String
}

struct AppFeature: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var emoji: String
    var summary: String
    var whyItMatters: String
    var hooks: [String]
}

struct ContentSuggestion: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var featureId: String
    var theme: VideoTheme
    var angle: String
    var hook: String
}

struct ScreenshotCandidate: Codable, Hashable {
    /// Path relative to the project root
    var path: String
    var label: String
    /// If true, the image is already framed/captioned (store screenshot etc.)
    var isFramed: Bool
}

struct ProjectAsset: Codable, Hashable, Identifiable {
    var id = UUID()
    var fileName: String
    var label: String
    var source: Source
    var isFramed: Bool = false
    var addedAt = Date()
    /// Source path relative to the project root, if it came from the repository
    var originalPath: String?
    /// Language derived from the language folder in the path (ContentLanguage code); nil if unknown
    var language: String?
    /// If this image is the localized version of another image, that image's file name
    var variantOf: String?

    enum Source: String, Codable {
        case repository, simulator, imported
    }
}

enum PostStatus: String, Codable, CaseIterable {
    case draft, rendering, ready, scheduled, publishing, published, failed

    var label: String {
        switch self {
        case .draft: String(localized: "Draft")
        case .rendering: String(localized: "Rendering")
        case .ready: String(localized: "Ready")
        case .scheduled: String(localized: "Scheduled")
        case .publishing: String(localized: "Publishing")
        case .published: String(localized: "Published")
        case .failed: String(localized: "Failed")
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc"
        case .rendering: "gearshape.2"
        case .ready: "checkmark.circle"
        case .scheduled: "calendar.badge.clock"
        case .publishing: "arrow.up.circle"
        case .published: "paperplane.fill"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum SocialPlatform: String, Codable, CaseIterable {
    case instagram
    // Later: tiktok, youtubeShorts, x ...
}

struct ContentPost: Codable, Identifiable, Hashable {
    var id = UUID()
    var projectId: UUID
    var platform: SocialPlatform = .instagram
    var featureId: String?
    var title: String
    /// ContentLanguage code; missing in old posts (Turkish is assumed)
    var language: String?
    var spec: VideoSpec
    var caption: String = ""
    var hashtags: [String] = []
    var altText: String?
    var postingTip: String?
    /// Voice/model/text the current voiceover files were made with; if it changes, the audio is regenerated
    var voiceSignature: String?
    var status: PostStatus = .draft
    var videoFile: String?
    var coverFile: String?
    var scheduledAt: Date?
    var publishedAt: Date?
    var mediaId: String?
    var permalink: String?
    var lastError: String?
    var metrics: PostMetrics?
    var createdAt = Date()
    /// Set if produced from a library (e.g. Promo Templates); `spec` is unused in that case
    var external: ExternalVideo?
    /// Instagram account it was shared to (insights are fetched with this account's token)
    var accountId: String?
    /// Set if produced from the user's own request (prompt)
    var brief: PostBrief?
    /// Script versions before Claude's revisions (oldest to newest)
    var revisions: [ScriptRevision]?
    /// Custom video Claude wrote from a storyboard (if set, `spec` is only used for voiceover/duration)
    var directed: DirectedVideo?

    /// Full text to post to Instagram
    var fullCaption: String {
        let tags = hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
        return tags.isEmpty ? caption : "\(caption)\n\n\(tags)"
    }

    /// The rendered video belongs to an older script
    var isVideoOutdated: Bool { videoFile != nil && status == .draft && external == nil }

    func snapshot(instruction: String, code: String? = nil) -> ScriptRevision {
        ScriptRevision(instruction: instruction, title: title, scenes: spec.scenes, caption: caption, hashtags: hashtags, altText: altText, postingTip: postingTip, storyboard: directed?.storyboard, code: code)
    }

    /// Mirrors the storyboard scenes into `spec.scenes` for voiceover and duration (audio files match in order).
    mutating func syncSpecFromStoryboard() {
        guard let board = directed?.storyboard else { return }
        spec.scenes = board.scenes.enumerated().map { i, s in
            var scene = VideoSpec.Scene(kind: .feature, title: s.text, durationSec: s.durationSec)
            scene.voiceover = s.voiceover
            scene.audio = spec.scenes.indices.contains(i) ? spec.scenes[i].audio : nil
            return scene
        }
    }

    mutating func apply(_ script: ContentAI.ScriptResult) {
        title = script.title
        spec.scenes = script.scenes
        caption = script.caption
        hashtags = script.hashtags.map { $0.replacingOccurrences(of: "#", with: "") }
        altText = script.altText
        postingTip = script.postingTip
        if let findings = script.findings, !findings.isEmpty { brief?.findings = findings }
        if let sources = script.sources, !sources.isEmpty {
            var merged = brief?.sources ?? []
            for s in sources where !merged.contains(s) { merged.append(s) }
            brief?.sources = merged
        }
    }

    mutating func applyStoryboard(_ result: ContentAI.StoryboardResult) {
        title = result.title
        var board = result.storyboard
        for i in board.scenes.indices {
            if board.scenes[i].voiceover?.trimmingCharacters(in: .whitespaces).isEmpty == true { board.scenes[i].voiceover = nil }
            if board.scenes[i].sfx?.trimmingCharacters(in: .whitespaces).isEmpty == true { board.scenes[i].sfx = nil }
        }
        directed?.storyboard = board
        caption = result.caption
        hashtags = result.hashtags.map { $0.replacingOccurrences(of: "#", with: "") }
        altText = result.altText
        postingTip = result.postingTip
        if let findings = result.findings, !findings.isEmpty { brief?.findings = findings }
        if let sources = result.sources, !sources.isEmpty {
            var merged = brief?.sources ?? []
            for s in sources where !merged.contains(s) { merged.append(s) }
            brief?.sources = merged
        }
    }

    /// Script changed: the existing video is out of date (needs a re-render)
    mutating func markScriptChanged() {
        if status == .ready || status == .failed { status = .draft }
        lastError = nil
    }
}

/// The user's request and the research Claude did for it
struct PostBrief: Codable, Hashable {
    var prompt: String
    var research: Bool = true
    /// Summary of the facts verified during research
    var findings: String?
    var sources: [String]?
}

/// Snapshot of the script before a revision
struct ScriptRevision: Codable, Hashable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    /// Instruction that requested the change after this version
    var instruction: String
    var title: String
    var scenes: [VideoSpec.Scene]
    var caption: String
    var hashtags: [String]
    var altText: String?
    var postingTip: String?
    /// For a directed video, the storyboard and code snapshot (`code/<name>` in the post folder)
    var storyboard: Storyboard?
    var code: String?
}

/// Custom promo video directed by Claude: the storyboard is approved first, then Claude writes the Remotion code.
struct DirectedVideo: Codable, Hashable {
    var storyboard: Storyboard
    /// Composition and folder name in the studio (src/videos/<id>)
    var compositionId: String
    /// Whether the code has been written (storyboard approved and produced)
    var produced = false
    /// Produced without voiceover (scene durations come from the storyboard)
    var muted: Bool?
    /// Claude's short summary and notes on the video it made
    var summary: String?
    var notes: String?
}

struct Storyboard: Codable, Hashable {
    /// The video's director concept: visual language, rhythm, color, hook idea
    var concept: String
    var scenes: [StoryScene]
}

struct StoryScene: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Visual director's note: what is shown, how it moves, which kit components
    var visual: String
    /// On-screen text (*emphasis* syntax)
    var text: String
    var voiceover: String?
    /// Project images to use (file names)
    var assets: [String]?
    var sfx: String?
    var durationSec: Double

    enum CodingKeys: String, CodingKey {
        case visual, text, voiceover, assets, sfx, durationSec
    }
}

struct PostMetrics: Codable, Hashable {
    var views: Int?
    var reach: Int?
    var likes: Int?
    var comments: Int?
    var shares: Int?
    var saved: Int?
    var fetchedAt = Date()
}

struct InstagramAccount: Codable, Hashable, Identifiable {
    var id: String { userId }
    var userId: String
    var username: String
    var name: String?
    var profilePictureURL: String?
    var followers: Int?
    var mediaCount: Int?
    var tokenExpiresAt: Date?
    /// API the account is connected through (Facebook Page or Instagram Login)
    var loginMode: InstagramLoginMode?
    /// Page the account is linked to, for Facebook Login
    var pageName: String?
}

struct AppData: Codable {
    var projects: [AppProject] = []
    var posts: [ContentPost] = []
    var accounts: [InstagramAccount] = []
    var libraries: [TemplateLibrary] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case projects, posts, accounts, libraries
        /// The single account from older versions
        case account
    }

    /// Fields added later that are missing from old data files are treated as empty (data is not reset).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([AppProject].self, forKey: .projects) ?? []
        posts = try c.decodeIfPresent([ContentPost].self, forKey: .posts) ?? []
        accounts = try c.decodeIfPresent([InstagramAccount].self, forKey: .accounts) ?? []
        if accounts.isEmpty, let legacy = try c.decodeIfPresent(InstagramAccount.self, forKey: .account) {
            accounts = [legacy]
        }
        libraries = try c.decodeIfPresent([TemplateLibrary].self, forKey: .libraries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projects, forKey: .projects)
        try c.encode(posts, forKey: .posts)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(libraries, forKey: .libraries)
    }
}
