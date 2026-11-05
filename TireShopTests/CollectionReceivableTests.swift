import XCTest
@testable import TireShop

final class CollectionReceivableTests: XCTestCase {
    private let invoices: [(id: String, balance: Double)] = [("first", 243.29), ("second", 100)]
    private var originals: [String: Double] { Dictionary(uniqueKeysWithValues: invoices) }

    func testFullQuickSplitFollowsRepeatedAdjustmentsAndKeepsOriginalSnapshot() throws {
        var draft = ReceivableCollectionDraft()
        XCTAssertEqual(draft.split(invoices: invoices, totalCents: 34_329), 0)
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations, ["first": "243.00", "second": "100.00"])
        draft.setAdjustment(.init(direction: .increase, amountText: "0.71"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "244.00")
        XCTAssertEqual(try draft.submissionAdjustments(originalBalances: originals), [
            .init(invoiceId: "first", amount: 0.71, expectedBalance: 243.29)
        ])
    }

    func testDeliberatePartialAmountSurvivesEditingAndRemovingAdjustment() throws {
        var draft = ReceivableCollectionDraft()
        draft.setAllocation("100.00", invoiceId: "first")
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "100.00")
        XCTAssertEqual(draft.balance(invoiceId: "first", original: 243.29), 243)
        draft.removeAdjustment(invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "100.00")
        XCTAssertEqual(draft.balance(invoiceId: "first", original: 243.29), 243.29)
        XCTAssertTrue(try draft.submissionAdjustments(originalBalances: originals).isEmpty)
    }

    func testTypedExactFullAmountFollowsChangesAndRemovingRestoresOriginal() {
        var draft = ReceivableCollectionDraft()
        draft.setAllocation("243.29", invoiceId: "first")
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "243.00")
        draft.setAdjustment(.init(direction: .increase, amountText: "0.71"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "244.00")
        draft.removeAdjustment(invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "243.29")
    }

    func testTypedExactRevisedBalanceRestoresOriginalWhenAdjustmentIsRemoved() {
        var draft = ReceivableCollectionDraft()
        draft.setAllocation("100", invoiceId: "first")
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        draft.setAllocation("243.00", invoiceId: "first")
        draft.removeAdjustment(invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "243.29")
    }

    func testPartialOverpaidAndMalformedAmountsStayAsEnteredAcrossAdjustments() {
        for entered in ["100.00", "243.30", "bad", "243.290"] {
            var draft = ReceivableCollectionDraft()
            draft.setAllocation(entered, invoiceId: "first")
            draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
            XCTAssertEqual(draft.allocations["first"], entered)
            draft.setAdjustment(.init(direction: .increase, amountText: "0.71"), invoiceId: "first", original: 243.29)
            XCTAssertEqual(draft.allocations["first"], entered)
            draft.removeAdjustment(invoiceId: "first", original: 243.29)
            XCTAssertEqual(draft.allocations["first"], entered)
        }
    }

    func testRemovingAdjustmentRestoresOnlyExactFullAmounts() {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 34_329)
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        draft.setAllocation("50", invoiceId: "second")
        draft.setAdjustment(.init(direction: .increase, amountText: "1"), invoiceId: "second", original: 100)
        draft.removeAllAdjustments(originalBalances: originals)
        XCTAssertEqual(draft.allocations, ["first": "243.29", "second": "50"])
        XCTAssertTrue(draft.adjustments.isEmpty)
    }

    func testIncompleteAdjustmentRetainsLastValidBalanceAndBlocksSubmission() throws {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 34_329)
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        for text in [".", "0.001", "-0.29", "243.29", "NaN"] {
            draft.setAdjustment(.init(direction: .reduce, amountText: text), invoiceId: "first", original: 243.29)
            XCTAssertEqual(draft.balance(invoiceId: "first", original: 243.29), 243, text)
            XCTAssertEqual(draft.allocations["first"], "243.00", text)
            XCTAssertThrowsError(try draft.submissionAdjustments(originalBalances: originals), text)
        }
        draft.setAdjustment(.init(direction: .increase, amountText: "0.71"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.allocations["first"], "244.00")
        XCTAssertEqual(try draft.submissionAdjustments(originalBalances: originals).count, 1)
    }

    func testDeselectingInvoiceDropsItsAdjustmentAndDoesNotResurrectIt() throws {
        for deselected in ["", "  ", "0", "0.00"] {
            var draft = ReceivableCollectionDraft()
            _ = draft.split(invoices: invoices, totalCents: 34_329)
            draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
            draft.setAllocation(deselected, invoiceId: "first")
            XCTAssertFalse(draft.isSelected("first"))
            XCTAssertNil(draft.adjustments["first"])
            XCTAssertEqual(draft.balance(invoiceId: "first", original: 243.29), 243.29)
            draft.setAllocation("100", invoiceId: "first")
            XCTAssertTrue(try draft.submissionAdjustments(originalBalances: originals).isEmpty)
        }
    }

    func testOldestFirstUsesRevisedDueAndPreservesExplicitTenderAndCredit() throws {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 40_000)
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"), invoiceId: "first", original: 243.29)
        let credit = draft.split(invoices: invoices, totalCents: 40_000)
        XCTAssertEqual(draft.allocations, ["first": "243.00", "second": "100.00"])
        XCTAssertEqual(credit, 5_700)
        let received = draft.allocations.values.compactMap(CollectionMoney.cents).reduce(0, +) + credit
        XCTAssertEqual(received, 40_000)
        XCTAssertFalse(ReceivableOverpaymentPolicy.allowsStoreCredit(
            excess: CollectionMoney.amount(cents: credit), paymentMethodAccountCode: "2400"
        ))
        let applications = try ReceivableOverpaymentPolicy.applicationsForSubmission([
            .init(invoiceId: "first", amount: 243), .init(invoiceId: "second", amount: 100)
        ], excess: CollectionMoney.amount(cents: credit))
        XCTAssertEqual(applications.map(\.amount), [243, 157])
        let input = ReceivablesPayInput(customerId: "customer", paymentMethodId: "cash", applications: applications,
            reference: nil, note: nil, adjustments: try draft.submissionAdjustments(originalBalances: originals))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual((body["applications"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((body["adjustments"] as? [[String: Any]])?.count, 1)
    }

    func testOneCentExcessAfterReductionIsVisibleAndRejected() throws {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 34_329)
        draft.setAdjustment(.init(direction: .reduce, amountText: "0.01"), invoiceId: "first", original: 243.29)
        let excess = draft.split(invoices: invoices, totalCents: 34_329)
        XCTAssertEqual(excess, 1)
        XCTAssertEqual(draft.allocations["first"], "243.28")
        XCTAssertThrowsError(try ReceivableOverpaymentPolicy.applicationsForSubmission([
            .init(invoiceId: "first", amount: 243.28), .init(invoiceId: "second", amount: 100)
        ], excess: CollectionMoney.amount(cents: excess)))
        XCTAssertEqual(try draft.submissionAdjustments(originalBalances: originals).first?.expectedBalance, 243.29)
    }

    func testRepricingCannotIncreaseExplicitBulkTender() {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 30_000)
        draft.setAdjustment(.init(direction: .increase, amountText: "100"), invoiceId: "first", original: 243.29)
        XCTAssertEqual(draft.split(invoices: invoices, totalCents: 30_000), 0)
        XCTAssertEqual(draft.allocations, ["first": "300.00", "second": ""])
        XCTAssertEqual(draft.balance(invoiceId: "first", original: 243.29), 343.29)
    }

    func testSplitDeselectsLaterInvoiceAndClearsItsAdjustment() throws {
        var draft = ReceivableCollectionDraft()
        _ = draft.split(invoices: invoices, totalCents: 34_329)
        draft.setAdjustment(.init(direction: .reduce, amountText: "1"), invoiceId: "second", original: 100)
        _ = draft.split(invoices: invoices, totalCents: 10_000)
        XCTAssertEqual(draft.allocations, ["first": "100.00", "second": ""])
        XCTAssertNil(draft.adjustments["second"])
        XCTAssertEqual(draft.balance(invoiceId: "second", original: 100), 100)
        XCTAssertTrue(try draft.submissionAdjustments(originalBalances: originals).isEmpty)
    }

    func testUnselectedOrRemovedInvoiceCannotCarryPriceAdjustment() {
        var draft = ReceivableCollectionDraft()
        draft.setAdjustment(.init(direction: .reduce, amountText: "1"), invoiceId: "first", original: 243.29)
        XCTAssertThrowsError(try draft.submissionAdjustments(originalBalances: originals))
        draft.setAllocation("100", invoiceId: "first")
        XCTAssertThrowsError(try draft.submissionAdjustments(originalBalances: ["second": 100]))
    }

    func testPerInvoiceFeesDoNotCreateACentFromTwoSubHalfCentFees() throws {
        let fee = try ReceivableCollectionFee.total(applications: [
            .init(invoiceId: "first", amount: 0.17), .init(invoiceId: "second", amount: 0.17)
        ], excess: 0, paymentMethodAccountCode: "1020", feeRate: "0.029")
        XCTAssertEqual(fee, 0)
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "0.34", feeRate: "0.029"), Decimal(string: "0.01"))
    }

    func testPerInvoiceFeesRoundPositiveHalfCentsUpBeforeSumming() throws {
        let fee = try ReceivableCollectionFee.total(applications: [
            .init(invoiceId: "first", amount: 0.5), .init(invoiceId: "second", amount: 0.5)
        ], excess: 0, paymentMethodAccountCode: "1020", feeRate: "0.01")
        XCTAssertEqual(fee, Decimal(string: "0.02"))
    }

    func testSplitFeeSumCanExceedFeeRoundedOnAggregateTender() throws {
        let fee = try ReceivableCollectionFee.total(applications: [
            .init(invoiceId: "first", amount: 2.5), .init(invoiceId: "second", amount: 2.5)
        ], excess: 0, paymentMethodAccountCode: "1020", feeRate: "0.03")
        XCTAssertEqual(fee, Decimal(string: "0.16"))
        XCTAssertEqual(ManualTenderAmounts.surcharge(amount: "5.00", feeRate: "0.03"), Decimal(string: "0.15"))
    }

    func testExcessIsChargedAsPartOfFinalInvoiceLine() throws {
        let applications: [ReceivableApplication] = [
            .init(invoiceId: "first", amount: 0.17), .init(invoiceId: "second", amount: 0.17)
        ]
        let fee = try ReceivableCollectionFee.total(applications: applications,
            excess: 0.02, paymentMethodAccountCode: "1020", feeRate: "0.029")
        XCTAssertEqual(fee, Decimal(string: "0.01"))
        XCTAssertEqual(applications.map(\.amount), [0.17, 0.17])
    }

    func testStoreCreditHasNoFeeEvenWithConfiguredFeeRate() throws {
        let fee = try ReceivableCollectionFee.total(applications: [
            .init(invoiceId: "first", amount: 100), .init(invoiceId: "second", amount: 50)
        ], excess: 0, paymentMethodAccountCode: "2400", feeRate: "0.03")
        XCTAssertEqual(fee, 0)
    }

    func testUncertainWritesAndStaleBalancesRequireRefreshButDefiniteRejectionDoesNot() {
        for status in [0, 408, 409, 429, 500, 503] {
            var recovery = ReceivableCollectionRecovery()
            recovery.recordFailure(APIError(status: status, message: "Rejected"), invoiceIds: ["first", "second"])
            XCTAssertTrue(recovery.needsRefresh, "HTTP \(status)")
            recovery.recordFailure(APIError(status: 400, message: "Invalid"), invoiceIds: ["third"])
            XCTAssertEqual(recovery.invoiceIds, ["first", "second"])
        }
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(APIError(status: 400, message: "Invalid"), invoiceIds: ["first"])
        XCTAssertFalse(recovery.needsRefresh)
        recovery.recordFailure(URLError(.cancelled), invoiceIds: ["first"])
        XCTAssertTrue(recovery.needsRefresh)
    }

    func testBackendStaleAdjustmentCodeRequiresRefreshEvenWithHTTP400() {
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(APIError(status: 400, message: "This invoice changed.", code: "PAYMENT_ADJUSTMENT_STALE"),
            invoiceIds: ["first"])
        XCTAssertTrue(recovery.needsRefresh)
        XCTAssertEqual(recovery.invoiceIds, ["first"])
    }

    func testFailedHistoryReadKeepsCollectionRetiredAndDoesNotReadBalance() async {
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(URLError(.timedOut), invoiceIds: ["first", "second"])
        let reads = CollectionRecoveryReads()
        do {
            _ = try await recovery.readRefresh(history: {
                await reads.history()
                throw URLError(.cannotConnectToHost)
            }, balances: {
                await reads.balance()
                return true
            })
            XCTFail("A failed history read must not unlock collection")
        } catch {}
        let balanceCount = await reads.balanceCount
        XCTAssertEqual(balanceCount, 0)
        XCTAssertTrue(recovery.needsRefresh)
        XCTAssertEqual(recovery.invoiceIds, ["first", "second"])
    }

    func testFailedBalanceReadKeepsCollectionRetiredUntilBothReadsSucceed() async throws {
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(APIError(status: 409, message: "Stale"), invoiceIds: ["first", "second"])
        let reads = CollectionRecoveryReads()
        do {
            _ = try await recovery.readRefresh(history: { await reads.history() }, balances: {
                await reads.balance()
                throw URLError(.cannotConnectToHost)
            }) as Bool
            XCTFail("A failed balance read must not unlock collection")
        } catch {}
        XCTAssertTrue(recovery.needsRefresh)
        let refreshed = try await recovery.readRefresh(history: { await reads.history() }, balances: {
            await reads.balance()
            return true
        })
        XCTAssertTrue(refreshed)
        recovery.refreshed()
        XCTAssertFalse(recovery.needsRefresh)
        let historyCount = await reads.historyCount
        let balanceCount = await reads.balanceCount
        XCTAssertEqual(historyCount, 2)
        XCTAssertEqual(balanceCount, 2)
    }

    func testRecoveryUsesCollectorReceiptReadWithoutSalesPermissionAndReloadsARBalance() async throws {
        let api = recoveryAPI()
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(URLError(.timedOut), invoiceIds: ["first", "second"])
        let detail = try await recovery.readRefresh(history: {
            try await api.refreshCollectionHistory()
        }, balances: {
            try await api.receivable(customerId: "customer")
        })
        XCTAssertEqual(detail.totalBalance, 0, "Fully collected invoices may disappear from open AR.")
        XCTAssertTrue(detail.openInvoices.isEmpty)
        XCTAssertTrue(recovery.needsRefresh, "Only the caller that retires the old draft may unlock collection.")
        recovery.refreshed()
        XCTAssertFalse(recovery.needsRefresh)
    }

    func testReceiptReadFailureKeepsRecoveryRetiredAndSkipsBalanceRefresh() async {
        let api = recoveryAPI(historyStatus: 503)
        var recovery = ReceivableCollectionRecovery()
        recovery.recordFailure(APIError(status: 400, message: "Changed", code: "PAYMENT_ADJUSTMENT_STALE"),
            invoiceIds: ["first"])
        let reads = CollectionRecoveryReads()
        do {
            _ = try await recovery.readRefresh(history: {
                try await api.refreshCollectionHistory()
            }, balances: {
                await reads.balance()
                return true
            })
            XCTFail("Unavailable receipt history must keep the draft retired.")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 503)
        } catch { XCTFail("Unexpected error: \(error)") }
        let balanceCount = await reads.balanceCount
        XCTAssertEqual(balanceCount, 0)
        XCTAssertTrue(recovery.needsRefresh)
    }

    private func recoveryAPI(historyStatus: Int = 200) -> MoneyAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollectionRecoveryProtocol.self]
        configuration.httpAdditionalHeaders = ["X-History-Status": String(historyStatus)]
        return MoneyAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }
}

private actor CollectionRecoveryReads {
    private(set) var historyCount = 0
    private(set) var balanceCount = 0

    func history() { historyCount += 1 }
    func balance() { balanceCount += 1 }
}

/// Emulates an AR collector with receivables.view and payments.collect, without sales.view.
private final class CollectionRecoveryProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.httpMethod, "GET", "Recovery must never replay a payment.")
            let status: Int
            let json: String
            switch url.path {
            case "/api/receipts":
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "page" }?.value, "1")
                XCTAssertEqual(query.first { $0.name == "pageSize" }?.value, "50")
                status = Int(request.value(forHTTPHeaderField: "X-History-Status") ?? "200") ?? 200
                json = status == 200 ? #"{"items":[],"total":0,"page":1,"pageSize":50}"#
                    : #"{"message":"Receipt history unavailable"}"#
            case "/api/receivables/customer":
                status = 200
                json = #"{"customer":{"id":"customer","name":"Customer"},"totalBalance":0,"openInvoices":[]}"#
            default:
                XCTFail("Recovery requested a route unavailable to this collector: \(url.path)")
                status = 403
                json = #"{"message":"Missing sales.view"}"#
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
