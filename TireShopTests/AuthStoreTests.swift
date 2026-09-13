import XCTest
@testable import TireShop

@MainActor
final class AuthStoreTests: XCTestCase {
    private func loginClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginStubProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }

    private func sessionClient(_ replies: [SessionStub.Reply]) -> (APIClient, SessionStub) {
        let identifier = UUID().uuidString
        let stub = SessionStub(replies: replies)
        SessionStubProtocol.register(stub, identifier: identifier)
        addTeardownBlock { SessionStubProtocol.unregister(identifier: identifier) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionStubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Auth-Test-ID": identifier]
        return (APIClient(session: URLSession(configuration: configuration)), stub)
    }

    private func savedSession(token: String = "saved-session-token") -> SavedSession {
        SavedSession(token: token, serverURL: Server.baseURL.absoluteString)
    }

    func testPasswordLoginPersistsSession() async throws {
        let api = loginClient()
        let storage = MemorySessionStorage()
        let auth = AuthStore(api: api, storage: storage)

        let result = try await auth.signIn(email: "password@example.com", password: "test-password")

        XCTAssertEqual(result, .ok)
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertEqual(storage.session?.token, "test-session-token")
        XCTAssertEqual(storage.session?.serverURL, Server.baseURL.absoluteString)
        XCTAssertEqual(auth.user?.id, "staff-1")
        XCTAssertTrue(auth.has("payments.collect"))
        XCTAssertTrue(auth.ready)
    }

    func testMFARequiresSuccessfulCodeBeforePersistingSession() async throws {
        let api = loginClient()
        let storage = MemorySessionStorage()
        let auth = AuthStore(api: api, storage: storage)

        let result = try await auth.signIn(email: "mfa@example.com", password: "test-password")
        XCTAssertEqual(result, .mfa(method: "TOTP", challengeToken: "test-challenge"))
        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)
        XCTAssertNil(storage.session)
        XCTAssertFalse(auth.has("payments.collect"))

        do {
            _ = try await auth.completeMFA(challengeToken: "test-challenge", code: "000000")
            XCTFail("An invalid verification code must not sign in")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)
        XCTAssertNil(storage.session)

        _ = try await auth.completeMFA(challengeToken: "test-challenge", code: "123456")
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertEqual(storage.session?.token, "test-session-token")
        XCTAssertEqual(storage.session?.serverURL, Server.baseURL.absoluteString)
        XCTAssertEqual(auth.user?.id, "staff-1")
        XCTAssertTrue(auth.has("payments.collect"))
    }

    func testInvalidPasswordDoesNotCreateSession() async throws {
        let api = loginClient()
        let storage = MemorySessionStorage()
        let auth = AuthStore(api: api, storage: storage)

        do {
            _ = try await auth.signIn(email: "password@example.com", password: "incorrect")
            XCTFail("An invalid password must not sign in")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }

        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)
        XCTAssertNil(storage.session)
        XCTAssertFalse(auth.has("payments.collect"))
    }

    func testFreshLaunchRestoresSavedTokenAndFetchesCurrentPermissions() async throws {
        let storage = MemorySessionStorage()
        let original = AuthStore(api: loginClient(), storage: storage)
        _ = try await original.signIn(email: "password@example.com", password: "test-password")
        XCTAssertTrue(original.has("payments.collect"))

        let (api, stub) = sessionClient([.http(200, Self.currentUserJSON)])
        let relaunched = AuthStore(api: api, storage: storage)
        XCTAssertFalse(relaunched.ready)
        XCTAssertNil(relaunched.user)
        XCTAssertFalse(relaunched.has("payments.collect"))

        await relaunched.restore()

        XCTAssertTrue(relaunched.ready)
        XCTAssertNil(relaunched.restoreError)
        XCTAssertEqual(relaunched.user?.id, "staff-1")
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertFalse(relaunched.has("payments.collect"), "Removed permissions must not survive a fresh launch")
        XCTAssertTrue(relaunched.has("inventory.read"))
        XCTAssertTrue(relaunched.canActOrRequest("sales.create"))
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/auth/session")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session-token")
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testMissingSavedSessionShowsLoginWithoutRequest() async {
        let (api, stub) = sessionClient([])
        let auth = AuthStore(api: api, storage: MemorySessionStorage())

        await auth.restore()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testSessionForDifferentServerIsClearedWithoutSendingToken() async {
        let (api, stub) = sessionClient([])
        let storage = MemorySessionStorage(session: SavedSession(
            token: "other-server-token", serverURL: "https://different-server.invalid"
        ))
        let auth = AuthStore(api: api, storage: storage)

        await auth.restore()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertNil(storage.session)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testExpiredSessionIsClearedAndShowsLogin() async {
        let (api, _) = sessionClient([.http(401, "{\"message\":\"Session expired\"}")])
        let storage = MemorySessionStorage(session: savedSession())
        let auth = AuthStore(api: api, storage: storage)

        await auth.restore()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertNil(storage.session)
    }

    func testOfflineRestoreKeepsSessionAndRetryCanSucceed() async {
        let (api, stub) = sessionClient([
            .failure(URLError(.notConnectedToInternet)), .http(200, Self.currentUserJSON)
        ])
        let storage = MemorySessionStorage(session: savedSession())
        let auth = AuthStore(api: api, storage: storage)

        await auth.restore()

        XCTAssertFalse(auth.ready)
        XCTAssertNotNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertEqual(storage.session?.token, "saved-session-token")
        XCTAssertFalse(auth.has("inventory.read"))

        await auth.restore()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertEqual(api.token, "saved-session-token")
        XCTAssertTrue(auth.has("inventory.read"))
        XCTAssertEqual(stub.requests.count, 2)
    }

    func testServerAndMalformedResponsesKeepSessionForRetry() async {
        for reply in [
            SessionStub.Reply.http(503, "{\"message\":\"Unavailable\"}"),
            .http(403, "{\"message\":\"Forbidden\"}"),
            .http(200, "{\"id\":\"incomplete-user\"}")
        ] {
            let (api, _) = sessionClient([reply])
            let storage = MemorySessionStorage(session: savedSession())
            let auth = AuthStore(api: api, storage: storage)

            await auth.restore()

            XCTAssertFalse(auth.ready)
            XCTAssertNotNil(auth.restoreError)
            XCTAssertNil(auth.user)
            XCTAssertNil(api.token)
            XCTAssertEqual(storage.session?.token, "saved-session-token")
        }
    }

    func testStorageReadFailureCanBeRetriedWithoutDeletingSession() async {
        let (api, stub) = sessionClient([.http(200, Self.currentUserJSON)])
        let storage = MemorySessionStorage(session: savedSession())
        storage.loadError = StorageFailure.unavailable
        let auth = AuthStore(api: api, storage: storage)

        await auth.restore()

        XCTAssertFalse(auth.ready)
        XCTAssertNotNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertEqual(storage.session?.token, "saved-session-token")
        XCTAssertTrue(stub.requests.isEmpty)

        storage.loadError = nil
        await auth.restore()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertTrue(auth.has("inventory.read"))
    }

    func testStorageSaveFailureDoesNotCreatePasswordOrMFASession() async {
        for useMFA in [false, true] {
            let api = loginClient()
            let storage = MemorySessionStorage()
            storage.saveError = StorageFailure.unavailable
            let auth = AuthStore(api: api, storage: storage)

            do {
                if useMFA {
                    _ = try await auth.completeMFA(challengeToken: "test-challenge", code: "123456")
                } else {
                    _ = try await auth.signIn(email: "password@example.com", password: "test-password")
                }
                XCTFail("A session must not become active when secure persistence fails")
            } catch {
                XCTAssertTrue(error is StorageFailure)
            }

            XCTAssertNil(api.token)
            XCTAssertNil(auth.user)
            XCTAssertNil(storage.session)
        }
    }

    func testSignOutRemovesPersistedSession() async throws {
        let api = loginClient()
        let storage = MemorySessionStorage()
        let auth = AuthStore(api: api, storage: storage)
        _ = try await auth.signIn(email: "password@example.com", password: "test-password")

        auth.signOut()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertNil(storage.session)
        XCTAssertFalse(auth.has("payments.collect"))

        let (relaunchedAPI, stub) = sessionClient([])
        let relaunched = AuthStore(api: relaunchedAPI, storage: storage)
        await relaunched.restore()
        XCTAssertTrue(relaunched.ready)
        XCTAssertNil(relaunched.user)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testSignOutWhileRestoreIsInFlightCannotSignBackIn() async {
        let (api, stub) = sessionClient([.deferred])
        let started = expectation(description: "Session validation started")
        stub.onDeferredRequest = { started.fulfill() }
        let storage = MemorySessionStorage(session: savedSession())
        let auth = AuthStore(api: api, storage: storage)
        let restore = Task { await auth.restore() }
        await fulfillment(of: [started], timeout: 2)

        XCTAssertFalse(auth.ready)
        XCTAssertNil(auth.user)
        auth.signOut()
        stub.completeDeferred(with: .http(200, Self.currentUserJSON))
        await restore.value

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertNil(storage.session)
    }

    func testSignOutStorageFailureRemainsGatedUntilRemovalCanBeRetried() async throws {
        let api = loginClient()
        let storage = MemorySessionStorage()
        let auth = AuthStore(api: api, storage: storage)
        _ = try await auth.signIn(email: "password@example.com", password: "test-password")
        storage.clearError = StorageFailure.unavailable

        auth.signOut()

        XCTAssertFalse(auth.ready)
        XCTAssertNotNil(auth.restoreError)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertEqual(storage.session?.token, "test-session-token")

        storage.clearError = nil
        auth.signOut()

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.restoreError)
        XCTAssertNil(storage.session)
    }

    func testRepeatedAndConcurrentRestoresDoNotSendDuplicateRequests() async {
        let (api, stub) = sessionClient([.deferred])
        let started = expectation(description: "Session validation started")
        stub.onDeferredRequest = { started.fulfill() }
        let auth = AuthStore(api: api, storage: MemorySessionStorage(session: savedSession()))
        let firstRestore = Task { await auth.restore() }
        await fulfillment(of: [started], timeout: 2)

        await auth.restore()
        XCTAssertFalse(auth.ready)
        XCTAssertNil(auth.user)
        XCTAssertEqual(stub.requests.count, 1)

        stub.completeDeferred(with: .http(200, Self.currentUserJSON))
        await firstRestore.value
        await auth.restore()
        XCTAssertTrue(auth.ready)
        XCTAssertTrue(auth.has("inventory.read"))
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testLateUnauthorizedResponseFromPreviousSessionKeepsNewLogin() async throws {
        let (api, stub) = sessionClient([
            .http(200, Self.currentUserJSON), .deferred, .http(200, LoginStubProtocol.sessionJSON)
        ])
        let storage = MemorySessionStorage(session: savedSession())
        let auth = AuthStore(api: api, storage: storage)
        await auth.restore()
        let started = expectation(description: "Old authenticated request started")
        stub.onDeferredRequest = { started.fulfill() }
        let oldRequest = Task { try await api.data("/test/protected") }
        await fulfillment(of: [started], timeout: 2)

        auth.signOut()
        _ = try await auth.signIn(email: "password@example.com", password: "test-password")
        stub.completeDeferred(with: .http(401, "{\"message\":\"Session expired\"}"))
        do {
            _ = try await oldRequest.value
            XCTFail("The old request must fail")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }

        XCTAssertTrue(auth.ready)
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertEqual(storage.session?.token, "test-session-token")
        XCTAssertEqual(auth.user?.id, "staff-1")
        XCTAssertTrue(auth.has("payments.collect"))
    }

    func testUnauthorizedResponseForCurrentSessionRemovesSavedCredential() async throws {
        let (api, _) = sessionClient([
            .http(200, Self.currentUserJSON), .http(401, "{\"message\":\"Session expired\"}")
        ])
        let storage = MemorySessionStorage(session: savedSession())
        let auth = AuthStore(api: api, storage: storage)
        await auth.restore()
        let cleared = expectation(description: "Unauthorized session removed")
        storage.onClear = { cleared.fulfill() }

        do {
            _ = try await api.data("/test/protected")
            XCTFail("The unauthorized request must fail")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }
        await fulfillment(of: [cleared], timeout: 2)

        XCTAssertTrue(auth.ready)
        XCTAssertNil(auth.user)
        XCTAssertNil(api.token)
        XCTAssertNil(storage.session)
        XCTAssertFalse(auth.has("inventory.read"))
    }

    private static let currentUserJSON = """
    {"id":"staff-1","email":"staff@example.com","fullName":"Staff User",
     "roleId":"stock-clerk","roleName":"Stock Clerk","isAdmin":false,
     "permissions":["inventory.read"],"approvalPermissions":["sales.create"],"mfaMethod":"TOTP"}
    """
}

private enum StorageFailure: Error {
    case unavailable
}

private final class MemorySessionStorage: SessionStorage {
    var session: SavedSession?
    var loadError: Error?
    var saveError: Error?
    var clearError: Error?
    var onClear: (() -> Void)?

    init(session: SavedSession? = nil) {
        self.session = session
    }

    func load() throws -> SavedSession? {
        if let loadError { throw loadError }
        return session
    }

    func save(_ session: SavedSession) throws {
        if let saveError { throw saveError }
        self.session = session
    }

    func clear() throws {
        if let clearError { throw clearError }
        session = nil
        onClear?()
    }
}

/// Every client gets a distinct registry entry so concurrent tests cannot route
/// requests through another test's responses. Deferred replies coordinate races
/// with expectations rather than timing assumptions.
private final class SessionStub {
    enum Reply {
        case http(Int, String)
        case failure(Error)
        case deferred
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recordedRequests: [URLRequest] = []
    private var pending: SessionStubProtocol?
    var onDeferredRequest: (() -> Void)?

    init(replies: [Reply]) {
        self.replies = replies
    }

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func receive(_ connection: SessionStubProtocol) {
        let reply = lock.withLock { () -> Reply in
            recordedRequests.append(connection.request)
            guard !replies.isEmpty else { return .failure(URLError(.resourceUnavailable)) }
            let reply = replies.removeFirst()
            if case .deferred = reply { pending = connection }
            return reply
        }
        if case .deferred = reply {
            onDeferredRequest?()
        } else {
            connection.complete(with: reply)
        }
    }

    func completeDeferred(with reply: Reply) {
        let connection = lock.withLock { () -> SessionStubProtocol? in
            defer { pending = nil }
            return pending
        }
        XCTAssertNotNil(connection, "A deferred request must start before it can complete")
        connection?.complete(with: reply)
    }
}

private final class SessionStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var stubs: [String: SessionStub] = [:]

    static func register(_ stub: SessionStub, identifier: String) {
        lock.withLock { stubs[identifier] = stub }
    }

    static func unregister(identifier: String) {
        _ = lock.withLock { stubs.removeValue(forKey: identifier) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let identifier = request.value(forHTTPHeaderField: "X-Auth-Test-ID") ?? ""
        guard let stub = Self.lock.withLock({ Self.stubs[identifier] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        stub.receive(self)
    }

    func complete(with reply: SessionStub.Reply) {
        switch reply {
        case .http(let status, let body):
            guard let url = request.url, let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .deferred:
            XCTFail("Deferred responses must be completed with a concrete result")
        }
    }

    override func stopLoading() {}
}

private final class LoginStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONDecoder().decode([String: String].self, from: data)
            let url = try XCTUnwrap(request.url)
            guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == nil else {
                throw URLError(.badServerResponse)
            }

            var status = 401
            var responseBody = "{\"message\":\"Invalid credentials\"}"
            if url.path == "/api/auth/login", body["password"] == "test-password" {
                status = 200
                responseBody = body["email"] == "mfa@example.com"
                    ? "{\"mfaRequired\":true,\"method\":\"TOTP\",\"challengeToken\":\"test-challenge\"}"
                    : Self.sessionJSON
            } else if url.path == "/api/auth/mfa/verify",
                      body["challengeToken"] == "test-challenge", body["code"] == "123456" {
                status = 200
                responseBody = Self.sessionJSON
            }

            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static let sessionJSON = """
    {"accessToken":"test-session-token","user":{
      "id":"staff-1","email":"staff@example.com","fullName":"Staff User",
      "roleId":"cashier","roleName":"Cashier","isAdmin":false,
      "permissions":["payments.collect"],"approvalPermissions":[],"mfaMethod":"TOTP"
    }}
    """
}
