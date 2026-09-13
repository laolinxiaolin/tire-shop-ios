import XCTest
@testable import TireShop

final class SalePricingTests: XCTestCase {
    private func price(customer: String = "a", sku: String = "sku_1", effective: String = "96.67") -> CustomerLastSalePrice {
        CustomerLastSalePrice(
            skuId: sku,
            unitPrice: "100.00",
            discount: "10.00",
            lineTotal: "290.00",
            effectiveUnitPrice: effective,
            qty: 3,
            saleId: "sale_\(customer)",
            saleRef: "XS-\(customer)",
            soldAt: "2026-09-01T12:00:00Z"
        )
    }

    @MainActor
    func testQuoteMergesOnlyMatchingUndiscountedPriceAndKeepsRetailReference() {
        let quote = QuoteStore()
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", unitPrice: 80, listPrice: 100)
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", unitPrice: 80, listPrice: 100)
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", unitPrice: 100, listPrice: 100)

        XCTAssertEqual(quote.lines.count, 2)
        XCTAssertEqual(quote.lines[0].qty, 2)
        XCTAssertEqual(quote.lines[0].listPrice, 100)
        XCTAssertEqual(quote.subtotal, 260)

        quote.lines[0].discount = 10
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", unitPrice: 80, listPrice: 100)
        XCTAssertEqual(quote.lines.count, 3)
        XCTAssertEqual(quote.lines[0].discount, 10)
        XCTAssertEqual(quote.lines[0].qty, 2)
        XCTAssertEqual(Set(quote.lines.map(\.id)).count, 3)
    }

    @MainActor
    func testEffectiveHistoryPriceClearsDiscountAndRoundedTaxOverride() {
        let quote = QuoteStore()
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", qty: 3, unitPrice: 100)
        let lineID = quote.lines[0].id
        quote.lines[0].discount = 10
        quote.taxOverride = 20

        quote.applyPrice(lineID, unitPrice: 96.67)

        XCTAssertNil(quote.lines[0].discount)
        XCTAssertNil(quote.taxOverride)
        XCTAssertEqual(quote.subtotal, 290.01, accuracy: 0.0001)
        XCTAssertEqual(quote.lines[0].listPrice, 100)
        quote.applyPrice(lineID, unitPrice: .infinity)
        quote.applyPrice(lineID, unitPrice: -1)
        XCTAssertEqual(quote.lines[0].unitPrice, 96.67)
        quote.applyPrice(lineID, unitPrice: 0)
        XCTAssertEqual(quote.subtotal, 0)
    }

    @MainActor
    func testZeroWholesalePriceIsKeptAndInvalidNewPricesAreRejected() {
        let quote = QuoteStore()
        quote.addLine(itemType: "SKU", itemId: "free", description: "Tire", unitPrice: 0, listPrice: 100)
        quote.addLine(itemType: "SKU", itemId: "bad", description: "Tire", unitPrice: .nan)
        quote.addLine(itemType: "SKU", itemId: "bad", description: "Tire", unitPrice: -2)
        XCTAssertEqual(quote.lines.count, 1)
        XCTAssertEqual(quote.lines[0].unitPrice, 0)
        XCTAssertEqual(quote.lines[0].listPrice, 100)
    }

