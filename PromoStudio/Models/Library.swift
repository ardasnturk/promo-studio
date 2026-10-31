import Foundation

/// An external Remotion project with ready-made video templates and Claude Code skills (e.g. Promo Templates).
struct TemplateLibrary: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Repository root: CLAUDE.md and .claude/skills live here
    var path: String
    /// Path of the Remotion project relative to the repository root (the folder with package.json)
    var remotionDir: String
    var skills: [LibrarySkill] = []
    var compositions: [LibraryComposition] = []
    var scannedAt: Date?

    var rootURL: URL { URL(fileURLWithPath: path) }
    var remotionURL: URL { rootURL.appendingPathComponent(remotionDir) }
}

struct LibrarySkill: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var argumentHint: String
}

struct LibraryComposition: Codable, Hashable, Identifiable {
    var id: String
    var folder: String
    /// With a Zod schema it can be re-rendered with new props without code changes
    var hasSchema: Bool
}

/// A video produced with a library skill or composition
struct ExternalVideo: Codable, Hashable {
    var libraryId: UUID
    var skill: String?
    var request: String
    var compositionId: String?
    /// Props used for the render (JSON text); can be edited and re-rendered
    var propsJson: String?
    var summary: String
    var sources: [String] = []
    var notes: String = ""
}

/// A concept suggested by a video-idea skill
struct VideoIdea: Codable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var hook: String
    var flow: String
    var why: String
    var skill: String
    var difficulty: String
    var request: String
}
