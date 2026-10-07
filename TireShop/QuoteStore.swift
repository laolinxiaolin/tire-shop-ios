import Foundation
import SwiftUI

/// The API stores a six-decimal fraction: four decimal places in a percentage.
enum SaleTaxPercentage {
    static func isValid(_ percent: Double) -> Bool {
        percent.isFinite && (0...100).contains(percent)
            && abs(percent - (percent * 10_000).rounded() / 10_000) < 1e-10
    }

    static func fromFraction(_ rate: Double) -> Double {
        (rate * 1_000_000).rounded() / 10_000
    }

    static func parseInput(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^[0-9]*(\.[0-9]{0,4})?$"#, options: .regularExpression) != nil else {
            return nil
        }
        let percent = normalized.isEmpty || normalized == "." ? 0 : Double(normalized)
        guard let percent, isValid(percent) else { return nil }
        return percent
    }

    static func text(_ percent: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), percent)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

struct QuoteCustomer: Equatable {
    let id: String
    let name: String
    let company: String?
    let taxExempt: Bool
    let taxExemptExpiresAt: String?
    let address: String?
    private let addressIsKnown: Bool
    let priceLevel: PriceLevel?
    let state: String?
    let county: String?
    let city: String?
    let postalCode: String?

    init(customer: Customer) {
        id = customer.id
        name = customer.name
        company = customer.company
        taxExempt = customer.taxExempt
        taxExemptExpiresAt = customer.taxExemptExpiresAt
        address = customer.address
        addressIsKnown = true
        priceLevel = customer.priceLevel
        state = customer.state
        county = customer.county
        city = customer.city
        postalCode = customer.postalCode
    }

    init(summary: CustomerSummary, taxExempt: Bool = false, taxExemptExpiresAt: String? = nil) {
        id = summary.id
        name = summary.name
        company = summary.company
        self.taxExempt = taxExempt
        self.taxExemptExpiresAt = taxExemptExpiresAt
        address = nil
        addressIsKnown = false
        priceLevel = nil
        state = nil
        county = nil
        city = nil
        postalCode = nil
    }

    private init(copying customer: QuoteCustomer, taxExempt: Bool) {
        id = customer.id
        name = customer.name
        company = customer.company
        self.taxExempt = taxExempt
        taxExemptExpiresAt = customer.taxExemptExpiresAt
        address = customer.address
        addressIsKnown = customer.addressIsKnown
        priceLevel = customer.priceLevel
        state = customer.state
        county = customer.county
        city = customer.city
        postalCode = customer.postalCode
    }

    func withTaxExempt(_ taxExempt: Bool) -> QuoteCustomer {
        QuoteCustomer(copying: self, taxExempt: taxExempt)
    }

    var hasActiveTaxExemption: Bool {
        guard taxExempt else { return false }
        guard let taxExemptExpiresAt else { return true }
        return AppFormat.date(taxExemptExpiresAt).map { $0 > Date() } ?? false
    }

    var hasKnownEmptyStreetAddress: Bool {
        addressIsKnown && address?.nilIfBlank == nil
    }
}

struct QuoteLine: Identifiable, Equatable {
    let id: String
    var itemType: String
    var itemId: String
    var description: String
    var qty: Int
    var unitPrice: Double
    var discount: Double?
    var listPrice: Double
    var savedLineId: String? = nil
    var standardUnitPrice: Double? = nil
    var priceSource: String? = nil
    var priceVersion: String? = nil
    var resolvedUnitPrice: Double? = nil
    var resolvedPriceSource: String? = nil

    var lineTotal: Double {
        unitPrice * Double(qty) - (discount ?? 0)
    }
}

@MainActor
final class QuoteStore: ObservableObject {
    typealias PricingPolicyLoader = () async throws -> FleetPricingPolicy
    typealias PricingPreviewLoader = (String, [String]) async throws -> [FleetPricePreview]
    typealias TaxRateLoader = (String, SaleFulfillment, String?) async throws -> CustomerTaxRateResponse