    @MainActor
    func testChangingCustomerDoesNotAutomaticallyOverwriteNegotiatedPrices() {
        let quote = QuoteStore()
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "a", name: "A", company: nil)))
        quote.addLine(itemType: "SKU", itemId: "tire", description: "Tire", unitPrice: 80, listPrice: 100)
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "b", name: "B", company: nil)))
        XCTAssertEqual(quote.lines[0].unitPrice, 80)
        XCTAssertEqual(quote.lines[0].listPrice, 100)
        quote.setCustomer(nil)
        XCTAssertEqual(quote.lines[0].unitPrice, 80)
    }

    func testWholesalePatchDistinguishesClearZeroAndUnchanged() throws {
        func object(_ patch: TireSkuPatchInput) throws -> [String: Any] {
            let encoded = try JSONEncoder().encode(patch)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        }
        XCTAssertNil(try object(TireSkuPatchInput())["priceWholesale"])
        XCTAssertEqual(try object(TireSkuPatchInput(priceWholesale: 0))["priceWholesale"] as? Double, 0)
        XCTAssertTrue(try object(TireSkuPatchInput(clearPriceWholesale: true))["priceWholesale"] is NSNull)
        let decoded = try JSONDecoder().decode(TireSkuPatchInput.self, from: Data("{\"priceWholesale\":42}".utf8))
        XCTAssertEqual(decoded.priceWholesale, 42)
        XCTAssertFalse(decoded.clearPriceWholesale)
    }

    @MainActor
    func testLateCustomerResponseCannotReplaceCurrentCustomerPrice() async {
        var finishA: CheckedContinuation<[CustomerLastSalePrice], Error>?
        let startedA = expectation(description: "Customer A request started")
        let store = SalePriceHistoryStore { customer, _ in
            if customer == "a" {
                return try await withCheckedThrowingContinuation { continuation in
                    finishA = continuation
                    startedA.fulfill()
                }
            }
            return [self.price(customer: customer, effective: "90.00")]
        }
        let requestA = SalePriceRequest(customerId: "a", skuIds: ["sku_1"])
        let requestB = SalePriceRequest(customerId: "b", skuIds: ["sku_1"])
        let taskA = Task { await store.load(requestA) }
        await fulfillment(of: [startedA], timeout: 1)
        await store.load(requestB)
        XCTAssertEqual(store.price(for: "sku_1", request: requestB)?.saleId, "sale_b")
        XCTAssertNil(store.price(for: "sku_1", request: requestA))

        finishA?.resume(returning: [price(customer: "a")])
        await taskA.value
        XCTAssertEqual(store.price(for: "sku_1", request: requestB)?.saleId, "sale_b")
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testCatalogHistoryDeduplicatesAndBoundsEachBatch() async {
        var batches: [[String]] = []
        let store = SalePriceHistoryStore { _, ids in
            batches.append(ids)
            return []
        }
        let ids = (0..<1105).map { String(format: "sku_%04d", $0) }
        await store.load(SalePriceRequest(customerId: "a", skuIds: ids + Array(ids.prefix(5))))
        XCTAssertEqual(batches.count, 12)
        XCTAssertTrue(batches.allSatisfy { $0.count <= 100 })
        XCTAssertEqual(batches.flatMap { $0 }, ids)

        await store.load(SalePriceRequest(customerId: nil, skuIds: ids))
        await store.load(SalePriceRequest(customerId: "a", skuIds: []))
        XCTAssertEqual(batches.count, 12)
        XCTAssertTrue(store.bySku.isEmpty)
    }

    @MainActor
    func testRefreshHidesOldPricesAndFailedRefreshCannotReuseThem() async {
        var callCount = 0
        var finishRefresh: CheckedContinuation<[CustomerLastSalePrice], Error>?
        let startedRefresh = expectation(description: "Refresh started")
        let store = SalePriceHistoryStore { _, _ in
            callCount += 1
            if callCount == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    finishRefresh = continuation
                    startedRefresh.fulfill()
                }
            }
            return [self.price()]
        }
        let request = SalePriceRequest(customerId: "a", skuIds: ["sku_1"])
        await store.load(request)
        XCTAssertNotNil(store.price(for: "sku_1", request: request))

        let refresh = Task { await store.load(request) }
        await fulfillment(of: [startedRefresh], timeout: 1)
        XCTAssertTrue(store.isLoading)
        XCTAssertNil(store.price(for: "sku_1", request: request))
        finishRefresh?.resume(throwing: URLError(.notConnectedToInternet))
        await refresh.value
        XCTAssertTrue(store.hasError)
        XCTAssertNil(store.price(for: "sku_1", request: request))

        await store.load(request)
        XCTAssertFalse(store.hasError)
        XCTAssertNotNil(store.price(for: "sku_1", request: request))
        await store.load(SalePriceRequest(customerId: nil, skuIds: ["sku_1"]))
        XCTAssertTrue(store.bySku.isEmpty)
    }

    @MainActor
    func testUnrequestedAndInvalidHistoryPricesAreIgnored() async {
        let store = SalePriceHistoryStore { _, _ in
            [self.price(sku: "other"), self.price(sku: "negative", effective: "-1"),
             self.price(sku: "invalid", effective: "nan"), self.price(sku: "zero", effective: "0")]
        }
        let request = SalePriceRequest(customerId: "a", skuIds: ["negative", "invalid", "zero"])
        await store.load(request)
        XCTAssertEqual(Set(store.bySku.keys), ["zero"])
        XCTAssertEqual(store.price(for: "zero", request: request)?.effectiveUnitPrice, "0")
    }
}
