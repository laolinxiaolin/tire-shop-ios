import XCTest
@testable import TireShop

final class APIClientTests: XCTestCase {
    func testSaleSalespersonAssignmentUsesPostAndReturnsUpdatedSale() async throws {
        let api = makeSalespersonAPI(expectedSalesperson: "employee-2")
        let sale = try await api.assignSalesperson(
            id: "sale-contract", body: SaleSalespersonPatch(salespersonId: "employee-2")
        )
        XCTAssertEqual(sale.id, "sale-contract")
        XCTAssertEqual(sale.salespersonId, "employee-2")
    }

    func testSaleSalespersonClearingPostsExplicitNull() async throws {
        let api = makeSalespersonAPI(expectedSalesperson: "null")
        let sale = try await api.assignSalesperson(
            id: "sale-contract", body: SaleSalespersonPatch(salespersonId: nil)
        )
        XCTAssertNil(sale.salespersonId)
    }

    private func makeSalespersonAPI(expectedSalesperson: String) -> SalesAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SaleSalespersonProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Expected-Salesperson": expectedSalesperson]
        return SalesAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }

    func testPaymentRegistrationValidatesCentsBeforePreparingProof() async throws {
        var preparedFields: [[String: String]] = []
        let client = APIClient(multipartBodyPreparation: { _, _, _, _, _, fields, _ in
            preparedFields.append(fields)
            throw CancellationError()
        })
        let api = PaymentApplicationsAPI(client: client)

        for amount in [12.345, 0.001, 0, -1, .nan, .infinity, 288.58000000000004] {
            do {
                _ = try await api.registerPayment(
                    id: "application", proofURL: URL(fileURLWithPath: "/unused-proof"),
                    fileName: "proof.pdf", mimeType: "application/pdf", idempotencyKey: "key",
                    amount: amount, paidAt: "2026-10-11", accountId: "bank",
                    method: nil, reference: nil, note: nil
                )
                XCTFail("Invalid amounts must be rejected before preparing the proof.")
            } catch let error as APIError {
                XCTAssertEqual(error.status, 400)
            }
        }
        XCTAssertTrue(preparedFields.isEmpty)

        for (amount, expected) in [(288.58, "288.58"), (0.07, "0.07"), (100, "100.00")] {
            do {
                _ = try await api.registerPayment(
                    id: "application", proofURL: URL(fileURLWithPath: "/unused-proof"),
                    fileName: "proof.pdf", mimeType: "application/pdf", idempotencyKey: "key",
                    amount: amount, paidAt: "2026-10-11", accountId: "bank",
                    method: nil, reference: nil, note: nil
                )
                XCTFail("The proof preparation stub must stop the request.")
            } catch is CancellationError {
                XCTAssertEqual(preparedFields.last?["amount"], expected)
            }
        }
        XCTAssertEqual(preparedFields.count, 3)
    }

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

private final class SaleSalespersonProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/api/sales/sale-contract/salesperson")
            XCTAssertEqual(request.httpMethod, "POST")
            let data: Data
            if let body = request.httpBody {
                data = body
            } else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
                data = body
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body.count, 1)
            let expectedSalesperson = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Expected-Salesperson"))
            if expectedSalesperson == "null" {
                XCTAssertTrue(body["salespersonId"] is NSNull, "Clearing must send an explicit null, not omit the field.")
            } else {
                XCTAssertEqual(body["salespersonId"] as? String, expectedSalesperson)
            }
            let routeMatches = request.httpMethod == "POST" && url.path == "/api/sales/sale-contract/salesperson"
            let salespersonJSON = expectedSalesperson == "null" ? "null" : "\"employee-2\""
            let json = routeMatches ? """
            {"id":"sale-contract","status":"INVOICED","location":"MAIN",
             "customer":{"id":"customer","name":"Customer"},"customerId":"customer",
             "subtotal":"100.00","taxRate":"0.00","taxAmount":"0.00","total":"100.00",
             "createdAt":"2026-10-11T12:00:00Z","lines":[],"salespersonId":\(salespersonJSON)}
            """ : #"{"message":"Cannot PATCH /api/sales/sale-contract/salesperson"}"#
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: routeMatches ? 201 : 404, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
