import XCTest
@testable import TireShop

final class APIClientTests: XCTestCase {
    func testPayableKeysRemainOneExactlyEncodedRequestSegment() async throws {
        for (vendorKey, encodedKey) in [
            ("v:vendor_1", "v%3Avendor_1"),
            ("road tire", "road%20tire"),
            ("A/B", "A%2FB"),
            ("literal%2Fkey", "literal%252Fkey"),
            ("vendor?#name", "vendor%3F%23name")
        ] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [PayablePathProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Expected-Path": "/api/payables/\(encodedKey)"]
            let api = MoneyAPI(client: APIClient(session: URLSession(configuration: configuration)))
            let result = try await api.payable(vendorKey: vendorKey)
            XCTAssertEqual(result.totalDue, 25)
        }
    }
}

private final class PayablePathProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let expectedPath = request.value(forHTTPHeaderField: "X-Expected-Path")
        XCTAssertEqual(components.percentEncodedPath, expectedPath,
                       "The actual URL sent to the backend must encode the vendor key once")
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        let matches = components.percentEncodedPath == expectedPath
        let body = matches
            ? "{\"vendorKey\":\"fixture\",\"totalDue\":25,\"items\":[]}"
            : "{\"message\":\"No payable exists at this request path\"}"
        guard let response = HTTPURLResponse(url: url, statusCode: matches ? 200 : 404,
                                             httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
