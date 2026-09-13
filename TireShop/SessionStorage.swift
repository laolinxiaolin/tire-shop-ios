import Foundation
import Security

struct SavedSession: Codable, Equatable {
    let token: String
    let serverURL: String
}

protocol SessionStorage {
    func load() throws -> SavedSession?
    func save(_ session: SavedSession) throws
    func clear() throws
}

enum KeychainSessionStorageError: Error, LocalizedError, Equatable {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "Could not access the saved session (Keychain error \(status))."
        case .invalidData:
            return "The saved session could not be read."
        }
    }
}

struct KeychainSessionStorage: SessionStorage {
    private let service: String
    private let account: String

    init(service: String = "tire-shop-ios", account: String = "ts_session_v1") {
        self.service = service
        self.account = account
    }

    func load() throws -> SavedSession? {
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)

        guard let data = result as? Data,
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else {
            throw KeychainSessionStorageError.invalidData
        }
        return session
    }

    func save(_ session: SavedSession) throws {
        // Keep the token bound to its server in a single Keychain item.
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else {
            try check(status)
            return
        }

        let newItem = itemQuery.merging(attributes) { _, new in new }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another writer may have added the same item after our update.
            try check(SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary))
        } else {
            try check(addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        if status != errSecItemNotFound {
            try check(status)
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw KeychainSessionStorageError.status(status)
        }
    }
}
