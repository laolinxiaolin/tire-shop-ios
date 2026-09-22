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

    var lineTotal: Double {
        unitPrice * Double(qty) - (discount ?? 0)
    }
}

@MainActor
final class QuoteStore: ObservableObject {
    typealias TaxRateLoader = (String, SaleFulfillment, String?) async throws -> CustomerTaxRateResponse

    private let fallbackTaxPct = 7.0
    private var defaultTaxPct = 7.0
    private var taxLookupGeneration = 0
    private var taxRateIsExplicit = false
    private let taxRateLoader: TaxRateLoader

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
    }) {
        self.taxRateLoader = taxRateLoader
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
            taxOverride = nil
            taxRate = SaleTaxPercentage.fromFraction(rate)
            taxResolutionId = result.automatic?.status == "RESOLVED"
                ? result.automatic?.resolutionId
                : nil
            self.customer = customer.withTaxExempt(result.source == "EXEMPT")
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
        taxOverride = nil
        lines[index].qty = max(1, qty)
    }

    func updatePrice(_ lineId: String, unitPrice: Double) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        taxOverride = nil
        lines[index].unitPrice = unitPrice.isFinite ? max(0, unitPrice) : 0
    }

    /// History prices already include the original line's discount.
    func applyPrice(_ lineId: String, unitPrice: Double) {
        guard unitPrice.isFinite, unitPrice >= 0,
              let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        taxOverride = nil
        lines[index].unitPrice = unitPrice
        lines[index].discount = nil
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
        }
        taxOverride = plan.taxAmount
    }

    func seed(from sale: Sale, customer: QuoteCustomer) {
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
                listPrice: unitPrice
            )
        }
        taxRate = SaleTaxPercentage.fromFraction(Double(sale.taxRate) ?? 0)
        taxOverride = nil
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
    }

    func clear() {
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
        guard let customer else {
            throw APIError(status: 0, message: "Pick a customer first.")
        }
        guard !taxLookupInProgress else {
            throw APIError(status: 0, message: "Wait for the tax calculation to finish.")
        }
        if let taxLookupError {
            throw APIError(status: 0, message: taxLookupError)
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
