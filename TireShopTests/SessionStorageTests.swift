import Security
import XCTest
@testable import TireShop

final class SessionStorageTests: XCTestCase {
    private var service = ""
    private let account = "test-session"

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = "tire-shop-ios.tests.session.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
        XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound)
        try super.tearDownWithError()
    }

    func testSavedSessionSurvivesNewStorageInstanceAndCanBeUpdated() throws {
        let original = SavedSession(token: "first-token", serverURL: "https://first.example.com")
        let replacement = SavedSession(token: "second-token", serverURL: "https://second.example.com")
        let writer = storage()
        XCTAssertNil(try writer.load())

        try writer.save(original)
        XCTAssertEqual(try storage().load(), original)

        try storage().save(replacement)
        XCTAssertEqual(try writer.load(), replacement)
        XCTAssertEqual(try storage().load(), replacement)
    }

    func testClearRemovesOnlySelectedAccountAndIsIdempotent() throws {
        let session = SavedSession(token: "test-token", serverURL: "https://example.com")
        let otherAccount = KeychainSessionStorage(service: service, account: "other-account")
        try storage().save(session)
        try otherAccount.save(session)

        try storage().clear()
        XCTAssertNil(try storage().load())
        XCTAssertEqual(try otherAccount.load(), session)
        XCTAssertNoThrow(try storage().clear())
    }

    func testSavedItemUsesDeviceOnlyUnlockedAccessibility() throws {
        try storage().save(SavedSession(token: "test-token", serverURL: "https://example.com"))
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?

        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testCorruptSavedItemReportsErrorAndCanBeReplaced() throws {
        var item = itemQuery
        item[kSecValueData as String] = Data("not valid session JSON".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)

        XCTAssertThrowsError(try storage().load()) { error in
            XCTAssertEqual(error as? KeychainSessionStorageError, .invalidData)
        }

        let replacement = SavedSession(token: "replacement-token", serverURL: "https://example.com")
        try storage().save(replacement)
        XCTAssertEqual(try storage().load(), replacement)
    }

    private func storage() -> KeychainSessionStorage {
        KeychainSessionStorage(service: service, account: account)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
