import AppKit
import Foundation

/// Collects screenshots and saves them to the project's asset folder.
enum AssetService {
    /// Copies repository images selected during analysis into the project assets (skips existing ones).
    static func importCandidates(_ candidates: [ScreenshotCandidate], into project: inout AppProject) {
        let dir = Paths.projectAssets(project.id)
        for c in candidates {
            let src = project.folderURL.appendingPathComponent(c.path)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let name = uniqueName(for: src, origin: c.path)
            if project.assets.contains(where: { $0.fileName == name }) { continue }
            do {
                try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(name))
                project.assets.append(ProjectAsset(
                    fileName: name, label: c.label, source: .repository, isFramed: c.isFramed,
                    originalPath: c.path, language: language(ofPath: c.path)
                ))
            } catch {
                continue
            }
        }
        if project.logoFile == nil, let logo = project.analysis?.logoPath, !logo.isEmpty {
            let src = project.folderURL.appendingPathComponent(logo)
            let name = "logo.\(src.pathExtension.isEmpty ? "png" : src.pathExtension.lowercased())"
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil { project.logoFile = name }
        }
    }

    static func importFiles(_ urls: [URL], into project: inout AppProject) {
        let dir = Paths.projectAssets(project.id)
        for url in urls {
            let name = uniqueName(for: url, origin: url.lastPathComponent + UUID().uuidString)
            if (try? FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(name))) != nil {
                project.assets.append(ProjectAsset(fileName: name, label: url.deletingPathExtension().lastPathComponent, source: .imported))
            }
        }
    }

    /// Takes a screenshot from the running iOS Simulator.
    static func captureSimulator(label: String, projectId: UUID) async throws -> ProjectAsset {
        let name = "sim-\(Int(Date().timeIntervalSince1970)).png"
        let dest = Paths.projectAssets(projectId).appendingPathComponent(name)
        do {
            try await ProcessRunner.run("xcrun", ["simctl", "io", "booted", "screenshot", dest.path])
        } catch {
            throw NSError(domain: "PromoStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Couldn't capture an image from the simulator. Make sure an iOS Simulator is running (booted).\n\(error.localizedDescription)")])
        }
        return ProjectAsset(fileName: name, label: label.isEmpty ? String(localized: "Simulator screen") : label, source: .simulator)
    }

    static func remove(_ asset: ProjectAsset, from project: inout AppProject) {
        try? FileManager.default.removeItem(at: url(of: asset, in: project))
        project.assets.removeAll { $0.id == asset.id }
    }

    static func url(of asset: ProjectAsset, in project: AppProject) -> URL {
        Paths.projectAssets(project.id).appendingPathComponent(asset.fileName)
    }

    // MARK: Localized images

    /// Checks whether any path component is a language folder (e.g. screenshots/en-US/01.png → "en").
    static func language(ofPath path: String) -> String? {
        for component in path.split(separator: "/").dropLast() {
            if let code = languageCode(forFolder: String(component)) { return code }
        }
        return nil
    }

    /// Converts folder names like "en-US", "de-DE", "zh-Hans", "pt-BR", "ja" to a ContentLanguage code.
    static func languageCode(forFolder name: String) -> String? {
        let n = name.replacingOccurrences(of: "_", with: "-")
        guard n.range(of: "^[a-zA-Z]{2}(-[a-zA-Z]{2,4})?$", options: .regularExpression) != nil else { return nil }
        let lower = n.lowercased()
        if lower.hasPrefix("zh") { return lower.contains("hant") || lower.hasSuffix("tw") || lower.hasSuffix("hk") ? nil : "zh-Hans" }
        let base = String(lower.prefix(2))
        return ContentLanguage.all.contains { $0.id == base } ? base : nil
    }

    /// Matches assets from older versions, saved without a source path, against the analysis candidate list.
    static func backfillOrigins(in project: inout AppProject) {
        guard let candidates = project.analysis?.screenshots else { return }
        for i in project.assets.indices where project.assets[i].originalPath == nil && project.assets[i].source == .repository {
            if let c = candidates.first(where: { uniqueName(for: URL(fileURLWithPath: $0.path), origin: $0.path) == project.assets[i].fileName }) {
                project.assets[i].originalPath = c.path
                project.assets[i].language = language(ofPath: c.path)
            }
        }
    }

    /// For each image from a language folder, finds its sibling in the target language (same file name, other language folder) and adds it to the project.
    /// Returns the assets in the target language.
    @discardableResult
    static func ensureLocalizedAssets(language target: String, in project: inout AppProject) -> [ProjectAsset] {
        backfillOrigins(in: &project)
        let fm = FileManager.default
        let dir = Paths.projectAssets(project.id)
        let label = ContentLanguage.find(target).label
        for asset in project.assets where asset.language != nil && asset.language != target {
            guard let original = asset.originalPath else { continue }
            var parts = original.split(separator: "/").map(String.init)
            guard let idx = parts.indices.dropLast().first(where: { languageCode(forFolder: parts[$0]) != nil }) else { continue }
            let parent = project.folderURL.appendingPathComponent(parts[..<idx].joined(separator: "/"))
            let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
            for folder in siblings.sorted() where languageCode(forFolder: folder) == target {
                parts[idx] = folder
                let path = parts.joined(separator: "/")
                let src = project.folderURL.appendingPathComponent(path)
                guard fm.fileExists(atPath: src.path) else { continue }
                let name = uniqueName(for: src, origin: path)
                if project.assets.contains(where: { $0.fileName == name }) { break }
                guard (try? fm.copyItem(at: src, to: dir.appendingPathComponent(name))) != nil else { continue }
                let baseLabel = asset.label.replacingOccurrences(of: #" \([^)]*\)$"#, with: "", options: .regularExpression)
                project.assets.append(ProjectAsset(
                    fileName: name, label: "\(baseLabel) (\(label))", source: .repository, isFramed: asset.isFramed,
                    originalPath: path, language: target
                ))
                break
            }
        }
        return project.assets.filter { $0.language == target }
    }

    private static func uniqueName(for src: URL, origin: String) -> String {
        let ext = src.pathExtension.lowercased()
        let base = src.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        // hashValue changes on every launch, so a stable djb2 hash is used
        let hash = String(origin.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } % 100_000)
        return "\(base.prefix(40))-\(hash).\(ext)"
    }
}
