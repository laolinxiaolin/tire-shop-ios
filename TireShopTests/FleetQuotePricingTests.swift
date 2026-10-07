import XCTest
@testable import TireShop

@MainActor
final class FleetQuotePricingTests: XCTestCase {
    func testQuoteReplacementInvalidatesPendingSubmissionButOrdinaryEditsKeepIt() throws {
        let quote = makeStore(enabled: false) { _, _ in [] }
        let initial = quote.generation
        quote.addLine(itemType: "SERVICE", itemId: "service", description: "Mount", unitPrice: 10)
        quote.updateQty(try XCTUnwrap(quote.lines.first?.id), qty: 2)
        XCTAssertTrue(quote.isCurrent(initial))
        quote.clear()
        XCTAssertFalse(quote.isCurrent(initial))
        XCTAssertTrue(quote.lines.isEmpty)
        let replacement = quote.generation
        quote.addLine(itemType: "SERVICE", itemId: "new-service", description: "New cart", unitPrice: 20)
        XCTAssertTrue(quote.isCurrent(replacement))
        XCTAssertFalse(quote.isCurrent(initial))
    }

    func testLatePricingPolicyCannotOverwriteReplacementQuote() async throws {
        var release: CheckedContinuation<FleetPricingPolicy, Error>?
        let quote = QuoteStore(pricingPolicyLoader: {
            try await withCheckedThrowingContinuation { release = $0 }
        })
        let submittedGeneration = quote.generation
        let pending = Task { try await quote.loadPricingPolicy() }
        while release == nil { await Task.yield() }
        quote.clear()
        quote.addLine(itemType: "SERVICE", itemId: "new", description: "New cart", unitPrice: 25)
        release?.resume(returning: FleetPricingPolicy(enabled: true))
        _ = try? await pending.value
        XCTAssertFalse(quote.isCurrent(submittedGeneration))
        XCTAssertNil(quote.pricingEnabled)
        XCTAssertEqual(quote.lines.first?.description, "New cart")
    }

    func testDisabledPolicyKeepsLegacyCatalogChoiceWithoutCallingPreview() async throws {
        var previewCalls = 0
        let quote = makeStore(enabled: false) { _, _ in
            previewCalls += 1
            throw APIError(status: 500, message: "Preview must not be used by the disabled policy")
        }
        let sku = try tire()

        try await quote.addSku(sku, qty: 2, overridePrice: 225)

        XCTAssertEqual(quote.pricingEnabled, false)
        XCTAssertEqual(previewCalls, 0)
        XCTAssertEqual(quote.lines.count, 1)
        XCTAssertEqual(quote.lines[0].unitPrice, 225)
        XCTAssertEqual(quote.lines[0].listPrice, 300)
        XCTAssertEqual(quote.subtotal, 450)
        XCTAssertNil(quote.lines[0].standardUnitPrice)
        XCTAssertNil(quote.lines[0].priceVersion)
        XCTAssertNil(quote.priceLevelAtQuote)
    }

    func testPolicyFailureCannotSilentlyChooseRetailAndCanBeRetried() async throws {
        var failed = true
        var previewCalls = 0
        let quote = QuoteStore(
            taxRateLoader: { _, _, _ in self.taxResponse() },
            pricingPolicyLoader: {
                if failed { throw APIError(status: 503, message: "Pricing unavailable") }
                return FleetPricingPolicy(enabled: false)
            },
            pricingPreviewLoader: { _, _ in
                previewCalls += 1
                return [self.preview()]
            }
        )
        do {
            try await quote.addSku(tire())
            XCTFail("A failed policy request must block adding a tire")
        } catch {
            XCTAssertEqual((error as? APIError)?.status, 503)
        }
        XCTAssertTrue(quote.lines.isEmpty)
        XCTAssertNil(quote.pricingEnabled)
        XCTAssertNotNil(quote.pricingError)
        XCTAssertEqual(previewCalls, 0)

        failed = false
        try await quote.addSku(tire())
        XCTAssertEqual(quote.lines[0].unitPrice, 300)
        XCTAssertEqual(quote.pricingEnabled, false)
        XCTAssertNil(quote.pricingError)
    }

