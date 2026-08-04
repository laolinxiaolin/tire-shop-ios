import CoreTransferable
import Foundation
import Security
import UniformTypeIdentifiers
import os

enum Server {
    static let defaultBaseURLString = "https://laolin.net"
    private static let storageKey = "ts_server_url"

    static var baseURL: URL {
        if
            let stored = UserDefaults.standard.string(forKey: storageKey),
            let url = normalized(stored)
        {
            return url
        }
        return URL(string: defaultBaseURLString)!
    }

    static var baseURLString: String {
        guard
            let stored = UserDefaults.standard.string(forKey: storageKey),
            let url = normalized(stored)
        else { return defaultBaseURLString }

        return url.absoluteString
    }

    /// Persist a new server URL. Accepts a bare host ("laolin.net") and adds
    /// https. Returns false without saving when the value is not a usable
    /// HTTPS URL; Debug builds also accept HTTP for local development. An empty
    /// value resets to the default.
    @discardableResult
    static func setBaseURL(_ raw: String) -> Bool {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return true
        }

        guard let url = normalized(raw) else { return false }
        UserDefaults.standard.set(url.absoluteString, forKey: storageKey)
        return true
    }

    private static func normalized(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return nil
        }

#if DEBUG
        guard scheme == "https" || scheme == "http" else { return nil }
#else
        guard scheme == "https" else { return nil }
#endif

        return url
    }
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
    let homeWarehouse: String?
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

enum UploadFilePreparation {
    static let maximumBytes = 50 * 1_024 * 1_024

    static func validate(byteCount: Int) throws {
        guard byteCount <= maximumBytes else {
            throw APIError(status: 0, message: "The selected file is larger than the 50 MB upload limit.")
        }
    }

