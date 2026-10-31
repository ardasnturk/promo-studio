import Foundation
import Security
import Synchronization

/// All secrets (Instagram tokens, Meta App Secret, Gemini key) are stored in a single Keychain item
/// as JSON, read once at launch and kept in memory: macOS asks for permission per item,
/// so this way at most one permission prompt appears.
enum Keychain {
    private static let service = "com.jastech.PromoStudio"
    private static let account = "secrets"
    /// Items from when the app was called "Automat"
    private static let legacyService = "com.jastech.automat"

    /// nil: not read from the Keychain yet
    private static let cache = Mutex<[String: String]?>(nil)

    static func get(_ key: String) -> String? {
        cache.withLock { values in
            if values == nil { values = load() }
            return values?[key]
        }
    }

    static func set(_ value: String?, for key: String) {
        cache.withLock { values in
            var current = values ?? load()
            let trimmed = value.flatMap { $0.isEmpty ? nil : $0 }
            guard current[key] != trimmed else { values = current; return }
            current[key] = trimmed
            values = current
            save(current)
        }
    }

    // MARK: Storage

    private static func load() -> [String: String] {
        if let data = readData(service: service, account: account),
           let values = try? JSONDecoder().decode([String: String].self, from: data) {
            return values
        }
        // First launch: migrate the old one-item-per-secret layout to a single item. Item names are listed without a prompt;
        // only one copy of each key is read (Promo Studio first, else Automat) to keep prompts few.
        let current = accounts(service: service), legacy = accounts(service: legacyService)
        var values: [String: String] = [:]
        for key in current.union(legacy) {
            let source = current.contains(key) ? service : legacyService
            if let data = readData(service: source, account: key),
               let value = String(data: data, encoding: .utf8), !value.isEmpty { values[key] = value }
        }
        guard !values.isEmpty else { return [:] }
        // Old items are deleted only if the new item was written
        guard save(values) else { return values }
        for key in current { delete(service: service, account: key) }
        for key in legacy { delete(service: legacyService, account: key) }
        return values
    }

    @discardableResult
    private static func save(_ values: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(values) else { return false }
        let base = baseQuery(service: service, account: account)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Promo Studio"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readData(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Account names of a service's items (no prompt, since only attributes are read)
    private static func accounts(service: String) -> Set<String> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]] else { return [] }
        return Set(list.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0 != account })
    }

    private static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    enum Key {
        /// Single-account token from older versions (moved into accounts on first launch)
        static let legacyInstagramToken = "instagram.accessToken"
        static func instagramToken(_ accountId: String) -> String { "instagram.token.\(accountId)" }
        static let metaAppSecret = "meta.appSecret"
        static let geminiApiKey = "gemini.apiKey"
    }
}
