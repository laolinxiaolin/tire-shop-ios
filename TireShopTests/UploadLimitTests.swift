import XCTest
@testable import TireShop

final class UploadLimitTests: XCTestCase {
    @MainActor
    func testAccountChangeDuringMultipartPreparationDoesNotSendUpload() async throws {
        try await assertUploadCancelledDuringPreparation { client, _ in client.token = "replacement-user" }
    }

    @MainActor
    func testServerChangeDuringMultipartPreparationDoesNotSendUpload() async throws {
        let previousServer = Server.baseURLString
        defer { Server.setBaseURL(previousServer) }
        try await assertUploadCancelledDuringPreparation { _, _ in Server.setBaseURL("https://different-upload-server.invalid") }
    }

    @MainActor
    func testCancellationDuringMultipartPreparationRemovesBodyWithoutSending() async throws {
        try await assertUploadCancelledDuringPreparation { _, upload in upload.cancel() }
    }

    @MainActor
    private func assertUploadCancelledDuringPreparation(
        change: (APIClient, Task<Void, Error>) -> Void
    ) async throws {
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("prepared body".utf8).write(to: bodyURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let started = expectation(description: "Multipart preparation started")
        let gate = UploadPreparationGate(started: started)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadLimitProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration), multipartBodyPreparation: { _, _, _, _, _, _, _ in
            await gate.prepare()
        })
        client.token = "original-user"
        let path = "/tax-data/session-\(UUID().uuidString)"
        let upload = Task {
            let _: EmptyBody = try await client.uploadMultipart(
                path, fileURL: bodyURL, fileName: "rates.json", mimeType: "application/json"
            )
        }
        await fulfillment(of: [started], timeout: 1)
        change(client, upload)
        await gate.complete(bodyURL)
        do {
            try await upload.value
            XCTFail("An obsolete or cancelled upload must not be sent")
        } catch is CancellationError {}
        XCTAssertEqual(UploadLimitProtocol.requestCount(for: "/api\(path)"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bodyURL.path), "An aborted upload must remove its prepared multipart file")
    }

    func testEndpointSpecificLimitIsEnforcedBeforeSending() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 65, count: 128).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadLimitProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration))

        do {
            let _: EmptyBody = try await client.uploadMultipart(
                "/tax-data/upload", fileURL: url, fileName: "rates.json",
                mimeType: "application/json", maximumFileBytes: 127
            )
            XCTFail("An oversized upload should never reach the server")
        } catch let error as APIError {
            XCTAssertTrue(error.message.contains("upload limit"))
        }

        let _: EmptyBody = try await client.uploadMultipart(
            "/tax-data/upload", fileURL: url, fileName: "rates.json",
            mimeType: "application/json", maximumFileBytes: 128
        )
    }

    func testDefaultLimitStillRejectsLargeOrdinaryAttachments() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(UploadFilePreparation.maximumBytes + 1))
        try handle.close()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadLimitProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration))
        do {
            let _: EmptyBody = try await client.uploadMultipart(
                "/tax-data/upload", fileURL: url, fileName: "attachment.pdf", mimeType: "application/pdf"
            )
            XCTFail("Ordinary attachments must keep the existing 50 MB limit")
        } catch let error as APIError {
            XCTAssertTrue(error.message.contains("50 MB"))
        }
    }
}

private final class UploadLimitProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestCounts: [String: Int] = [:]

    static func requestCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[path] ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requestCounts[request.url?.path ?? "", default: 0] += 1
        Self.lock.unlock()
        guard let url = request.url, request.httpMethod == "POST",
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor UploadPreparationGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<URL, Never>?

    init(started: XCTestExpectation) { self.started = started }

    func prepare() async -> URL {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func complete(_ url: URL) { continuation?.resume(returning: url) }
}
