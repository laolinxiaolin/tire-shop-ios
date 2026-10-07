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

    static func make(invoiceId: String, customerId: String?, rows: [PaymentRow], methods: [PaymentMethod]) throws -> Self {
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
        return Self(customerId: customerId?.nilIfBlank, lines: lines)
    }

    static func money(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0, decimal <= Decimal(999_999_999_999) / 100 else { return nil }
        return NSDecimalNumber(decimal: decimal).doubleValue
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

    func record(_ input: ManualReceiptInput, refresh: () async throws -> Void) async {
        guard !recording, !reconciling, !needsReconciliation, !completed else { return }
        recording = true
        error = nil
        defer { recording = false }
        do {
            _ = try await collect(input)
        } catch {
            if let status = (error as? APIError)?.status {
                needsReconciliation = status == 0 || status >= 500 || [408, 409, 429].contains(status)
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

    func reconcile(refresh: () async throws -> Void) async {
        guard needsReconciliation, !reconciling, !completed else { return }
        reconciling = true
        defer { reconciling = false }
        do {
            try await refresh()
            completed = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
