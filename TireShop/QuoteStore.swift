import Foundation
import SwiftUI

struct QuoteCustomer: Equatable {
    let id: String
    let name: String
    let company: String?
    let taxExempt: Bool
    let state: String?
    let county: String?
    let city: String?
    let postalCode: String?

    init(customer: Customer) {
        id = customer.id
        name = customer.name
        company = customer.company
        taxExempt = customer.taxExempt
        state = customer.state
        county = customer.county
        city = customer.city
        postalCode = customer.postalCode
    }

    init(summary: CustomerSummary, taxExempt: Bool = false) {
        id = summary.id
        name = summary.name
        company = summary.company
        self.taxExempt = taxExempt
        state = nil
        county = nil
        city = nil
        postalCode = nil
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
    private let fallbackTaxPct = 7.0
    private var defaultTaxPct = 7.0
    private var taxLookupGeneration = 0
    private var taxRateIsExplicit = false

    @Published var customer: QuoteCustomer?
    @Published var lines: [QuoteLine] = []
    @Published var taxRate = 7.0
    @Published var taxOverride: Double?
    @Published var taxLookupMessage: String?
    @Published var editingSaleId: String?
    @Published var pendingConfirmationSaleId: String?
    @Published var pendingCreationIdempotencyKey: String?
    @Published var pendingCreationInput: SaleUpsertInput?
    @Published var location = ""

    var subtotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }
    }

    var taxAmount: Double {
        guard customer?.taxExempt != true else { return 0 }
        if let taxOverride {
            return taxOverride
        }
        return (subtotal * (taxRate / 100) * 100).rounded() / 100
    }

    var total: Double {
        ((subtotal + taxAmount) * 100).rounded() / 100
    }

    func restoreDefaultTaxRate() async {
        do {
            let general = try await SettingsAPI().general()
            defaultTaxPct = (general.defaultTaxRate * 10000).rounded() / 100
            if editingSaleId == nil && lines.isEmpty && !taxRateIsExplicit {
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
        taxRate = defaultTaxPct
        taxLookupMessage = nil
        self.customer = customer
    }

    func setTaxRate(_ pct: Double) {
        taxLookupGeneration += 1
        taxRateIsExplicit = true
        taxOverride = nil
        taxRate = pct
        taxLookupMessage = nil
    }

    func setLocation(_ code: String) {
        location = code
    }

    func applyCustomerTaxRate() async {
        taxLookupGeneration += 1
        let generation = taxLookupGeneration

        guard let customer, customer.taxExempt != true else {
            taxRateIsExplicit = false
            taxRate = defaultTaxPct
            taxLookupMessage = nil
            return
        }
        guard customer.state?.nilIfBlank != nil
            || customer.county?.nilIfBlank != nil
            || customer.city?.nilIfBlank != nil
            || customer.postalCode?.nilIfBlank != nil else {
            taxRateIsExplicit = false
            taxRate = defaultTaxPct
            taxLookupMessage = nil
            return
        }

        do {
            let rate = try await TaxRatesAPI().lookup(
                state: customer.state?.nilIfBlank ?? "GA",
                county: customer.county?.nilIfBlank,
                city: customer.city?.nilIfBlank,
                postalCode: customer.postalCode?.nilIfBlank
            )
            guard generation == taxLookupGeneration, self.customer?.id == customer.id else { return }
            guard let rate else {
                taxRateIsExplicit = false
                taxOverride = nil
                taxRate = defaultTaxPct
                taxLookupMessage = "No saved tax rate matched this customer location."
                return
            }
            let fraction = rate.rate
            taxRateIsExplicit = true
            taxOverride = nil
            taxRate = (fraction * 10000).rounded() / 100
            let location = [rate.county, rate.city, rate.postalCode].compactMap { $0?.nilIfBlank }.joined(separator: " - ")
            taxLookupMessage = location.isEmpty ? "Applied saved tax rate." : "Applied tax for \(location)."
        } catch {
            guard generation == taxLookupGeneration, self.customer?.id == customer.id else { return }
            taxLookupMessage = (error as? LocalizedError)?.errorDescription ?? "Could not look up tax rate."
        }
    }

    func addLine(itemType: String, itemId: String, description: String, qty: Int = 1, unitPrice: Double) {
        taxOverride = nil
        if let index = lines.firstIndex(where: { $0.itemType == itemType && $0.itemId == itemId }) {
            lines[index].qty += qty
            return
        }

        lines.append(QuoteLine(
            id: "l\(Date().timeIntervalSince1970)-\(lines.count)",
            itemType: itemType,
            itemId: itemId,
            description: description,
            qty: max(1, qty),
            unitPrice: max(0, unitPrice),
            discount: nil,
            listPrice: max(0, unitPrice)
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
        lines[index].unitPrice = max(0, unitPrice)
    }

    func removeLine(_ lineId: String) {
        taxOverride = nil
        lines.removeAll { $0.id == lineId }
    }

    func roundTotal(to target: Double) {
        let target = Self.roundMoney(target)
        guard target > 0 else { return }
        let effectiveRate = customer?.taxExempt == true ? 0 : taxRate / 100
        guard let plan = Self.roundTotalPlan(lines: lines, taxRate: effectiveRate, target: target) else { return }
        for index in lines.indices {
            lines[index].unitPrice = plan.lines[index].unitPrice
            lines[index].discount = plan.lines[index].discount
        }
        taxOverride = plan.taxAmount
    }

    func seed(from sale: Sale, customer: QuoteCustomer) {
        taxLookupGeneration += 1
        taxRateIsExplicit = true
        self.customer = customer
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
        taxRate = ((Double(sale.taxRate) ?? 0) * 10000).rounded() / 100
        taxOverride = nil
        taxLookupMessage = nil
        editingSaleId = sale.id
        pendingConfirmationSaleId = nil
        pendingCreationIdempotencyKey = nil
        pendingCreationInput = nil
        location = sale.location
    }

    func clear() {
        taxLookupGeneration += 1
        taxRateIsExplicit = false
        customer = nil
        lines = []
        taxRate = defaultTaxPct
        taxOverride = nil
        taxLookupMessage = nil
        editingSaleId = nil
        pendingConfirmationSaleId = nil
        pendingCreationIdempotencyKey = nil
        pendingCreationInput = nil
        location = ""
    }

    func saleInput() throws -> SaleUpsertInput {
        guard let customer else {
            throw APIError(status: 0, message: "Pick a customer first.")
        }

        return SaleUpsertInput(
            customerId: customer.id,
            taxRate: customer.taxExempt ? 0 : taxRate / 100,
            taxAmount: customer.taxExempt ? nil : taxOverride,
            location: location.nilIfBlank,
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
