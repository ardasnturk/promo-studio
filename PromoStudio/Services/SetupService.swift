import Foundation

/// One row of the setup checklist: a tool or setting Promo Studio needs.
struct Requirement: Identifiable, Sendable {
    enum Item: String, CaseIterable, Sendable {
        case claude, node, remotion, git, xcode, gemini, instagram, templates
    }

    enum Status: Sendable {
        case ready
        /// Required item is missing or not working
        case missing
        /// Optional item is not installed
        case notSetUp
    }

    let item: Item
    var status: Status
    /// Version found, or what needs to be done
    var detail: String

    var id: Item { item }
    /// Videos cannot be produced without these
    var isRequired: Bool { [.claude, .node, .remotion].contains(item) }
}

/// Checks requirements. Commands run with the login shell PATH (ProcessRunner); the main thread does not wait.
enum SetupService {
    static let minimumNodeMajor = 20

    static func check(hasGeminiKey: Bool, isConnected: Bool, hasLibrary: Bool) async -> [Requirement] {
        async let claude = checkClaude()
        async let node = checkNode()
        async let git = checkGit()
        async let xcode = checkXcode()
        let nodeResult = await node
        return [
            await claude,
            nodeResult,
            checkRemotion(nodeReady: nodeResult.status == .ready),
            await git,
            await xcode,
            Requirement(item: .gemini, status: hasGeminiKey ? .ready : .notSetUp,
                        detail: hasGeminiKey
                            ? String(localized: "Voiceover is enabled.")
                            : String(localized: "For voiceover. Videos can be made without it.")),
            Requirement(item: .instagram, status: isConnected ? .ready : .notSetUp,
                        detail: isConnected
                            ? String(localized: "Videos can be published and scheduled.")
                            : String(localized: "For publishing. Without it, save videos and post them yourself.")),
            Requirement(item: .templates, status: hasLibrary ? .ready : .notSetUp,
                        detail: hasLibrary
                            ? String(localized: "A template library is connected.")
                            : String(localized: "Ready-made video formats and skills. Optional.")),
        ]
    }

    private static func checkClaude() async -> Requirement {
        guard let version = await output("claude", ["--version"]) else {
            return Requirement(item: .claude, status: .missing,
                               detail: String(localized: "Not found. Install Claude Code, then sign in by running claude in Terminal."))
        }
        let shortVersion = version.split(separator: " ").first.map(String.init) ?? version
        // `claude auth status --json` → {"loggedIn": true, "authMethod": "claude.ai", …}
        let status = await output("claude", ["auth", "status", "--json"])
        let json = status.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if json?["loggedIn"] as? Bool == false {
            return Requirement(item: .claude, status: .missing,
                               detail: String(localized: "Version \(shortVersion) is installed but not signed in. Run claude auth login in Terminal."))
        }
        return Requirement(item: .claude, status: .ready, detail: String(localized: "Version \(shortVersion), signed in"))
    }

    private static func checkNode() async -> Requirement {
        guard let version = await output("node", ["--version"]) else {
            return Requirement(item: .node, status: .missing,
                               detail: String(localized: "Not found. Install Node.js \(minimumNodeMajor) or later from nodejs.org or with brew install node."))
        }
        let major = Int(version.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").first ?? "") ?? 0
        guard major >= minimumNodeMajor else {
            return Requirement(item: .node, status: .missing,
                               detail: String(localized: "\(version) is too old. Node.js \(minimumNodeMajor) or later is required."))
        }
        return Requirement(item: .node, status: .ready, detail: version)
    }

    private static func checkRemotion(nodeReady: Bool) -> Requirement {
        if RemotionService.isInstalled {
            return Requirement(item: .remotion, status: .ready, detail: String(localized: "Installed"))
        }
        return Requirement(item: .remotion, status: .missing,
                           detail: nodeReady
                               ? String(localized: "Not installed yet. Installing takes a few minutes.")
                               : String(localized: "Install Node.js first."))
    }

    private static func checkGit() async -> Requirement {
        guard let version = await output("git", ["--version"]) else {
            return Requirement(item: .git, status: .notSetUp,
                               detail: String(localized: "Needed to install and update Promo Templates. Install with xcode-select --install."))
        }
        return Requirement(item: .git, status: .ready, detail: version.replacingOccurrences(of: "git version ", with: ""))
    }

    private static func checkXcode() async -> Requirement {
        guard await output("xcrun", ["--find", "simctl"]) != nil else {
            return Requirement(item: .xcode, status: .notSetUp,
                               detail: String(localized: "Needed only for localized screens from the Simulator."))
        }
        return Requirement(item: .xcode, status: .ready, detail: String(localized: "Simulator available"))
    }

    /// First output line of the command; nil if the tool is missing or fails
    private static func output(_ tool: String, _ args: [String]) async -> String? {
        guard let out = try? await ProcessRunner.run(tool, args) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if args.contains("--json") { return trimmed }
        return trimmed.split(separator: "\n").first.map(String.init)
    }
}
