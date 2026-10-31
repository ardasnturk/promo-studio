import Foundation

enum Paths {
    static let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("Promo Studio", isDirectory: true)
        // The app used to be called "Automat"; its data is moved to the new folder once.
        let legacy = support.appendingPathComponent("Automat", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: url)
            try? fm.removeItem(at: url.appendingPathComponent("control.json"))
        }
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var dataFile: URL { root.appendingPathComponent("data.json") }
    static var remotion: URL { root.appendingPathComponent("remotion", isDirectory: true) }

    static func projectAssets(_ id: UUID) -> URL { ensure(root.appendingPathComponent("projects/\(id.uuidString)/assets")) }
    static func post(_ id: UUID) -> URL { ensure(root.appendingPathComponent("posts/\(id.uuidString)")) }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
