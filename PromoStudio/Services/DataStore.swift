import Foundation

/// Stores all app data in a single JSON file (Application Support/Promo Studio/data.json).
enum DataStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> AppData {
        guard let data = try? Data(contentsOf: Paths.dataFile) else { return AppData() }
        do {
            return try decoder.decode(AppData.self, from: data)
        } catch {
            // Back up the corrupt file before overwriting it
            let backup = Paths.root.appendingPathComponent("data.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: Paths.dataFile, to: backup)
            return AppData()
        }
    }

    static func save(_ appData: AppData) {
        guard let data = try? encoder.encode(appData) else { return }
        try? data.write(to: Paths.dataFile, options: .atomic)
    }
}
