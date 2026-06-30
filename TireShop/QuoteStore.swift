import Foundation
import SwiftUI

struct QuoteCustomer: Equatable {
    let id: String
    let name: String
    let company: String?
    let taxExempt: Bool

    init(customer: Customer) {
        id = customer.id
        name = customer.name
        company = customer.company
        taxExempt = customer.taxExempt
    }

    init(summary: CustomerSummary, taxExempt: Bool = false) {
        id = summary.id
        name = summary.name
        company = summary.company
        self.taxExempt = taxExempt
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

    @Published var customer: QuoteCustomer?
    @Published var lines: [QuoteLine] = []
    @Published var taxRate = 7.0
    @Published var editingSaleId: String?

    var subtotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }
    }

    var taxAmount: Double {
        guard customer?.taxExempt != true else { return 0 }
        return (subtotal * (taxRate / 100) * 100).rounded() / 100
    }

    var total: Double {
        ((subtotal + taxAmount) * 100).rounded() / 100
    }

    func restoreDefaultTaxRate() async {
        do {
            let general = try await SettingsAPI().general()
            defaultTaxPct = (general.defaultTaxRate * 10000).rounded() / 100
            if editingSaleId == nil && lines.isEmpty {
                taxRate = defaultTaxPct
            }
        } catch {
            defaultTaxPct = fallbackTaxPct
        }
    }

    func setCustomer(_ customer: QuoteCustomer?) {
        self.customer = customer
    }

    func addLine(itemType: String, itemId: String, description: String, qty: Int = 1, unitPrice: Double) {
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
        lines[index].qty = max(1, qty)
    }

    func updatePrice(_ lineId: String, unitPrice: Double) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[index].unitPrice = max(0, unitPrice)
    }

    func removeLine(_ lineId: String) {
        lines.removeAll { $0.id == lineId }
    }

    func roundTotal(to target: Double) {
        guard target > 0, subtotal > 0 else { return }
        let effectiveRate = customer?.taxExempt == true ? 0 : taxRate / 100
        let targetSubtotal = effectiveRate > 0 ? target / (1 + effectiveRate) : target
        let factor = targetSubtotal / subtotal
        for index in lines.indices {
            lines[index].unitPrice = (lines[index].unitPrice * factor * 100).rounded() / 100
        }
    }

    func seed(from sale: Sale, customer: QuoteCustomer) {
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
        editingSaleId = sale.id
    }

    func clear() {
        customer = nil
        lines = []
        taxRate = defaultTaxPct
        editingSaleId = nil
    }

    func saleInput() throws -> SaleUpsertInput {
        guard let customer else {
            throw APIError(status: 0, message: "Pick a customer first.")
        }

        return SaleUpsertInput(
            customerId: customer.id,
            taxRate: customer.taxExempt ? 0 : taxRate / 100,
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
}