    func testFleetAgreementPreservesStandardAndSubtractsAdditionalAdjustmentOnce() async throws {
        var requestedCustomer: String?
        var requestedSkus: [String] = []
        let quote = makeStore { customerId, skuIds in
            requestedCustomer = customerId
            requestedSkus = skuIds
            return [self.preview(standard: "260.00", actual: "255.00", source: "AGREEMENT")]
        }
        quote.setCustomer(try customer("fleet", level: .fleet))
        quote.setLocation("MAIN")
        quote.taxLookupInProgress = false

        try await quote.addSku(tire(), qty: 4)

        XCTAssertEqual(requestedCustomer, "fleet")
        XCTAssertEqual(requestedSkus, ["tire"])
        XCTAssertEqual(quote.priceLevelAtQuote, .fleet)
        XCTAssertEqual(quote.lines[0].standardUnitPrice, 260)
        XCTAssertEqual(quote.lines[0].listPrice, 260)
        XCTAssertEqual(quote.lines[0].unitPrice, 255)
        XCTAssertEqual(quote.lines[0].priceSource, "AGREEMENT")
        XCTAssertEqual(quote.lines[0].priceVersion, "current-version")
        XCTAssertEqual(quote.subtotal, 1_020)

        quote.lines[0].discount = 2
        XCTAssertEqual(quote.lines[0].lineTotal, 1_018)
        XCTAssertEqual(quote.subtotal, 1_018)
        let submitted = try quote.saleInput().lines[0]
        XCTAssertEqual(submitted.qty, 4)
        XCTAssertEqual(submitted.unitPrice, 255)
        XCTAssertEqual(submitted.discount, 2)
        XCTAssertEqual(submitted.priceVersion, "current-version")
        XCTAssertNil(submitted.id)
    }

    func testQuantityOnlyEditKeepsSavedBaselineAndLineIdentityWithoutPreview() async throws {
        var previewCalls = 0
        let quote = makeStore { _, _ in
            previewCalls += 1
            throw APIError(status: 500, message: "A quantity change must not reprice")
        }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        _ = try await quote.loadPricingPolicy()
        let lineId = try XCTUnwrap(quote.lines.first?.id)

        quote.updateQty(lineId, qty: 6)
        let submitted = try quote.saleInput().lines[0]

        XCTAssertEqual(previewCalls, 0)
        XCTAssertEqual(quote.lines[0].standardUnitPrice, 260)
        XCTAssertEqual(quote.lines[0].unitPrice, 255)
        XCTAssertEqual(quote.lines[0].priceSource, "OVERRIDE")
        XCTAssertEqual(quote.lines[0].discount, 2)
        XCTAssertEqual(submitted.id, "saved-tire-line")
        XCTAssertNil(submitted.priceVersion)
        XCTAssertEqual(submitted.qty, 6)
        XCTAssertEqual(submitted.unitPrice, 255)
        XCTAssertEqual(submitted.discount, 2)
    }

    func testAddingAtChangedCustomerLevelRequiresReviewOfExistingBaselines() async throws {
        let quote = makeStore { _, _ in
            [self.preview(level: .retail, standard: "300.00", actual: "300.00", source: "STANDARD")]
        }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        let acceptedLines = quote.lines
        let acceptedTax = quote.taxOverride

        do {
            try await quote.addSku(tire())
            XCTFail("Adding a tire cannot change the header level while existing lines retain Fleet baselines")
        } catch {
            guard case QuotePricingError.reviewRequired = error else {
                return XCTFail("Expected price review, got \(error)")
            }
        }

        XCTAssertEqual(quote.lines, acceptedLines)
        XCTAssertEqual(quote.priceLevelAtQuote, .fleet)
        XCTAssertEqual(quote.taxOverride, acceptedTax)
        XCTAssertEqual(quote.lines[0].standardUnitPrice, 260)
        XCTAssertEqual(quote.lines[0].savedLineId, "saved-tire-line")
    }