    static func copySecurityScopedFile(_ sourceURL: URL, prefix: String) async throws -> URL {
        let copyTask = Task.detached(priority: .utility) {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw APIError(status: 0, message: "The selected upload is not a regular file.")
            }
            guard let fileSize = values.fileSize else {
                throw APIError(status: 0, message: "Could not determine the selected file's size.")
            }
            try validate(byteCount: fileSize)
            try Task.checkCancellation()

            let safeName = sourceURL.lastPathComponent
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: ".")
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(prefix)-\(UUID().uuidString)-\(safeName)")

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                try Task.checkCancellation()
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        return try await withTaskCancellationHandler {
            try await copyTask.value
        } onCancel: {
            copyTask.cancel()
        }
    }

    static func writeTemporaryData(
        _ data: Data,
        filename: String,
        prefix: String
    ) async throws -> URL {
        let writeTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let destination = try writeTemporaryDataSynchronously(
                data,
                filename: filename,
                prefix: prefix
            )

            do {
                try Task.checkCancellation()
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        return try await withTaskCancellationHandler {
            try await writeTask.value
        } onCancel: {
            writeTask.cancel()
        }
    }

    static func writeTemporaryDataSynchronously(
        _ data: Data,
        filename: String,
        prefix: String
    ) throws -> URL {
        try validate(byteCount: data.count)

        let safeName = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)-\(safeName)")

        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

enum TemporaryDownloadStore {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TireShopDownloads", isDirectory: true)

    static func remove(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeStaleFiles(olderThan cutoff: Date = Date().addingTimeInterval(-86_400)) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files {
            guard
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let modified = values.contentModificationDate,
                modified < cutoff
            else {
                continue
            }
            remove(file)
        }
    }
}

struct UploadPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let copiedURL = try await UploadFilePreparation.copySecurityScopedFile(
                received.file,
                prefix: "photo-import"
            )
            return UploadPhotoFile(url: copiedURL)
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    /// Requests read the token from the cooperative pool while sign-in and
    /// sign-out write it from the main actor, so it is lock-guarded rather than
    /// a bare stored property.
    private let tokenLock = OSAllocatedUnfairLock<String?>(initialState: nil)

    var token: String? {
        get { tokenLock.withLock { $0 } }
        set { tokenLock.withLock { $0 = newValue } }
    }

    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
        Task.detached(priority: .utility) {
            TemporaryDownloadStore.removeStaleFiles()
        }
    }

    func login(email: String, password: String) async throws -> LoginResult {
        let body = ["email": email, "password": password]
        let envelope: LoginResultEnvelope = try await request(
            "/auth/login",
            method: "POST",
            body: body,
            noAuthBounce: true,
            includeAuth: false
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
            noAuthBounce: true,
            includeAuth: false
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
        let multipartURL = try await Self.makeMultipartBodyFile(
            sourceURL: fileURL,
            boundary: boundary,
            fieldName: fieldName,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
        defer { try? FileManager.default.removeItem(at: multipartURL) }

        var request = URLRequest(url: try Self.endpointURL(for: path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let requestToken = token
        if let requestToken {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: request, fromFile: multipartURL)
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        return try decode(
            data: data,
            response: response,
            requestToken: requestToken,
            unauthorizedMessage: "Session expired. Please sign in again."
        )
    }

    func download(_ path: String, fileName: String) async throws -> URL {
        var request = URLRequest(url: try Self.endpointURL(for: path))
        let requestToken = token
        if let requestToken {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 {
            invalidateSession(ifCurrentRequestToken: requestToken)
            throw APIError(status: 401, message: "Session expired. Please sign in again.")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: "Download failed (\(http.statusCode)).")
        }

        let normalizedName = fileName.replacingOccurrences(of: "\\", with: "/")
        let requestedName = normalizedName.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        let safeName: String
        if let requestedName, requestedName != ".", requestedName != ".." {
            let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
            let sanitized = requestedName.components(separatedBy: forbidden).joined(separator: "_")
            safeName = sanitized.nilIfBlank ?? "download"
        } else {
            safeName = "download"
        }

        let downloadDirectory = TemporaryDownloadStore.directory
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let destination = downloadDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func data(_ path: String, noAuthBounce: Bool = false) async throws -> Data {
        var request = URLRequest(url: try Self.endpointURL(for: path))
        let requestToken = token
        if let requestToken {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            throw APIError(status: 0, message: "Can't reach the server at \(Server.baseURL.absoluteString).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 && !noAuthBounce {
            invalidateSession(ifCurrentRequestToken: requestToken)
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
        noAuthBounce: Bool = false,
        includeAuth: Bool = true,
        idempotencyKey: String? = nil
    ) async throws -> T {
        try await performRequest(
            path,
            method: method,
            bodyData: nil,
            noAuthBounce: noAuthBounce,
            includeAuth: includeAuth,
            idempotencyKey: idempotencyKey
        )
    }

    func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        body: Body,
        noAuthBounce: Bool = false,
        includeAuth: Bool = true,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await performRequest(
            path,
            method: method,
            bodyData: bodyData,
            noAuthBounce: noAuthBounce,
            includeAuth: includeAuth,
            idempotencyKey: idempotencyKey
        )
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        method: String,
        bodyData: Data?,
        noAuthBounce: Bool,
        includeAuth: Bool,
        idempotencyKey: String?
    ) async throws -> T {
        var request = URLRequest(url: try Self.endpointURL(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestToken = includeAuth ? token : nil
        if let requestToken {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey = idempotencyKey?.nilIfBlank {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Self.isCancellation(error) {
                throw error
            }
            throw APIError(
                status: 0,
                message: "Can't reach the server at \(Server.baseURL.absoluteString). Check the network."
            )
        }

        return try decode(
            data: data,
            response: response,
            noAuthBounce: noAuthBounce,
            requestToken: requestToken,
            unauthorizedMessage: "Session expired. Please sign in again."
        )
    }

    private func decode<T: Decodable>(
        data: Data,
        response: URLResponse,
        noAuthBounce: Bool = false,
        requestToken: String?,
        unauthorizedMessage: String
    ) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server returned an invalid response.")
        }

        if http.statusCode == 401 && !noAuthBounce {
            invalidateSession(ifCurrentRequestToken: requestToken)
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

    /// Build the absolute URL for an API path, keeping any query string the
    /// caller already percent-encoded into `path`.
    private static func endpointURL(for path: String) throws -> URL {
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = "/api\(pieces.first.map(String.init) ?? path)"
        if pieces.count > 1 {
            components?.percentEncodedQuery = String(pieces[1])
        }

        guard let url = components?.url else {
            throw APIError(status: 0, message: "The request URL is invalid.")
        }

        return url
    }

    private func invalidateSession(ifCurrentRequestToken requestToken: String?) {
        guard let requestToken else { return }

        // Check and clear under one lock so that concurrent 401s from the same
        // session tear it down — and notify — exactly once.
        let didInvalidate = tokenLock.withLock { current -> Bool in
            guard current == requestToken else { return false }
            current = nil
            return true
        }

        guard didInvalidate else { return }
        KeychainStore.deleteToken()
        onUnauthorized?()
    }

    private static func makeMultipartBodyFile(
        sourceURL: URL,
        boundary: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> URL {
        let task = Task.detached(priority: .utility) {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw APIError(status: 0, message: "The selected upload is not a regular file.")
            }
            guard (values.fileSize ?? 0) <= UploadFilePreparation.maximumBytes else {
                throw APIError(status: 0, message: "The selected file is larger than the 50 MB upload limit.")
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TireShopUploads", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bodyURL = directory.appendingPathComponent(UUID().uuidString)
            guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
                throw APIError(status: 0, message: "Could not prepare the selected file for upload.")
            }

            do {
                let output = try FileHandle(forWritingTo: bodyURL)
                defer { try? output.close() }

                func write(_ string: String) throws {
                    try output.write(contentsOf: Data(string.utf8))
                }

                for (rawName, value) in fields {
                    let name = Self.multipartHeaderValue(rawName, fallback: "field")
                    try write("--\(boundary)\r\n")
                    try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                    try write("\(value)\r\n")
                }

                let safeFieldName = Self.multipartHeaderValue(fieldName, fallback: "file")
                let safeFileName = Self.multipartHeaderValue(fileName, fallback: "upload")
                let safeMimeType = Self.multipartHeaderValue(mimeType, fallback: "application/octet-stream")
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(safeFieldName)\"; filename=\"\(safeFileName)\"\r\n")
                try write("Content-Type: \(safeMimeType)\r\n\r\n")

                let input = try FileHandle(forReadingFrom: sourceURL)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: chunk)
                }
                try write("\r\n--\(boundary)--\r\n")
                return bodyURL
            } catch {
                try? FileManager.default.removeItem(at: bodyURL)
                throw error
            }
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func multipartHeaderValue(_ value: String, fallback: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return sanitized.nilIfBlank ?? fallback
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        return false
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
