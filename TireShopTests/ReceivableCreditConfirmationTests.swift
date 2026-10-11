import XCTest
@testable import TireShop

final class ReceivableCreditConfirmationTests: XCTestCase {
    func testConfirmationReportsBookedCreditRatherThanExpectedTenderExcess() async throws {
        let confirmation = try await collect("booked")
        XCTAssertEqual(confirmation.result.ref, "rc-booked")
        XCTAssertEqual(confirmation.createdStoreCredit, 0.02)
        XCTAssertEqual(ReceivableCreditProtocol.calls("booked", method: "POST"), 1)
        XCTAssertEqual(ReceivableCreditProtocol.calls("booked", method: "GET"), 1)
    }

    func testReceiptWithNoBookedCreditDoesNotClaimTheEnteredExcess() async throws {
        let confirmation = try await collect("zero")
        XCTAssertEqual(confirmation.createdStoreCredit, 0)
        XCTAssertEqual(confirmation.result.ref, "rc-zero")
    }

    func testReadFailureAndCancellationKeepTheSuccessfulReceiptWithoutReposting() async throws {
        for scenario in ["unavailable", "cancelled"] {
            let confirmation = try await collect(scenario)
            XCTAssertEqual(confirmation.result.ref, "rc-\(scenario)")
            XCTAssertNil(confirmation.createdStoreCredit)
            XCTAssertEqual(ReceivableCreditProtocol.calls(scenario, method: "POST"), 1)
            XCTAssertEqual(ReceivableCreditProtocol.calls(scenario, method: "GET"), 1)
        }
    }

    func testMissingCreditFieldsAndMismatchedReceiptIdentityStayUnknown() async throws {
        for scenario in ["missing-credit", "partial-credit", "wrong-customer", "wrong-id", "wrong-ref", "reversed"] {
            let confirmation = try await collect(scenario)
            XCTAssertEqual(confirmation.result.ref, "rc-\(scenario)")
            XCTAssertNil(confirmation.createdStoreCredit, scenario)
            XCTAssertEqual(ReceivableCreditProtocol.calls(scenario, method: "POST"), 1)
        }
    }

    func testLegacyPostResponseWithoutReceiptIdStaysSuccessfulAndCreditUnknown() async throws {
        let confirmation = try await collect("legacy")
        XCTAssertEqual(confirmation.result.ref, "rc-legacy")
        XCTAssertNil(confirmation.result.receiptId)
        XCTAssertNil(confirmation.createdStoreCredit)
        XCTAssertEqual(ReceivableCreditProtocol.calls("legacy", method: "POST"), 1)
        XCTAssertEqual(ReceivableCreditProtocol.calls("legacy", method: "GET"), 0)
    }

    @MainActor
    func testBothLanguagesExplainUnsupportedCentAndUnknownCredit() {
        for key in ["payment.oneCentOverpaymentUnsupported", "payment.creditConfirmationUnavailable"] {
            XCTAssertNotNil(I18nStore.messages[.en]?[key])
            XCTAssertNotNil(I18nStore.messages[.zh]?[key])
            XCTAssertNotEqual(I18nStore.messages[.en]?[key], I18nStore.messages[.zh]?[key])
        }
    }

    private func collect(_ scenario: String) async throws -> ReceivablePaymentConfirmation {
        ReceivableCreditProtocol.reset(scenario)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReceivableCreditProtocol.self]
        let api = MoneyAPI(client: APIClient(session: URLSession(configuration: configuration)))
        return try await api.payReceivablesWithCreditConfirmation(
            .init(customerId: "customer", paymentMethodId: scenario,
                  applications: [.init(invoiceId: "invoice", amount: 100.02)],
                  reference: nil, note: nil), idempotencyKey: "credit-\(scenario)"
        )
    }
}

private final class ReceivableCreditProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestCounts: [String: [String: Int]] = [:]

    static func reset(_ scenario: String) {
        lock.lock()
        defer { lock.unlock() }
        requestCounts[scenario] = [:]
    }

    static func calls(_ scenario: String, method: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[scenario]?[method] ?? 0
    }

    private static func record(_ scenario: String, method: String) {
        lock.lock()
        defer { lock.unlock() }
        requestCounts[scenario, default: [:]][method, default: 0] += 1
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let method = try XCTUnwrap(request.httpMethod)
            let scenario: String
            let object: [String: Any]
            var statusCode = 200
            if method == "POST" {
                XCTAssertEqual(url.path, "/api/receivables/pay")
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
                scenario = try XCTUnwrap(body["paymentMethodId"] as? String)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "credit-\(scenario)")
                Self.record(scenario, method: method)
                if scenario == "legacy" {
                    object = ["ref": "rc-\(scenario)"]
                } else {
                    object = ["ref": "rc-\(scenario)", "receiptId": scenario]
                }
            } else {
                XCTAssertEqual(method, "GET")
                scenario = url.lastPathComponent
                XCTAssertEqual(url.path, "/api/receipts/\(scenario)")
                Self.record(scenario, method: method)
                if scenario == "cancelled" {
                    client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
                    return
                }
                if scenario == "unavailable" {
                    statusCode = 503
                    object = ["message": "Receipt detail unavailable"]
                } else {
                    var line: [String: Any] = ["id": "payment", "invoiceId": "invoice",
                                              "amount": 100.02, "surchargeAmount": 0]
                    if scenario != "missing-credit" {
                        line["overpaymentAmount"] = scenario == "zero" ? 0 : 0.02
                    }
                    var lines = [line]
                    if scenario == "partial-credit" {
                        lines.append(["id": "other", "invoiceId": "invoice", "amount": 1, "surchargeAmount": 0])
                    }
                    object = ["id": scenario == "wrong-id" ? "other" : scenario,
                              "ref": scenario == "wrong-ref" ? "rc-other" : "rc-\(scenario)",
                              "customer": ["id": scenario == "wrong-customer" ? "other" : "customer", "name": "Fixture customer"],
                              "total": 100.02, "status": scenario == "reversed" ? "REVERSED" : "POSTED", "lines": lines]
                }
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