    func testPriceAcceptancePreservesUnknownCreationOutcomeAndBlocksRepeatedCreation() async throws {
        let quote = makeStore { _, _ in [self.preview()] }
        quote.setCustomer(try customer("fleet", level: .fleet))
        quote.taxLookupInProgress = false
        try await quote.addSku(tire(), qty: 4)
        let originalSubmission = try quote.saleInput()
        quote.pendingCreationInput = originalSubmission
        quote.pendingCreationIdempotencyKey = "unknown-post-attempt"
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let originalBody = try encoder.encode(originalSubmission)

        let prepared = try await quote.preparePriceRefresh()
        try quote.acceptPrices(try XCTUnwrap(prepared))

        XCTAssertEqual(quote.pendingCreationIdempotencyKey, "unknown-post-attempt")
        XCTAssertEqual(try encoder.encode(XCTUnwrap(quote.pendingCreationInput)), originalBody,
                       "Accepting new prices must conserve the original uncertain POST payload")
        XCTAssertTrue(quote.hasUnconfirmedCreation)
        XCTAssertThrowsError(try quote.saleInput()) { error in
            guard case QuotePricingError.unconfirmedCreation = error else {
                return XCTFail("Expected a block on repeating unknown creation, got \(error)")
            }
        }

        quote.pendingConfirmationSaleId = "known-saved-sale"
        XCTAssertFalse(quote.hasUnconfirmedCreation)
        XCTAssertNoThrow(try quote.saleInput(), "A known sale can proceed without creating a second sale")
        XCTAssertEqual(try encoder.encode(XCTUnwrap(quote.pendingCreationInput)), originalBody)
    }

    func testPriceRefreshRequiresAcceptanceAndCreatesNewSkuPricingEvidence() async throws {
        let quote = makeStore { _, _ in
            [self.preview(standard: "280.00", actual: "270.00", source: "AGREEMENT", version: "refreshed")]
        }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        let originalLines = quote.lines
        let originalCustomer = quote.customer

        let prepared = try await quote.preparePriceRefresh()
        let proposal = try XCTUnwrap(prepared)

        XCTAssertEqual(quote.lines, originalLines)
        XCTAssertEqual(quote.customer, originalCustomer)
        XCTAssertEqual(quote.lines[0].savedLineId, "saved-tire-line")
        try quote.acceptPrices(proposal)
        XCTAssertEqual(quote.lines[0].qty, 4)
        XCTAssertEqual(quote.lines[0].standardUnitPrice, 280)
        XCTAssertEqual(quote.lines[0].unitPrice, 270)
        XCTAssertEqual(quote.lines[0].priceSource, "AGREEMENT")
        XCTAssertEqual(quote.lines[0].priceVersion, "refreshed")
        XCTAssertNil(quote.lines[0].savedLineId)
        XCTAssertNil(quote.lines[0].discount)
        XCTAssertEqual(quote.lines[1], originalLines[1], "Refreshing tire prices must preserve the service line")
        let submitted = try quote.saleInput()
        XCTAssertNil(submitted.lines[0].id)
        XCTAssertEqual(submitted.lines[0].priceVersion, "refreshed")
        XCTAssertEqual(submitted.lines[1].id, "saved-service-line")
    }

    func testRetryCannotAdoptOlderBaselineOrSourceAfterAcceptingNewPricing() async throws {
        for (standard, source) in [("265.00", "OVERRIDE"), ("260.00", "AGREEMENT")] {
            let quote = makeStore { _, _ in
                [self.preview(standard: standard, actual: "255.00", source: source, version: "accepted-version")]
            }
            let oldSavedSale = try savedSale(adjustment: "0.00")
            quote.seed(from: oldSavedSale, customer: try customer("fleet", level: .fleet))
            let prepared = try await quote.preparePriceRefresh()
            try quote.acceptPrices(try XCTUnwrap(prepared))
            let acceptedLines = quote.lines

            quote.adoptSavedPricing(from: oldSavedSale)

            XCTAssertEqual(quote.lines, acceptedLines, "A retry must not restore older pricing evidence")
            XCTAssertEqual(quote.lines[0].standardUnitPrice, Double(standard))
            XCTAssertEqual(quote.lines[0].unitPrice, 255)
            XCTAssertEqual(quote.lines[0].priceSource, source)
            XCTAssertEqual(quote.lines[0].priceVersion, "accepted-version")
            XCTAssertNil(quote.lines[0].savedLineId)
            let submitted = try quote.saleInput().lines[0]
            XCTAssertNil(submitted.id)
            XCTAssertEqual(submitted.priceVersion, "accepted-version")
        }
    }

