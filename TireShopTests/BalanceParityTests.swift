import XCTest
@testable import TireShop

final class BalanceParityTests: XCTestCase {
    private struct Row: Codable, Identifiable, Equatable {
        let id: String
        let balance: Double
    }

    private func page(_ number: Int, rows: [Row], total: Int = 3, balance: Double = 900) -> BalancePage<Row> {
        BalancePage(items: rows, total: total, page: number, pageSize: 2,
                    summary: BalanceSummary(balance: balance, buckets: BalanceBuckets(current: 500, b30: 300, b90: 100)))
    }

    @MainActor
    func testTotalsUseCompleteServerSummaryAndPageRowsAreDeduplicated() async {
        let store = BalanceListStore<Row>(pageSize: 2) { number, _, _ in
            self.page(number, rows: number == 1
                      ? [Row(id: "a", balance: 10), Row(id: "b", balance: 20)]
                      : [Row(id: "b", balance: 25), Row(id: "c", balance: 30)])
        }
        await store.reload(query: "")
        XCTAssertEqual(store.summary?.balance, 900)
        XCTAssertEqual(store.summary?.buckets.b90, 100)
        XCTAssertEqual(store.total, 3)
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(store.items[1].balance, 25)
        XCTAssertFalse(store.hasMore)
    }

    @MainActor
    func testFailedLaterPagePreservesRowsAndRetriesSamePage() async {
        var requested: [Int] = []
        var fail = true
        let store = BalanceListStore<Row>(pageSize: 2) { number, _, _ in
            requested.append(number)
            if number == 2 && fail {
                fail = false
                throw URLError(.networkConnectionLost)
            }
            return self.page(number, rows: [Row(id: "row_\(number)", balance: 10)])
        }
        await store.reload(query: "")
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["row_1"])
        XCTAssertEqual(store.summary?.balance, 900)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(requested, [1, 2, 2])
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.items.count, 2)
    }

    @MainActor
    func testRetryAfterFailedRefreshReloadsFirstPageBeforeLoadingMore() async {
        var requests: [Int] = []
        let store = BalanceListStore<Row>(pageSize: 2) { number, _, _ in
            requests.append(number)
            if requests.count == 2 { throw URLError(.timedOut) }
            return self.page(number, rows: [Row(id: "row", balance: 10)])
        }
        await store.reload(query: "")
        await store.reload(query: "")
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(requests, [1, 1])
        await store.retry()
        XCTAssertEqual(requests, [1, 1, 1])
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testLatePageCannotReplaceNewSearchOrItsSummary() async {
        var finish: CheckedContinuation<BalancePage<Row>, Error>?
        let started = expectation(description: "Later page started")
        let store = BalanceListStore<Row>(pageSize: 2) { number, _, query in
            if number == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
            return self.page(number, rows: [Row(id: query ?? "all", balance: 10)],
                             total: query == nil ? 3 : 1, balance: query == nil ? 900 : 10)
        }
        await store.reload(query: "")
        let oldRequest = Task { await store.loadMore() }
        await fulfillment(of: [started], timeout: 2)
        await store.reload(query: "  Acme  ")
        finish?.resume(returning: page(2, rows: [Row(id: "old", balance: 200)]))
        await oldRequest.value
        XCTAssertEqual(store.items.map(\.id), ["Acme"])
        XCTAssertEqual(store.summary?.balance, 10)
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.hasMore)
    }

    func testWholesalePatchDistinguishesUnchangedClearZeroAndPrice() throws {
        func object(_ input: TireSkuPatchInput) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        }
        XCTAssertNil(try object(TireSkuPatchInput())["priceWholesale"])
        let cleared = try object(TireSkuPatchInput(clearPriceWholesale: true))
        XCTAssertTrue(cleared["priceWholesale"] is NSNull)
        XCTAssertNil(cleared["clearPriceWholesale"])
        XCTAssertEqual(try object(TireSkuPatchInput(priceWholesale: 0))["priceWholesale"] as? Double, 0)
        XCTAssertEqual(try object(TireSkuPatchInput(priceWholesale: 85.50))["priceWholesale"] as? Double, 85.50)
        let decoded = try JSONDecoder().decode(TireSkuPatchInput.self, from: Data("{\"priceWholesale\":90}".utf8))
        XCTAssertFalse(decoded.clearPriceWholesale)
        XCTAssertEqual(decoded.priceWholesale, 90)
    }

    func testPaymentCarriesReviewedVendorIdentity() throws {
        let input = PayablesPayInput(expectedVendorKey: "v:vendor_1", applications: [PayableApplication(costId: "cost_1", amount: 100)], paidAt: "2026-09-11", reference: nil, note: nil, accountId: "account_1")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual(object["expectedVendorKey"] as? String, "v:vendor_1")
    }

    func testBalanceSummaryDecodesEvenWhenPageIsEmpty() throws {
        let response = try JSONDecoder().decode(BalancePage<Row>.self, from: Data("""
        {"items":[],"total":12,"page":8,"pageSize":2,"summary":{"balance":1234.56,"buckets":{"current":1000,"b30":200,"b60":30,"b90":4.56}}}
        """.utf8))
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertEqual(response.total, 12)
        XCTAssertEqual(response.summary.balance, 1234.56)
        XCTAssertEqual(response.summary.buckets.b60, 30)
    }

    @MainActor
    func testNewWorkflowLabelsExistInBothAppLanguages() {
        let keys = [
            "sku.wholesale", "sku.wholesaleHint", "salePrice.lastSold", "salePrice.historySource",
            "salePrice.discounted", "salePrice.error", "salePrice.wholesaleUnset", "salePrice.useLast",
            "purchasing.paymentStatus.unpaid", "purchasing.paymentStatus.partial", "purchasing.paymentStatus.paid",
            "purchasing.supplierChange.title", "purchasing.supplierChange.confirm", "purchasing.supplierChange.reason",
            "accounting.cash.addAccount", "accounting.cash.addAccountHelp",
            "expenseReceipt.camera", "expenseReceipt.photos", "expenseReceipt.files", "expenseReceipt.saved",
            "documentUpload.preparing", "documentUpload.prepareFailed"
        ]
        for key in keys {
            for language in AppLanguage.allCases {
                XCTAssertNotNil(I18nStore.messages[language]?[key], "Missing \(language.rawValue): \(key)")
            }
        }
    }
}
