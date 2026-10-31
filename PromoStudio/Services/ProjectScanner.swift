import Foundation
import ImageIO

/// Finds images in the project folder that could be screenshots.
enum ProjectScanner {
    struct ImageInfo {
        var relativePath: String
        var width: Int
        var height: Int
    }

    private static let skipDirs: Set<String> = [
        "node_modules", ".git", "Pods", "build", "DerivedData", "vendor", ".build", "dist", ".next",
        ".expo", ".gradle", "Carthage", ".turbo", "coverage", "AppIcon.appiconset", ".swiftpm",
    ]
    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static func findImages(in root: URL, limit: Int = 160) -> [ImageInfo] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [ImageInfo] = []
        for case let url as URL in e {
            if skipDirs.contains(url.lastPathComponent) {
                e.skipDescendants()
                continue
            }
            guard imageExts.contains(url.pathExtension.lowercased()),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 40_000,
                  let (w, h) = dimensions(url), min(w, h) >= 400 else { continue }
            let rel = String(url.path.dropFirst(root.path.count + 1))
            found.append(ImageInfo(relativePath: rel, width: w, height: h))
            if found.count > limit * 3 { break }
        }
        // Prioritize screenshot / marketing folders and portrait images
        func score(_ i: ImageInfo) -> Int {
            let p = i.relativePath.lowercased()
            var s = 0
            for k in ["screenshot", "marketing", "fastlane", "store", "promo", "public"] where p.contains(k) { s += 3 }
            if i.height > i.width { s += 2 }
            if p.contains("/tr/") || p.contains("tr-tr") || p.contains("en-us") { s += 1 }
            return s
        }
        return Array(found.sorted { score($0) > score($1) }.prefix(limit))
    }

    static func dimensions(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}
