import XCTest
@testable import TireShop

final class CustomerTaxAPITests: XCTestCase {
    func testSaveReloadsFullCustomerRelationsAfterRawMutation() async throws {
        let api = makeAPI()
        let result = try await api.saveOverride(customerId: "complete", body: input)
        guard case .reloaded(let customer) = result else {
            return XCTFail("The full profile should be available")
        }
        XCTAssertEqual(customer.documents?.first?.id, "certificate")
        XCTAssertNotNil(customer.sales)
        XCTAssertEqual(customer.salesperson?.fullName, "Sales Person")
        XCTAssertEqual(CustomerTaxProtocol.requests(for: "complete"), ["PATCH", "GET"])
    }

    func testFailedPostSaveReloadRetriesOnlyGET() async throws {
        let api = makeAPI()
        let result = try await api.saveOverride(customerId: "reload", body: input)
        guard case .needsCustomerReload = result else {
            return XCTFail("A committed mutation with a failed read needs read-only recovery")
        }
        let customer = try await api.reloadCustomer(customerId: "reload")
        XCTAssertEqual(customer.documents?.first?.id, "certificate")
        XCTAssertEqual(CustomerTaxProtocol.requests(for: "reload"), ["PATCH", "GET", "GET"])
    }

    func testFailedMutationDoesNotReloadOrReportSuccess() async throws {
        do {
            _ = try await makeAPI().saveOverride(customerId: "rejected", body: input)
            XCTFail("A rejected mutation must throw")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
        XCTAssertEqual(CustomerTaxProtocol.requests(for: "rejected"), ["PATCH"])
    }

    private var input: CustomerTaxOverrideInput {
        CustomerTaxOverrideInput(taxRateOverride: 0.08, useShopDefault: false, reason: "Reviewed", expiresAt: nil)
    }

    private func makeAPI() -> CustomerTaxAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CustomerTaxProtocol.self]
        return CustomerTaxAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }
}

private final class CustomerTaxProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestLog: [String: [String]] = [:]

    static func requests(for id: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestLog[id] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        let components = url.path.split(separator: "/")
        guard components.count >= 3 else { return }
        let id = String(components[2])
        Self.lock.lock()
        Self.requestLog[id, default: []].append(method)
        let getCount = Self.requestLog[id, default: []].filter { $0 == "GET" }.count
        Self.lock.unlock()
        let status: Int
        let json: String
        if method == "PATCH", url.path == "/api/customers/\(id)/tax-rate" {
            status = id == "rejected" ? 403 : 200
            json = "{}"
        } else if method == "GET", url.path == "/api/customers/\(id)" {
            status = id == "reload" && getCount == 1 ? 503 : 200
            json = """
            {"id":"\(id)","name":"Customer","taxExempt":false,"accountEnabled":false,"taxRateOverride":"0.08",
             "createdAt":"2026-09-01T12:00:00Z","sales":[],
             "salesperson":{"id":"employee","fullName":"Sales Person","status":"ACTIVE"},
             "documents":[{"id":"certificate","kind":"RESALE_CERT","filename":"certificate.pdf",
                "mimeType":"application/pdf","sizeBytes":10,"createdAt":"2026-09-01T12:00:00Z"}]}
            """
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
