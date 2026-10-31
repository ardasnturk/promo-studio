import CoreGraphics
import Foundation
import ImageIO

enum SimulatorError: LocalizedError {
    case noDevice
    case appNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noDevice: String(localized: "No suitable iPhone simulator found. Download an iOS simulator runtime in Xcode.")
        case let .appNotFound(id): String(localized: "The build finished, but the app \(id) wasn't found.")
        }
    }
}

/// Launches the app in the iOS Simulator in the requested language with demo data and captures the recipe's screens.
enum SimulatorService {
    /// Device reserved for Promo Studio so the user's own simulators are left alone
    static let deviceName = "Promo Studio · iPhone"
    /// Device created by older versions (also used, to avoid creating another)
    static let legacyDeviceName = "Automat · iPhone"

    /// ContentLanguage code → (AppleLanguages, AppleLocale)
    static func localeArguments(for code: String) -> [String] {
        let locales = ["tr": "tr_TR", "en": "en_US", "de": "de_DE", "es": "es_ES", "it": "it_IT",
                       "fr": "fr_FR", "pt": "pt_BR", "ja": "ja_JP", "zh-Hans": "zh_CN"]
        let appleLanguage = code == "pt" ? "pt-BR" : code
        return ["-AppleLanguages", "(\(appleLanguage))", "-AppleLocale", locales[code] ?? "en_US"]
    }

