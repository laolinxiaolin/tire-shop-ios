import XCTest
@testable import TireShop

final class SalePricingTests: XCTestCase {
    private func taxResponse(
        rate: Double?,
        source: String = "LOCATION",
        resolutionId: String? = "resolution-1",
        code: String? = nil
    ) -> CustomerTaxRateResponse {
        CustomerTaxRateResponse(
            rate: rate,
            source: source,
            resolution: .init(problemCode: code),
            automatic: .init(
                status: rate == nil ? "UNRESOLVED" : "RESOLVED",
                resolutionId: resolutionId,
                rate: rate,
                code: code
            )
        )
    }

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
    func testDraftDetectionProtectsUnfinishedSaleContext() {
        let quote = QuoteStore()
        XCTAssertFalse(quote.hasDraft)

        quote.addLine(itemType: "SERVICE", itemId: "mount", description: "Mount", unitPrice: 20)
        XCTAssertTrue(quote.hasDraft)

        quote.clear()
        XCTAssertFalse(quote.hasDraft)

        quote.pendingCreationIdempotencyKey = "retry-key"
        XCTAssertTrue(quote.hasDraft)
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

    @MainActor
    func testVerifiedCustomerTaxRateIsLoadedAndIncludedWithFulfillment() async throws {
        var requestedFulfillment: SaleFulfillment?
        var requestedLocation: String?
        let quote = QuoteStore { _, fulfillment, location in
            requestedFulfillment = fulfillment
            requestedLocation = location
            return self.taxResponse(rate: 0.0825)
        }
        quote.setLocation("MAIN")
        quote.setFulfillment(.pickup)
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))

        await quote.applyCustomerTaxRate()

        XCTAssertEqual(requestedFulfillment, .pickup)
        XCTAssertEqual(requestedLocation, "MAIN")
        XCTAssertEqual(quote.taxRate, 8.25)
        XCTAssertEqual(quote.taxResolutionId, "resolution-1")
        XCTAssertFalse(quote.taxLookupInProgress)
        XCTAssertNil(quote.taxLookupError)

