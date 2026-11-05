import XCTest
@testable import TireShop

final class CollectionAdjustmentTests: XCTestCase {
    func testUnsignedAmountsUseExactCentsAndRejectPastedSigns() {
        let valid: [(String, Int64)] = [("0", 0), ("0.01", 1), ("288.58", 28_858),
            (" 00288.59 ", 28_859), ("9999999999.99", 999_999_999_999)]
        for (text, cents) in valid {
            XCTAssertEqual(CollectionMoney.cents(text), cents, text)
            XCTAssertEqual(CollectionMoney.cents(CollectionMoney.amount(cents: cents)), cents, text)
        }
        for text in ["", "+1", "-1", "--1", "+-1", ".29", "1.", "1.234", "1e2", "1,00",
                     "NaN", "Infinity", "10000000000", "1 2", "$1", "−1"] {
            XCTAssertNil(CollectionMoney.cents(text), text)
        }
        XCTAssertNil(CollectionMoney.cents(Double.nan))
        XCTAssertNil(CollectionMoney.cents(Double.infinity))
        XCTAssertNil(CollectionMoney.cents(-1.0))
        XCTAssertNil(CollectionMoney.cents(0.001))
        XCTAssertEqual(CollectionMoney.text(cents: -29), "-0.29")
        XCTAssertEqual(CollectionMoney.text(cents: 28_858), "288.58")
    }

    func testDirectionChangesOnlyTheFinalBalanceDeltaAndRetainsOriginalSnapshot() throws {
        var draft = CollectionAdjustmentDraft(direction: .reduce, amountText: "0.29")
        XCTAssertEqual(try draft.adjustedBalance(originalBalance: 100.29), 100)
        XCTAssertEqual(try draft.adjustment(invoiceId: "invoice", originalBalance: 100.29),
            .init(invoiceId: "invoice", amount: -0.29, expectedBalance: 100.29))
        draft.direction = .increase
        XCTAssertEqual(try draft.adjustedBalance(originalBalance: 100.29), 100.58)
        XCTAssertEqual(try draft.adjustment(invoiceId: "invoice", originalBalance: 100.29),
            .init(invoiceId: "invoice", amount: 0.29, expectedBalance: 100.29))
    }

    func testTenderAutofillPreservesPartialOverpaidAndMalformedAmounts() {
        for amounts in [["100"], ["100", "143"], ["100", "143.30"], ["100", "143.290"],
                        ["100", "143."], ["100", "+143.29"], ["100", "bad"]] {
            XCTAssertNil(CollectionTenderAutofill.followBalance(
                amounts: amounts, from: 243.29, to: 243), amounts.joined(separator: ", "))
        }
        XCTAssertNil(CollectionTenderAutofill.followBalance(amounts: ["0"], from: 0, to: 1))
        XCTAssertNil(CollectionTenderAutofill.followBalance(amounts: ["100"], from: 100, to: 0))
        XCTAssertNil(CollectionTenderAutofill.followBalance(amounts: ["100"], from: 100, to: -1))
        XCTAssertNil(CollectionTenderAutofill.followBalance(amounts: ["100"], from: .nan, to: 100))
    }

