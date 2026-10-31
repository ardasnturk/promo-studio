import Foundation

/// Promo Templates (https://github.com/ardasnturk/promo-templates): one-click install and
/// updates based on GitHub Releases. The library has no UI of its own, so Promo Studio handles these.
enum TemplatesService {
    static let repository = "ardasnturk/promo-templates"
    static let cloneURL = "https://github.com/\(repository).git"
    static let pageURL = URL(string: "https://github.com/\(repository)")!
    static let folderName = "promo-templates"

    enum Failure: LocalizedError {
        case alreadyExists(String)
        case localChanges
        case notGit

        var errorDescription: String? {
            switch self {
            case let .alreadyExists(path): String(localized: "\(path) already exists. To add the library from there, use \"Add Library…\", or choose another folder.")
            case .localChanges: String(localized: "The library has uncommitted local changes. Commit or discard them before updating.")
            case .notGit: String(localized: "This library isn't a git clone; download it again from GitHub to update.")
            }
        }
    }

    /// Version and GitHub repository from `package.json` (Remotion folder)
    struct PackageInfo {
        var version: SemanticVersion?
        var repository: String?
    }

    static func packageInfo(_ lib: TemplateLibrary) -> PackageInfo {
        let url = lib.remotionURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return PackageInfo() }
        let repoField = (json["repository"] as? [String: Any])?["url"] as? String ?? json["repository"] as? String
        let repo = repoField.flatMap { field -> String? in
            guard let m = field.firstMatch(of: /github\.com[\/:]([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/) else { return nil }
            return "\(m.1)/\(m.2)"
        }
        return PackageInfo(version: (json["version"] as? String).flatMap(SemanticVersion.init), repository: repo)
    }

    static func isPromoTemplates(_ lib: TemplateLibrary) -> Bool {
        packageInfo(lib).repository?.lowercased() == repository
    }

    /// Tag of the repository's latest release (not draft or pre-release); nil if there are no releases.
    static func latestVersion(of repo: String) async throws -> SemanticVersion? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String else { return nil }
        return SemanticVersion(tag)
    }

    /// Clones into `parent/promo-templates`, installs the Remotion skills and dependencies; returns the folder.
    static func install(into parent: URL, onLine: @escaping @Sendable (String) -> Void) async throws -> URL {
        let dest = parent.appendingPathComponent(folderName)
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw Failure.alreadyExists(dest.path) }
        onLine(String(localized: "Downloading Promo Templates…"))
        try await ProcessRunner.run("git", ["clone", cloneURL, dest.path], cwd: parent, onLine: onLine)
        try await prepare(dest, onLine: onLine)
        return dest
    }

    /// Fast-forwards to the latest release if there are no local changes, and refreshes dependencies.
    static func update(_ lib: TemplateLibrary, onLine: @escaping @Sendable (String) -> Void) async throws {
        let root = lib.rootURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { throw Failure.notGit }
        let status = try await ProcessRunner.run("git", ["status", "--porcelain", "--untracked-files=no"], cwd: root)
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.localChanges }
        onLine(String(localized: "Updating Promo Templates…"))
        try await ProcessRunner.run("git", ["pull", "--ff-only"], cwd: root, onLine: onLine)
        try await prepare(root, onLine: onLine)
    }

    /// Remotion's agent skills (`npx remotion skills add`) and npm dependencies
    private static func prepare(_ root: URL, onLine: @escaping @Sendable (String) -> Void) async throws {
        onLine(String(localized: "Installing Remotion skills…"))
        // Skills are optional; the templates still work if they fail to install
        _ = try? await ProcessRunner.run("npx", ["--yes", "remotion", "skills", "add"], cwd: root, onLine: onLine)
        let remotion = root.appendingPathComponent("templates")
        let dir = FileManager.default.fileExists(atPath: remotion.appendingPathComponent("package.json").path) ? remotion : root
        onLine(String(localized: "Running npm install (may take a few minutes the first time)…"))
        try await ProcessRunner.run("npm", ["install", "--no-audit", "--no-fund"], cwd: dir, onLine: onLine)
    }
}