    /// Finds the Promo Studio device, or creates an iPhone Pro on the newest iOS; boots it if not running.
    static func ensureDevice(onStatus: @Sendable (String) -> Void) async throws -> String {
        let json = try await ProcessRunner.run("xcrun", ["simctl", "list", "-j", "devices", "available"])
        let data = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let devices = data?["devices"] as? [String: [[String: Any]]] ?? [:]
        var udid = devices.values.joined().first { [deviceName, legacyDeviceName].contains($0["name"] as? String ?? "") }?["udid"] as? String

        if udid == nil {
            onStatus(String(localized: "Creating simulator…"))
            let runtimes = devices.keys.filter { $0.contains("iOS") }.sorted { version($1).lexicographicallyPrecedes(version($0)) }
            for runtime in runtimes {
                for type in ["iPhone-17-Pro", "iPhone-16-Pro", "iPhone-15-Pro"] {
                    if let out = try? await ProcessRunner.run("xcrun", ["simctl", "create", deviceName, "com.apple.CoreSimulator.SimDeviceType.\(type)", runtime]) {
                        udid = out.trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
                if udid != nil { break }
            }
        }
        guard let udid else { throw SimulatorError.noDevice }

        let state = devices.values.joined().first { $0["udid"] as? String == udid }?["state"] as? String
        if state != "Booted" {
            onStatus(String(localized: "Booting simulator…"))
            _ = try? await ProcessRunner.run("xcrun", ["simctl", "boot", udid])
            try await ProcessRunner.run("xcrun", ["simctl", "bootstatus", udid, "-b"])
        }
        // A clean status bar: 9:41, full battery, full signal
        _ = try? await ProcessRunner.run("xcrun", ["simctl", "status_bar", udid, "override", "--time", "9:41",
                                                   "--batteryState", "charged", "--batteryLevel", "100",
                                                   "--cellularMode", "active", "--cellularBars", "4", "--wifiBars", "3"])
        return udid
    }

    static func isInstalled(_ bundleId: String, on udid: String) async -> Bool {
        (try? await ProcessRunner.run("xcrun", ["simctl", "get_app_container", udid, bundleId])) != nil
    }

    /// Builds and installs the app for the simulator.
    static func buildAndInstall(_ recipe: CaptureRecipe, project: AppProject, udid: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let dir = project.folderURL.appendingPathComponent(recipe.buildDirectory)
        if !recipe.prebuildCommand.trimmingCharacters(in: .whitespaces).isEmpty {
            onLine(String(localized: "Preparing: \(recipe.prebuildCommand)"))
            try await ProcessRunner.run("/bin/zsh", ["-lc", recipe.prebuildCommand], cwd: dir, onLine: onLine)
        }
        let derived = Paths.ensure(Paths.root.appendingPathComponent("derived/\(project.id.uuidString)"))
        let projectFlag = recipe.projectFile.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        onLine(String(localized: "Building \(recipe.scheme)…"))
        try await ProcessRunner.run("xcodebuild", [
            projectFlag, recipe.projectFile, "-scheme", recipe.scheme, "-configuration", "Debug",
            "-destination", "id=\(udid)", "-derivedDataPath", derived.path,
            "CODE_SIGNING_ALLOWED=NO", "build",
        ], cwd: dir) { line in
            if line.contains("error:") || line.hasPrefix("**") || line.contains("Compiling") { onLine(line) }
        }

        let products = derived.appendingPathComponent("Build/Products/Debug-iphonesimulator")
        let apps = (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: {
            $0.pathExtension == "app"
                && (NSDictionary(contentsOf: $0.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String) == recipe.bundleId
        }) else { throw SimulatorError.appNotFound(recipe.bundleId) }
        onLine(String(localized: "Installing on the simulator…"))
        try await ProcessRunner.run("xcrun", ["simctl", "install", udid, app.path])
    }

    // MARK: Capture tool (XCUITest)

    private static var runnerDir: URL { Paths.root.appendingPathComponent("capture-runner") }

    /// Copies the bundled capture tool and builds it once for the simulator (again if the source changes).
    /// Returns: the .xctestrun file.
    static func prepareRunner(udid: String, onStatus: @Sendable (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        let source = runnerDir.appendingPathComponent("src")
        let derived = runnerDir.appendingPathComponent("dd")
        if let bundled = Bundle.main.url(forResource: "CaptureRunner", withExtension: nil) {
            let marker = "CaptureUITests/CaptureTests.swift"
            let changed = (try? Data(contentsOf: bundled.appendingPathComponent(marker))) != (try? Data(contentsOf: source.appendingPathComponent(marker)))
            if changed {
                try? fm.removeItem(at: source)
                try? fm.removeItem(at: derived)
                Paths.ensure(runnerDir)
                try fm.copyItem(at: bundled, to: source)
            }
        }
        let products = derived.appendingPathComponent("Build/Products")
        if let existing = (try? fm.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "xctestrun" }) {
            return existing
        }
        onStatus(String(localized: "Building the capture tool (first time only)…"))
        try await ProcessRunner.run("xcodebuild", [
            "build-for-testing", "-project", "PromoStudioCaptureRunner.xcodeproj", "-scheme", "CaptureUITests",
            "-destination", "id=\(udid)", "-derivedDataPath", derived.path, "CODE_SIGNING_ALLOWED=NO",
        ], cwd: source)
        guard let run = (try? fm.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "xctestrun" }) else {
            throw SimulatorError.appNotFound("PromoStudioCaptureRunner")
        }
        return run
    }

    /// Captures the recipe's screens in the given language. Each screen is shot in the dark/light theme of the image it localizes.
    /// Returns: screen ID → PNG file.
    static func capture(
        _ recipe: CaptureRecipe,
        shots: [CaptureRecipe.Shot],
        language: String,
        udid: String,
        into dir: URL,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> [String: URL] {
        let xctestrun = try await prepareRunner(udid: udid, onStatus: onStatus)
        let langLabel = ContentLanguage.find(language).label
        var result: [String: URL] = [:]

        let groups = Dictionary(grouping: shots) { isDark(dir.appendingPathComponent($0.assetFile)) }
        for (dark, group) in groups.sorted(by: { !$0.key && $1.key }) {
            _ = try? await ProcessRunner.run("xcrun", ["simctl", "ui", udid, "appearance", dark ? "dark" : "light"])
            var jobShots: [[String: Any]] = []
            for shot in group {
                let file = dir.appendingPathComponent("sim-\(shot.id)-\(language).png")
                try? FileManager.default.removeItem(at: file)
                jobShots.append([
                    "id": shot.id,
                    "launchArguments": recipe.launchArguments + localeArguments(for: language) + shot.extraArguments,
                    "url": shot.url,
                    "taps": shot.taps ?? [],
                    "waitSeconds": shot.waitSeconds,
                    "output": file.path,
                ])
                result[shot.id] = file
            }
            let jobFile = runnerDir.appendingPathComponent("job-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: ["bundleId": recipe.bundleId, "shots": jobShots]).write(to: jobFile)
            defer { try? FileManager.default.removeItem(at: jobFile) }

            let labels = Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0.label) })
            onStatus(String(localized: "\(langLabel): capturing…"))
            try await ProcessRunner.run(
                "xcodebuild",
                ["test-without-building", "-xctestrun", xctestrun.path, "-destination", "id=\(udid)"],
                extraEnvironment: ["TEST_RUNNER_PROMO_STUDIO_JOB": jobFile.path]
            ) { line in
                if let r = line.range(of: "AUTOMAT_SHOT_DONE ") {
                    let id = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    onStatus("\(langLabel): \(labels[id] ?? id) ✓")
                } else if let r = line.range(of: "AUTOMAT_TAP_MISSING ") {
                    onStatus(String(localized: "Element to tap not found: \(line[r.upperBound...])"))
                }
            }
        }
        return result.filter { FileManager.default.fileExists(atPath: $0.value.path) }
    }

    /// Guesses whether the image is in dark mode from its average brightness.
    static func isDark(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        guard let ctx = CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        }
        return sum / 256 < 100
    }

    private static func version(_ runtime: String) -> [Int] {
        runtime.split(separator: ".").last.map { $0.split(separator: "-").dropFirst().compactMap { Int($0) } } ?? []
    }
}
