import Foundation

/// Which Meta API is used to connect to Instagram.
enum InstagramLoginMode: String, Codable, CaseIterable, Identifiable {
    /// graph.facebook.com — the Instagram account must be linked to a Facebook Page
    case facebook
    /// graph.instagram.com — "Instagram API with Instagram Login"
    case instagram

    var id: String { rawValue }

    var label: String {
        switch self {
        case .facebook: String(localized: "Facebook login (via a Facebook Page)")
        case .instagram: String(localized: "Instagram login")
        }
    }

    var defaultRedirectURI: String {
        switch self {
        case .facebook: "https://www.facebook.com/connect/login_success.html"
        case .instagram: "https://localhost/promostudio/callback"
        }
    }
}

/// Non-secret settings kept in UserDefaults. Secret values (tokens, app secret) live in the Keychain.
struct AppSettings: Codable, Equatable {
    var loginMode: InstagramLoginMode = .facebook
    var metaAppId: String = ""
    var redirectURI: String = InstagramLoginMode.facebook.defaultRedirectURI
    var graphVersion: String = "v26.0"
    var claudeModel: String = ""
    /// Default language code for new content (ContentLanguage.id)
    var contentLanguage: String = ContentLanguage.systemDefault
    var maxHashtags: Int = 5
    var defaultTheme: VideoTheme = .hype
    var autoPublishWhenReady: Bool = false
    var voiceoverEnabled: Bool = true
    var ttsVoice: String = "Fenrir"
    var ttsModel: String = "gemini-3.1-flash-tts-preview"
    var musicEnabled: Bool = true
    /// Check daily for new versions of Promo Studio and the template libraries
    var automaticallyChecksForUpdates: Bool = true
    /// Don't show the Promo Templates install suggestion again
    var templatesPromptDismissed: Bool = false

    private static let key = "settings"
    /// Settings from when the app was called "Automat" (under another bundle ID)
    private static let legacyDomain = "com.jastech.automat"
    private static let legacyKey = "automat.settings"

    init() {}

    /// Fields added later that are missing from old records use defaults (settings are not reset).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        loginMode = try c.decodeIfPresent(InstagramLoginMode.self, forKey: .loginMode) ?? d.loginMode
        metaAppId = try c.decodeIfPresent(String.self, forKey: .metaAppId) ?? d.metaAppId
        redirectURI = try c.decodeIfPresent(String.self, forKey: .redirectURI) ?? d.redirectURI
        graphVersion = try c.decodeIfPresent(String.self, forKey: .graphVersion) ?? d.graphVersion
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        // Older versions stored the language name
        let storedLanguage = try c.decodeIfPresent(String.self, forKey: .contentLanguage) ?? d.contentLanguage
        contentLanguage = ["Türkçe": "tr", "English": "en"][storedLanguage] ?? storedLanguage
        maxHashtags = try c.decodeIfPresent(Int.self, forKey: .maxHashtags) ?? d.maxHashtags
        defaultTheme = try c.decodeIfPresent(VideoTheme.self, forKey: .defaultTheme) ?? d.defaultTheme
        autoPublishWhenReady = try c.decodeIfPresent(Bool.self, forKey: .autoPublishWhenReady) ?? d.autoPublishWhenReady
        voiceoverEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceoverEnabled) ?? d.voiceoverEnabled
        ttsVoice = try c.decodeIfPresent(String.self, forKey: .ttsVoice) ?? d.ttsVoice
        ttsModel = try c.decodeIfPresent(String.self, forKey: .ttsModel) ?? d.ttsModel
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? d.musicEnabled
        automaticallyChecksForUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? d.automaticallyChecksForUpdates
        templatesPromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .templatesPromptDismissed) ?? d.templatesPromptDismissed
    }

    static func load() -> AppSettings {
        let current = UserDefaults.standard.data(forKey: key)
        guard let data = current ?? UserDefaults(suiteName: legacyDomain)?.data(forKey: legacyKey),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        // Settings read from the old ID are written to the new ID right away
        if current == nil { s.save() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