    func testTenderAutofillFollowsSplitBalanceAndRestoresRemovedAdjustment() throws {
        let original = ["100", "143.29"]
        let reduced = try XCTUnwrap(CollectionTenderAutofill.followBalance(
            amounts: original, from: 243.29, to: 243))
        XCTAssertEqual(reduced, ["100", "143.00"])
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: reduced, from: 243, to: 243.29), original)
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: ["60", "40"], from: 100, to: 100.29), ["60", "40.29"])
    }

    func testTenderAutofillConsumesLargeReductionBackwardsWithoutCreditOrNegativeRows() throws {
        let reduced = try XCTUnwrap(CollectionTenderAutofill.followBalance(
            amounts: [" 080 ", "10", "10", "", "  ", "0.00"], from: 100, to: 75))
        XCTAssertEqual(reduced, ["75.00", "0.00", "0.00", "", "  ", "0.00"])
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: reduced, from: 75, to: 100), ["100.00", "0.00", "0.00", "", "  ", "0.00"])
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: [" 080 ", "10", "10"], from: 100, to: 95), [" 080 ", "10", "5.00"])
    }

    func testTenderAutofillUsesExactCentsAndLeavesUnchangedFormattingAlone() {
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: ["0.1", "0.20", "", " 0 "], from: 0.30, to: 0.29),
            ["0.1", "0.19", "", " 0 "])
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: ["0.1", "0.20"], from: 0.30, to: 0.01), ["0.01", "0.00"])
        XCTAssertEqual(CollectionTenderAutofill.followBalance(
            amounts: [" 00100 ", "0.00", ""], from: 100, to: 100), [" 00100 ", "0.00", ""])
    }

    func testBlankAndZeroDraftsDoNotSendAdjustments() throws {
        for text in ["", "  ", "0", "0.00"] {
            let draft = CollectionAdjustmentDraft(direction: .increase, amountText: text)
            XCTAssertNil(try draft.adjustment(invoiceId: "invoice", originalBalance: 100))
            XCTAssertEqual(try draft.adjustedBalance(originalBalance: 100), 100)
        }
    }

    func testIncompleteAndInvalidDraftsBlockSubmissionWithoutChangingTheText() {
        for text in ["1.", "-0.29", "+0.29", "1.001", "bad", "10000000000"] {
            let draft = CollectionAdjustmentDraft(direction: .reduce, amountText: text)
            XCTAssertEqual(draft.validationError(originalBalance: 100), "payment.invalidAdjustment", text)
            XCTAssertThrowsError(try draft.adjustment(invoiceId: "invoice", originalBalance: 100), text)
            XCTAssertEqual(draft.amountText, text)
        }
    }

    func testReductionMustLeaveAtLeastOneCentToCollect() throws {
        XCTAssertEqual(try CollectionAdjustmentDraft(direction: .reduce, amountText: "99.99")
            .adjustedBalance(originalBalance: 100), 0.01)
        for text in ["100", "100.01"] {
            XCTAssertEqual(CollectionAdjustmentDraft(direction: .reduce, amountText: text)
                .validationError(originalBalance: 100), "payment.adjustmentBalancePositive")
        }
        XCTAssertEqual(CollectionAdjustmentDraft(direction: .increase, amountText: "0.01")
            .validationError(originalBalance: 0), "payment.adjustmentBalancePositive")
        XCTAssertEqual(CollectionAdjustmentDraft(direction: .increase, amountText: "0.01")
            .validationError(originalBalance: 9_999_999_999.99), "payment.invalidAdjustment")
    }

    func testPolicyFailsClosedUnlessOverrideOrCanonicalPricingIsDisabled() {
        XCTAssertFalse(CollectionAdjustmentPermission.allows(hasOverride: false, policyEnabled: nil))
        XCTAssertFalse(CollectionAdjustmentPermission.allows(hasOverride: false, policyEnabled: true))
        XCTAssertTrue(CollectionAdjustmentPermission.allows(hasOverride: false, policyEnabled: false))
        for policy in [nil, true, false] as [Bool?] {
            XCTAssertTrue(CollectionAdjustmentPermission.allows(hasOverride: true, policyEnabled: policy))
        }
    }

    func testBatchRevisesEachInvoiceOnceAndKeepsUnadjustedInvoices() throws {
        let adjustments = [adjustment("a", -0.29, 100.29), adjustment("b", 10, 50)]
        XCTAssertEqual(try CollectionAdjustmentValidation.revisedBalances(
            adjustments: adjustments, invoiceBalances: ["a": 100.29, "b": 50, "c": 20]),
            ["a": 100, "b": 60, "c": 20])
        assertError("payment.adjustmentDuplicate") {
            try CollectionAdjustmentValidation.validate(
                adjustments: [adjustments[0], adjustments[0]], paidInvoiceIds: ["a"])
        }
        assertError("payment.adjustmentInvoiceMismatch") {
            try CollectionAdjustmentValidation.validate(adjustments: adjustments, paidInvoiceIds: ["a"])
        }
        assertError("payment.adjustmentStale") {
            try CollectionAdjustmentValidation.validate(
                adjustments: [adjustments[0]], invoiceBalances: ["a": 99.29])
        }
    }

    func testDTOValidationRejectsZeroNonMoneyAndNonpositiveBalances() {
        for value in [0.0, -0.0, .nan, .infinity, -.infinity, 0.001, 10_000_000_000] {
            assertError("payment.invalidAdjustment") {
                try CollectionAdjustmentValidation.validate(
                    adjustments: [adjustment("a", value, 100)], paidInvoiceIds: ["a"])
            }
        }
        for balance in [Double.nan, .infinity, -1, 1.001, 10_000_000_000] {
            assertError("payment.invalidAdjustment") {
                try CollectionAdjustmentValidation.validate(
                    adjustments: [adjustment("a", -0.29, balance)], paidInvoiceIds: ["a"])
            }
        }
        for value in [-100.0, -100.01] {
            assertError("payment.adjustmentBalancePositive") {
                try CollectionAdjustmentValidation.validate(
                    adjustments: [adjustment("a", value, 100)], paidInvoiceIds: ["a"])
            }
        }
    }

    func testManualReceiptUsesRevisedBalanceForSplitTenderCreditValidation() throws {
        let increase = adjustment("invoice", 0.29, 100)
        // Before repricing this was a one-cent excess; afterwards it is partial.
        let partial = try receipt(amounts: ["100.01"], balance: 100, adjustments: [increase])
        XCTAssertEqual(partial.lines.map(\.amount), [100.01])
        let decrease = adjustment("invoice", -0.29, 100.29)
        let split = try receipt(amounts: ["60", "40"], balance: 100.29, adjustments: [decrease])
        XCTAssertEqual(split.lines.map(\.amount), [60, 40])
        // After repricing this split now has an unsupported one-cent excess.
        assertError("payment.oneCentOverpaymentUnsupported") {
            _ = try receipt(amounts: ["60", "40.01"], balance: 100.29, adjustments: [decrease])
        }
        assertError("payment.adjustmentStale") {
            _ = try receipt(amounts: ["100"], balance: 100.28, adjustments: [decrease])
        }
    }

    func testManualAndReceivableJSONOmitUnusedAdjustmentsAndEncodeSignedCents() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plainReceipt = try receipt(amounts: ["100"], balance: 100, adjustments: [])
        XCTAssertFalse(try json(plainReceipt, encoder: encoder).contains("adjustments"))
        let reduction = adjustment("invoice", -0.29, 100.29)
        let adjusted = try receipt(amounts: ["100"], balance: 100.29, adjustments: [reduction])
        XCTAssertTrue(try json(adjusted, encoder: encoder).contains(
            "\"adjustments\":[{\"amount\":-0.29,\"expectedBalance\":100.29,\"invoiceId\":\"invoice\"}]"))
        var ar = ReceivablesPayInput(customerId: "customer", paymentMethodId: "cash",
            applications: [.init(invoiceId: "invoice", amount: 100)], reference: nil, note: nil)
        XCTAssertFalse(try json(ar, encoder: encoder).contains("adjustments"))
        ar.adjustments = []
        XCTAssertFalse(try json(ar, encoder: encoder).contains("adjustments"))
        ar.adjustments = [reduction]
        XCTAssertTrue(try json(ar, encoder: encoder).contains(
            "\"adjustments\":[{\"amount\":-0.29,\"expectedBalance\":100.29,\"invoiceId\":\"invoice\"}]"))
        ar.adjustments = [adjustment("invoice", 288.58, 100.29)]
        XCTAssertTrue(try json(ar, encoder: encoder).contains("\"amount\":288.58,"))
    }

    func testWireEncodingRejectsDuplicateOrUnmatchedAdjustmentsAndMissingPositiveTender() {
        let change = adjustment("invoice", -0.29, 100.29)
        for changes in [[change, change], [adjustment("other", -0.29, 100.29)]] {
            let input = ManualReceiptInput(customerId: "customer", lines: [.init(invoiceId: "invoice",
                paymentMethodId: "cash", amount: 100, reference: nil, plannedDepositDate: nil)],
                adjustments: changes)
            XCTAssertThrowsError(try JSONEncoder().encode(input))
            let ar = ReceivablesPayInput(customerId: "customer", paymentMethodId: "cash",
                applications: [.init(invoiceId: "invoice", amount: 100)], reference: nil, note: nil,
                adjustments: changes)
            XCTAssertThrowsError(try JSONEncoder().encode(ar))
        }
        let noTender = ReceivablesPayInput(customerId: "customer", paymentMethodId: "cash",
            applications: [.init(invoiceId: "invoice", amount: 0)], reference: nil, note: nil,
            adjustments: [change])
        XCTAssertThrowsError(try JSONEncoder().encode(noTender))
    }

    func testAPIClientPreservesStaleCodeWithLocalizedMessagesForJSONDataAndMultipart() async throws {
        let proof = FileManager.default.temporaryDirectory.appendingPathComponent("adjustment-proof-\(UUID().uuidString).txt")
        try Data("proof".utf8).write(to: proof)
        defer { try? FileManager.default.removeItem(at: proof) }
        for language in ["en", "zh"] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [CollectionAdjustmentStaleProtocol.self]
            configuration.httpAdditionalHeaders = ["X-Adjustment-Test-Language": language]
            let api = APIClient(session: URLSession(configuration: configuration))
            let expectedMessage = language == "zh"
                ? "该发票已变更，请重新加载后再调整价格。"
                : "This invoice changed. Reload it before adjusting the price."
            for requestType in ["json", "data", "multipart"] {
                do {
                    switch requestType {
                    case "json":
                        let _: EmptyResponse = try await api.request("/receipts", method: "POST", body: ["test": "stale"])
                    case "data":
                        _ = try await api.data("/adjustment-state")
                    default:
                        let _: EmptyResponse = try await api.uploadMultipart("/adjustment-proof", fileURL: proof,
                            fileName: "proof.txt", mimeType: "text/plain")
                    }
                    XCTFail("A stale invoice must reject the request.")
                } catch let error as APIError {
                    XCTAssertEqual(error.status, 400, requestType)
                    XCTAssertEqual(error.code, "PAYMENT_ADJUSTMENT_STALE", requestType)
                    XCTAssertEqual(error.message, expectedMessage, requestType)
                }
            }
        }
    }

    @MainActor
    func testHTTP400StaleAdjustmentRetiresManualFormUntilReadOnlyReconciliation() async {
        var collections = 0
        var refreshes = 0
        let store = ManualReceiptStore { _ in
            collections += 1
            throw APIError(status: 400, message: "该发票已变更，请重新加载后再调整价格。",
                           code: "PAYMENT_ADJUSTMENT_STALE")
        }
        let input = ManualReceiptInput(customerId: "customer", lines: [.init(invoiceId: "invoice",
            paymentMethodId: "cash", amount: 100, reference: nil, plannedDepositDate: nil)],
            adjustments: [adjustment("invoice", -0.29, 100.29)])
        await store.record(input) { refreshes += 1 }
        XCTAssertTrue(store.needsReconciliation)
        XCTAssertFalse(store.completed)
        await store.record(input) { refreshes += 1 }
        XCTAssertEqual(collections, 1)
        XCTAssertEqual(refreshes, 0)
        await store.reconcile { throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(store.needsReconciliation)
        XCTAssertFalse(store.completed)
        await store.record(input) { refreshes += 1 }
        XCTAssertEqual(collections, 1)
        await store.reconcile { refreshes += 1 }
        XCTAssertTrue(store.completed)
        XCTAssertNil(store.error)
        await store.record(input) { refreshes += 1 }
        XCTAssertEqual(collections, 1)
        XCTAssertEqual(refreshes, 1)
    }

    private func adjustment(_ id: String, _ amount: Double, _ balance: Double) -> InvoiceCollectionAdjustment {
        .init(invoiceId: id, amount: amount, expectedBalance: balance)
    }

    private func receipt(amounts: [String], balance: Double, adjustments: [InvoiceCollectionAdjustment]) throws -> ManualReceiptInput {
        try ManualReceiptInput.make(invoiceId: "invoice", customerId: "customer",
            rows: amounts.map { .init(paymentMethodId: "cash", amount: $0, reference: "") },
            methods: [.init(id: "cash", name: "Cash", feeRate: nil, isActive: true,
                processor: nil, account: .init(code: "1000", name: "Cash"))],
            balance: balance, adjustments: adjustments)
    }

    private func json<T: Encodable>(_ input: T, encoder: JSONEncoder) throws -> String {
        try XCTUnwrap(String(data: encoder.encode(input), encoding: .utf8))
    }

    private func assertError(_ key: String, file: StaticString = #filePath, line: UInt = #line,
                             _ action: () throws -> Void) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual((error as? APIError)?.message, key, file: file, line: line)
        }
    }
}

private final class CollectionAdjustmentStaleProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(["/api/receipts", "/api/adjustment-state", "/api/adjustment-proof"].contains(url.path))
            let message = request.value(forHTTPHeaderField: "X-Adjustment-Test-Language") == "zh"
                ? "该发票已变更，请重新加载后再调整价格。"
                : "This invoice changed. Reload it before adjusting the price."
            let body = try JSONSerialization.data(withJSONObject: [
                "statusCode": 400, "error": "Bad Request", "message": message,
                "code": "PAYMENT_ADJUSTMENT_STALE", "params": [:]
            ] as [String: Any])
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