        let input = try quote.saleInput()
        XCTAssertEqual(input.fulfillment, .pickup)
        XCTAssertEqual(input.taxResolutionId, "resolution-1")
        XCTAssertEqual(input.taxRate, 0.0825)
    }

    @MainActor
    func testUnresolvedTaxBlocksSaleUntilRetrySucceeds() async throws {
        var shouldResolve = false
        let quote = QuoteStore { _, _, _ in
            shouldResolve
                ? self.taxResponse(rate: 0.07)
                : self.taxResponse(rate: nil, resolutionId: nil, code: "ADDRESS_REVIEW_REQUIRED")
        }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))

        await quote.applyCustomerTaxRate()
        XCTAssertEqual(quote.taxLookupError, "ADDRESS_REVIEW_REQUIRED")
        XCTAssertThrowsError(try quote.saleInput())

        shouldResolve = true
        await quote.applyCustomerTaxRate()
        XCTAssertNil(quote.taxLookupError)
        XCTAssertNoThrow(try quote.saleInput())
    }

    @MainActor
    func testExpiredExemptionDoesNotSuppressVerifiedTax() async {
        let quote = QuoteStore { _, _, _ in
            self.taxResponse(rate: 0.08)
        }
        quote.setCustomer(QuoteCustomer(
            summary: CustomerSummary(id: "customer", name: "Customer", company: nil),
            taxExempt: true,
            taxExemptExpiresAt: "2020-01-01T00:00:00.000Z"
        ))

        XCTAssertFalse(quote.customer?.taxExempt ?? true)
        await quote.applyCustomerTaxRate()
        XCTAssertEqual(quote.taxAmount, 0)
        XCTAssertFalse(quote.customer?.taxExempt ?? true)
        XCTAssertEqual(quote.taxRate, 8)
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

    @MainActor
    func testTaxRateOverrideRequiresAdminAndRejectsInvalidPercentages() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        await quote.applyCustomerTaxRate()

        quote.setTaxRate(8.5, isAdmin: false)
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertEqual(quote.taxRate, 7)
        XCTAssertEqual(quote.taxResolutionId, "resolution-1")

        let invalidRates: [Double] = [.nan, .infinity, -.infinity, -0.01, 100.01, 8.12345, 0.00001]
        for rate in invalidRates {
            quote.setTaxRate(rate, isAdmin: true)
            XCTAssertFalse(quote.overrideTaxRate, "Rejected percentage: \(rate)")
            XCTAssertEqual(quote.taxRate, 7)
            XCTAssertEqual(quote.taxResolutionId, "resolution-1")
        }

        quote.setTaxRate(8.1234, isAdmin: true)
        for rate in invalidRates {
            quote.setTaxRate(rate, isAdmin: true)
            XCTAssertTrue(quote.overrideTaxRate)
            XCTAssertEqual(quote.taxRate, 8.1234, accuracy: 0.0000001)
        }
        quote.setTaxRate(9, isAdmin: false)
        XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)
    }

    @MainActor
    func testManualTaxRatePreservesPrecisionAndAcceptsZeroAndOneHundredPercent() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        quote.addLine(itemType: "SERVICE", itemId: "service", description: "Service", unitPrice: 100)
        await quote.applyCustomerTaxRate()

        quote.setTaxRate(8.1234, isAdmin: true)
        XCTAssertTrue(quote.overrideTaxRate)
        XCTAssertEqual(quote.effectiveTaxRate, 8.1234, accuracy: 0.0000001)
        XCTAssertEqual(quote.taxAmount, 8.12)
        XCTAssertNil(quote.taxResolutionId)
        XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)

        quote.setTaxRate(0, isAdmin: true)
        XCTAssertTrue(quote.overrideTaxRate)
        XCTAssertEqual(quote.effectiveTaxRate, 0)
        XCTAssertEqual(quote.taxAmount, 0)
        XCTAssertEqual(try quote.saleInput().taxRate, 0)

        quote.setTaxRate(100, isAdmin: true)
        XCTAssertEqual(quote.effectiveTaxRate, 100)
        XCTAssertEqual(quote.taxAmount, 100)
        XCTAssertEqual(try quote.saleInput().taxRate, 1)
    }

    @MainActor
    func testAutomaticTaxRatePreservesSixFractionalDigits() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.081234) }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        await quote.applyCustomerTaxRate()

        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertEqual(quote.effectiveTaxRate, 8.1234, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)
        XCTAssertEqual(quote.taxResolutionId, "resolution-1")
    }

    @MainActor
    func testManualTaxRateSurvivesQueuedAndInFlightAutomaticLookups() async throws {
        var finishLookup: CheckedContinuation<CustomerTaxRateResponse, Error>?
        var requestCount = 0
        let started = expectation(description: "Automatic tax lookup started")
        let quote = QuoteStore { _, _, _ in
            requestCount += 1
            return try await withCheckedThrowingContinuation { continuation in
                finishLookup = continuation
                started.fulfill()
            }
        }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        let pendingLookup = Task { await quote.applyCustomerTaxRate() }
        await fulfillment(of: [started], timeout: 1)

        quote.setTaxRate(8.1234, isAdmin: true)
        await quote.applyCustomerTaxRate()
        XCTAssertEqual(requestCount, 1)
        finishLookup?.resume(returning: taxResponse(rate: 0.09))
        await pendingLookup.value

        XCTAssertTrue(quote.overrideTaxRate)
        XCTAssertEqual(quote.taxRate, 8.1234, accuracy: 0.0000001)
        XCTAssertFalse(quote.taxLookupInProgress)
        XCTAssertNil(quote.taxLookupError)
        XCTAssertNil(quote.taxResolutionId)
        XCTAssertTrue(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testReturningToAutomaticTaxClearsOverrideAndFetchesCurrentRate() async throws {
        var requestCount = 0
        let quote = QuoteStore { _, _, _ in
            requestCount += 1
            return self.taxResponse(rate: 0.089)
        }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        quote.setTaxRate(8.1234, isAdmin: true)

        await quote.useAutomaticTaxRate()

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertEqual(quote.effectiveTaxRate, 8.9, accuracy: 0.0000001)
        XCTAssertEqual(quote.taxResolutionId, "resolution-1")
        XCTAssertFalse(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testSavedOverrideSurvivesEditingIncludingAnExemptCustomer() async throws {
        let sale = try decodedSale(evidenceType: "SALE_RATE_OVERRIDE")
        XCTAssertEqual(sale.taxEvidence?.type, "SALE_RATE_OVERRIDE")

        for taxExempt in [false, true] {
            var lookupCount = 0
            let quote = QuoteStore { _, _, _ in
                lookupCount += 1
                return self.taxResponse(rate: 0, source: "EXEMPT", resolutionId: nil)
            }
            quote.seed(from: sale, customer: QuoteCustomer(summary: sale.customer, taxExempt: taxExempt))
            await quote.applyCustomerTaxRate()

            XCTAssertEqual(lookupCount, 0)
            XCTAssertTrue(quote.overrideTaxRate)
            XCTAssertEqual(quote.effectiveTaxRate, 8.1234, accuracy: 0.0000001)
            XCTAssertEqual(quote.taxAmount, 8.12)
            XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)
            XCTAssertTrue(try quote.saleInput().overrideTaxRate)
        }
    }

    @MainActor
    func testManualOverrideCanReplaceExemptionAndReturnToExemption() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0, source: "EXEMPT", resolutionId: nil) }
        quote.setCustomer(QuoteCustomer(
            summary: CustomerSummary(id: "customer", name: "Customer", company: nil),
            taxExempt: true
        ))
        quote.addLine(itemType: "SERVICE", itemId: "service", description: "Service", unitPrice: 100)
        await quote.applyCustomerTaxRate()
        XCTAssertEqual(quote.taxAmount, 0)

        quote.setTaxRate(8.1234, isAdmin: true)
        XCTAssertEqual(quote.taxAmount, 8.12)
        XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)

        await quote.useAutomaticTaxRate()
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertEqual(quote.effectiveTaxRate, 0)
        XCTAssertEqual(quote.taxAmount, 0)
        XCTAssertEqual(try quote.saleInput().taxRate, 0)
    }

    @MainActor
    func testCustomerFulfillmentAndLocationChangesClearOverrideButLocationAndFulfillmentNoOpsDoNot() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        let customer = QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil))
        quote.setCustomer(customer)
        quote.setLocation("MAIN")
        quote.setTaxRate(8.1234, isAdmin: true)

        quote.setLocation("MAIN")
        quote.setFulfillment(.delivery)
        XCTAssertTrue(quote.overrideTaxRate)
        XCTAssertEqual(quote.taxRate, 8.1234, accuracy: 0.0000001)

        quote.setFulfillment(.pickup)
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertTrue(quote.taxLookupInProgress)
        await quote.applyCustomerTaxRate()

        quote.setTaxRate(8.1234, isAdmin: true)
        quote.setLocation("BRANCH")
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertTrue(quote.taxLookupInProgress)
        await quote.applyCustomerTaxRate()

        quote.setTaxRate(8.1234, isAdmin: true)
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "other", name: "Other", company: nil)))
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertTrue(quote.taxLookupInProgress)
        await quote.applyCustomerTaxRate()
        XCTAssertFalse(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testReselectingCustomerRefreshesTaxAndClearsOverride() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        let customer = QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil))
        quote.setCustomer(customer)
        quote.setTaxRate(8.1234, isAdmin: true)

        quote.setCustomer(customer)
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertTrue(quote.taxLookupInProgress)
        await quote.applyCustomerTaxRate()
        XCTAssertEqual(quote.effectiveTaxRate, 7)
        XCTAssertFalse(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testDeliveryLocationChangeAlsoClearsManualOverride() async throws {
        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        quote.setLocation("MAIN")
        await quote.applyCustomerTaxRate()
        quote.setTaxRate(8.1234, isAdmin: true)

        quote.setLocation("BRANCH")
        XCTAssertFalse(quote.overrideTaxRate)
        await quote.applyCustomerTaxRate()
        XCTAssertEqual(quote.effectiveTaxRate, 7)
        XCTAssertFalse(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testSalePayloadAlwaysExplicitlyEncodesTaxOverrideMode() async throws {
        func object(_ input: SaleUpsertInput) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        }
        let defaultInput = SaleUpsertInput(customerId: "customer", taxRate: 0.07, taxAmount: nil, lines: [])
        XCTAssertEqual(try object(defaultInput)["overrideTaxRate"] as? Bool, false)

        let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.07) }
        quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
        quote.setTaxRate(8.1234, isAdmin: true)
        let manual = try object(quote.saleInput())
        XCTAssertEqual(manual["overrideTaxRate"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(manual["taxRate"] as? Double), 0.081234, accuracy: 0.00000001)
        XCTAssertNil(manual["taxResolutionId"])

        await quote.useAutomaticTaxRate()
        let automatic = try object(quote.saleInput())
        XCTAssertEqual(automatic["overrideTaxRate"] as? Bool, false)
        XCTAssertEqual(automatic["taxResolutionId"] as? String, "resolution-1")
    }

    @MainActor
    func testLegacySaleWithoutTaxEvidenceStillDecodesAndSeedsAutomaticMode() throws {
        let sale = try decodedSale()
        XCTAssertNil(sale.taxEvidence)
        XCTAssertNil(sale.fulfillment)
        XCTAssertNil(sale.taxResolutionId)

        let quote = QuoteStore()
        quote.seed(from: sale, customer: QuoteCustomer(summary: sale.customer))
        XCTAssertFalse(quote.overrideTaxRate)
        XCTAssertEqual(quote.fulfillment, .delivery)
        XCTAssertEqual(quote.effectiveTaxRate, 8.1234, accuracy: 0.0000001)
        XCTAssertFalse(try quote.saleInput().overrideTaxRate)
    }

    @MainActor
    func testShopDefaultResponsesNeedNoTaxResolutionIncludingZeroRate() async throws {
        for rate in [0.089, 0.0] {
            let automaticVariants = [
                ",\"automatic\":{\"status\":\"SHOP_DEFAULT\",\"rate\":\(rate)}",
                ",\"automatic\":null",
                ""
            ]
            for automatic in automaticVariants {
                let json = "{\"rate\":\(rate),\"source\":\"DEFAULT\",\"resolution\":null\(automatic)}"
                let response = try JSONDecoder().decode(CustomerTaxRateResponse.self, from: Data(json.utf8))
                let quote = QuoteStore { _, _, _ in response }
                quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
                quote.addLine(itemType: "SERVICE", itemId: "service", description: "Service", unitPrice: 100)

                await quote.applyCustomerTaxRate()

                XCTAssertFalse(quote.taxLookupInProgress)
                XCTAssertNil(quote.taxLookupError)
                XCTAssertNil(quote.taxResolutionId)
                XCTAssertFalse(quote.overrideTaxRate)
                XCTAssertEqual(quote.taxLookupMessage, "newQuote.taxShopDefaultApplied")
                XCTAssertEqual(quote.effectiveTaxRate, rate * 100, accuracy: 0.0000001)
                XCTAssertEqual(quote.taxAmount, rate * 100, accuracy: 0.0000001)
                let input = try quote.saleInput()
                XCTAssertEqual(try XCTUnwrap(input.taxRate), rate, accuracy: 0.00000001)
                XCTAssertNil(input.taxResolutionId)
                XCTAssertFalse(input.overrideTaxRate)
            }
        }
    }

    func testTaxPercentageInputKeepsFourDecimalPlacesAndHandlesEditingStates() throws {
        let accepted: [(String, Double)] = [
            ("", 0), (".", 0), (",", 0), ("0", 0), ("8.", 8),
            ("8.1234", 8.1234), ("8,1234", 8.1234), (".1234", 0.1234),
            ("100", 100), ("100.0000", 100)
        ]
        for (text, expected) in accepted {
            XCTAssertEqual(try XCTUnwrap(SaleTaxPercentage.parseInput(text)), expected, accuracy: 0.0000001)
        }
        for text in ["8.12345", "100.0001", "-1", "101", "1e1", "nan", "infinity", "8..1", "8,1.2"] {
            XCTAssertNil(SaleTaxPercentage.parseInput(text), "Rejected input: \(text)")
        }
    }

    func testTaxPercentageDisplayPreservesPrecisionWithoutTrailingZeros() {
        let cases: [(Double, String)] = [
            (0, "0"), (8, "8"), (8.9, "8.9"), (8.1234, "8.1234"),
            (8.12, "8.12"), (0.0001, "0.0001"), (100, "100")
        ]
        for (percent, expected) in cases {
            XCTAssertEqual(SaleTaxPercentage.text(percent), expected)
        }
    }

    @MainActor
    func testMainPickupShopDefaultUnblocksUnresolvedDeliveryButOtherUnresolvedLocationsStayBlocked() async throws {
        for rate in [0.089, 0.0] {
            let fallback = CustomerTaxRateResponse(
                rate: rate,
                source: "DEFAULT",
                resolution: nil,
                automatic: .init(status: "SHOP_DEFAULT", resolutionId: nil, rate: rate, code: nil)
            )
            let quote = QuoteStore { _, fulfillment, location in
                if fulfillment == .pickup && location == "MAIN" { return fallback }
                return self.taxResponse(rate: nil, resolutionId: nil, code: "ADDRESS_REVIEW_REQUIRED")
            }
            quote.setLocation("MAIN")
            quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
            await quote.applyCustomerTaxRate()
            XCTAssertEqual(quote.taxLookupError, "ADDRESS_REVIEW_REQUIRED")
            XCTAssertThrowsError(try quote.saleInput())

            quote.setFulfillment(.pickup)
            await quote.applyCustomerTaxRate()
            XCTAssertNil(quote.taxLookupError)
            XCTAssertNil(quote.taxResolutionId)
            XCTAssertEqual(quote.taxLookupMessage, "newQuote.taxShopDefaultApplied")
            XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), rate, accuracy: 0.00000001)

            quote.setLocation("BRANCH")
            await quote.applyCustomerTaxRate()
            XCTAssertEqual(quote.taxLookupError, "ADDRESS_REVIEW_REQUIRED")
            XCTAssertThrowsError(try quote.saleInput())
        }
    }

    @MainActor
    func testExemptionAndCustomerOverrideTakePrecedenceOverAutomaticShopDefault() async throws {
        let cases: [(String, Double, String)] = [
            ("EXEMPT", 0, "newQuote.taxExemptionApplied"),
            ("OVERRIDE", 0.061234, "newQuote.taxCustomerOverrideApplied")
        ]
        for (source, rate, message) in cases {
            let response = CustomerTaxRateResponse(
                rate: rate,
                source: source,
                resolution: nil,
                automatic: .init(status: "SHOP_DEFAULT", resolutionId: nil, rate: 0.089, code: nil)
            )
            let quote = QuoteStore { _, _, _ in response }
            quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
            quote.addLine(itemType: "SERVICE", itemId: "service", description: "Service", unitPrice: 100)
            await quote.applyCustomerTaxRate()

            XCTAssertEqual(quote.effectiveTaxRate, rate * 100, accuracy: 0.0000001)
            XCTAssertEqual(quote.taxAmount, (rate * 10_000).rounded() / 100, accuracy: 0.0000001)
            XCTAssertEqual(quote.customer?.taxExempt, source == "EXEMPT")
            XCTAssertEqual(quote.taxLookupMessage, message)
            XCTAssertNil(quote.taxLookupError)
            XCTAssertNil(quote.taxResolutionId)
            XCTAssertFalse(quote.overrideTaxRate)
            XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), rate, accuracy: 0.00000001)
        }
    }

    @MainActor
    func testSixDecimalTaxFractionCalculatesLargeSaleWithoutLosingCents() async throws {
        for useManualOverride in [false, true] {
            let quote = QuoteStore { _, _, _ in self.taxResponse(rate: 0.081235) }
            quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
            quote.addLine(itemType: "SERVICE", itemId: "service", description: "Service", unitPrice: 50_000)
            await quote.applyCustomerTaxRate()
            if useManualOverride { quote.setTaxRate(8.1235, isAdmin: true) }

            XCTAssertEqual(quote.taxAmount, 4_061.75, accuracy: 0.0000001)
            XCTAssertEqual(quote.total, 54_061.75, accuracy: 0.0000001)
            let input = try quote.saleInput()
            XCTAssertEqual(input.overrideTaxRate, useManualOverride)
            XCTAssertEqual(try XCTUnwrap(input.taxRate), 0.081235, accuracy: 0.00000001)
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
            XCTAssertEqual(try XCTUnwrap(encoded["taxRate"] as? Double), 0.081235, accuracy: 0.00000001)
        }
    }

    @MainActor
    func testCancelledTaxLookupCanRetryWithoutOverwritingANewerManualRate() async throws {
        let cancellationErrors: [Error] = [CancellationError(), URLError(.cancelled)]
        for cancellationError in cancellationErrors {
            for overrideBeforeCancellation in [false, true] {
                var finishLookup: CheckedContinuation<CustomerTaxRateResponse, Error>?
                var requestCount = 0
                let started = expectation(description: "Cancellable tax lookup started")
                let quote = QuoteStore { _, _, _ in
                    requestCount += 1
                    if requestCount == 1 {
                        return try await withCheckedThrowingContinuation { continuation in
                            finishLookup = continuation
                            started.fulfill()
                        }
                    }
                    return self.taxResponse(rate: 0.07)
                }
                quote.setCustomer(QuoteCustomer(summary: CustomerSummary(id: "customer", name: "Customer", company: nil)))
                let pendingLookup = Task { await quote.applyCustomerTaxRate() }
                await fulfillment(of: [started], timeout: 1)
                if overrideBeforeCancellation { quote.setTaxRate(8.1234, isAdmin: true) }
                pendingLookup.cancel()
                finishLookup?.resume(throwing: cancellationError)
                await pendingLookup.value

                XCTAssertNil(quote.taxLookupError)
                XCTAssertEqual(quote.overrideTaxRate, overrideBeforeCancellation)
                if overrideBeforeCancellation {
                    XCTAssertFalse(quote.taxLookupInProgress)
                    XCTAssertEqual(quote.effectiveTaxRate, 8.1234, accuracy: 0.0000001)
                    XCTAssertEqual(try XCTUnwrap(quote.saleInput().taxRate), 0.081234, accuracy: 0.00000001)
                } else {
                    XCTAssertTrue(quote.taxLookupInProgress)
                    XCTAssertThrowsError(try quote.saleInput())
                    await quote.applyCustomerTaxRate()
                    XCTAssertEqual(requestCount, 2)
                    XCTAssertFalse(quote.taxLookupInProgress)
                    XCTAssertNil(quote.taxLookupError)
                    XCTAssertEqual(try quote.saleInput().taxRate, 0.07)
                }
            }
        }
    }

    private func decodedSale(evidenceType: String? = nil) throws -> Sale {
        let evidence = evidenceType.map { ",\"taxEvidence\":{\"type\":\"\($0)\"}" } ?? ""
        let json = """
        {
            "id": "sale-1", "status": "DRAFT", "location": "MAIN",
            "customer": {"id": "customer", "name": "Customer"}, "customerId": "customer",
            "subtotal": "100.00", "taxRate": "0.081234", "taxAmount": "8.12", "total": "108.12",
            "createdAt": "2026-09-21T12:00:00Z",
            "lines": [{"id": "line-1", "itemType": "SERVICE", "itemId": "service", "description": "Service",
                       "qty": 1, "unitPrice": "100.00", "discount": "0", "lineTotal": "100.00"}]
            \(evidence)
        }
        """
        return try JSONDecoder().decode(Sale.self, from: Data(json.utf8))
    }
}
