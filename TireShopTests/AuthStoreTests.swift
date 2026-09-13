import XCTest
@testable import TireShop

@MainActor
final class AuthStoreTests: XCTestCase {
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginStubProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }

    func testPasswordLoginCreatesSession() async throws {
        let api = client()
        let auth = AuthStore(api: api)

        let result = try await auth.signIn(email: "password@example.com", password: "test-password")

        XCTAssertEqual(result, .ok)
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertEqual(auth.user?.id, "staff-1")
        XCTAssertTrue(auth.has("payments.collect"))
    }

    func testMFARequiresSuccessfulCodeBeforeCreatingSession() async throws {
        let api = client()
        let auth = AuthStore(api: api)

        let result = try await auth.signIn(email: "mfa@example.com", password: "test-password")
        XCTAssertEqual(result, .mfa(method: "TOTP", challengeToken: "test-challenge"))
        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)
        XCTAssertFalse(auth.has("payments.collect"))

        do {
            _ = try await auth.completeMFA(challengeToken: "test-challenge", code: "000000")
            XCTFail("An invalid verification code must not sign in")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)

        _ = try await auth.completeMFA(challengeToken: "test-challenge", code: "123456")
        XCTAssertEqual(api.token, "test-session-token")
        XCTAssertEqual(auth.user?.id, "staff-1")
        XCTAssertTrue(auth.has("payments.collect"))
    }

    func testInvalidPasswordDoesNotCreateSession() async throws {
        let api = client()
        let auth = AuthStore(api: api)

        do {
            _ = try await auth.signIn(email: "password@example.com", password: "incorrect")
            XCTFail("An invalid password must not sign in")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 401)
        }

        XCTAssertNil(api.token)
        XCTAssertNil(auth.user)
        XCTAssertFalse(auth.has("payments.collect"))
    }
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

    private static let sessionJSON = """
    {"accessToken":"test-session-token","user":{
      "id":"staff-1","email":"staff@example.com","fullName":"Staff User",
      "roleId":"cashier","roleName":"Cashier","isAdmin":false,
      "permissions":["payments.collect"],"approvalPermissions":[],"mfaMethod":"TOTP"
    }}
    """
}
