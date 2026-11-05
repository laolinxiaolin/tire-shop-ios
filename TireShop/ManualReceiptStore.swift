import Foundation
import SwiftUI

struct ManualReceiptInput: Encodable, Equatable {
    struct Line: Encodable, Equatable {
        let invoiceId: String
        let paymentMethodId: String
        /// Net application. The server adds the method's surcharge once.
        let amount: Double
        let reference: String?
        let plannedDepositDate: String?
    }

    let customerId: String?
    let lines: [Line]
    let adjustments: [InvoiceCollectionAdjustment]?

    init(customerId: String?, lines: [Line], adjustments: [InvoiceCollectionAdjustment]? = nil) {
        self.customerId = customerId
        self.lines = lines
        self.adjustments = adjustments?.isEmpty == false ? adjustments : nil
    }

    private enum CodingKeys: String, CodingKey {
        case customerId, lines, adjustments
    }

    func encode(to encoder: Encoder) throws {
        try CollectionAdjustmentValidation.validate(
            adjustments: adjustments ?? [],
            paidInvoiceIds: Set(lines.filter { $0.amount > 0 }.map(\.invoiceId))
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(customerId, forKey: .customerId)
        try container.encode(lines, forKey: .lines)
        try container.encodeIfPresent(adjustments, forKey: .adjustments)
    }

    static func make(invoiceId: String, customerId: String?, rows: [PaymentRow], methods: [PaymentMethod],
                     balance: Double? = nil, adjustments: [InvoiceCollectionAdjustment] = []) throws -> Self {
        var lines: [Line] = []
        for row in rows {
            if row.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let amount = money(row.amount) else {
                throw APIError(status: 400, message: "payment.invalidAmount")
            }
            if amount == 0 { continue }
            guard let method = methods.first(where: { $0.id == row.paymentMethodId }),
                  method.isActive, method.processor == nil else {
                throw APIError(status: 400, message: "payment.invalidMethod")
            }
            let isCheck = method.account.code == "1010"
            guard !isCheck || CheckDates.isValid(row.plannedDepositDate) else {
                throw APIError(status: 400, message: "payment.depositDateRequired")
            }
            lines.append(Line(invoiceId: invoiceId, paymentMethodId: method.id, amount: amount,
                              reference: row.reference.nilIfBlank,
                              plannedDepositDate: isCheck ? row.plannedDepositDate : nil))
        }
        guard !lines.isEmpty else {
            throw APIError(status: 400, message: "payment.addOne")
        }
        try CollectionAdjustmentValidation.validate(
            adjustments: adjustments, paidInvoiceIds: Set(lines.map(\.invoiceId))
        )
        let revisedBalance: Double?
        if let balance {
            revisedBalance = try CollectionAdjustmentValidation.revisedBalances(
                adjustments: adjustments, invoiceBalances: [invoiceId: balance]
            )[invoiceId]
        } else {
            guard adjustments.isEmpty else {
                throw APIError(status: 400, message: "payment.adjustmentStale")
            }
            revisedBalance = nil
        }
        if let revisedBalance, ManualPaymentCreditCompatibility.hasUnsupportedCredit(
            amounts: lines.map(\.amount), balance: revisedBalance
        ) {
            throw APIError(status: 400, message: "payment.oneCentOverpaymentUnsupported")
        }
        return Self(customerId: customerId?.nilIfBlank, lines: lines, adjustments: adjustments)
    }

    static func money(_ text: String) -> Double? {
        guard let cents = CollectionMoney.cents(text) else { return nil }
        return CollectionMoney.amount(cents: cents)
    }
}

enum ManualPaymentCreditCompatibility {
    /// Receipts book split tenders sequentially. Even a supported total excess
    /// can include a one-cent excess on an earlier or later individual tender.
    static func hasUnsupportedCredit(amounts: [Double], balance: Double) -> Bool {
        guard var remaining = CollectionMoney.cents(balance) else { return true }
        for amount in amounts {
            guard let tender = CollectionMoney.cents(amount) else { return true }
            if tender - remaining == 1 { return true }
            remaining = max(0, remaining - tender)
        }
        return false
    }
}

struct ManualReceiptResult: Decodable, Equatable {
    let id: String
    let ref: String
    let total: Double
    let surchargeTotal: Double
    let paymentCount: Int
}

enum ManualTenderAmounts {
    static func surcharge(amount: String, feeRate: String?) -> Decimal {
        guard let net = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
              let feeRate, let rate = Decimal(string: feeRate, locale: Locale(identifier: "en_US_POSIX")),
              net > 0, rate > 0 else { return 0 }
        var raw = net * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .plain)
        return rounded
    }
}

/// The receipt endpoint has no replay guarantee. A lost response retires the
/// form until current balances and payment history have been read successfully.
@MainActor
final class ManualReceiptStore: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var reconciling = false
    @Published private(set) var needsReconciliation = false
    @Published private(set) var completed = false
    @Published private(set) var error: String?
    private var pendingCardPaymentID: String?
    private let collect: (ManualReceiptInput) async throws -> ManualReceiptResult

    init(collect: @escaping (ManualReceiptInput) async throws -> ManualReceiptResult = {
        try await PaymentsAPI().recordReceipt($0)
    }) {
        self.collect = collect
    }

    /// Card completion also changes the balance. Lock the existing tender form
    /// synchronously, before its asynchronous refresh can fail or yield.
    func requireReconciliation() {
        guard !completed else { return }
        needsReconciliation = true
        error = nil
    }

    func requireCardReconciliation(paymentIntentId: String) {
        guard !completed else { return }
        requireReconciliation()
        pendingCardPaymentID = paymentIntentId
    }

    func record(_ input: ManualReceiptInput, refresh: () async throws -> Void) async {
        guard !recording, !reconciling, !needsReconciliation, !completed else { return }
        recording = true
        error = nil
        defer { recording = false }
        do {
            _ = try await collect(input)
        } catch {
            if let error = error as? APIError {
                needsReconciliation = error.code == "PAYMENT_ADJUSTMENT_STALE"
                    || error.status == 0 || error.status >= 500 || [408, 409, 429].contains(error.status)
            } else {
                needsReconciliation = true
            }
            self.error = error.localizedDescription
            return
        }
        // A refresh failure follows a successful collection; it must never
        // make the collection available to submit again.
        requireReconciliation()
        await reconcile(refresh: refresh)
    }

    func reconcile(
        invoicePayments: (() async throws -> [InvoicePayment])? = nil,
        refresh: () async throws -> Void
    ) async {
        guard needsReconciliation, !reconciling, !completed else { return }
        reconciling = true
        defer { reconciling = false }
        do {
            if let pendingCardPaymentID {
                guard let invoicePayments,
                      try await invoicePayments().contains(where: { $0.externalId == pendingCardPaymentID }) else {
                    throw APIError(status: 0, message: "The previous card payment is still being recorded. Refresh again before collecting the remaining balance.")
                }
            }
            try await refresh()
            completed = true
            pendingCardPaymentID = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
