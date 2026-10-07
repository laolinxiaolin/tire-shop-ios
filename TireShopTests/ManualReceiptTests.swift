import XCTest
@testable import TireShop

@MainActor
final class ManualReceiptTests: XCTestCase {
    func testSplitPaymentSubmitsOneReceiptWithNetAmountsAndCheckDate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManualReceiptProtocol.self]
        let api = PaymentsAPI(client: APIClient(session: URLSession(configuration: configuration)))
        var check = PaymentRow(paymentMethodId: "check", amount: "12.34", reference: "123")
        check.plannedDepositDate = "2026-10-07"
        var cash = PaymentRow(paymentMethodId: "cash", amount: "0.01", reference: "")
        cash.plannedDepositDate = "2026-10-08"
        let card = PaymentRow(paymentMethodId: "manual-card", amount: "100.00", reference: "txn")
        let input = try ManualReceiptInput.make(invoiceId: "invoice", customerId: "customer",
            rows: [check, cash, card], methods: methods())
        let changed = expectation(forNotification: .checkRegisterDidChange, object: nil)
        let result = try await api.recordReceipt(input)
        XCTAssertEqual(result.paymentCount, 3)
        XCTAssertEqual(result.total, 115.35)
        await fulfillment(of: [changed], timeout: 1)
    }

    func testEveryRowIsValidatedBeforeAReceiptCanBeSent() throws {
        let valid = PaymentRow(paymentMethodId: "cash", amount: "100", reference: "")
        for value in ["-1", "0.001", "NaN", "inf", "1e2", "10000000000", "bad"] {
            let invalid = PaymentRow(paymentMethodId: "cash", amount: value, reference: "")
            XCTAssertThrowsError(try ManualReceiptInput.make(invoiceId: "invoice", customerId: nil,
                rows: [valid, invalid], methods: methods()), value)
        }
        for date in ["", "2026-02-29", "2026-10-07T00:00:00Z"] {
            var check = PaymentRow(paymentMethodId: "check", amount: "50", reference: "")
            check.plannedDepositDate = date
            XCTAssertThrowsError(try ManualReceiptInput.make(invoiceId: "invoice", customerId: nil,
                rows: [valid, check], methods: methods()), date)
        }
        XCTAssertThrowsError(try ManualReceiptInput.make(invoiceId: "invoice", customerId: nil,
            rows: [.init(paymentMethodId: "inactive", amount: "50", reference: "")], methods: methods()))
        XCTAssertEqual(ManualReceiptInput.money("9999999999.99"), 9999999999.99)
    }

    func testOneCentExcessIsPreservedAsCustomerCredit() {
        XCTAssertTrue(ManualPaymentOverpaymentPolicy.isOverpayment(totalApplied: 100.01, balance: 100))
        XCTAssertEqual(ManualPaymentOverpaymentPolicy.amount(totalApplied: 100.01, balance: 100), 0.01)
        XCTAssertEqual(ManualPaymentOverpaymentPolicy.appliedToInvoice(totalApplied: 100.01, balance: 100), 100)
        XCTAssertFalse(ManualPaymentOverpaymentPolicy.isOverpayment(totalApplied: 100, balance: 100))
    }

    func testFeesRoundHalfCentsLikeTheServerAndRemainPerTender() {
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "7.50", feeRate: "0.03"), Decimal(string: "0.23"))
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "2.50", feeRate: "0.03"), Decimal(string: "0.08"))
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "100.00", feeRate: "0.03"), 3)
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "100.00", feeRate: nil), 0)
    }

    func testLostResponsesRequireReconciliationWithoutReplayingCollection() async {
        for failure in [APIError(status: 0, message: "Lost"), APIError(status: 503, message: "Lost"),
                        APIError(status: 408, message: "Timeout"), APIError(status: 409, message: "Conflict")] {
            var calls = 0
            var refreshes = 0
            let store = ManualReceiptStore { _ in calls += 1; throw failure }
            await store.record(input()) { refreshes += 1 }
            XCTAssertTrue(store.needsReconciliation)
            await store.record(input()) { refreshes += 1 }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(refreshes, 0)
            await store.reconcile { refreshes += 1 }
            XCTAssertTrue(store.completed)
            await store.record(input()) { refreshes += 1 }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(refreshes, 1)
        }
    }

    func testRefreshFailureAfterCommittedReceiptNeverAllowsAnotherCollection() async {
        var calls = 0
        let store = ManualReceiptStore { _ in calls += 1; return self.result() }
        await store.record(input()) { throw APIError(status: 400, message: "Refresh failed") }
        XCTAssertTrue(store.needsReconciliation)
        XCTAssertFalse(store.completed)
        await store.record(input()) {}
        XCTAssertEqual(calls, 1)
        await store.reconcile { throw URLError(.notConnectedToInternet) }
        XCTAssertFalse(store.completed)
        await store.reconcile {}
        XCTAssertTrue(store.completed)
        XCTAssertNil(store.error)
    }

    func testDefiniteRejectionPermitsCorrectedCollection() async {
        var calls = 0
        let store = ManualReceiptStore { _ in
            calls += 1
            if calls == 1 { throw APIError(status: 400, message: "Invalid tender") }
            return self.result()
        }
        await store.record(input()) {}
        XCTAssertFalse(store.needsReconciliation)
        XCTAssertFalse(store.completed)
        await store.record(input()) {}
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(store.completed)
    }

    func testCommittedCardLocksManualTendersBeforeRefreshAndKeepsThemLockedOnFailure() async {
        var manualCollections = 0
        let store = ManualReceiptStore { _ in
            manualCollections += 1
            return self.result()
        }
        store.requireReconciliation()
        XCTAssertTrue(store.needsReconciliation)
        await store.record(input()) {}
        XCTAssertEqual(manualCollections, 0)
        await store.reconcile { throw APIError(status: 503, message: "Balance refresh failed") }
        XCTAssertFalse(store.completed)
        XCTAssertTrue(store.needsReconciliation)
        await store.record(input()) {}
        XCTAssertEqual(manualCollections, 0)
        await store.reconcile {}
        XCTAssertTrue(store.completed)
        await store.record(input()) {}
        XCTAssertEqual(manualCollections, 0)
    }

    func testConcurrentTapCannotStartASecondReceipt() async throws {
        var calls = 0
        var release: CheckedContinuation<ManualReceiptResult, Error>?
        let store = ManualReceiptStore { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { release = $0 }
        }
        let first = Task { await store.record(input()) {} }
        while release == nil { await Task.yield() }
        await store.record(input()) {}
        XCTAssertEqual(calls, 1)
        release?.resume(returning: result())
        await first.value
        XCTAssertTrue(store.completed)
    }

    private func input() -> ManualReceiptInput {
        .init(customerId: "customer", lines: [.init(invoiceId: "invoice", paymentMethodId: "cash",
            amount: 100, reference: nil, plannedDepositDate: nil)])
    }

    private func result() -> ManualReceiptResult {
        .init(id: "receipt", ref: "rc-1", total: 100, surchargeTotal: 0, paymentCount: 1)
    }

    private func methods() -> [PaymentMethod] {
        [("cash", "1000", nil, true), ("check", "1010", nil, true),
         ("manual-card", "1020", "0.03", true), ("inactive", "1000", nil, false)].map { id, code, fee, active in
            PaymentMethod(id: id, name: id, feeRate: fee, isActive: active,
                processor: nil, account: .init(code: code, name: code))
        }
    }
}

private final class ManualReceiptProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/receipts")
            let data: Data
            if let body = request.httpBody { data = body } else {
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
            XCTAssertEqual(body["customerId"] as? String, "customer")
            let lines = try XCTUnwrap(body["lines"] as? [[String: Any]])
            XCTAssertEqual(lines.count, 3)
            XCTAssertEqual(lines.map { $0["invoiceId"] as? String }, ["invoice", "invoice", "invoice"])
            XCTAssertEqual(lines.map { $0["amount"] as? Double }, [12.34, 0.01, 100])
            XCTAssertEqual(lines[0]["plannedDepositDate"] as? String, "2026-10-07")
            XCTAssertNil(lines[1]["plannedDepositDate"])
            XCTAssertNil(lines[2]["plannedDepositDate"])
            XCTAssertEqual(lines[0]["reference"] as? String, "123")
            XCTAssertNil(lines[1]["reference"])
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"id":"receipt","ref":"rc-1","total":115.35,"surchargeTotal":3,"paymentCount":3}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
