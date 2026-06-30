import SwiftUI
import Foundation

struct TireFilterOption: Identifiable, Hashable {
    let value: String
    let labelKey: String

    var id: String { value.isEmpty ? "all" : value }
}

enum TireFilterOptions {
    static let categories = [
        TireFilterOption(value: "", labelKey: "status.ALL"),
        TireFilterOption(value: "SEMI", labelKey: "tire.category.SEMI"),
        TireFilterOption(value: "LT", labelKey: "tire.category.LT")
    ]

    static let positions = [
        TireFilterOption(value: "", labelKey: "status.ALL"),
        TireFilterOption(value: "STEER", labelKey: "tire.position.STEER"),
        TireFilterOption(value: "DRIVE", labelKey: "tire.position.DRIVE"),
        TireFilterOption(value: "TRAILER", labelKey: "tire.position.TRAILER"),
        TireFilterOption(value: "ALL_POSITION", labelKey: "tire.position.ALL_POSITION")
    ]
}

struct FilterChips: View {
    @EnvironmentObject private var i18n: I18nStore

    @Binding var value: String
    let options: [TireFilterOption]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(options) { option in
                    Button {
                        value = option.value
                    } label: {
                        Text(i18n.t(option.labelKey))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 6)
                            .background(value == option.value ? Theme.primary : Theme.card)
                            .foregroundStyle(value == option.value ? Theme.primaryText : Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .stroke(value == option.value ? Theme.primary : Theme.border)
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.xs)
        }
    }
}

struct PaymentSheetNativeView: View {
    private let storeCreditCode = "2400"

    let invoiceId: String
    let balance: Double
    let customerId: String?
    let onPaid: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var methods: [PaymentMethod] = []
    @State private var creditBalance: Double?
    @State private var rows: [PaymentRow] = []
    @State private var loading = false
    @State private var recording = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RowLine(title: "Balance owed", trailing: AppFormat.money(balance))
                }

                if loading {
                    Section {
                        ProgressView()
                    }
                } else if methods.isEmpty {
                    Section {
                        Text("No manual payment methods are active.")
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Section("Payments") {
                        ForEach($rows) { $row in
                            PaymentRowEditor(
                                row: $row,
                                methods: methods,
                                creditBalance: creditBalance,
                                storeCreditCode: storeCreditCode
                            )
                        }
                        .onDelete { offsets in
                            rows.remove(atOffsets: offsets)
                        }

                        Button("Add payment method") {
                            addRow()
                        }
                    }

                    Section("Totals") {
                        RowLine(title: "Applied to invoice", trailing: AppFormat.money(totalApplied))
                        if totalSurcharge > 0 {
                            RowLine(title: "Card fee", trailing: AppFormat.money(totalSurcharge))
                            RowLine(title: "Customer pays", trailing: AppFormat.money(totalCustomerPays))
                        }
                        RowLine(
                            title: remaining >= 0 ? "Remaining balance" : "Overpayment",
                            trailing: AppFormat.money(abs(remaining))
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(recording ? "Recording..." : recordTitle) {
                        Task { await record() }
                    }
                    .disabled(!canRecord)
                }
            }
            .navigationTitle("Record payment")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await load()
            }
        }
    }

    private var validRows: [PaymentRow] {
        rows.filter { $0.amountValue > 0 && !$0.paymentMethodId.isEmpty }
    }

    private var totalApplied: Double {
        roundMoney(validRows.reduce(0) { $0 + $1.amountValue })
    }

    private var totalSurcharge: Double {
        roundMoney(validRows.reduce(0) { $0 + surcharge(for: $1) })
    }

    private var totalCustomerPays: Double {
        roundMoney(totalApplied + totalSurcharge)
    }

    private var remaining: Double {
        roundMoney(balance - totalApplied)
    }

    private var overpay: Bool {
        totalApplied - balance > 0.01
    }

    private var storeCreditApplied: Double {
        roundMoney(validRows.filter { method(for: $0)?.account.code == storeCreditCode }.reduce(0) { $0 + $1.amountValue })
    }

    private var overCredit: Bool {
        guard let creditBalance else { return false }
        return storeCreditApplied > creditBalance + 0.005
    }

    private var canRecord: Bool {
        !recording && !validRows.isEmpty && !overpay && !overCredit
    }

    private var recordTitle: String {
        validRows.count <= 1 ? "Record payment" : "Record \(validRows.count) payments"
    }

    @MainActor
    private func load() async {
        guard methods.isEmpty else { return }
        loading = true
        errorMessage = nil

        do {
            let loadedMethods = try await CashAccountsAPI().methods()
            methods = loadedMethods.filter { $0.isActive && $0.processor == nil }
            if let customerId {
                creditBalance = (try? await CustomersAPI().creditBalance(id: customerId))?.balance
            }
            if let first = methods.first(where: { $0.account.code != storeCreditCode }) ?? methods.first {
                rows = [PaymentRow(paymentMethodId: first.id, amount: String(format: "%.2f", balance), reference: "")]
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        loading = false
    }

    @MainActor
    private func record() async {
        recording = true
        errorMessage = nil

        do {
            if validRows.isEmpty {
                throw APIError(status: 0, message: "Add at least one payment.")
            }
            if overpay {
                throw APIError(status: 0, message: "Payment exceeds the invoice balance.")
            }
            if overCredit {
                throw APIError(status: 0, message: "Store credit exceeds the available balance.")
            }

            for row in validRows {
                let gross = roundMoney(row.amountValue + surcharge(for: row))
                _ = try await PaymentsAPI().record(
                    invoiceId: invoiceId,
                    body: PaymentRecordInput(
                        paymentMethodId: row.paymentMethodId,
                        amount: gross,
                        reference: row.reference.nilIfBlank,
                        note: nil
                    )
                )
            }

            onPaid()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        recording = false
    }

    private func addRow() {
        let remainingAmount = max(0, remaining)
        rows.append(PaymentRow(
            paymentMethodId: methods.first?.id ?? "",
            amount: remainingAmount > 0 ? String(format: "%.2f", remainingAmount) : "",
            reference: ""
        ))
    }

    private func method(for row: PaymentRow) -> PaymentMethod? {
        methods.first { $0.id == row.paymentMethodId }
    }

    private func surcharge(for row: PaymentRow) -> Double {
        guard
            let method = method(for: row),
            method.account.code != storeCreditCode,
            let feeText = method.feeRate,
            let feeRate = Double(feeText),
            feeRate > 0
        else {
            return 0
        }

        return roundMoney(row.amountValue * feeRate)
    }

    private func roundMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private struct PaymentRow: Identifiable {
    let id = UUID()
    var paymentMethodId: String
    var amount: String
    var reference: String

    var amountValue: Double {
        Double(amount) ?? 0
    }
}

private struct PaymentRowEditor: View {
    @Binding var row: PaymentRow

    let methods: [PaymentMethod]
    let creditBalance: Double?
    let storeCreditCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Picker("Method", selection: $row.paymentMethodId) {
                ForEach(methods) { method in
                    Text(method.name).tag(method.id)
                }
            }

            TextField("Amount", text: $row.amount)
                .keyboardType(.decimalPad)

            TextField("Reference", text: $row.reference)

            if let method = methods.first(where: { $0.id == row.paymentMethodId }) {
                if method.account.code == storeCreditCode {
                    Text("Available store credit: \(AppFormat.money(creditBalance))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                } else if let feeText = method.feeRate, let feeRate = Double(feeText), feeRate > 0 {
                    Text("Card fee: \(String(format: "%.2f", feeRate * 100))%")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