    private let fallbackTaxPct = 7.0
    private var defaultTaxPct = 7.0
    private var taxLookupGeneration = 0
    private var taxRateIsExplicit = false
    private let taxRateLoader: TaxRateLoader
    private let pricingPolicyLoader: PricingPolicyLoader
    private let pricingPreviewLoader: PricingPreviewLoader
    private var pricingContextGeneration = 0
    private var pricingPolicyRequestId = UUID()
    private var pricingPolicyTask: Task<FleetPricingPolicy, Error>?

    @Published private(set) var generation = UUID()

    func isCurrent(_ submittedGeneration: UUID) -> Bool {
        generation == submittedGeneration
    }

    @Published private(set) var pricingEnabled: Bool?
    @Published private(set) var pricingLoading = false
    @Published private(set) var pricingError: String?
    @Published private(set) var priceLevelAtQuote: PriceLevel?

    @Published var customer: QuoteCustomer?
    @Published var lines: [QuoteLine] = []
    @Published var taxRate = 7.0
    @Published var taxOverride: Double?
    @Published private(set) var overrideTaxRate = false
    @Published private(set) var taxContextRevision = 0
    @Published var taxLookupInProgress = false
    @Published var taxLookupError: String?
    @Published var taxLookupMessage: String?
    @Published var taxResolutionId: String?
    @Published var editingSaleId: String?
    @Published var pendingConfirmationSaleId: String?
    @Published var pendingCreationIdempotencyKey: String?
    @Published var pendingCreationInput: SaleUpsertInput?
    @Published var location = ""
    @Published var fulfillment: SaleFulfillment = .delivery

    init(taxRateLoader: @escaping TaxRateLoader = { customerId, fulfillment, location in
        try await CustomersAPI().taxRate(
            customerId: customerId,
            fulfillment: fulfillment,
            location: location
        )
    }, pricingPolicyLoader: @escaping PricingPolicyLoader = { try await FleetPricingAPI().policy() },
       pricingPreviewLoader: @escaping PricingPreviewLoader = { customerId, skuIds in
        try await FleetPricingAPI().preview(customerId: customerId, skuIds: skuIds)
    }) {
        self.taxRateLoader = taxRateLoader
        self.pricingPolicyLoader = pricingPolicyLoader
        self.pricingPreviewLoader = pricingPreviewLoader
    }

