import Foundation
import Security

enum Server {
    static let baseURL = URL(string: "https://awstire.tail263731.ts.net")!
}

struct APIError: Error, LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? { message }
}

struct SessionUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    var fullName: String
    let roleId: String
    let roleName: String
    let isAdmin: Bool
    let permissions: [String]
    let approvalPermissions: [String]?
    let mfaMethod: String?
}

struct MFALoginChallenge: Decodable, Equatable {
    let method: String
    let challengeToken: String
}

struct LoginSession: Decodable, Equatable {
    let accessToken: String
    let user: SessionUser
    let usedBackupCode: Bool?
    let backupCodesRemaining: Int?
}

enum LoginResult: Equatable {
    case session(LoginSession)
    case mfa(MFALoginChallenge)
}

private struct LoginResultEnvelope: Decodable {
    let mfaRequired: Bool?
    let method: String?
    let challengeToken: String?
    let accessToken: String?
    let user: SessionUser?
    let usedBackupCode: Bool?
    let backupCodesRemaining: Int?
}

final class APIClient {
    static let shared = APIClient()

    var token: String?
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(email: String, password: String) async throws -> LoginResult {
        let body = ["email": email, "password": password]
        let envelope: LoginResultEnvelope = try await request(
            "/auth/login",
            method: "POST",
            body: body,
            noAuthBounce: true
        )

        if envelope.mfaRequired == true {
            guard let challengeToken = envelope.challengeToken else {
                throw APIError(status: 0, message: "The server returned an invalid MFA challenge.")
            }

            return .mfa(
                MFALoginChallenge(
                    method: envelope.method ?? "TOTP",
                    challengeToken: challengeToken
                )
            )
        }

        guard let accessToken = envelope.accessToken, let user = envelope.user else {
            throw APIError(status: 0, message: "The server returned an invalid login session.")
        }

        return .session(
            LoginSession(
                accessToken: accessToken,
                user: user,
                usedBackupCode: envelope.usedBackupCode,
                backupCodesRemaining: envelope.backupCodesRemaining
            )
        )
    }

    func verifyMFA(challengeToken: String, code: String) async throws -> LoginSession {
        try await request(
            "/auth/mfa/verify",
            method: "POST",
            body: ["challengeToken": challengeToken, "code": code],
            noAuthBounce: true
        )
    }

    func uploadMultipart<T: Decodable>(
        _ path: String,
        fileURL: URL,
        fieldName: String = "file",
        fileName: String,
        mimeType: String,
        fields: [String: String] = [:]
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api\(path)"

        guard let url = components?.url else {
            throw APIError(status: 0, message: "The request URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for (name, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        body.appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        return try decode(data: data, response: response, unauthorizedMessage: "Session expired. Please sign in again.")
    }

    func download(_ path: String, fileName: String) async throws -> URL {
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api\(path)"

        guard let url = components?.url else {
            throw APIError(status: 0, message: "The request URL is invalid.")
        }

        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 {
            token = nil
            KeychainStore.deleteToken()
            onUnauthorized?()
            throw APIError(status: 401, message: "Session expired. Please sign in again.")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: "Download failed (\(http.statusCode)).")
        }

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func data(_ path: String, noAuthBounce: Bool = false) async throws -> Data {
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = "/api\(pieces.first.map(String.init) ?? path)"
        if pieces.count > 1 {
            components?.percentEncodedQuery = String(pieces[1])
        }

        guard let url = components?.url else {
            throw APIError(status: 0, message: "The request URL is invalid.")
        }

        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 && !noAuthBounce {
            token = nil
            KeychainStore.deleteToken()
            onUnauthorized?()
            throw APIError(status: 401, message: "Session expired. Please sign in again.")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorMessage(from: data, status: http.statusCode))
        }

        return data
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        noAuthBounce: Bool = false
    ) async throws -> T {
        try await performRequest(path, method: method, bodyData: nil, noAuthBounce: noAuthBounce)
    }

    func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        body: Body,
        noAuthBounce: Bool = false
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await performRequest(path, method: method, bodyData: bodyData, noAuthBounce: noAuthBounce)
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        method: String,
        bodyData: Data?,
        noAuthBounce: Bool
    ) async throws -> T {
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = "/api\(pieces.first.map(String.init) ?? path)"
        if pieces.count > 1 {
            components?.percentEncodedQuery = String(pieces[1])
        }

        guard let url = components?.url else {
            throw APIError(status: 0, message: "The request URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError(
                status: 0,
                message: "Can't reach the server at \(Server.baseURL.absoluteString). Check the network."
            )
        }

        return try decode(
            data: data,
            response: response,
            noAuthBounce: noAuthBounce,
            unauthorizedMessage: "Session expired. Please sign in again."
        )
    }

    private func decode<T: Decodable>(
        data: Data,
        response: URLResponse,
        noAuthBounce: Bool = false,
        unauthorizedMessage: String
    ) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 && !noAuthBounce {
            token = nil
            KeychainStore.deleteToken()
            onUnauthorized?()
            throw APIError(status: 401, message: unauthorizedMessage)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorMessage(from: data, status: http.statusCode))
        }

        if T.self == EmptyResponse.self {
            guard let empty = EmptyResponse.value as? T else {
                throw APIError(status: 0, message: "The empty response type is invalid.")
            }
            return empty
        }

        return try decoder.decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"]
        else {
            return "Request failed (\(status))."
        }

        if let text = message as? String {
            return text
        }

        if let messages = message as? [String] {
            return messages.joined(separator: ", ")
        }

        return "Request failed (\(status))."
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}

struct EmptyResponse: Decodable {}

extension EmptyResponse {
    static let value = EmptyResponse()
}

enum KeychainStore {
    private static let service = "tire-shop-ios"
    private static let account = "ts_token"

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        deleteToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8)
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
