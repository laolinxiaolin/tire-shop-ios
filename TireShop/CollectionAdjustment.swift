import Foundation

/// Values exchanged with collection endpoints are bounded to whole cents. Keep
/// arithmetic in cents and convert through decimal text only at the API edge.
enum CollectionMoney {
    static let maximumCents: Int64 = 999_999_999_999

    static func cents(_ text: String) -> Int64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0, decimal <= Decimal(maximumCents) / 100 else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }

    static func cents(_ amount: Double) -> Int64? {
        guard amount.isFinite, amount >= 0 else { return nil }
        return cents(String(amount))
    }

    static func amount(cents: Int64) -> Double {
        // NSDecimalNumber.doubleValue can produce a longer decimal tail which
        // the server's maxDecimalPlaces validator correctly rejects.
        Double(text(cents: cents)) ?? 0
    }

    static func text(cents: Int64) -> String {
        let magnitude = cents.magnitude
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

enum CollectionTenderAutofill {
    /// Follow a revised balance only while the existing tenders cover the old
    /// balance exactly. Partial payments and unfinished edits retain their intent.
    static func followBalance(amounts: [String], from oldBalance: Double, to newBalance: Double) -> [String]? {
        guard let oldCents = CollectionMoney.cents(oldBalance), oldCents > 0,
              let newCents = CollectionMoney.cents(newBalance), newCents > 0 else { return nil }
        var cents: [Int64] = []
        var total: Int64 = 0
        for amount in amounts {
            if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cents.append(0)
                continue
            }
            guard let value = CollectionMoney.cents(amount) else { return nil }
            // The total cannot overflow: stop once it exceeds the bounded old
            // balance, since that tender list is already ineligible to follow.
            total += value
            guard total <= oldCents else { return nil }
            cents.append(value)
        }
        guard total == oldCents else { return nil }
        var result = amounts
        let change = newCents - oldCents
        if change > 0 {
            guard let last = cents.lastIndex(where: { $0 > 0 }) else { return nil }
            result[last] = CollectionMoney.text(cents: cents[last] + change)
        } else if change < 0 {
            var remaining = -change
            for index in cents.indices.reversed() where cents[index] > 0 {
                let consumed = min(cents[index], remaining)
                result[index] = CollectionMoney.text(cents: cents[index] - consumed)
                remaining -= consumed
                if remaining == 0 { break }
            }
        }
        return result
    }
}

struct InvoiceCollectionAdjustment: Codable, Equatable {
    let invoiceId: String
    /// Signed change to the final invoice total, including tax.
    let amount: Double
    /// Original open balance reviewed by the collector, before the adjustment.
    let expectedBalance: Double
}

enum CollectionAdjustmentDirection: String, CaseIterable, Identifiable {
    case reduce
    case increase

    var id: String { rawValue }
    var localizationKey: String { self == .reduce ? "payment.reduceBy" : "payment.increaseBy" }
}

struct CollectionAdjustmentDraft: Equatable {
    var direction: CollectionAdjustmentDirection = .reduce
    var amountText = ""

    var isEmpty: Bool { amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// A blank or zero draft does not submit a zero-valued adjustment.
    func adjustment(invoiceId: String, originalBalance: Double) throws -> InvoiceCollectionAdjustment? {
        let change = try signedCents()
        guard change != 0 else { return nil }
        guard !invoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError(status: 400, message: "payment.adjustmentInvoiceMismatch")
        }
        _ = try adjustedBalance(originalBalance: originalBalance)
        return InvoiceCollectionAdjustment(
            invoiceId: invoiceId,
            amount: CollectionMoney.amount(cents: change),
            expectedBalance: originalBalance
        )
    }

    func adjustedBalance(originalBalance: Double) throws -> Double {
        guard let balance = CollectionMoney.cents(originalBalance) else {
            throw APIError(status: 400, message: "payment.invalidAdjustment")
        }
        let change = try signedCents()
        guard change == 0 || balance > 0, balance + change > 0 else {
            throw APIError(status: 400, message: "payment.adjustmentBalancePositive")
        }
        guard balance + change <= CollectionMoney.maximumCents else {
            throw APIError(status: 400, message: "payment.invalidAdjustment")
        }
        return CollectionMoney.amount(cents: balance + change)
    }

    func validationError(originalBalance: Double) -> String? {
        do {
            _ = try adjustedBalance(originalBalance: originalBalance)
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "payment.invalidAdjustment"
        }
    }

    private func signedCents() throws -> Int64 {
        if isEmpty { return 0 }
        guard let cents = CollectionMoney.cents(amountText) else {
            throw APIError(status: 400, message: "payment.invalidAdjustment")
        }
        return direction == .reduce ? -cents : cents
    }
}

enum CollectionAdjustmentPermission {
    /// Unknown/failed policy cannot grant access. Explicit override permission
    /// also covers administrators through AuthStore.has.
    static func allows(hasOverride: Bool, policyEnabled: Bool?) -> Bool {
        hasOverride || policyEnabled == false
    }
}

enum CollectionAdjustmentValidation {
    static func validate(
        adjustments: [InvoiceCollectionAdjustment],
        invoiceBalances: [String: Double]
    ) throws {
        _ = try revisedBalances(adjustments: adjustments, invoiceBalances: invoiceBalances)
    }

    static func revisedBalances(
        adjustments: [InvoiceCollectionAdjustment],
        invoiceBalances: [String: Double]
    ) throws -> [String: Double] {
        try validate(adjustments: adjustments, paidInvoiceIds: Set(invoiceBalances.keys))
        var balances = invoiceBalances
        for adjustment in adjustments {
            guard let original = invoiceBalances[adjustment.invoiceId],
                  let originalCents = CollectionMoney.cents(original),
                  let expectedCents = CollectionMoney.cents(adjustment.expectedBalance),
                  originalCents == expectedCents else {
                throw APIError(status: 400, message: "payment.adjustmentStale")
            }
            let change = try deltaCents(adjustment.amount)
            balances[adjustment.invoiceId] = CollectionMoney.amount(cents: originalCents + change)
        }
        return balances
    }

    /// The server applies adjustments and positive tenders together. Reject an
    /// unmatched or duplicate adjustment before any collection request is sent.
    static func validate(
        adjustments: [InvoiceCollectionAdjustment],
        paidInvoiceIds: Set<String>
    ) throws {
        var seen = Set<String>()
        for adjustment in adjustments {
            guard !adjustment.invoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  paidInvoiceIds.contains(adjustment.invoiceId) else {
                throw APIError(status: 400, message: "payment.adjustmentInvoiceMismatch")
            }
            guard seen.insert(adjustment.invoiceId).inserted else {
                throw APIError(status: 400, message: "payment.adjustmentDuplicate")
            }
            let change = try deltaCents(adjustment.amount)
            guard let expected = CollectionMoney.cents(adjustment.expectedBalance) else {
                throw APIError(status: 400, message: "payment.invalidAdjustment")
            }
            guard expected > 0, expected + change > 0 else {
                throw APIError(status: 400, message: "payment.adjustmentBalancePositive")
            }
            guard expected + change <= CollectionMoney.maximumCents else {
                throw APIError(status: 400, message: "payment.invalidAdjustment")
            }
        }
    }

    private static func deltaCents(_ amount: Double) throws -> Int64 {
        guard amount.isFinite, let magnitude = CollectionMoney.cents(abs(amount)), magnitude > 0 else {
            throw APIError(status: 400, message: "payment.invalidAdjustment")
        }
        return amount < 0 ? -magnitude : magnitude
    }
}