    var subtotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }
    }

    var taxAmount: Double {
        guard customer?.taxExempt != true || overrideTaxRate else { return 0 }
        if let taxOverride {
            return taxOverride
        }
        return (subtotal * (effectiveTaxRate / 100) * 100).rounded() / 100
    }

    var effectiveTaxRate: Double {
        customer?.taxExempt == true && !overrideTaxRate ? 0 : taxRate
    }

    var total: Double {
        ((subtotal + taxAmount) * 100).rounded() / 100
    }

    var hasDraft: Bool {
        customer != nil || !lines.isEmpty || editingSaleId != nil
            || pendingConfirmationSaleId != nil || pendingCreationIdempotencyKey != nil
    }

    var hasUnconfirmedCreation: Bool {
        pendingCreationInput != nil && pendingConfirmationSaleId == nil
    }

    var hasUnresolvedPrices: Bool {
        pricingEnabled == true && lines.contains {
            $0.itemType == "SKU" && (priceLevelAtQuote == nil || $0.standardUnitPrice == nil
                || ($0.savedLineId == nil && $0.priceVersion == nil))
        }
    }

    /// A failed policy request never opts a client into the legacy resolver.
    @discardableResult
    func loadPricingPolicy(force: Bool = false) async throws -> Bool {
        if let pricingEnabled, !force { return pricingEnabled }
        if force {
            pricingPolicyTask?.cancel()
            pricingPolicyTask = nil
            pricingPolicyRequestId = UUID()
            pricingEnabled = nil
        }
        if pricingPolicyTask == nil {
            let loader = pricingPolicyLoader
            pricingPolicyTask = Task { try await loader() }
        }
        guard let task = pricingPolicyTask else { throw CancellationError() }
        let requestId = pricingPolicyRequestId
        pricingLoading = true
        pricingError = nil
        do {
            let policy = try await task.value
            try Task.checkCancellation()
            guard requestId == pricingPolicyRequestId else { throw CancellationError() }
            pricingEnabled = policy.enabled
            pricingLoading = false
            pricingPolicyTask = nil
            return policy.enabled
        } catch {
            if requestId == pricingPolicyRequestId {
                pricingLoading = false
                pricingPolicyTask = nil
                if !(error is CancellationError) {
                    pricingError = (error as? LocalizedError)?.errorDescription ?? "Could not load pricing policy."
                }
            }
            throw error
        }
    }

    func addSku(_ sku: TireSku, qty: Int = 1, overridePrice: Double? = nil) async throws {
        let generation = pricingContextGeneration
        let requestedCustomer = customer?.id
        let requestedLocation = location
        let enabled = try await loadPricingPolicy()
        guard generation == pricingContextGeneration, customer?.id == requestedCustomer,
              location == requestedLocation else { throw CancellationError() }
        if let overridePrice, !Self.validMoney(overridePrice, allowZero: true) {
            throw QuotePricingError.invalidPrice
        }
        if !enabled {
            guard let retail = Double(sku.priceRetail), Self.validMoney(retail, allowZero: true) else {
                throw QuotePricingError.invalidPrice
            }
            addLine(itemType: "SKU", itemId: sku.id,
                    description: "\(sku.brand) \(sku.model) \(sku.size)", qty: qty,
                    unitPrice: overridePrice ?? retail, listPrice: retail)
            return
        }
        guard let requestedCustomer else { throw QuotePricingError.pickCustomer }
        let resolved = try await pricingPreviewLoader(requestedCustomer, [sku.id])
        try Task.checkCancellation()
        guard generation == pricingContextGeneration, customer?.id == requestedCustomer,
              location == requestedLocation else { throw CancellationError() }
        let prices = try Self.validatedPrices(resolved, skuIds: [sku.id])
        guard let price = prices[sku.id], let standard = Double(price.standardUnitPrice),
              let actual = Double(price.unitPrice) else { throw QuotePricingError.invalidPreview }
        if lines.contains(where: { $0.itemType == "SKU" }),
           priceLevelAtQuote != price.priceLevel {
            throw QuotePricingError.reviewRequired
        }
        let selectedPrice = overridePrice ?? actual
        taxOverride = nil
        priceLevelAtQuote = price.priceLevel
        // A new tire never inherits an older saved line's pricing evidence.
        if let index = lines.firstIndex(where: {
            $0.itemType == "SKU" && $0.itemId == sku.id && $0.savedLineId == nil
                && $0.priceVersion == price.version && $0.unitPrice == selectedPrice
                && $0.standardUnitPrice == standard && ($0.discount ?? 0) == 0
        }) {
            lines[index].qty += max(1, qty)
        } else {
            lines.append(QuoteLine(id: UUID().uuidString, itemType: "SKU", itemId: sku.id,
                description: "\(sku.brand) \(sku.model) \(sku.size)", qty: max(1, qty),
                unitPrice: selectedPrice, discount: nil, listPrice: standard,
                standardUnitPrice: standard,
                priceSource: selectedPrice == actual ? price.priceSource : "OVERRIDE",
                priceVersion: price.version, resolvedUnitPrice: actual,
                resolvedPriceSource: price.priceSource))
        }
    }

    func prepareCustomerSelection(_ next: QuoteCustomer) async throws -> QuotePricingProposal? {
        let generation = pricingContextGeneration
        let originals = lines
        let originalCustomerId = customer?.id
        let enabled = try await loadPricingPolicy()
        guard generation == pricingContextGeneration, lines == originals else { throw QuotePricingError.staleReview }
        guard enabled, next.id != originalCustomerId,
              originals.contains(where: { $0.itemType == "SKU" }) else {
            setCustomer(next)
            return nil
        }
        return try await pricingProposal(for: next, originalCustomerId: originalCustomerId,
                                         originals: originals, generation: generation)
    }

    func preparePriceRefresh() async throws -> QuotePricingProposal? {
        guard let customer else { throw QuotePricingError.pickCustomer }
        let generation = pricingContextGeneration
        let originals = lines
        guard try await loadPricingPolicy(force: true) else { return nil }
        guard generation == pricingContextGeneration, lines == originals else { throw QuotePricingError.staleReview }
        guard originals.contains(where: { $0.itemType == "SKU" }) else { return nil }
        return try await pricingProposal(for: customer, originalCustomerId: customer.id,
                                         originals: originals, generation: generation)
    }

    private func pricingProposal(for next: QuoteCustomer, originalCustomerId: String?,
                                 originals: [QuoteLine], generation: Int) async throws -> QuotePricingProposal {
        let ids = Array(Set(originals.filter { $0.itemType == "SKU" }.map(\.itemId))).sorted()
        let resolved = try await pricingPreviewLoader(next.id, ids)
        try Task.checkCancellation()
        guard generation == pricingContextGeneration, customer?.id == originalCustomerId,
              lines == originals else { throw QuotePricingError.staleReview }
        let prices = try Self.validatedPrices(resolved, skuIds: ids)
        guard let level = resolved.first?.priceLevel else { throw QuotePricingError.invalidPreview }
        let proposed = try originals.map { original -> QuoteLine in
            var line = original
            if next.id != originalCustomerId { line.savedLineId = nil }
            guard line.itemType == "SKU" else { return line }
            guard let price = prices[line.itemId], let actual = Double(price.unitPrice),
                  let standard = Double(price.standardUnitPrice) else { throw QuotePricingError.invalidPreview }
            line.savedLineId = nil
            line.unitPrice = actual
            line.listPrice = standard
            line.standardUnitPrice = standard
            line.priceSource = price.priceSource
            line.resolvedUnitPrice = actual
            line.resolvedPriceSource = price.priceSource
            line.priceVersion = price.version
            line.discount = nil
            return line
        }
        return QuotePricingProposal(customer: next, originalCustomerId: originalCustomerId,
            originalLines: originals, proposedLines: proposed, priceLevel: level,
            contextGeneration: generation)
    }

    func acceptPrices(_ proposal: QuotePricingProposal) throws {
        guard proposal.contextGeneration == pricingContextGeneration,
              customer?.id == proposal.originalCustomerId, lines == proposal.originalLines else {
            throw QuotePricingError.staleReview
        }
        if customer?.id != proposal.customer.id { setCustomer(proposal.customer) }
        lines = proposal.proposedLines
        priceLevelAtQuote = proposal.priceLevel
        taxOverride = nil
    }

    /// Bind a newly persisted draft's trusted IDs before a confirmation retry.
    func adoptSavedPricing(from sale: Sale) {
        guard sale.customerId == customer?.id, sale.lines.count == lines.count else { return }
        if lines.contains(where: { $0.itemType == "SKU" }), sale.priceLevelAtQuote != priceLevelAtQuote { return }
        var unmatched = sale.lines
        var adopted = lines
        for index in adopted.indices {
            let line = adopted[index]
            guard let savedIndex = unmatched.firstIndex(where: {
                $0.itemType == line.itemType && $0.itemId == line.itemId && $0.qty == line.qty
                    && Double($0.unitPrice) == line.unitPrice && Double($0.discount) == (line.discount ?? 0)
                    && $0.standardUnitPrice.flatMap(Double.init) == line.standardUnitPrice
                    && $0.priceSource == line.priceSource
            }) else { return }
            let saved = unmatched.remove(at: savedIndex)
            adopted[index].savedLineId = saved.id
            adopted[index].standardUnitPrice = saved.standardUnitPrice.flatMap(Double.init)
            adopted[index].priceSource = saved.priceSource
            adopted[index].resolvedUnitPrice = Double(saved.unitPrice)
            adopted[index].resolvedPriceSource = saved.priceSource
            adopted[index].priceVersion = nil
        }
        lines = adopted
        priceLevelAtQuote = sale.priceLevelAtQuote
    }

    private static func validatedPrices(_ resolved: [FleetPricePreview], skuIds: [String]) throws -> [String: FleetPricePreview] {
        var prices: [String: FleetPricePreview] = [:]
        for price in resolved {
            guard skuIds.contains(price.skuId), prices[price.skuId] == nil,
                  let standard = Double(price.standardUnitPrice), validMoney(standard, allowZero: false),
                  let actual = Double(price.unitPrice), validMoney(actual, allowZero: false),
                  !price.version.isEmpty,
                  resolved.first?.priceLevel == price.priceLevel else { throw QuotePricingError.invalidPreview }
            prices[price.skuId] = price
        }
        guard prices.count == Set(skuIds).count else { throw QuotePricingError.invalidPreview }
        return prices
    }

    private static func validMoney(_ value: Double, allowZero: Bool) -> Bool {
        value.isFinite && (allowZero ? value >= 0 : value > 0) && value <= 9_999_999_999.99
            && abs(value * 100 - (value * 100).rounded()) < 0.0001
    }

    func restoreDefaultTaxRate() async {
        do {
            let general = try await SettingsAPI().general()
            defaultTaxPct = SaleTaxPercentage.fromFraction(general.defaultTaxRate)
            if customer == nil && editingSaleId == nil && lines.isEmpty && !taxRateIsExplicit {
                taxRate = defaultTaxPct
            }
        } catch {
            defaultTaxPct = fallbackTaxPct
        }
    }

    func setCustomer(_ customer: QuoteCustomer?) {
        pricingContextGeneration += 1
        if self.customer?.id != customer?.id {
            priceLevelAtQuote = nil
            for index in lines.indices {
                lines[index].savedLineId = nil
                if lines[index].itemType == "SKU" {
                    lines[index].standardUnitPrice = nil
                    lines[index].priceSource = nil
                    lines[index].priceVersion = nil
                }
            }
        }
        taxLookupGeneration += 1
        taxRateIsExplicit = false
        taxOverride = nil
        overrideTaxRate = false
        taxRate = defaultTaxPct
        taxLookupInProgress = customer != nil
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = nil
        self.customer = customer.map { $0.withTaxExempt($0.hasActiveTaxExemption) }
        taxContextRevision += 1
    }

    func setTaxRate(_ pct: Double, isAdmin: Bool) {
        guard isAdmin, SaleTaxPercentage.isValid(pct) else { return }
        taxLookupGeneration += 1
        taxRateIsExplicit = true
        overrideTaxRate = true
        taxOverride = nil
        taxRate = (pct * 10_000).rounded() / 10_000
        taxLookupInProgress = false
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = nil
    }

    func setLocation(_ code: String) {
        guard location != code else { return }
        location = code
        guard fulfillment == .pickup || overrideTaxRate else { return }
        invalidateAutomaticTax()
    }

    private func invalidateAutomaticTax(scheduleLookup: Bool = true) {
        taxLookupGeneration += 1
        overrideTaxRate = false
        taxOverride = nil
        taxRateIsExplicit = false
        taxLookupInProgress = customer != nil
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = nil
        if scheduleLookup { taxContextRevision += 1 }
    }

    func setFulfillment(_ fulfillment: SaleFulfillment) {
        guard self.fulfillment != fulfillment else { return }
        self.fulfillment = fulfillment
        invalidateAutomaticTax()
    }

    func useAutomaticTaxRate() async {
        invalidateAutomaticTax(scheduleLookup: false)
        await applyCustomerTaxRate()
    }

    func applyCustomerTaxRate() async {
        // A queued view callback must not replace an administrator's newer edit.
        guard !overrideTaxRate else { return }
        taxLookupGeneration += 1
        let generation = taxLookupGeneration
        let requestedFulfillment = fulfillment
        let requestedLocation = location

        guard let customer else {
            taxRateIsExplicit = false
            taxRate = defaultTaxPct
            taxLookupInProgress = false
            taxLookupError = nil
            taxLookupMessage = nil
            taxResolutionId = nil
            return
        }

        taxLookupInProgress = true
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = nil
        var resumeLookupOnReturn = false
        defer {
            if generation == taxLookupGeneration {
                taxLookupInProgress = resumeLookupOnReturn
            }
        }

        do {
            let result = try await taxRateLoader(
                customer.id,
                requestedFulfillment,
                requestedFulfillment == .pickup ? requestedLocation.nilIfBlank : nil
            )
            guard generation == taxLookupGeneration, self.customer?.id == customer.id else { return }
            guard let rate = result.rate else {
                taxRateIsExplicit = false
                taxOverride = nil
                taxRate = defaultTaxPct
                let problem = result.automatic?.code
                    ?? result.resolution?.problemCode
                    ?? "Tax address is unresolved."
                taxLookupError = problem
                taxLookupMessage = problem
                return
            }
            taxRateIsExplicit = true
            let refreshedTaxRate = SaleTaxPercentage.fromFraction(rate)
            let refreshedExemption = result.source == "EXEMPT"
            // A shop-default refresh must retain the saved round-total amount
            // when its rate is unchanged. Price/context edits already clear it.
            if taxRate != refreshedTaxRate || customer.taxExempt != refreshedExemption {
                taxOverride = nil
            }
            taxRate = refreshedTaxRate
            taxResolutionId = result.automatic?.status == "RESOLVED"
                ? result.automatic?.resolutionId
                : nil
            self.customer = customer.withTaxExempt(refreshedExemption)
            switch result.source {
            case "EXEMPT": taxLookupMessage = "newQuote.taxExemptionApplied"
            case "DEFAULT": taxLookupMessage = "newQuote.taxShopDefaultApplied"
            case "OVERRIDE": taxLookupMessage = "newQuote.taxCustomerOverrideApplied"
            default: taxLookupMessage = "newQuote.taxVerifiedApplied"
            }
        } catch {
            guard generation == taxLookupGeneration, self.customer?.id == customer.id else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                // Navigation cancels the view task. Keep work pending so the
                // next appearance resumes it without displaying a tax error.
                resumeLookupOnReturn = true
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not look up tax rate."
            taxLookupError = message
            taxLookupMessage = message
        }
    }

    func addLine(itemType: String, itemId: String, description: String, qty: Int = 1, unitPrice: Double, listPrice: Double? = nil) {
        guard unitPrice.isFinite, unitPrice >= 0 else { return }
        let quantity = max(1, qty)
        taxOverride = nil
        // Preserve explicit price choices and any existing line discount.
        if let index = lines.firstIndex(where: {
            $0.itemType == itemType && $0.itemId == itemId
                && $0.unitPrice == unitPrice && ($0.discount ?? 0) == 0
        }) {
            lines[index].qty += quantity
            return
        }

        lines.append(QuoteLine(
            id: UUID().uuidString,
            itemType: itemType,
            itemId: itemId,
            description: description,
            qty: quantity,
            unitPrice: unitPrice,
            discount: nil,
            listPrice: listPrice.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? unitPrice
        ))
    }

    func updateQty(_ lineId: String, qty: Int) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        let nextQuantity = max(1, qty)
        guard lines[index].qty != nextQuantity else { return }
        taxOverride = nil
        lines[index].qty = nextQuantity
    }

    func updatePrice(_ lineId: String, unitPrice: Double) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        let nextPrice = unitPrice.isFinite ? max(0, unitPrice) : 0
        guard lines[index].unitPrice != nextPrice else { return }
        taxOverride = nil
        lines[index].unitPrice = nextPrice
        updatePriceSource(at: index)
    }

    /// History prices already include the original line's discount.
    func applyPrice(_ lineId: String, unitPrice: Double) {
        guard unitPrice.isFinite, unitPrice >= 0,
              let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        taxOverride = nil
        lines[index].unitPrice = unitPrice
        lines[index].discount = nil
        updatePriceSource(at: index)
    }

    func removeLine(_ lineId: String) {
        taxOverride = nil
        lines.removeAll { $0.id == lineId }
    }

    func roundTotal(to target: Double) {
        let target = Self.roundMoney(target)
        guard target > 0 else { return }
        let effectiveRate = effectiveTaxRate / 100
        guard let plan = Self.roundTotalPlan(lines: lines, taxRate: effectiveRate, target: target) else { return }
        for (index, planned) in zip(lines.indices, plan.lines) {
            lines[index].unitPrice = planned.unitPrice
            lines[index].discount = planned.discount
            updatePriceSource(at: index)
        }
        taxOverride = plan.taxAmount
    }

    func seed(from sale: Sale, customer: QuoteCustomer) {
        generation = UUID()
        pricingContextGeneration += 1
        priceLevelAtQuote = sale.priceLevelAtQuote
        taxLookupGeneration += 1
        taxRateIsExplicit = true
        overrideTaxRate = sale.taxEvidence?.type == "SALE_RATE_OVERRIDE"
        self.customer = customer.withTaxExempt(customer.hasActiveTaxExemption)
        lines = sale.lines.map { line in
            let unitPrice = Double(line.unitPrice) ?? 0
            return QuoteLine(
                id: "l\(line.id)",
                itemType: line.itemType,
                itemId: line.itemId,
                description: line.description,
                qty: line.qty,
                unitPrice: unitPrice,
                discount: Double(line.discount),
                listPrice: line.standardUnitPrice.flatMap(Double.init) ?? unitPrice,
                savedLineId: line.id,
                standardUnitPrice: line.standardUnitPrice.flatMap(Double.init),
                priceSource: line.priceSource,
                resolvedUnitPrice: unitPrice,
                resolvedPriceSource: line.priceSource
            )
        }
        taxRate = SaleTaxPercentage.fromFraction(Double(sale.taxRate) ?? 0)
        taxOverride = Double(sale.taxAmount).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        taxLookupInProgress = false
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = sale.taxResolutionId
        editingSaleId = sale.id
        pendingConfirmationSaleId = nil
        pendingCreationIdempotencyKey = nil
        pendingCreationInput = nil
        location = sale.location
        fulfillment = sale.fulfillment ?? .delivery

        let needsAutomaticRefresh = !overrideTaxRate && (
            sale.taxRateSource == "DEFAULT"
                || sale.taxEvidence?.type == "SHOP_DEFAULT_PICKUP"
                || sale.taxEvidence?.type == "SHOP_DEFAULT_MISSING_CUSTOMER_ADDRESS"
                || (fulfillment == .delivery && customer.hasKnownEmptyStreetAddress)
        )
        if needsAutomaticRefresh {
            // Settings may have changed, or a previously verified delivery
            // address may have been removed. Block saving until the view's tax
            // task refreshes the rate; a manual sale override remains intact.
            taxRateIsExplicit = false
            taxLookupInProgress = true
            taxResolutionId = nil
            taxContextRevision += 1
        }
    }

    func clear() {
        generation = UUID()
        pricingContextGeneration += 1
        pricingPolicyTask?.cancel()
        pricingPolicyTask = nil
        pricingPolicyRequestId = UUID()
        pricingEnabled = nil
        pricingLoading = false
        pricingError = nil
        priceLevelAtQuote = nil
        taxLookupGeneration += 1
        taxRateIsExplicit = false
        overrideTaxRate = false
        customer = nil
        lines = []
        taxRate = defaultTaxPct
        taxOverride = nil
        taxLookupInProgress = false
        taxLookupError = nil
        taxLookupMessage = nil
        taxResolutionId = nil
        editingSaleId = nil
        pendingConfirmationSaleId = nil
        pendingCreationIdempotencyKey = nil
        pendingCreationInput = nil
        location = ""
        fulfillment = .delivery
    }

    func saleInput() throws -> SaleUpsertInput {
        guard fulfillment != .freight else {
            throw APIError(status: 400, message: "sales.freightEditInWeb")
        }
        guard !hasUnconfirmedCreation else { throw QuotePricingError.unconfirmedCreation }
        guard let customer else {
            throw APIError(status: 0, message: "Pick a customer first.")
        }
        guard !taxLookupInProgress else {
            throw APIError(status: 0, message: "Wait for the tax calculation to finish.")
        }
        if let taxLookupError {
            throw APIError(status: 0, message: taxLookupError)
        }

        if pricingEnabled == true, hasUnresolvedPrices {
            throw QuotePricingError.reviewRequired
        }
        if pricingEnabled == true, lines.contains(where: { line in
            !Self.validMoney(line.unitPrice, allowZero: true) || line.qty < 1
                || !Self.validMoney(line.discount ?? 0, allowZero: true)
                || (line.discount ?? 0) > line.unitPrice * Double(line.qty)
        }) {
            throw QuotePricingError.invalidPrice
        }

        return SaleUpsertInput(
            customerId: customer.id,
            taxRate: (effectiveTaxRate * 10_000).rounded() / 1_000_000,
            taxAmount: customer.taxExempt && !overrideTaxRate ? nil : taxOverride,
            location: location.nilIfBlank,
            fulfillment: fulfillment,
            taxResolutionId: taxResolutionId,
            overrideTaxRate: overrideTaxRate,
            lines: lines.map {
                NewSaleLine(
                    id: pricingEnabled == true ? $0.savedLineId : nil,
                    priceVersion: pricingEnabled == true ? $0.priceVersion : nil,
                    itemType: $0.itemType,
                    itemId: $0.itemId,
                    description: $0.description,
                    qty: $0.qty,
                    unitPrice: $0.unitPrice,
                    discount: $0.discount
                )
            }
        )
    }

    private static func roundMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func updatePriceSource(at index: Int) {
        guard pricingEnabled == true, lines[index].itemType == "SKU" else { return }
        lines[index].priceSource = lines[index].unitPrice == lines[index].resolvedUnitPrice
            ? lines[index].resolvedPriceSource : "OVERRIDE"
    }

    private static func roundTotalPlan(lines: [QuoteLine], taxRate: Double, target: Double) -> (lines: [QuoteLine], taxAmount: Double)? {
        let base = lines.reduce(0) { $0 + $1.unitPrice * Double($1.qty) }
        guard base > 0 else { return nil }

        let guess = taxRate > 0 ? target / (1 + taxRate) : target
        var targetSubtotal = roundMoney(guess)
        if taxRate > 0 {
            for delta in [0.0, -0.01, 0.01, -0.02, 0.02] {
                let subtotal = roundMoney(guess + delta)
                if roundMoney(subtotal + roundMoney(subtotal * taxRate)) == target {
                    targetSubtotal = subtotal
                    break
                }
            }
        }

        let factor = targetSubtotal / base
        var adjusted = lines.map { line in
            var next = line
            next.unitPrice = Foundation.ceil(line.unitPrice * factor * 100) / 100
            next.discount = nil
            return next
        }

        let sum = roundMoney(adjusted.reduce(0) { $0 + roundMoney($1.unitPrice * Double($1.qty)) })
        let discount = roundMoney(sum - targetSubtotal)
        if discount > 0, let index = adjusted.indices.max(by: {
            adjusted[$0].unitPrice * Double(adjusted[$0].qty) < adjusted[$1].unitPrice * Double(adjusted[$1].qty)
        }) {
            adjusted[index].discount = discount
        }

        return (adjusted, roundMoney(target - targetSubtotal))
    }
}
