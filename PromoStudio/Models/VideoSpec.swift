import Foundation

/// Mirrors RemotionTemplate/src/types.ts exactly. If you change it, update both together.
struct VideoSpec: Codable, Hashable {
    var theme: VideoTheme
    var brand: Brand
    var scenes: [Scene]
    var music: String?
    var fps: Int?
    var lang: String?

    struct Brand: Codable, Hashable {
        var appName: String
        var primary: String
        var accent: String
        var background: String
        var logo: String?
        var storeLabel: String?
    }

    struct Scene: Codable, Hashable, Identifiable {
        var id = UUID()
        var kind: SceneKind
        var title: String
        var subtitle: String?
        /// File name of the project asset in the Studio; converted to a public/ path when rendering.
        var image: String?
        var imageStyle: ImageStyle?
        var bullets: [String]?
        var stat: String?
        var emoji: String?
        var durationSec: Double?
        /// Text spoken in this scene; may start with a tone tag like [excited] (not spoken)
        var voiceover: String?
        /// Voiceover file in the post folder; converted to a public/ path when rendering
        var audio: String?

        enum CodingKeys: String, CodingKey {
            case kind, title, subtitle, image, imageStyle, bullets, stat, emoji, durationSec, voiceover, audio
        }
    }

    enum SceneKind: String, Codable, CaseIterable, Hashable {
        case hook, screenshot, feature, stat, cta

        var label: String {
            switch self {
            case .hook: String(localized: "Hook")
            case .screenshot: String(localized: "Screenshot")
            case .feature: String(localized: "Feature list")
            case .stat: String(localized: "Stat")
            case .cta: String(localized: "Call to action")
            }
        }
    }

    enum ImageStyle: String, Codable, CaseIterable, Hashable {
        case phone, raw
    }

    var totalDuration: Double {
        let sum = scenes.reduce(0) { $0 + ($1.durationSec ?? 3) }
        return max(1, sum - 0.4 * Double(max(0, scenes.count - 1)))
    }
}

enum VideoTheme: String, Codable, CaseIterable, Hashable, Identifiable {
    case hype, showcase, neon, minimal
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hype: String(localized: "Hype — fast, energetic")
        case .showcase: String(localized: "Showcase — sleek product showcase")
        case .neon: String(localized: "Neon — techy, bright")
        case .minimal: String(localized: "Minimal — clean, premium")
        }
    }
}
