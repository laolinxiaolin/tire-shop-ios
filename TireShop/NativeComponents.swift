import SwiftUI
import Foundation
import UIKit
import StripePaymentSheet

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
                    CompactFilterChip(
                        title: i18n.t(option.labelKey),
                        selected: value == option.value
                    ) {
                        value = option.value
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.xs)
        }
    }
}

struct CompactFilterChip: View {
    let title: String
    let selected: Bool
    var invalid = false
    var accessibilityLabel: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var label: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 30)
            .background(selected ? accentColor : Theme.card)
            .foregroundStyle(selected ? Theme.primaryText : foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(selected ? accentColor : borderColor)
            )
    }

    private var accentColor: Color {
        invalid ? Theme.danger : Theme.primary
    }

    private var foregroundColor: Color {
        invalid ? Theme.danger : Theme.text
    }

    private var borderColor: Color {
        invalid ? Theme.danger : Theme.border
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
    @State private var postedApplied = 0.0
    @State private var recordingTask: Task<Void, Never>?
    @State private var showCardSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RowLine(title: "Balance owed", trailing: AppFormat.money(effectiveBalance))
                }

                Section("Card") {
                    Button {
                        showCardSheet = true
                    } label: {
                        Label("Enter card number", systemImage: "creditcard")
                    }
                    .disabled(recording || effectiveBalance <= 0)
                }

                if loading {
                    Section("Manual record") {
                        ProgressView()
                    }
                } else if methods.isEmpty {
                    Section("Manual record") {
                        Text("No manual payment methods are active.")
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Section("Manual record") {
                        ForEach($rows) { $row in
                            PaymentRowEditor(
                                row: $row,
                                methods: methods,
                                creditBalance: creditBalance,
                                storeCreditCode: storeCreditCode
                            )
                            .disabled(recording)
                        }
                        .onDelete { offsets in
                            rows.remove(atOffsets: offsets)
                        }

                        Button("Add manual payment method") {
                            addRow()
                        }
                        .disabled(recording)
                    }

                    Section("Totals") {
                        let totals = paymentTotals
                        let remainder = remaining(totals)
                        RowLine(title: "Applied to invoice", trailing: AppFormat.money(totals.applied))
                        if totals.surcharge > 0 {
                            RowLine(title: "Card fee", trailing: AppFormat.money(totals.surcharge))
                            RowLine(title: "Customer pays", trailing: AppFormat.money(totals.customerPays))
                        }
                        RowLine(
                            title: remainder >= 0 ? "Remaining balance" : "Overpayment",
                            trailing: AppFormat.money(abs(remainder))
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
                    let totals = paymentTotals
                    Button(recording ? "Recording..." : recordTitle(totals)) {
                        startRecording()
                    }
                    .disabled(!canRecord(totals))
                }
            }
            .disabled(recording)
            .navigationTitle("Take payment")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        if postedApplied > 0 {
                            onPaid()
                        }
                        dismiss()
                    }
                    .disabled(recording)
                }
            }
            .task {
                await load()
            }
            .sheet(isPresented: $showCardSheet) {
                KeyedCardSplitSheet(
                    invoiceId: invoiceId,
                    balance: effectiveBalance,
                    onPaid: {
                        showCardSheet = false
                        onPaid()
                        dismiss()
                    }
                )
            }
            .interactiveDismissDisabled(recording)
            .onDisappear {
                if recording {
                    recordingTask?.cancel()
                }
            }
        }
    }

    private static func isValid(_ row: PaymentRow) -> Bool {
        row.amountValue > 0 && !row.paymentMethodId.isEmpty
    }

    private var validRows: [PaymentRow] {
        rows.filter(Self.isValid)
    }

    private var effectiveBalance: Double {
        max(0, roundMoney(balance - postedApplied))
    }

    /// The totals the sheet renders. Resolved in one pass over `rows` with a
    /// single `methods` lookup per row, because every value here derives from
    /// the same set of valid rows and the sheet reads all of them together.
    private struct PaymentTotals {
        var validRowCount = 0
        var applied = 0.0
        var surcharge = 0.0
        var storeCredit = 0.0
        var customerPays = 0.0
    }

    private var paymentTotals: PaymentTotals {
        var totals = PaymentTotals()
        for row in rows where Self.isValid(row) {
            let rowMethod = method(for: row)
            totals.validRowCount += 1
            totals.applied += row.amountValue
            totals.surcharge += surcharge(for: row, method: rowMethod)
            if rowMethod?.account.code == storeCreditCode {
                totals.storeCredit += row.amountValue
            }
        }

        totals.applied = roundMoney(totals.applied)
        totals.surcharge = roundMoney(totals.surcharge)
        totals.storeCredit = roundMoney(totals.storeCredit)
        totals.customerPays = roundMoney(totals.applied + totals.surcharge)
        return totals
    }

    private func remaining(_ totals: PaymentTotals) -> Double {
        roundMoney(effectiveBalance - totals.applied)
    }

    private func isOverpay(_ totals: PaymentTotals) -> Bool {
        totals.applied - effectiveBalance > 0.01
    }

    private func isOverCredit(_ totals: PaymentTotals) -> Bool {
        guard let creditBalance else { return false }
        return totals.storeCredit > creditBalance + 0.005
    }

    private func canRecord(_ totals: PaymentTotals) -> Bool {
        !recording && totals.validRowCount > 0
            && !isOverpay(totals) && !isOverCredit(totals)
    }

    private func recordTitle(_ totals: PaymentTotals) -> String {
        totals.validRowCount <= 1
            ? "Record manual payment"
            : "Record \(totals.validRowCount) manual payments"
    }

    @MainActor
    private func present(paymentSheet: PaymentSheet) async throws -> PaymentSheetResult {
        guard let controller = UIApplication.shared.tireShopTopViewController else {
            throw APIError(status: 0, message: "Card entry could not open.")
        }

        return await withCheckedContinuation { continuation in
            paymentSheet.present(from: controller) { result in
                continuation.resume(returning: result)
            }
        }
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
                rows = [
                    PaymentRow(
                        paymentMethodId: first.id,
                        amount: String(format: "%.2f", effectiveBalance),
                        reference: ""
                    )
                ]
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        loading = false
    }

    @MainActor
    private func record() async {
        guard !recording else { return }
        recording = true
        errorMessage = nil
        defer { recording = false }

        do {
            let totals = paymentTotals
            if totals.validRowCount == 0 {
                throw APIError(status: 0, message: "Add at least one payment.")
            }
            if isOverpay(totals) {
                throw APIError(status: 0, message: "Payment exceeds the invoice balance.")
            }
            if isOverCredit(totals) {
                throw APIError(status: 0, message: "Store credit exceeds the available balance.")
            }

            let rowsToRecord = validRows
            for row in rowsToRecord {
                try Task.checkCancellation()

                if row.attempted {
                    if try await paymentWasRecorded(row) {
                        applyRecorded(row)
                        continue
                    }
                } else if let index = rows.firstIndex(where: { $0.id == row.id }) {
                    rows[index].attempted = true
                }

                let gross = roundMoney(row.amountValue + surcharge(for: row))
                do {
                    _ = try await PaymentsAPI().record(
                        invoiceId: invoiceId,
                        body: PaymentRecordInput(
                            paymentMethodId: row.paymentMethodId,
                            amount: gross,
                            reference: row.reference.nilIfBlank,
                            note: row.reconciliationMarker
                        ),
                        idempotencyKey: row.id.uuidString
                    )
                } catch {
                    if (try? await paymentWasRecorded(row)) == true {
                        applyRecorded(row)
                        continue
                    }
                    throw error
                }

                applyRecorded(row)
            }

            onPaid()
            dismiss()
        } catch is CancellationError {
            if postedApplied > 0 {
                errorMessage = "Some payments were recorded. Only the remaining entries are shown."
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            errorMessage = postedApplied > 0
                ? "Some payments were recorded. Only the remaining entries are shown. \(message)"
                : message
        }
    }

    private func startRecording() {
        guard recordingTask == nil else { return }
        recordingTask = Task {
            await record()
            recordingTask = nil
        }
    }

    @MainActor
    private func paymentWasRecorded(_ row: PaymentRow) async throws -> Bool {
        let payments = try await PaymentsAPI().invoicePayments(invoiceId: invoiceId)
        return payments.contains { $0.note == row.reconciliationMarker }
    }

    @MainActor
    private func applyRecorded(_ row: PaymentRow) {
        guard rows.contains(where: { $0.id == row.id }) else { return }
        postedApplied = roundMoney(postedApplied + row.amountValue)
        if method(for: row)?.account.code == storeCreditCode, let creditBalance {
            self.creditBalance = max(0, roundMoney(creditBalance - row.amountValue))
        }
        rows.removeAll { $0.id == row.id }
    }

    private func addRow() {
        let remainingAmount = max(0, remaining(paymentTotals))
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
        surcharge(for: row, method: method(for: row))
    }

    private func surcharge(for row: PaymentRow, method: PaymentMethod?) -> Double {
        guard
            let method,
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

// MARK: - Keyed card split charge (partial amounts + preflight)

/// Collects a keyed-card charge. The amount entered is what the card is charged,
/// fee included — the server divides the fee back out and applies the rest to
/// the invoice. Anything below the fee-inclusive ceiling splits the payment,
/// leaving the remainder for another tender.
private struct KeyedCardSplitSheet: View {
    let invoiceId: String
    let balance: Double
    let onPaid: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var preflight: ChargePreflight?
    /// The server's fee-inclusive full-balance total: both the default and the
    /// most this card can be charged. Quoted, never computed here — the client
    /// has no business knowing the fee rate.
    @State private var maxGross: Double?
    @State private var quoting = true
    @State private var checked = false
    @State private var acknowledgedWarnings = false
    @State private var charging = false
    @State private var errorMessage: String?

    private var amountValue: Double {
        AppFormat.parseAmount(amountText) ?? 0
    }

    private var validAmount: Bool {
        guard let maxGross else { return false }
        return amountValue > 0 && amountValue <= maxGross + 0.005
    }

    private var hasWarnings: Bool {
        (preflight?.warnings.isEmpty ?? true) == false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RowLine(title: "Invoice balance", trailing: AppFormat.money(balance))
                    if let maxGross {
                        RowLine(title: "With card fee", trailing: AppFormat.money(maxGross))
                    }
                }

                Section {
                    TextField("Amount charged to the card", text: $amountText)
                        .keyboardType(.decimalPad)
                        .disabled(maxGross == nil)
                    Button("Charge the full balance") {
                        if let maxGross { amountText = String(format: "%.2f", maxGross) }
                    }
                    .disabled(maxGross == nil)
                } header: {
                    Text("Amount charged to the card")
                } footer: {
                    if quoting {
                        Text("Getting the card total from the server...")
                    } else if let maxGross {
                        Text("This is what the card is charged, card fee included. Up to \(AppFormat.money(maxGross)). Enter less to leave the rest for another tender.")
                    } else {
                        Text("The server could not quote this invoice, so there is no amount to charge.")
                    }
                }

                if checked {
                    if let preflight {
                        Section("Breakdown") {
                            RowLine(title: "Charged to the card", trailing: AppFormat.money(preflight.amount))
                            RowLine(title: "Applied to invoice", trailing: AppFormat.money(preflight.applied))
                            if preflight.surcharge > 0 {
                                RowLine(title: "Card fee", trailing: AppFormat.money(preflight.surcharge))
                            }
                            if preflight.isPartial {
                                RowLine(title: "Balance left open", trailing: AppFormat.money(preflight.remaining))
                                if let remainingGross = preflight.remainingGross {
                                    RowLine(title: "Next full card charge", trailing: AppFormat.money(remainingGross))
                                }
                            }
                        }

                        if hasWarnings {
                            Section("Warnings") {
                                ForEach(preflight.warnings, id: \.code) { warning in
                                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.danger)
                                }
                                Button(acknowledgedWarnings ? "Warnings acknowledged" : "Acknowledge warnings") {
                                    acknowledgedWarnings = true
                                }
                                .disabled(acknowledgedWarnings)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }

                Section {
                    Button(checked ? (charging ? "Charging..." : "Charge \(AppFormat.money(preflight?.amount ?? amountValue))") : "Check charge") {
                        Task { await continueFlow() }
                    }
                    .disabled(charging || !validAmount || (checked && hasWarnings && !acknowledgedWarnings))
                }
            }
            .navigationTitle("Card payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(charging)
                }
            }
            .task {
                await loadCeiling()
            }
            .onChange(of: amountText) { _, _ in
                checked = false
                preflight = nil
                acknowledgedWarnings = false
            }
            .interactiveDismissDisabled(charging)
        }
    }

    @MainActor
    private func continueFlow() async {
        errorMessage = nil
        if !checked {
            await checkPreflight()
            return
        }
        await charge()
    }

    /// Quote the whole balance once on open. Its gross is the ceiling and the
    /// default, so the fee never has to be worked out on this side.
    @MainActor
    private func loadCeiling() async {
        guard maxGross == nil else { return }
        quoting = true
        defer { quoting = false }
        do {
            let quote = try await PaymentsAPI().chargePreflight(invoiceId: invoiceId, processor: .keyedCard)
            maxGross = quote.amount
            if amountText.isEmpty {
                amountText = String(format: "%.2f", quote.amount)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not price this invoice."
        }
    }

    @MainActor
    private func checkPreflight() async {
        charging = true
        defer { charging = false }
        do {
            preflight = try await PaymentsAPI().chargePreflight(
                invoiceId: invoiceId,
                processor: .keyedCard,
                grossAmount: roundMoney(amountValue)
            )
            checked = true
            acknowledgedWarnings = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not check this charge."
        }
    }

    @MainActor
    private func charge() async {
        charging = true
        errorMessage = nil
        defer { charging = false }
        do {
            let status = try await PaymentsAPI().gatewayStatus()
            guard status.enabled, status.provider.lowercased() == "stripe" else {
                throw APIError(status: 0, message: "Stripe payments are not enabled.")
            }
            guard let publishableKey = status.publishableKey?.nilIfBlank else {
                throw APIError(status: 0, message: "Stripe publishable key is not configured.")
            }

            // Mint the intent from the same gross the preflight quoted, not its
            // applied portion: re-deriving the fee from the net can land a cent
            // off the total the operator just confirmed.
            let intent = try await PaymentsAPI().cardIntent(invoiceId: invoiceId, grossAmount: preflight?.amount ?? roundMoney(amountValue))
            guard let clientSecret = intent.clientSecret?.nilIfBlank else {
                throw APIError(status: 0, message: "The server did not return a card payment client secret.")
            }

            STPAPIClient.shared.publishableKey = publishableKey

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Tire Force US"
            configuration.allowsDelayedPaymentMethods = false

            let paymentSheet = PaymentSheet(
                paymentIntentClientSecret: clientSecret,
                configuration: configuration
            )
            let result = try await present(paymentSheet: paymentSheet)

            switch result {
            case .completed:
                if let paymentIntentId = intent.paymentIntentId?.nilIfBlank {
                    _ = try? await PaymentsAPI().settleManual(paymentIntentId: paymentIntentId)
                }
                onPaid()
                dismiss()
            case .canceled:
                errorMessage = "Card entry canceled."
            case .failed(let error):
                throw error
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Card payment failed."
        }
    }

    @MainActor
    private func present(paymentSheet: PaymentSheet) async throws -> PaymentSheetResult {
        guard let controller = UIApplication.shared.tireShopTopViewController else {
            throw APIError(status: 0, message: "Card entry could not open.")
        }

        return await withCheckedContinuation { continuation in
            paymentSheet.present(from: controller) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func roundMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private extension UIApplication {
    var tireShopTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .tireShopTopPresentedViewController
    }
}

private extension UIViewController {
    var tireShopTopPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.tireShopTopPresentedViewController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.tireShopTopPresentedViewController ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.tireShopTopPresentedViewController ?? tabBarController
        }

        return self
    }
}

private struct PaymentRow: Identifiable {
    let id = UUID()
    var paymentMethodId: String
    var amount: String
    var reference: String
    var attempted = false

    var amountValue: Double {
        Double(amount) ?? 0
    }

    var reconciliationMarker: String {
        "[ios-payment:\(id.uuidString)]"
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