    func testRetryCannotRestoreOlderCustomerLevelEvenWhenDollarPricesMatch() async throws {
        let quote = makeStore { _, _ in
            [self.preview(level: .retail, standard: "260.00", actual: "255.00",
                          source: "OVERRIDE", version: "retail-version")]
        }
        let oldSavedSale = try savedSale(adjustment: "0.00")
        quote.seed(from: oldSavedSale, customer: try customer("fleet", level: .fleet))
        let prepared = try await quote.preparePriceRefresh()
        try quote.acceptPrices(try XCTUnwrap(prepared))
        let acceptedLines = quote.lines

        quote.adoptSavedPricing(from: oldSavedSale)

        XCTAssertEqual(quote.priceLevelAtQuote, .retail)
        XCTAssertEqual(quote.lines, acceptedLines)
        XCTAssertNil(quote.lines[0].savedLineId)
        let submitted = try quote.saleInput().lines[0]
        XCTAssertNil(submitted.id)
        XCTAssertEqual(submitted.priceVersion, "retail-version")
    }

    func testManualPriceEditsDisplayOverrideAndRestoreResolvedSource() async throws {
        for (actual, source) in [("255.00", "AGREEMENT"), ("260.00", "STANDARD")] {
            let quote = makeStore { _, _ in [self.preview(actual: actual, source: source)] }
            quote.setCustomer(try customer("fleet", level: .fleet))
            try await quote.addSku(tire())
            let id = quote.lines[0].id
            let resolvedActual = try XCTUnwrap(Double(actual))

            quote.updatePrice(id, unitPrice: 250)
            XCTAssertEqual(quote.lines[0].priceSource, "OVERRIDE")
            XCTAssertEqual(quote.lines[0].standardUnitPrice, 260)
            XCTAssertEqual(quote.lines[0].priceVersion, "current-version")
            quote.updatePrice(id, unitPrice: resolvedActual)
            XCTAssertEqual(quote.lines[0].priceSource, source)

            quote.lines[0].discount = 2
            quote.applyPrice(id, unitPrice: 250)
            XCTAssertEqual(quote.lines[0].priceSource, "OVERRIDE")
            XCTAssertNil(quote.lines[0].discount)
            quote.applyPrice(id, unitPrice: resolvedActual)
            XCTAssertEqual(quote.lines[0].priceSource, source)
            XCTAssertEqual(quote.lines[0].standardUnitPrice, 260)
            XCTAssertEqual(quote.lines[0].priceVersion, "current-version")
        }
    }

    func testChangingCustomerDoesNotMutateSaleBeforeAcceptingNewPrices() async throws {
        var requestedCustomer: String?
        let quote = makeStore { id, _ in
            requestedCustomer = id
            return [self.preview(level: .wholesale, standard: "240.00", actual: "240.00", source: "STANDARD")]
        }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        let originalLines = quote.lines
        let originalCustomer = quote.customer
        let next = try customer("wholesale", level: .wholesale)

        let prepared = try await quote.prepareCustomerSelection(next)
        let proposal = try XCTUnwrap(prepared)

        XCTAssertEqual(requestedCustomer, "wholesale")
        XCTAssertEqual(quote.customer, originalCustomer)
        XCTAssertEqual(quote.lines, originalLines)
        XCTAssertEqual(quote.priceLevelAtQuote, .fleet)
        try quote.acceptPrices(proposal)
        XCTAssertEqual(quote.customer?.id, "wholesale")
        XCTAssertEqual(quote.priceLevelAtQuote, .wholesale)
        XCTAssertEqual(quote.lines[0].unitPrice, 240)
        XCTAssertEqual(quote.lines[0].standardUnitPrice, 240)
        XCTAssertTrue(quote.lines.allSatisfy { $0.savedLineId == nil })
        XCTAssertNil(quote.lines[0].discount)
        XCTAssertEqual(quote.lines[1].unitPrice, originalLines[1].unitPrice)
        quote.taxLookupInProgress = false
        XCTAssertEqual(try quote.saleInput().customerId, "wholesale")
    }

