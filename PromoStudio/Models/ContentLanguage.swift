import Foundation

/// Language in which the video, voiceover and caption are produced.
struct ContentLanguage: Identifiable, Hashable {
    /// BCP-47 code; used as `lang` in Remotion (for capitalization rules)
    let id: String
    /// Name shown in the UI
    let label: String
    /// Name used in Claude prompts
    let promptName: String
    let storeLabel: String

    static let all: [ContentLanguage] = [
        .init(id: "tr", label: "Türkçe", promptName: "Türkçe", storeLabel: "App Store’da indir"),
        .init(id: "en", label: "English", promptName: "English", storeLabel: "Download on the App Store"),
        .init(id: "de", label: "Deutsch", promptName: "Deutsch (German)", storeLabel: "Im App Store laden"),
        .init(id: "es", label: "Español", promptName: "Español (Spanish)", storeLabel: "Descárgala en el App Store"),
        .init(id: "it", label: "Italiano", promptName: "Italiano (Italian)", storeLabel: "Scarica su App Store"),
        .init(id: "fr", label: "Français", promptName: "Français (French)", storeLabel: "Télécharger dans l’App Store"),
        .init(id: "pt", label: "Português", promptName: "Português do Brasil (Brazilian Portuguese)", storeLabel: "Baixe na App Store"),
        .init(id: "ja", label: "日本語", promptName: "日本語 (Japanese)", storeLabel: "App Storeでダウンロード"),
        .init(id: "ko", label: "한국어", promptName: "한국어 (Korean)", storeLabel: "App Store에서 다운로드"),
        .init(id: "zh-Hans", label: "简体中文", promptName: "简体中文 (Simplified Chinese)", storeLabel: "在 App Store 下载"),
    ]

    /// Default for new installs: the Mac's first preferred language if videos can be made in it, else English
    static var systemDefault: String {
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language
            if code.languageCode?.identifier == "zh" { return "zh-Hans" }
            if let match = all.first(where: { $0.id == code.languageCode?.identifier }) { return match.id }
        }
        return "en"
    }

    static func find(_ code: String?) -> ContentLanguage {
        all.first { $0.id == code } ?? all[0]
    }
}