    func testStaleReviewCannotOverwriteQuantityChanges() async throws {
        let quote = makeStore { _, _ in [self.preview()] }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        let prepared = try await quote.preparePriceRefresh()
        let proposal = try XCTUnwrap(prepared)
        let id = quote.lines[0].id
        quote.updateQty(id, qty: 8)

        XCTAssertThrowsError(try quote.acceptPrices(proposal)) { error in
            guard case QuotePricingError.staleReview = error else {
                return XCTFail("Expected stale review, got \(error)")
            }
        }
        XCTAssertEqual(quote.lines[0].qty, 8)
        XCTAssertEqual(quote.lines[0].savedLineId, "saved-tire-line")
        XCTAssertEqual(quote.lines[0].unitPrice, 255)
    }

    func testStaleReviewCannotRestoreClearedCart() async throws {
        let quote = makeStore { _, _ in [self.preview()] }
        quote.seed(from: try savedSale(), customer: try customer("fleet", level: .fleet))
        let prepared = try await quote.preparePriceRefresh()
        let proposal = try XCTUnwrap(prepared)
        quote.clear()

        XCTAssertThrowsError(try quote.acceptPrices(proposal))
        XCTAssertNil(quote.customer)
        XCTAssertTrue(quote.lines.isEmpty)
        XCTAssertNil(quote.priceLevelAtQuote)
    }

    func testIncompleteAndInvalidPreviewNeverAddsAQuotedLine() async throws {
        let cases: [[FleetPricePreview]] = [
            [],
            [preview(sku: "unrequested")],
            [preview(), preview()],
            [preview(standard: "0.00")],
            [preview(standard: "260.001")],
            [preview(actual: "NaN")],
            [preview(actual: "-1.00")],
            [preview(version: "")]
        ]
        for response in cases {
            let quote = makeStore { _, _ in response }
            quote.setCustomer(try customer("fleet", level: .fleet))
            do {
                try await quote.addSku(tire())
                XCTFail("An incomplete or invalid preview must be rejected: \(response)")
            } catch {
                guard case QuotePricingError.invalidPreview = error else {
                    XCTFail("Expected invalid preview, got \(error)")
                    continue
                }
            }
            XCTAssertTrue(quote.lines.isEmpty)
            XCTAssertNil(quote.priceLevelAtQuote)
        }
    }

    func testSavedLegacyDraftNeedsReviewedPricingBeforeSubmission() async throws {
        let quote = makeStore { _, _ in [self.preview()] }
        quote.seed(from: try savedSale(includeBaseline: false), customer: try customer("fleet", level: .fleet))
        _ = try await quote.loadPricingPolicy()

        XCTAssertTrue(quote.hasUnresolvedPrices)
        XCTAssertThrowsError(try quote.saleInput())
        let prepared = try await quote.preparePriceRefresh()
        let proposal = try XCTUnwrap(prepared)
        XCTAssertNil(quote.lines[0].standardUnitPrice)
        try quote.acceptPrices(proposal)
        XCTAssertFalse(quote.hasUnresolvedPrices)
        XCTAssertNoThrow(try quote.saleInput())
    }

    func testInFlightAddCannotAppendAfterCustomerChanges() async throws {
        var finish: CheckedContinuation<[FleetPricePreview], Error>?
        let started = expectation(description: "Fleet preview started")
        let quote = makeStore { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        quote.setCustomer(try customer("fleet", level: .fleet))
        let sku = try tire()
        let add = Task { try await quote.addSku(sku) }
        await fulfillment(of: [started], timeout: 2)
        quote.setCustomer(try customer("retail", level: .retail))
        try XCTUnwrap(finish).resume(returning: [preview()])

        do {
            try await add.value
            XCTFail("The old customer's response must be discarded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(quote.customer?.id, "retail")
        XCTAssertTrue(quote.lines.isEmpty)
        XCTAssertNil(quote.priceLevelAtQuote)
    }

    func testInFlightAddCannotAppendAfterWarehouseChanges() async throws {
        var finish: CheckedContinuation<[FleetPricePreview], Error>?
        let started = expectation(description: "Fleet preview started")
        let quote = makeStore { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        quote.setCustomer(try customer("fleet", level: .fleet))
        quote.setLocation("MAIN")
        let sku = try tire()
        let add = Task { try await quote.addSku(sku) }
        await fulfillment(of: [started], timeout: 2)
        quote.setLocation("SECOND")
        try XCTUnwrap(finish).resume(returning: [preview()])

        do {
            try await add.value
            XCTFail("A price response for the previous sale context must be discarded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(quote.location, "SECOND")
        XCTAssertTrue(quote.lines.isEmpty)
        XCTAssertNil(quote.priceLevelAtQuote)
    }

    private func makeStore(
        enabled: Bool = true,
        preview: @escaping QuoteStore.PricingPreviewLoader
    ) -> QuoteStore {
        QuoteStore(taxRateLoader: { _, _, _ in self.taxResponse() },
                   pricingPolicyLoader: { FleetPricingPolicy(enabled: enabled) },
                   pricingPreviewLoader: preview)
    }

    private func taxResponse() -> CustomerTaxRateResponse {
        CustomerTaxRateResponse(rate: 0.07, source: "LOCATION", resolution: nil,
                                automatic: .init(status: "RESOLVED", resolutionId: "tax", rate: 0.07, code: nil))
    }

    private func preview(
        sku: String = "tire", level: PriceLevel = .fleet,
        standard: String = "260.00", actual: String = "255.00",
        source: String = "AGREEMENT", version: String = "current-version"
    ) -> FleetPricePreview {
        FleetPricePreview(skuId: sku, priceLevel: level, standardUnitPrice: standard,
                          unitPrice: actual, priceSource: source, version: version)
    }

    private func tire() throws -> TireSku {
        let json = """
        {"id":"tire","sku":"TBR-1","brand":"Test","model":"Fleet","size":"11R22.5",
         "category":"TBR","position":"STEER","priceRetail":"300.00","priceWholesale":"240.00",
         "priceFleet":"260.00","priceCost":"100.00","reorderPoint":0,"active":true,"inventory":[]}
        """
        return try JSONDecoder().decode(TireSku.self, from: Data(json.utf8))
    }

    private func customer(_ id: String, level: PriceLevel) throws -> QuoteCustomer {
        let json = """
        {"id":"\(id)","name":"\(id)","taxExempt":false,"accountEnabled":false,"address":"123 Fleet Street",
         "priceLevel":"\(level.rawValue)","createdAt":"2026-10-02T12:00:00Z"}
        """
        return QuoteCustomer(customer: try JSONDecoder().decode(Customer.self, from: Data(json.utf8)))
    }

    private func savedSale(includeBaseline: Bool = true, adjustment: String = "2.00") throws -> Sale {
        let pricing = includeBaseline ? #", "standardUnitPrice":"260.00", "priceSource":"OVERRIDE""# : ""
        let tireAmount = 1_020 - (Double(adjustment) ?? 0)
        let subtotal = tireAmount + 20
        let tax = (subtotal * 0.07 * 100).rounded() / 100
        let json = """
        {"id":"sale","status":"DRAFT","location":"MAIN","priceLevelAtQuote":"FLEET",
         "customer":{"id":"fleet","name":"Fleet customer"},"customerId":"fleet",
         "subtotal":"\(subtotal)","taxRate":"0.07","taxAmount":"\(tax)","total":"\(subtotal + tax)",
         "createdAt":"2026-10-02T12:00:00Z","lines":[
           {"id":"saved-tire-line","itemType":"SKU","itemId":"tire","description":"Fleet tire",
            "qty":4,"unitPrice":"255.00","discount":"\(adjustment)","lineTotal":"\(tireAmount)"\(pricing)},
           {"id":"saved-service-line","itemType":"SERVICE","itemId":"mount","description":"Mount",
            "qty":1,"unitPrice":"20.00","discount":"0.00","lineTotal":"20.00"}
         ]}
        """
        return try JSONDecoder().decode(Sale.self, from: Data(json.utf8))
    }
}
