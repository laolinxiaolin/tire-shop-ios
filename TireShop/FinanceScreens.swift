import Foundation
import SwiftUI

// Full-featured finance screens ported from the web UI:
// apps/web/app/{money,accounting,accounting/cash,accounting/fet,accounting/eod}.
// Money = AR/AP ledgers + numbered settlement documents; Accounting = P&L /
// trial balance / journal; Cash = balances, transfers, expenses, methods.

// MARK: - Shared helpers

private enum FinanceDay {
    static func string(_ date: Date) -> String { ShopClock.dayString(from: date) }

    static var todayString: String { string(Date()) }

    static var monthStart: Date {
        ShopClock.monthStart()
    }

    /// Format a plain calendar date (yyyy-MM-dd) without any timezone shift.
    static func calendar(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return s }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)/\(parts[0])"
    }
}

private struct FinanceSubmissionIdentity {
    private var fingerprint: Data?
    private var idempotencyKey = UUID().uuidString

    mutating func key<Body: Encodable>(for body: Body) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let nextFingerprint = try encoder.encode(body)

        if fingerprint != nextFingerprint {
            fingerprint = nextFingerprint
            idempotencyKey = UUID().uuidString
        }

        return idempotencyKey
    }
}

enum ReceivableOverpaymentPolicy {
    static let storeCreditAccountCode = "2400"

    static func excess(received: Double, openBalance: Double) -> Double {
        let difference = roundMoney(received - openBalance)
        return difference > 0.01 ? difference : 0
    }

    static func allowsStoreCredit(excess: Double, paymentMethodAccountCode: String?) -> Bool {
        excess <= 0.005 || paymentMethodAccountCode != storeCreditAccountCode
    }

    /// The receipts endpoint accepts invoice lines only. Put the unapplied
    /// tender on the final line so the server can cap that invoice and create
    /// the matching customer-credit ledger entry for the excess.
    static func applicationsForSubmission(
        _ applications: [ReceivableApplication],
        excess: Double
    ) -> [ReceivableApplication] {
        guard excess > 0.005, let last = applications.indices.last else { return applications }
        var result = applications
        result[last] = ReceivableApplication(
            invoiceId: result[last].invoiceId,
            amount: roundMoney(result[last].amount + excess)
        )
        return result
    }

    private static func roundMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// Human label for a container-cost category code.
private func prettyCostCategory(_ c: String) -> String {
    switch c {
    case "DOWN_PAYMENT": return "Down payment"
    case "BALANCE_PAYMENT": return "Balance payment"
    case "SUPPLIER_OTHER": return "Supplier — other"
    case "FREIGHT": return "Sea freight"
    case "DUTY": return "Customs duty"
    case "TRUCKING": return "Trucking"
    case "LABOR": return "Unloading labor"
    case "OTHER": return "Other"
    default: return c
    }
}

private struct AgeBadge: View {
    let days: Int

    private var color: Color {
        days >= 60 ? .red : days >= 30 ? .orange : .green
    }

    var body: some View {
        Text("\(days)d")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct AgingStripView: View {
    let buckets: BalanceBuckets

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            cell("Current", buckets.current, .green)
            cell("31-60", buckets.b30, .orange)
            cell("61-90", buckets.b60, .orange)
            cell("90+", buckets.b90, .red)
        }
    }

    private func cell(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
            Text(AppFormat.money(value))
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.sm)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(color.opacity(0.4)))
    }
}

private struct DocStatusBadge: View {
    let status: String

    var body: some View {
        let reversed = status == "REVERSED"
        Text(reversed ? "REVERSED" : "POSTED")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background((reversed ? Color.red : Color.green).opacity(0.15))
            .foregroundStyle(reversed ? Color.red : Color.green)
            .clipShape(Capsule())
    }
}

// MARK: - Money (AR / AP / documents)

struct MoneyNativeView: View {
    private enum Tab: String, CaseIterable {
        case receivables
        case payables
        case applications
        case history

        /// Tab labels track the web console's Money page so both consoles read
        /// the same; see `apps/web/app/money/page.tsx`.
        var titleKey: String {
            switch self {
            case .receivables: return "money.receivables"
            case .payables: return "money.payables"
            case .applications: return "pa.title"
            case .history: return "receipt.history"
            }
        }
    }

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @State private var tab: Tab = .receivables

    private var tabs: [Tab] {
        var available: [Tab] = []
        if auth.has("receivables.view") { available.append(.receivables) }
        if auth.has("payables.view") { available.append(.payables) }
        if auth.has("paymentapps.view") { available.append(.applications) }
        // Numbered documents carry their own permissions: someone who can only
        // see payment applications must not mount the receipt and
        // supplier-payment requests.
        if auth.has("payments.collect") || auth.has("payables.view") {
            available.append(.history)
        }
        return available
    }

    private var selectedTab: Tab? {
        tabs.contains(tab) ? tab : tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                // Four segments of the web's wording truncate to nothing at
                // iPhone width, so scroll the labels the way its TabBar does.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(tabs, id: \.self) { value in
                            CompactFilterChip(
                                title: i18n.t(value.titleKey),
                                selected: selectedTab == value
                            ) {
                                tab = value
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.sm)
                }
                .accessibilityLabel(i18n.t("nav.money"))
            }

            if let selectedTab {
                switch selectedTab {
                case .receivables: ReceivablesTabView()
                case .payables: PayablesTabView()
                case .applications: PaymentApplicationsNativeView()
                case .history: MoneyDocumentsTabView()
                }
            } else {
                EmptyStateView(text: "You do not have permission to view receivables or payables.")
            }
        }
        .background(Theme.background)
        .onChange(of: selectedTab) { _, next in
            if let next, tab != next {
                tab = next
            }
        }
    }
}

private struct ReceivablesTabView: View {
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var balances = BalanceListStore<ReceivableCustomer> { page, size, q in
        try await MoneyAPI().receivables(page: page, pageSize: size, q: q)
    }
    private var items: [ReceivableCustomer] { balances.items }
    private var loaded: Bool { balances.loaded }
    @State private var errorMessage: String?
    @State private var q = ""
    @State private var collectTarget: ReceivableCustomer?
    @State private var emailTarget: ReceivableCustomer?
    @State private var statementPreview: PreviewFile?
    @State private var downloadingStatement = false

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage = balances.errorMessage ?? errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else {
                let rows = items
                List {
                    if let message = balances.errorMessage ?? errorMessage {
                        Section {
                            Text(message).foregroundStyle(Theme.danger)
                            Button("Retry") {
                                Task {
                                    if balances.errorMessage != nil { await balances.retry() }
                                    else { await reload() }
                                }
                            }
                            .disabled(balances.loading)
                        }
                    }
                    if balances.loading { ProgressView() }

                    Section {
                        summaryHeader(rows)
                    }

                    Section {
                        if items.isEmpty && q.nilIfBlank == nil {
                            Text("Nothing outstanding. Every invoice is paid.")
                                .foregroundStyle(Theme.muted)
                        } else if rows.isEmpty {
                            Text("No customers match \"\(q)\".")
                                .foregroundStyle(Theme.muted)
                        }

                        ForEach(rows, id: \.customer.id) { row in
                            Button {
                                collectTarget = row
                            } label: {
                                receivableRow(row)
                            }
                            .tint(Theme.text)
                            .swipeActions {
                                Button("Statement") { Task { await downloadStatement(row) } }
                                    .tint(Theme.primary)
                                Button("Email") { emailTarget = row }
                                    .tint(.blue)
                            }
                            .onAppear {
                                if row.customer.id == items.last?.customer.id { Task { await loadMore() } }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await reload() }
            }
        }
        .searchable(text: $q, prompt: "Search customers")
        .task(id: q) { await balances.reload(query: q, debounce: true) }
        .sheet(item: $collectTarget) { target in
            CollectReceivableSheet(customer: target.customer) {
                Task { await reload() }
            }
        }
        .sheet(item: $emailTarget) { target in
            EmailStatementSheet(customer: target.customer)
        }
        .sheet(item: $statementPreview) { preview in
            QuickLookSheet(url: preview.url)
        }
    }

    private func summaryHeader(_ rows: [ReceivableCustomer]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(q.nilIfBlank == nil ? "TOTAL OPEN A/R" : "FILTERED OPEN A/R")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.muted)
            Text(balances.summary.map { AppFormat.money($0.balance) } ?? "—")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.text)
            Text("Across \(balances.total) customer\(balances.total == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            if let summary = balances.summary { AgingStripView(buckets: summary.buckets) }
            if downloadingStatement {
                Label("Preparing statement...", systemImage: "arrow.down.doc")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func receivableRow(_ row: ReceivableCustomer) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.customer.company?.nilIfBlank ?? row.customer.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.sm) {
                    Text("\(row.openCount) open invoice\(row.openCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    AgeBadge(days: row.ageDays)
                }
            }
            Spacer()
            Text(AppFormat.money(row.openBalance))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        await balances.reload(query: q)
    }

    @MainActor
    private func loadMore() async {
        await balances.loadMore()
    }

    @MainActor
    private func downloadStatement(_ row: ReceivableCustomer) async {
        downloadingStatement = true
        do {
            let url = try await MoneyAPI().downloadStatement(customerId: row.customer.id)
            statementPreview = PreviewFile(url: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Statement download failed."
        }
        downloadingStatement = false
    }
}

extension ReceivableCustomer: Identifiable {
    var id: String { customer.id }
}

private struct EmailStatementSheet: View {
    let customer: CustomerSummary

    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var subject = ""
    @State private var message = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Customer's email on file", text: $to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Subject (blank = default)", text: $subject)
                    TextField("Message (blank = default)", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("The statement PDF is attached automatically.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle("Email statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Sending..." : "Send") { Task { await send() } }
                        .disabled(busy)
                }
            }
        }
    }

    @MainActor
    private func send() async {
        busy = true
        errorMessage = nil
        do {
            _ = try await MoneyAPI().emailStatement(
                customerId: customer.id,
                body: StatementEmailInput(to: to.nilIfBlank, subject: subject.nilIfBlank, message: message.nilIfBlank)
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not send the statement."
        }
        busy = false
    }
}

private struct CollectReceivableSheet: View {
    let customer: CustomerSummary
    let onPaid: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.dismiss) private var dismiss

    @State private var detail: ReceivableCustomerDetail?
    @State private var methods: [PaymentMethod] = []
    @State private var paymentMethodId = ""
    @State private var reference = ""
    @State private var note = ""
    @State private var plannedDepositDate = ""
    @State private var bulkAmount = ""
    @State private var allocations: [String: String] = [:]
    @State private var overpaymentAmount = 0.0
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var postedRef: String?
    @State private var postedStoreCredit = 0.0
    @State private var submissionIdentity = FinanceSubmissionIdentity()
    @State private var submissionTask: Task<Void, Never>?
    @State private var showOverpaymentConfirmation = false

    private var canCollect: Bool { auth.has("payments.collect") }

    private var selectedMethod: PaymentMethod? {
        methods.first { $0.id == paymentMethodId }
    }

    private var plannedDepositDateError: String? {
        selectedMethod?.account.code == "1010" && !CheckDates.isValid(plannedDepositDate)
            ? i18n.t("payment.depositDateRequired")
            : nil
    }

    private var overpaymentError: String? {
        guard !ReceivableOverpaymentPolicy.allowsStoreCredit(
            excess: overpaymentAmount,
            paymentMethodAccountCode: selectedMethod?.account.code
        ) else { return nil }
        return i18n.t("payment.storeCreditCannotCreateCredit")
    }

    /// What the entered allocations add up to, and which rows are unusable.
    /// Resolved in one pass: the invoice list re-read these per rendered row,
    /// so drawing N invoices rebuilt both sets N times.
    private struct AllocationState {
        var applications: [ReceivableApplication] = []
        var invalidRows: Set<String> = []
        var overpaidRows: Set<String> = []
        var totalApplied = 0.0
    }

    private var allocationState: AllocationState {
        var state = AllocationState()
        for invoice in detail?.openInvoices ?? [] {
            let entry = allocations[invoice.id]
            let amount = Double(entry ?? "") ?? 0

            if amount.isFinite, amount > 0 {
                state.applications.append(
                    ReceivableApplication(invoiceId: invoice.id, amount: amount)
                )
                state.totalApplied += amount
            }

            if amount.isFinite, amount - invoice.balance > 0.01 {
                state.overpaidRows.insert(invoice.id)
            }

            // Validation reads the trimmed entry, so " 5 " is accepted here
            // even though it does not parse into an application above.
            if let raw = entry?.nilIfBlank {
                guard let typed = Double(raw), typed.isFinite, typed >= 0 else {
                    state.invalidRows.insert(invoice.id)
                    continue
                }
            }
        }
        return state
    }

    var body: some View {
        let state = allocationState
        NavigationStack {
            Group {
                if let detail {
                    form(detail, state: state)
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading open invoices...")
                }
            }
            .navigationTitle(customer.company?.nilIfBlank ?? customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(busy)
                }
                if canCollect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Posting..." : "Collect") { requestSubmission() }
                            .disabled(
                                busy
                                    || state.totalApplied <= 0
                                    || paymentMethodId.isEmpty
                                    || !state.invalidRows.isEmpty
                                    || !state.overpaidRows.isEmpty
                                    || overpaymentError != nil
                            )
                    }
                }
            }
            .alert(i18n.t("payment.confirmOverpayment"), isPresented: $showOverpaymentConfirmation) {
                Button(i18n.t("common.cancel"), role: .cancel) {}
                Button(i18n.t("payment.confirmCollectCredit")) { startSubmission() }
            } message: {
                Text(overpaymentConfirmationMessage(totalApplied: state.totalApplied))
            }
            .alert("Payment recorded", isPresented: Binding(
                get: { postedRef != nil },
                set: { if !$0 { postedRef = nil; onPaid(); dismiss() } }
            )) {
                Button("OK") {}
            } message: {
                if postedStoreCredit > 0.005 {
                    Text(
                        "Receipt # \(postedRef ?? "")\n"
                            + i18n.t("payment.creditSaved", [
                                "credit": AppFormat.money(postedStoreCredit),
                            ])
                    )
                } else {
                    Text("Receipt # \(postedRef ?? "")")
                }
            }
        }
        .task { if detail == nil { await load() } }
        .interactiveDismissDisabled(busy)
        .onDisappear {
            if busy {
                submissionTask?.cancel()
            }
        }
    }

    private func form(_ detail: ReceivableCustomerDetail, state: AllocationState) -> some View {
        Form {
            if canCollect {
                Section("Payment") {
                    Picker("Method", selection: $paymentMethodId) {
                        ForEach(methods) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .onChange(of: paymentMethodId) { _, _ in
                        plannedDepositDate = ""
                    }
                    if selectedMethod?.account.code == "1010" {
                        PlannedCheckDepositDateField(date: $plannedDepositDate)
                    }
                    TextField("Reference / check #", text: $reference)
                    TextField("Note (optional)", text: $note)
                }

                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(Theme.muted)
                        TextField("\(String(format: "%.2f", detail.totalBalance)) = pay all", text: $bulkAmount)
                            .keyboardType(.decimalPad)
                    }
                    Button("Collect all in full") { collectAllInFull(detail) }
                    Button("Apply oldest first") { applyOldestFirst(detail) }
                } header: {
                    Text("Quick split")
                } footer: {
                    if overpaymentAmount > 0.005 {
                        Text(i18n.t("payment.excessBecomesCredit"))
                    } else {
                        Text("Or type an amount on each invoice below.")
                    }
                }
            }

            Section("Open invoices — total \(AppFormat.money(detail.totalBalance))") {
                ForEach(detail.openInvoices) { inv in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text(inv.ref ?? inv.id)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            AgeBadge(days: inv.ageDays)
                            Spacer()
                            Text(AppFormat.money(inv.balance))
                                .font(.subheadline)
                        }
                        if canCollect {
                            HStack {
                                Text("Apply $")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                TextField("0.00", text: Binding(
                                    get: { allocations[inv.id] ?? "" },
                                    set: {
                                        allocations[inv.id] = $0
                                        bulkAmount = ""
                                        overpaymentAmount = 0
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            }
                            if state.overpaidRows.contains(inv.id) {
                                Text("Amount exceeds the remaining balance.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if state.invalidRows.contains(inv.id) {
                                Text("Enter zero or a positive dollar amount.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if canCollect {
                    HStack {
                        Text(i18n.t("payment.appliedToInvoices"))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(AppFormat.money(state.totalApplied))
                            .fontWeight(.semibold)
                    }
                    if overpaymentAmount > 0.005 {
                        RowLine(
                            title: i18n.t("payment.storeCredit"),
                            subtitle: i18n.t("payment.creditFromOverpayment"),
                            trailing: AppFormat.money(overpaymentAmount)
                        )
                        HStack {
                            Text(i18n.t("payment.totalReceived"))
                                .fontWeight(.semibold)
                            Spacer()
                            Text(AppFormat.money(state.totalApplied + overpaymentAmount))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if canCollect, let fee = feeNote(totalApplied: state.totalApplied + overpaymentAmount) {
                Section {
                    Text(fee)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if overpaymentAmount > 0.005, overpaymentError == nil {
                Section {
                    Label(i18n.t("payment.warningOverpayment"), systemImage: "exclamationmark.triangle.fill")
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Text(i18n.t("payment.verifyCustomerOverpayment", [
                        "credit": AppFormat.money(overpaymentAmount),
                    ]))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                }
            }

            if let overpaymentError {
                Section {
                    Text(overpaymentError).foregroundStyle(.red).font(.subheadline)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
        }
    }

    private func feeNote(totalApplied: Double) -> String? {
        guard let method = methods.first(where: { $0.id == paymentMethodId }),
              let rate = method.feeRate.flatMap(Double.init), rate > 0, totalApplied > 0
        else { return nil }
        let fee = (totalApplied * rate * 100).rounded() / 100
        return "A \(String(format: "%.1f", rate * 100))% card fee applies: +\(AppFormat.money(fee)) (customer pays \(AppFormat.money(totalApplied + fee)))."
    }

    private func overpaymentConfirmationMessage(totalApplied: Double) -> String {
        let totalReceived = totalApplied + overpaymentAmount
        let methodName = selectedMethod?.name ?? "the selected payment method"
        var message = i18n.t("payment.confirmCustomerOverpayment", [
            "applied": AppFormat.money(totalApplied),
            "credit": AppFormat.money(overpaymentAmount),
            "total": AppFormat.money(totalReceived),
            "method": methodName,
        ])
        if let rate = selectedMethod?.feeRate.flatMap(Double.init), rate > 0 {
            let fee = (totalReceived * rate * 100).rounded() / 100
            message += " " + i18n.t("payment.feeAppliesSummary", [
                "fee": AppFormat.money(fee),
                "total": AppFormat.money(totalReceived + fee),
            ])
        }
        return message
    }

    private func collectAllInFull(_ detail: ReceivableCustomerDetail) {
        bulkAmount = String(format: "%.2f", detail.totalBalance)
        split(detail, total: detail.totalBalance)
    }

    private func applyOldestFirst(_ detail: ReceivableCustomerDetail) {
        guard let total = Double(bulkAmount), total.isFinite, total > 0 else {
            errorMessage = "Enter a positive amount first"
            return
        }
        errorMessage = nil
        split(detail, total: total)
    }

    private func split(_ detail: ReceivableCustomerDetail, total: Double) {
        var remaining = total
        var next: [String: String] = [:]
        for inv in detail.openInvoices {
            let apply = min(remaining, inv.balance)
            next[inv.id] = apply > 0 ? String(format: "%.2f", apply) : ""
            remaining = ((remaining - apply) * 100).rounded() / 100
        }
        allocations = next
        overpaymentAmount = ReceivableOverpaymentPolicy.excess(
            received: total,
            openBalance: detail.totalBalance
        )
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            async let d = MoneyAPI().receivable(customerId: customer.id)
            async let ms = CashAccountsAPI().methods()
            let (loadedDetail, loadedMethods) = try await (d, ms)
            detail = loadedDetail
            // This endpoint records manual tenders. Processor-backed methods
            // must use their gateway flow and are rejected by the backend here.
            methods = loadedMethods.filter { $0.isActive && $0.processor == nil }
            if paymentMethodId.isEmpty { paymentMethodId = methods.first?.id ?? "" }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load invoices."
        }
    }

    @MainActor
    private func submit() async {
        guard canCollect else {
            errorMessage = "You do not have permission to collect payments."
            return
        }
        let state = allocationState
        guard !state.applications.isEmpty else {
            errorMessage = "Enter an amount for at least one invoice."
            return
        }
        guard state.invalidRows.isEmpty else {
            errorMessage = "One or more invoice amounts are invalid."
            return
        }
        guard state.overpaidRows.isEmpty else {
            errorMessage = "One or more amounts exceed the remaining invoice balance."
            return
        }
        guard overpaymentError == nil else {
            errorMessage = overpaymentError
            return
        }
        guard !paymentMethodId.isEmpty else {
            errorMessage = "Select a payment method."
            return
        }
        guard plannedDepositDateError == nil else {
            errorMessage = plannedDepositDateError
            return
        }

        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            let applications = ReceivableOverpaymentPolicy.applicationsForSubmission(
                state.applications,
                excess: overpaymentAmount
            )
            let input = ReceivablesPayInput(
                customerId: customer.id,
                paymentMethodId: paymentMethodId,
                applications: applications,
                reference: reference.nilIfBlank,
                note: note.nilIfBlank,
                plannedDepositDate: selectedMethod?.account.code == "1010"
                    ? plannedDepositDate
                    : nil
            )
            let idempotencyKey = try submissionIdentity.key(for: input)
            let result = try await MoneyAPI().payReceivables(
                input,
                idempotencyKey: idempotencyKey
            )
            if let ref = result.ref {
                postedStoreCredit = overpaymentAmount
                postedRef = ref
            } else {
                busy = false
                onPaid()
                dismiss()
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
            }
        }
    }

    private func startSubmission() {
        guard submissionTask == nil else { return }
        submissionTask = Task { @MainActor in
            await submit()
            submissionTask = nil
        }
    }

    private func requestSubmission() {
        guard submissionTask == nil else { return }
        if let message = plannedDepositDateError {
            errorMessage = message
            return
        }
        if overpaymentAmount > 0.005 {
            showOverpaymentConfirmation = true
        } else {
            startSubmission()
        }
    }
}

private struct PayablesTabView: View {
    @EnvironmentObject private var auth: AuthStore

    @StateObject private var balances = BalanceListStore<PayableVendor> { page, size, q in
        try await MoneyAPI().payables(page: page, pageSize: size, q: q)
    }
    private var items: [PayableVendor] { balances.items }
    private var loaded: Bool { balances.loaded }
    @State private var errorMessage: String?
    @State private var q = ""
    @State private var payTarget: PayableVendor?

    private var canPay: Bool {
        auth.canActOrRequest("payables.pay")
    }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage = balances.errorMessage ?? errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else {
                let rows = items
                List {
                    if let message = balances.errorMessage ?? errorMessage {
                        Section {
                            Text(message).foregroundStyle(Theme.danger)
                            Button("Retry") {
                                Task {
                                    if balances.errorMessage != nil { await balances.retry() }
                                    else { await reload() }
                                }
                            }
                            .disabled(balances.loading)
                        }
                    }
                    if balances.loading { ProgressView() }

                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text(q.nilIfBlank == nil ? "TOTAL OPEN A/P" : "FILTERED OPEN A/P")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.muted)
                            Text(balances.summary.map { AppFormat.money($0.balance) } ?? "—")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.text)
                            Text("Across \(balances.total) vendor\(balances.total == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            if let summary = balances.summary { AgingStripView(buckets: summary.buckets) }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }

                    Section {
                        if items.isEmpty && q.nilIfBlank == nil {
                            Text("Nothing owed. All container costs are settled.")
                                .foregroundStyle(Theme.muted)
                        } else if rows.isEmpty {
                            Text("No vendors match \"\(q)\".")
                                .foregroundStyle(Theme.muted)
                        }

                        ForEach(rows, id: \.vendorKey) { row in
                            Button {
                                payTarget = row
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.vendor?.nilIfBlank ?? "No vendor")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(row.vendor == nil ? Theme.muted : Theme.text)
                                            .lineLimit(1)
                                        HStack(spacing: Theme.Space.sm) {
                                            Text("\(row.count) open item\(row.count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(Theme.muted)
                                            AgeBadge(days: row.ageDays)
                                        }
                                    }
                                    Spacer()
                                    Text(AppFormat.money(row.totalDue))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.vertical, 2)
                            }
                            .tint(Theme.text)
                            .disabled(!canPay)
                            .onAppear {
                                if row.vendorKey == items.last?.vendorKey { Task { await loadMore() } }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await reload() }
            }
        }
        .searchable(text: $q, prompt: "Search vendors")
        .task(id: q) { await balances.reload(query: q, debounce: true) }
        .sheet(item: $payTarget) { target in
            PayVendorSheet(vendorKey: target.vendorKey) {
                Task { await reload() }
            }
        }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        await balances.reload(query: q)
    }

    @MainActor
    private func loadMore() async {
        await balances.loadMore()
    }


}

extension PayableVendor: Identifiable {
    var id: String { vendorKey }
}

private struct PayVendorSheet: View {
    let vendorKey: String
    let onPaid: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var detail: PayableVendorDetail?
    @State private var accounts: [CashAccount] = []
    @State private var accountId = ""
    @State private var paidAt = Date()
    @State private var reference = ""
    @State private var note = ""
    @State private var amounts: [String: String] = [:]
    @State private var pendingApproval = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var postedRef: String?
    @State private var approvalQueued = false
    @State private var submissionIdentity = FinanceSubmissionIdentity()
    @State private var submissionTask: Task<Void, Never>?

    private var canPay: Bool {
        auth.canActOrRequest("payables.pay")
    }

    /// What the entered amounts add up to, and which rows overpay. Resolved in
    /// one pass: the payable list re-read `overpaidRows` per rendered row, so
    /// drawing N items rebuilt the set N times.
    private struct PayableState {
        var applications: [PayableApplication] = []
        var overpaidRows: Set<String> = []
        var totalSelected = 0.0
    }

    private var payableState: PayableState {
        var state = PayableState()
        for item in detail?.items ?? [] {
            let amount = Double(amounts[item.id] ?? "") ?? 0

            if amount > 0 {
                state.applications.append(
                    PayableApplication(costId: item.id, amount: amount)
                )
                state.totalSelected += amount
            }

            if amount - item.remaining > 0.01 {
                state.overpaidRows.insert(item.id)
            }
        }
        return state
    }

    var body: some View {
        let state = payableState
        NavigationStack {
            Group {
                if let detail {
                    form(detail, state: state)
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
            .navigationTitle(detail?.vendor ?? "Pay vendor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(busy)
                }
                if canPay {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Saving..." : "Pay \(AppFormat.money(state.totalSelected))") {
                            startSubmission()
                        }
                        .disabled(
                            busy
                                || state.totalSelected <= 0
                                || accountId.isEmpty
                                || !state.overpaidRows.isEmpty
                                || pendingApproval
                        )
                    }
                }
            }
            .alert("Payment recorded", isPresented: Binding(
                get: { postedRef != nil },
                set: { if !$0 { postedRef = nil; onPaid(); dismiss() } }
            )) {
                Button("OK") {}
            } message: {
                Text("Payment # \(postedRef ?? "")")
            }
            .alert("Submitted for approval", isPresented: $approvalQueued) {
                Button("OK") { onPaid(); dismiss() }
            } message: {
                Text("The payment needs a manager's approval before it posts.")
            }
        }
        .task { if detail == nil { await load() } }
        .interactiveDismissDisabled(busy)
        .onDisappear {
            if busy {
                submissionTask?.cancel()
            }
        }
    }

    private func form(_ detail: PayableVendorDetail, state: PayableState) -> some View {
        Form {
            Section("Payment") {
                DatePicker("Paid on", selection: $paidAt, displayedComponents: .date)
                Picker("Paid from", selection: $accountId) {
                    ForEach(accounts) { a in
                        Text("\(a.name) (\(a.code))").tag(a.id)
                    }
                }
                TextField("Reference / wire #", text: $reference)
                TextField("Note (optional)", text: $note)
                Button("Pay all in full") { payAll(detail) }
            }

            Section("Open costs — due \(AppFormat.money(detail.totalDue))") {
                ForEach(detail.items) { item in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text(prettyCostCategory(item.category))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            AgeBadge(days: item.ageDays)
                            Spacer()
                            Text(AppFormat.money(item.remaining))
                                .font(.subheadline)
                        }
                        if let container = item.container {
                            Text("\(container.ref ?? container.id) · \(container.supplier.name)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        } else if let transfer = item.transfer {
                            Text("\(transfer.ref ?? transfer.id) · \(transfer.fromLocation) → \(transfer.toLocation)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        if let description = item.description?.nilIfBlank {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        if item.amountPaid > 0 {
                            Text("\(AppFormat.money(item.amountPaid)) of \(AppFormat.money(item.amount)) already paid")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Text("Apply $")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            TextField("0.00", text: Binding(
                                get: { amounts[item.id] ?? "" },
                                set: { amounts[item.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            if (Double(amounts[item.id] ?? "") ?? 0) == 0 {
                                Button("Full") { amounts[item.id] = String(format: "%.2f", item.remaining) }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                            } else {
                                Button("Skip") { amounts[item.id] = "" }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    .tint(Theme.muted)
                            }
                        }
                        if state.overpaidRows.contains(item.id) {
                            Text("Amount exceeds the remaining balance.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Text("Total being paid")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(AppFormat.money(state.totalSelected))
                        .fontWeight(.semibold)
                }
            }

            if pendingApproval {
                Section {
                    Text("A payment for this vendor is already awaiting approval. Wait for the decision before paying again.")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
        }
        .disabled(!canPay || busy)
    }

    private func payAll(_ detail: PayableVendorDetail) {
        var next: [String: String] = [:]
        for item in detail.items {
            next[item.id] = String(format: "%.2f", item.remaining)
        }
        amounts = next
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            async let d = MoneyAPI().payable(vendorKey: vendorKey)
            async let accts = CashAccountsAPI().list()
            let (loadedDetail, loadedAccounts) = try await (d, accts)
            detail = loadedDetail
            accounts = loadedAccounts
            if accountId.isEmpty {
                accountId = loadedAccounts.first(where: { $0.code == "1020" })?.id ?? loadedAccounts.first?.id ?? ""
            }
            payAll(loadedDetail)

            let costIds = Set(loadedDetail.items.map(\.id))
            if let approvals = try? await ApprovalsAPI().list(status: "PENDING", pageSize: 100) {
                pendingApproval = approvals.items.contains {
                    $0.action == "payable.pay" && $0.entityId.map(costIds.contains) == true
                }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the vendor's open costs."
        }
    }

    @MainActor
    private func submit() async {
        guard canPay else {
            errorMessage = "You do not have permission to pay vendors."
            return
        }
        let state = payableState
        guard !state.applications.isEmpty else {
            errorMessage = "Enter an amount for at least one payable."
            return
        }
        guard state.overpaidRows.isEmpty else {
            errorMessage = "One or more amounts exceed the remaining balance."
            return
        }
        guard !accountId.isEmpty else {
            errorMessage = "Select the account to pay from."
            return
        }

        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            let input = PayablesPayInput(
                expectedVendorKey: vendorKey,
                applications: state.applications,
                paidAt: FinanceDay.string(paidAt),
                reference: reference.nilIfBlank,
                note: note.nilIfBlank,
                accountId: accountId.nilIfBlank
            )
            let idempotencyKey = try submissionIdentity.key(for: input)
            let result = try await MoneyAPI().payPayables(
                input,
                idempotencyKey: idempotencyKey
            )
            if result.approvalRequest != nil {
                approvalQueued = true
            } else if let ref = result.ref {
                postedRef = ref
            } else {
                busy = false
                onPaid()
                dismiss()
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
            }
        }
    }

    private func startSubmission() {
        guard submissionTask == nil else { return }
        submissionTask = Task { @MainActor in
            await submit()
            submissionTask = nil
        }
    }
}

// MARK: - Money documents (receipt / supplier payment history)

private struct MoneyDocumentsTabView: View {
    private enum Kind: String, CaseIterable {
        case receipts = "Receipts"
        case payments = "Supplier payments"
    }

    @EnvironmentObject private var auth: AuthStore
    @State private var kind: Kind = .receipts

    private var kinds: [Kind] {
        var available: [Kind] = []
        if auth.has("payments.collect") { available.append(.receipts) }
        if auth.has("payables.view") { available.append(.payments) }
        return available
    }

    var body: some View {
        VStack(spacing: 0) {
            if kinds.count > 1 {
                Picker("Kind", selection: $kind) {
                    ForEach(kinds, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.sm)
            }

            switch kind {
            case .receipts: ReceiptsListView()
            case .payments: SupplierPaymentsListView()
            }
        }
        .onAppear {
            if !kinds.contains(kind), let first = kinds.first { kind = first }
        }
    }
}

private struct ReceiptsListView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var items: [CustomerReceipt] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var loadedPage = 1
    @State private var errorMessage: String?
    @State private var openId: String?

    private let pageSize = 50

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else if items.isEmpty {
                EmptyStateView(text: "No receipts yet.")
            } else {
                List(items) { doc in
                    Button {
                        openId = doc.id
                    } label: {
                        documentRow(
                            ref: doc.ref,
                            party: doc.customer?.company?.nilIfBlank ?? doc.customer?.name ?? "—",
                            total: doc.total,
                            lineCount: doc.lineCount,
                            date: doc.createdAt,
                            status: doc.status
                        )
                    }
                    .tint(Theme.text)
                    .onAppear {
                        if doc.id == items.last?.id { Task { await loadMore() } }
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
        .task { if !loaded { await reload() } }
        .sheet(item: Binding(
            get: { openId.map { DocumentSheetTarget(id: $0) } },
            set: { openId = $0?.id }
        )) { target in
            ReceiptDetailSheet(id: target.id, canReverse: auth.has("payments.reverse")) {
                Task { await reload() }
            }
        }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        do {
            let page = try await MoneyAPI().receipts(page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
            loadedPage = 1
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load receipts."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = loadedPage + 1
        if let page = try? await MoneyAPI().receipts(page: nextPage, pageSize: pageSize) {
            items.appendNewElements(from: page.items)
            total = page.total
            loadedPage = nextPage
        }
        loadingMore = false
    }
}

private struct DocumentSheetTarget: Identifiable {
    let id: String
}

private func documentRow(ref: String, party: String, total: Double, lineCount: Int, date: String, status: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Space.xs) {
        HStack {
            Text(ref)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospaced()
            Spacer()
            Text(AppFormat.money(total))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        HStack {
            Text(party)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer()
            Text("\(lineCount) line\(lineCount == 1 ? "" : "s") · \(AppFormat.shortDate(date))")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            DocStatusBadge(status: status)
        }
    }
    .padding(.vertical, 2)
}

private struct ReceiptDetailSheet: View {
    let id: String
    let canReverse: Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var doc: CustomerReceiptDetail?
    @State private var busy = false
    @State private var confirmingReverse = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let doc {
                    List {
                        Section {
                            RowLine(title: "Customer", subtitle: nil, trailing: doc.customer?.company?.nilIfBlank ?? doc.customer?.name ?? "—")
                            RowLine(title: "Total", trailing: AppFormat.money(doc.total))
                            RowLine(title: "Method", trailing: doc.paymentMethod ?? "—")
                            if let reference = doc.reference?.nilIfBlank {
                                RowLine(title: "Reference", trailing: reference)
                            }
                            HStack {
                                Text("Status").fontWeight(.semibold)
                                Spacer()
                                DocStatusBadge(status: doc.status)
                            }
                        }

                        Section("Lines") {
                            ForEach(doc.lines) { line in
                                RowLine(
                                    title: line.invoiceRef ?? line.invoiceId,
                                    subtitle: line.paymentMethod,
                                    trailing: AppFormat.money(line.amount)
                                )
                            }
                        }

                        if canReverse && doc.status == "POSTED" {
                            Section {
                                Button("Reverse receipt", role: .destructive) { confirmingReverse = true }
                                    .disabled(busy)
                            }
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                            }
                        }
                    }
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
            .navigationTitle(doc.map { "Receipt \($0.ref)" } ?? "Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Reverse this receipt?", isPresented: $confirmingReverse) {
                Button("Cancel", role: .cancel) {}
                Button("Reverse", role: .destructive) { Task { await reverse() } }
            } message: {
                Text("This reopens the invoices the receipt paid and backs out the cash.")
            }
        }
        .task { if doc == nil { await load() } }
    }

    @MainActor
    private func load() async {
        do {
            doc = try await MoneyAPI().receipt(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the receipt."
        }
    }

    @MainActor
    private func reverse() async {
        busy = true
        errorMessage = nil
        do {
            _ = try await MoneyAPI().reverseReceipt(id: id)
            onChanged()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reverse the receipt."
        }
        busy = false
    }
}

private struct SupplierPaymentsListView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var items: [SupplierPayment] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var loadedPage = 1
    @State private var errorMessage: String?
    @State private var openId: String?

    private let pageSize = 50

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else if items.isEmpty {
                EmptyStateView(text: "No supplier payments yet.")
            } else {
                List(items) { doc in
                    Button {
                        openId = doc.id
                    } label: {
                        documentRow(
                            ref: doc.ref,
                            party: doc.vendor ?? "—",
                            total: doc.total,
                            lineCount: doc.lineCount,
                            date: doc.paidAt,
                            status: doc.status
                        )
                    }
                    .tint(Theme.text)
                    .onAppear {
                        if doc.id == items.last?.id { Task { await loadMore() } }
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
        .task { if !loaded { await reload() } }
        .sheet(item: Binding(
            get: { openId.map { DocumentSheetTarget(id: $0) } },
            set: { openId = $0?.id }
        )) { target in
            SupplierPaymentDetailSheet(id: target.id, canReverse: auth.has("payables.pay")) {
                Task { await reload() }
            }
        }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        do {
            let page = try await MoneyAPI().supplierPayments(page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
            loadedPage = 1
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load supplier payments."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = loadedPage + 1
        if let page = try? await MoneyAPI().supplierPayments(page: nextPage, pageSize: pageSize) {
            items.appendNewElements(from: page.items)
            total = page.total
            loadedPage = nextPage
        }
        loadingMore = false
    }
}

struct SupplierPaymentDetailSheet: View {
    let id: String
    let canReverse: Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var doc: SupplierPaymentDetail?
    @State private var busy = false
    @State private var confirmingReverse = false
    @State private var approvalQueued = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let doc {
                    List {
                        Section {
                            RowLine(title: "Vendor", trailing: doc.vendor ?? "—")
                            RowLine(title: "Total", trailing: AppFormat.money(doc.total))
                            RowLine(
                                title: "Paid from",
                                trailing: doc.fundingAccount.map { "\($0.name) (\($0.code))" } ?? "Bank Account (1020)"
                            )
                            if let reference = doc.reference?.nilIfBlank {
                                RowLine(title: "Reference", trailing: reference)
                            }
                            HStack {
                                Text("Status").fontWeight(.semibold)
                                Spacer()
                                DocStatusBadge(status: doc.status)
                            }
                        }

                        Section("Lines") {
                            ForEach(doc.lines) { line in
                                RowLine(
                                    title: prettyCostCategory(line.category),
                                    subtitle: line.container.map { $0.ref ?? $0.id }
                                        ?? line.transfer.map { $0.ref ?? $0.id }
                                        ?? "Source document",
                                    trailing: AppFormat.money(line.amount)
                                )
                            }
                        }

                        if canReverse && doc.status == "POSTED" {
                            Section {
                                Button("Reverse payment", role: .destructive) { confirmingReverse = true }
                                    .disabled(busy)
                            }
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                            }
                        }
                    }
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
            .navigationTitle(doc.map { "Payment \($0.ref)" } ?? "Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Reverse this payment?", isPresented: $confirmingReverse) {
                Button("Cancel", role: .cancel) {}
                Button("Reverse", role: .destructive) { Task { await reverse() } }
            } message: {
                Text("This reopens the supplier costs and returns the cash to the funding account.")
            }
            .alert("Submitted for approval", isPresented: $approvalQueued) {
                Button("OK") { onChanged(); dismiss() }
            }
        }
        .task { if doc == nil { await load() } }
    }

    @MainActor
    private func load() async {
        do {
            doc = try await MoneyAPI().supplierPayment(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the payment."
        }
    }

    @MainActor
    private func reverse() async {
        busy = true
        errorMessage = nil
        do {
            let result = try await MoneyAPI().reverseSupplierPayment(id: id)
            if result.approvalRequest != nil {
                approvalQueued = true
            } else {
                onChanged()
                dismiss()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reverse the payment."
        }
        busy = false
    }
}

// MARK: - Accounting (P&L / trial balance / journal)

struct AccountingNativeView: View {
    private enum Tab: String, CaseIterable {
        case pnl = "P&L"
        case accounts = "Accounts"
        case journal = "Journal"
    }

    @State private var tab: Tab = .pnl

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)

            switch tab {
            case .pnl: PnlTabView()
            case .accounts: TrialBalanceTabView()
            case .journal: JournalTabView()
            }
        }
        .background(Theme.background)
    }
}

private struct PnlRequestKey: Hashable {
    let from: String
    let to: String
}

private struct PnlTabView: View {
    @State private var from = FinanceDay.monthStart
    @State private var to = Date()
    @State private var pnl: Pnl?
    @State private var loading = false
    @State private var errorMessage: String?

    private var requestKey: PnlRequestKey {
        PnlRequestKey(from: FinanceDay.string(from), to: FinanceDay.string(to))
    }

    var body: some View {
        List {
            Section {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, displayedComponents: .date)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }

            if let pnl {
                pnlSection(title: "Revenue", rows: pnl.revenue, total: pnl.revenueTotal, positive: true)
                pnlSection(title: "Expenses", rows: pnl.expenses, total: pnl.expensesTotal, positive: false)

                Section {
                    HStack {
                        Text("Net income")
                            .fontWeight(.bold)
                        Spacer()
                        Text(AppFormat.money(pnl.netIncome))
                            .fontWeight(.bold)
                            .foregroundStyle(pnl.netIncome >= 0 ? Color.green : Color.red)
                    }
                }
            } else if loading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading...").foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(requestKey) }
        .task(id: requestKey) { await load(requestKey) }
    }

    private func pnlSection(title: String, rows: [Pnl.Line], total: Double, positive: Bool) -> some View {
        Section(title) {
            if rows.isEmpty {
                Text("No activity in this period.")
                    .foregroundStyle(Theme.muted)
            }
            ForEach(rows, id: \.code) { row in
                RowLine(title: row.name, subtitle: row.code, trailing: AppFormat.money(row.total))
            }
            HStack {
                Text("Total \(title.lowercased())")
                    .fontWeight(.semibold)
                Spacer()
                Text(AppFormat.money(total))
                    .fontWeight(.semibold)
                    .foregroundStyle(positive ? Color.green : Theme.text)
            }
        }
    }

    @MainActor
    private func load(_ key: PnlRequestKey) async {
        loading = true
        errorMessage = nil
        do {
            let loaded = try await AccountingAPI().pnl(from: key.from, to: key.to)
            guard key == requestKey, !Task.isCancelled else { return }
            pnl = loaded
            loading = false
        } catch {
            guard key == requestKey, !Task.isCancelled, !isFinanceRequestCancellation(error) else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the P&L."
            loading = false
        }
    }
}

private struct TrialBalanceTabView: View {
    var body: some View {
        AsyncContentView(load: AccountingAPI().accounts) { accounts in
            List(accounts) { account in
                RowLine(
                    title: "\(account.code) · \(account.name)",
                    subtitle: account.type,
                    trailing: AppFormat.money(account.balance)
                )
            }
            .listStyle(.plain)
        }
    }
}

/// Resolve a journal entry's ref (type + id) to the in-app route for the source
/// transaction, or nil when it has no native detail screen.
private func journalRefRoute(refType: String?, refId: String?) -> AppRoute? {
    guard let refType, let refId else { return nil }
    let type = refType.hasPrefix("reversal:") ? String(refType.dropFirst("reversal:".count)) : refType
    let id = refId.split(separator: ":").first.map(String.init) ?? refId
    if type.hasPrefix("sale") { return .saleDetail(id) }
    if type == "Container" || type.hasPrefix("container") { return .containerDetail(id) }
    if type == "inventory-count" { return .inventoryCountDetail(id) }
    if type == "stock-transfer" { return .transferDetail(id) }
    return nil
}

private struct JournalTabView: View {
    @State private var items: [JournalEntry] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var loadedPage = 1
    @State private var errorMessage: String?

    private let pageSize = 25

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else if items.isEmpty {
                EmptyStateView(text: "No journal entries yet.")
            } else {
                List(items) { entry in
                    JournalEntryRow(entry: entry)
                        .onAppear {
                            if entry.id == items.last?.id { Task { await loadMore() } }
                        }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
            }
        }
        .task { if !loaded { await reload() } }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        do {
            let page = try await AccountingAPI().journal(page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
            loadedPage = 1
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the journal."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = loadedPage + 1
        if let page = try? await AccountingAPI().journal(page: nextPage, pageSize: pageSize) {
            items.appendNewElements(from: page.items)
            total = page.total
            loadedPage = nextPage
        }
        loadingMore = false
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry

    private var isReversal: Bool { entry.refType?.hasPrefix("reversal:") == true }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(AppFormat.shortDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
                if isReversal {
                    Text("REVERSAL")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }

            if let route = journalRefRoute(refType: entry.refType, refId: entry.refId) {
                NavigationLink(value: route) {
                    Text(entry.memo ?? "—")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.memo ?? "—")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
            }

            ForEach(entry.lines) { line in
                HStack {
                    Text("\(line.account.code) \(line.account.name)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if let debit = Double(line.debit), debit > 0 {
                        Text("−\(AppFormat.money(debit))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }
                    if let credit = Double(line.credit), credit > 0 {
                        Text("+\(AppFormat.money(credit))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

// MARK: - Cash accounts

struct CashAccountsNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    enum Tab: String, CaseIterable {
        case transfers = "Transfers"
        case expenses = "Expenses"
        case methods = "Payment Methods"
    }

    @State private var accounts: [CashAccount] = []
    @State private var tab: Tab = .transfers
    @State private var loaded = false
    @State private var errorMessage: String?

    @State private var showingAddAccount = false
    @State private var loadGeneration = 0
    @State private var refreshing = false
    @State private var showingTransfer = false
    @State private var showingExpense = false
    @State private var showingAddMethod = false
    @State private var historyAccount: CashAccount?
    @State private var receiptsExpense: ExpensePayment?
    @State private var reverseTransferTarget: CashTransfer?
    @State private var reverseExpenseTarget: ExpensePayment?
    @State private var deleteMethodTarget: PaymentMethod?
    @State private var editingMethod: PaymentMethod?

    // Independent infinite-scroll pagination state per tab.
    @State private var transfers: [CashTransfer] = []
    @State private var transfersTotal = 0
    @State private var transfersPage = 0
    @State private var transfersLoadingMore = false

    @State private var expenses: [ExpensePayment] = []
    @State private var expensesTotal = 0
    @State private var expensesPage = 0
    @State private var expensesLoadingMore = false

    @State private var methods: [PaymentMethod] = []
    @State private var methodsTotal = 0
    @State private var methodsPage = 0
    @State private var methodsLoadingMore = false

    private let pageSize = 30

    private var canManage: Bool { auth.has("accounting.manage") }
    private var totalCash: Double { accounts.reduce(0) { $0 + $1.balance } }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, accounts.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                content
            }
        }
        .background(Theme.background)
        .task { if !loaded { await load() } }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAddAccount = true } label: { Label(i18n.t("accounting.cash.addAccount"), systemImage: "building.columns") }
                        Button { showingTransfer = true } label: { Label("Transfer funds", systemImage: "arrow.left.arrow.right") }
                        Button { showingExpense = true } label: { Label("Record expense", systemImage: "minus.circle") }
                        Button { showingAddMethod = true } label: { Label("Add payment method", systemImage: "creditcard") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddCashAccountSheet { account in
                loadGeneration += 1
                refreshing = false
                accounts.removeAll { $0.id == account.id }
                accounts.append(account)
                accounts.sort { $0.code < $1.code }
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingTransfer) {
            TransferFundsSheet(accounts: accounts) { Task { await load() } }
        }
        .sheet(isPresented: $showingExpense) {
            RecordExpenseSheet(accounts: accounts) { Task { await load() } }
        }
        .sheet(isPresented: $showingAddMethod) {
            AddPaymentMethodSheet(accounts: accounts) { Task { await load() } }
        }
        .sheet(item: $editingMethod) { method in
            AddPaymentMethodSheet(accounts: accounts, editing: method) { Task { await load() } }
        }
        .sheet(item: $historyAccount) { account in
            AccountHistorySheet(account: account)
        }
        .sheet(item: $receiptsExpense) { expense in
            ExpenseReceiptsSheet(expense: expense, canManage: canManage) { Task { await load() } }
        }
        .alert("Reverse this transfer?", isPresented: Binding(
            get: { reverseTransferTarget != nil },
            set: { if !$0 { reverseTransferTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { reverseTransferTarget = nil }
            Button("Reverse", role: .destructive) { Task { await reverseTransfer() } }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Reverse this expense?", isPresented: Binding(
            get: { reverseExpenseTarget != nil },
            set: { if !$0 { reverseExpenseTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { reverseExpenseTarget = nil }
            Button("Reverse", role: .destructive) { Task { await reverseExpense() } }
        } message: {
            Text("The money is returned to the account it was paid from.")
        }
        .alert("Delete payment method?", isPresented: Binding(
            get: { deleteMethodTarget != nil },
            set: { if !$0 { deleteMethodTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteMethodTarget = nil }
            Button("Delete", role: .destructive) { Task { await deleteMethod() } }
        } message: {
            Text("\"\(deleteMethodTarget?.name ?? "")\" is removed permanently. Methods with recorded payments can't be deleted.")
        }
    }

    private var content: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    Button("Retry") { Task { await load() } }.disabled(refreshing)
                }
            }

            Section("Balances") {
                ForEach(accounts) { account in
                    Button {
                        historyAccount = account
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.text)
                                Text(account.code)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                    .monospaced()
                            }
                            Spacer()
                            Text(AppFormat.money(account.balance))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(account.balance >= 0 ? Color.green : Color.red)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                HStack {
                    Text("Total cash position")
                        .fontWeight(.bold)
                    Spacer()
                    Text(AppFormat.money(totalCash))
                        .fontWeight(.bold)
                }
            }

            Section {
                Picker("Category", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            switch tab {
            case .transfers:
                transfersSection
            case .expenses:
                expensesSection
            case .methods:
                methodsSection
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private var transfersSection: some View {
        Section("Transfer history") {
            if transfers.isEmpty && !loaded {
                Text("Loading...").foregroundStyle(Theme.muted)
            } else if transfers.isEmpty {
                Text("No transfers yet.").foregroundStyle(Theme.muted)
            }
            ForEach(transfers) { transfer in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(transfer.ref)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if transfer.reversedAt != nil {
                            Text("REVERSED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text(AppFormat.money(transfer.amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text("\(transfer.fromAccount.name) → \(transfer.toAccount.name)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    HStack {
                        Text(AppFormat.shortDate(transfer.createdAt))
                        if transfer.counts.depositChecks > 0 {
                            Text("· \(transfer.counts.depositChecks) check\(transfer.counts.depositChecks == 1 ? "" : "s")")
                        }
                        if let fee = Double(transfer.fee), fee > 0 {
                            Text("· fee \(AppFormat.money(fee))")
                        }
                        if let reference = transfer.reference?.nilIfBlank {
                            Text("· \(reference)").lineLimit(1)
                        }
                        if let note = transfer.note?.nilIfBlank {
                            Text("· \(note)").lineLimit(1)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
                .swipeActions {
                    if canManage && transfer.reversedAt == nil {
                        Button("Reverse", role: .destructive) { reverseTransferTarget = transfer }
                    }
                }
                .opacity(transfer.reversedAt == nil ? 1 : 0.55)
                .onAppear {
                    if transfer.id == transfers.last?.id { Task { await loadMoreTransfers() } }
                }
            }
            if transfersLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    private var expensesSection: some View {
        Section("Operating expenses") {
            if expenses.isEmpty && !loaded {
                Text("Loading...").foregroundStyle(Theme.muted)
            } else if expenses.isEmpty {
                Text("No expenses recorded.").foregroundStyle(Theme.muted)
            }
            ForEach(expenses) { expense in
                Button {
                    receiptsExpense = expense
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(expense.expenseCode) \(expense.expenseName)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer()
                            Text(AppFormat.money(expense.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.text)
                        }
                        HStack {
                            Text(AppFormat.shortDate(expense.date))
                            if let payee = expense.payee?.nilIfBlank {
                                Text("· \(payee)").lineLimit(1)
                            }
                            Text("· from \(expense.paidFromCode)")
                            Spacer()
                            Text(expense.receiptCount > 0 ? "\(expense.receiptCount) receipt\(expense.receiptCount == 1 ? "" : "s")" : "No receipts")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    }
                }
                .swipeActions {
                    if canManage {
                        Button("Reverse", role: .destructive) { reverseExpenseTarget = expense }
                    }
                }
                .onAppear {
                    if expense.id == expenses.last?.id { Task { await loadMoreExpenses() } }
                }
            }
            if expensesLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    private var methodsSection: some View {
        Section("Payment methods") {
            if methods.isEmpty && !loaded {
                Text("Loading...").foregroundStyle(Theme.muted)
            } else if methods.isEmpty {
                Text("No payment methods.").foregroundStyle(Theme.muted)
            }
            ForEach(methods) { method in
                HStack {
                    Button {
                        if canManage {
                            editingMethod = method
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.text)
                            Text("\(method.account.code) \(method.account.name)\(feeLabel(method))")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            if let payout = method.payoutAccount {
                                Text("Pays out to \(payout.code) \(payout.name)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canManage)

                    if canManage {
                        Button {
                            Task { await toggleMethod(method) }
                        } label: {
                            Text(method.isActive ? "Active" : "Off")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(method.isActive ? Theme.primary : Theme.muted)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text(method.isActive ? "Active" : "Off")
                            .font(.caption)
                            .foregroundStyle(method.isActive ? Theme.primary : Theme.muted)
                    }
                }
                .swipeActions {
                    if canManage {
                        Button("Delete", role: .destructive) { deleteMethodTarget = method }
                    }
                }
                .onAppear {
                    if method.id == methods.last?.id { Task { await loadMoreMethods() } }
                }
            }
            if methodsLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    private func feeLabel(_ method: PaymentMethod) -> String {
        guard let rate = method.feeRate.flatMap(Double.init), rate > 0 else { return "" }
        return String(format: " · %.2f%% fee", rate * 100)
    }

    @MainActor
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        refreshing = true
        transfersLoadingMore = false
        expensesLoadingMore = false
        methodsLoadingMore = false
        errorMessage = nil
        defer { if generation == loadGeneration { refreshing = false; loaded = true } }
        async let accountResult = financeResult { try await CashAccountsAPI().list() }
        async let transferResult = financeResult { try await CashAccountsAPI().transfersPaged(page: 1, pageSize: pageSize) }
        async let expenseResult = financeResult { try await CashAccountsAPI().expenses(page: 1, pageSize: pageSize) }
        async let methodResult = financeResult { try await CashAccountsAPI().methodsPaged(page: 1, pageSize: pageSize) }
        let (accountResponse, transferResponse, expenseResponse, methodResponse) = await (accountResult, transferResult, expenseResult, methodResult)
        guard generation == loadGeneration else { return }
        var failures: [String] = []
        switch accountResponse {
        case .success(let value): accounts = value
        case .failure(let error): failures.append(error.localizedDescription)
        }
        switch transferResponse {
        case .success(let value):
            transfers = value.items
            transfersTotal = value.total
            transfersPage = 1
        case .failure(let error): failures.append(error.localizedDescription)
        }
        switch expenseResponse {
        case .success(let value):
            expenses = value.items
            expensesTotal = value.total
            expensesPage = 1
        case .failure(let error): failures.append(error.localizedDescription)
        }
        switch methodResponse {
        case .success(let value):
            methods = value.items
            methodsTotal = value.total
            methodsPage = 1
        case .failure(let error): failures.append(error.localizedDescription)
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    @MainActor
    private func loadMoreTransfers() async {
        guard !refreshing, !transfersLoadingMore, transfersPage * pageSize < transfersTotal else { return }
        let generation = loadGeneration
        transfersLoadingMore = true
        defer { if generation == loadGeneration { transfersLoadingMore = false } }
        do {
            let page = try await CashAccountsAPI().transfersPaged(page: transfersPage + 1, pageSize: pageSize)
            guard generation == loadGeneration else { return }
            transfers.appendNewElements(from: page.items)
            transfersPage += 1
            transfersTotal = page.total
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreExpenses() async {
        guard !refreshing, !expensesLoadingMore, expensesPage * pageSize < expensesTotal else { return }
        let generation = loadGeneration
        expensesLoadingMore = true
        defer { if generation == loadGeneration { expensesLoadingMore = false } }
        do {
            let page = try await CashAccountsAPI().expenses(page: expensesPage + 1, pageSize: pageSize)
            guard generation == loadGeneration else { return }
            expenses.appendNewElements(from: page.items)
            expensesPage += 1
            expensesTotal = page.total
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMoreMethods() async {
        guard !refreshing, !methodsLoadingMore, methodsPage * pageSize < methodsTotal else { return }
        let generation = loadGeneration
        methodsLoadingMore = true
        defer { if generation == loadGeneration { methodsLoadingMore = false } }
        do {
            let page = try await CashAccountsAPI().methodsPaged(page: methodsPage + 1, pageSize: pageSize)
            guard generation == loadGeneration else { return }
            methods.appendNewElements(from: page.items)
            methodsPage += 1
            methodsTotal = page.total
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reverseTransfer() async {
        guard let target = reverseTransferTarget else { return }
        reverseTransferTarget = nil
        do {
            _ = try await CashAccountsAPI().reverseTransfer(id: target.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reverse the transfer."
        }
    }

    @MainActor
    private func reverseExpense() async {
        guard let target = reverseExpenseTarget else { return }
        reverseExpenseTarget = nil
        do {
            _ = try await CashAccountsAPI().reverseExpense(id: target.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reverse the expense."
        }
    }

    @MainActor
    private func toggleMethod(_ method: PaymentMethod) async {
        do {
            _ = try await CashAccountsAPI().updateMethod(id: method.id, body: PaymentMethodPatchInput(isActive: !method.isActive))
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update the payment method."
        }
    }

    @MainActor
    private func deleteMethod() async {
        guard let target = deleteMethodTarget else { return }
        deleteMethodTarget = nil
        do {
            _ = try await CashAccountsAPI().deleteMethod(id: target.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete the payment method."
        }
    }
}

private struct AccountHistorySheet: View {
    let account: CashAccount

    @Environment(\.dismiss) private var dismiss
    @State private var items: [AccountHistory.Item] = []
    @State private var total = 0
    @State private var balance: Double?
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var loadedPage = 1
    @State private var errorMessage: String?

    private let pageSize = 50

    // Money in/out depends on the account's normal side: debit-normal accounts
    // (assets, expenses) grow with debits; credit-normal accounts are reversed.
    private var debitNormal: Bool { account.type == "ASSET" || account.type == "EXPENSE" }

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, items.isEmpty {
                    RetryView(message: errorMessage) { Task { await reload() } }
                } else if items.isEmpty {
                    EmptyStateView(text: "No activity on this account yet.")
                } else {
                    List {
                        Section {
                            RowLine(title: "Balance", trailing: AppFormat.money(balance ?? account.balance))
                        }
                        Section {
                            ForEach(items) { item in
                                historyRow(item)
                                    .onAppear {
                                        if item.id == items.last?.id { Task { await loadMore() } }
                                    }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(account.code) · \(account.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { if !loaded { await reload() } }
    }

    private func historyRow(_ item: AccountHistory.Item) -> some View {
        let moneyIn = debitNormal ? item.debit : item.credit
        let moneyOut = debitNormal ? item.credit : item.debit
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(AppFormat.shortDate(item.date))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
                if moneyOut > 0 {
                    Text("−\(AppFormat.money(moneyOut))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
                if moneyIn > 0 {
                    Text("+\(AppFormat.money(moneyIn))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
            }
            Text(item.memo ?? "—")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        do {
            let page = try await AccountingAPI().accountHistory(code: account.code, page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
            loadedPage = 1
            balance = page.account.balance
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the account history."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = loadedPage + 1
        if let page = try? await AccountingAPI().accountHistory(code: account.code, page: nextPage, pageSize: pageSize) {
            items.appendNewElements(from: page.items)
            total = page.total
            loadedPage = nextPage
        }
        loadingMore = false
    }
}

struct TransferFundsSheet: View {
    let accounts: [CashAccount]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var i18n: I18nStore
    @State private var fromCode: String
    @State private var toCode: String
    @State private var amount = ""
    @State private var fee = ""
    @State private var reference = ""
    @State private var note = ""
    @State private var checks: UndepositedChecks?
    @State private var checksError: String?
    @State private var loadingChecks = false
    @State private var checkedIds = Set<String>()
    @State private var today = CheckDates.string(Date())
    @State private var confirmationFor: CheckDepositDraft?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var submissionIdentity = FinanceSubmissionIdentity()
    @State private var submissionTask: Task<Void, Never>?
    @AccessibilityFocusState private var warningFocused: Bool

    init(
        accounts: [CashAccount],
        initialFromCode: String? = nil,
        initialToCode: String? = nil,
        onDone: @escaping () -> Void
    ) {
        self.accounts = accounts
        self.onDone = onDone
        let codes = accounts.map(\.code)
        _fromCode = State(initialValue: CheckDepositDraft.initialAccountCode(
            preset: initialFromCode, accountCodes: codes, fallbackIndex: 0
        ))
        _toCode = State(initialValue: CheckDepositDraft.initialAccountCode(
            preset: initialToCode, accountCodes: codes, fallbackIndex: 1
        ))
    }

    // An empty or failed check lookup must never turn account 1010 into a
    // manual-amount transfer, which would leave the check payments unlinked.
    private var isCheckDeposit: Bool { fromCode == "1010" }

    private var checkedItems: [UndepositedCheck] {
        (checks?.items ?? []).filter { checkedIds.contains($0.id) }
    }

    private var checkedTotal: Double { checkedItems.reduce(0) { $0 + $1.amount } }

    private var effectiveAmount: Double { isCheckDeposit ? checkedTotal : (Double(amount) ?? 0) }

    private var checksNeedingConfirmation: [UndepositedCheck] {
        guard isCheckDeposit else { return [] }
        return checkedItems.filter {
            let status = CheckDates.status(plannedDepositDate: $0.plannedDepositDate, asOf: today)
            return status == .future || status == .unscheduled
        }
    }

    private var draft: CheckDepositDraft { currentDraft(asOf: today) }

    private var confirmationVisible: Bool { draft.isConfirmed(by: confirmationFor) }

    private var submissionDisabled: Bool {
        saving || fromCode.isEmpty || toCode.isEmpty ||
        (isCheckDeposit && (checks == nil || checksError != nil || loadingChecks || checkedItems.isEmpty))
    }

    private func currentDraft(asOf day: String) -> CheckDepositDraft {
        CheckDepositDraft(
            fromCode: fromCode, toCode: toCode, amount: amount, fee: fee,
            reference: reference, note: note, today: day,
            selectedChecks: checkedItems.sorted { $0.id < $1.id }.map {
                CheckDepositDraft.SelectedCheck(id: $0.id, amount: $0.amount, plannedDepositDate: $0.plannedDepositDate)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    Section {
                        Picker(i18n.t("accounting.cash.fromAccount"), selection: $fromCode) {
                            Text(i18n.t("accounting.cash.selectAccount")).tag("")
                            ForEach(accounts) { account in
                                Text("\(account.code) — \(account.name)").tag(account.code)
                            }
                        }
                        Picker(i18n.t("accounting.cash.toAccount"), selection: $toCode) {
                            Text(i18n.t("accounting.cash.selectAccount")).tag("")
                            ForEach(accounts) { account in
                                Text("\(account.code) — \(account.name)").tag(account.code)
                            }
                        }
                    }

                    if isCheckDeposit {
                        checkSelectionSection
                    } else {
                        Section {
                            TextField(i18n.t("accounting.cash.amountDollars"), text: $amount)
                                .keyboardType(.decimalPad)
                        }
                    }

                    Section {
                        TextField(i18n.t("accounting.cash.feeDollars"), text: $fee)
                            .keyboardType(.decimalPad)
                        TextField(i18n.t("accounting.cash.referencePlaceholderTransfer"), text: $reference)
                            .accessibilityLabel(i18n.t("accounting.cash.referenceOptional"))
                        TextField(i18n.t("accounting.cash.noteOptional"), text: $note)
                    } footer: {
                        if let feeValue = Double(fee), feeValue > 0, effectiveAmount > 0 {
                            Text(i18n.t("accounting.cash.feeNote", [
                                "arrive": AppFormat.money(effectiveAmount - feeValue),
                                "fee": AppFormat.money(feeValue)
                            ]))
                        }
                    }

                    if confirmationVisible {
                        confirmationSection.id("deposit-warning")
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(Theme.danger).font(.subheadline)
                        }
                    }
                }
                .onChange(of: confirmationVisible) { _, visible in
                    if visible {
                        withAnimation { scroll.scrollTo("deposit-warning", anchor: .top) }
                        warningFocused = true
                    }
                }
            }
            .navigationTitle(i18n.t(isCheckDeposit ? "accounting.cash.depositChecksTitle" : "accounting.cash.transferTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("accounting.cash.cancel")) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t(saving ? "accounting.cash.transferring" :
                        (isCheckDeposit ? "accounting.cash.confirmDeposit" : "accounting.cash.confirmTransfer"))) {
                        startSubmission()
                    }
                    .disabled(submissionDisabled || confirmationVisible)
                }
            }
            .onChange(of: fromCode) { _, code in
                if code == "1010" {
                    toCode = accounts.contains { $0.code == "1020" } ? "1020" : ""
                }
            }
            .onChange(of: draft) { _, updated in
                if confirmationFor != updated { confirmationFor = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = CheckDates.string(Date()) }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                today = CheckDates.string(now)
            }
            .task { await loadChecks() }
            .interactiveDismissDisabled(saving)
            .onDisappear {
                if saving { submissionTask?.cancel() }
            }
        }
    }

    private var checkSelectionSection: some View {
        Section {
            if let checksError {
                Text(checksError).foregroundStyle(Theme.danger)
                Button(i18n.t("common.retry")) { Task { await loadChecks() } }
                    .disabled(loadingChecks)
            } else if loadingChecks || checks == nil {
                ProgressView(i18n.t("common.loading"))
            } else if let checks, checks.items.isEmpty {
                Text(i18n.t("checks.empty")).foregroundStyle(Theme.muted)
            } else if let checks {
                Button(i18n.t(checkedItems.count == checks.items.count ? "accounting.cash.deselectAll" : "accounting.cash.selectAll")) {
                    checkedIds = checkedItems.count == checks.items.count ? [] : Set(checks.items.map(\.id))
                }
                ForEach(checks.items) { check in
                    Button {
                        if checkedIds.contains(check.id) {
                            checkedIds.remove(check.id)
                        } else {
                            checkedIds.insert(check.id)
                        }
                    } label: {
                        checkRow(check)
                    }
                    .accessibilityAddTraits(checkedIds.contains(check.id) ? .isSelected : [])
                }
                HStack {
                    Text(i18n.t("accounting.cash.checksSelected", ["n": checkedItems.count]))
                    Spacer()
                    Text(AppFormat.money(checkedTotal))
                }
                .fontWeight(.semibold)
            }
        } header: {
            Text(i18n.t("accounting.cash.checksToDeposit"))
        }
    }

    private func checkRow(_ check: UndepositedCheck) -> some View {
        HStack(alignment: .top) {
            Image(systemName: checkedIds.contains(check.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checkedIds.contains(check.id) ? Theme.primary : Theme.muted)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.customerName + (check.reference.map { " · #\($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                Text(([CheckDisplay.received(check.createdAt, locale: i18n.language.locale)] + [check.receiptRef, check.invoiceRef].compactMap { $0 }).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text(i18n.t("payment.plannedDepositDate"))
                    .font(.caption)
                    .foregroundStyle(Theme.text)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        CheckDepositDateLabel(plannedDepositDate: check.plannedDepositDate, asOf: today)
                        checkStatusLabel(check)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        CheckDepositDateLabel(plannedDepositDate: check.plannedDepositDate, asOf: today)
                        checkStatusLabel(check)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 4)
            Text(AppFormat.money(check.amount))
                .font(.subheadline)
                .foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder
    private func checkStatusLabel(_ check: UndepositedCheck) -> some View {
        switch CheckDates.status(plannedDepositDate: check.plannedDepositDate, asOf: today) {
        case .future: Text(i18n.t("checks.notDueYet")).foregroundStyle(Theme.text)
        case .dueToday: Text(i18n.t("checks.dueToday")).foregroundStyle(Theme.text)
        case .overdue: Text(i18n.t("checks.overdue")).foregroundStyle(Theme.text)
        case .unscheduled: EmptyView()
        }
    }

    private var confirmationSection: some View {
        Section {
            Text(i18n.t("accounting.cash.depositWarningTitle"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($warningFocused)
            Text(i18n.t("accounting.cash.depositWarningBody"))
                .font(.subheadline)
            ForEach(checksNeedingConfirmation) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Text(([check.customerName] + [check.reference.map { "#\($0)" }, check.receiptRef, check.invoiceRef].compactMap { $0 }
                        + [AppFormat.money(check.amount)]).joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                    Text(check.plannedDepositDate.flatMap { CheckDates.isValid($0) ? $0 : nil }.map { date in
                        i18n.t("accounting.cash.depositWarningFuture", ["date": CheckDepositDateLabel.calendarLabel(date)])
                    } ?? i18n.t("accounting.cash.depositWarningUnscheduled"))
                        .font(.caption)
                }
            }
            Button(i18n.t("accounting.cash.reviewChecks")) { confirmationFor = nil }
            Button(i18n.t("accounting.cash.depositAnyway")) { startSubmission(confirmed: true) }
                .fontWeight(.semibold)
                .disabled(submissionDisabled)
        }
    }

    @MainActor
    private func loadChecks() async {
        guard !loadingChecks else { return }
        loadingChecks = true
        checksError = nil
        defer { loadingChecks = false }
        do {
            let response = try await CashAccountsAPI().undepositedChecks()
            guard !Task.isCancelled else { return }
            checks = response
            checkedIds.formIntersection(Set(response.items.map(\.id)))
        } catch {
            guard !Task.isCancelled else { return }
            checksError = (error as? LocalizedError)?.errorDescription ?? i18n.t("accounting.cash.checksLoadFailed")
        }
    }

    @MainActor
    private func submit(confirmed: Bool) async {
        guard accounts.contains(where: { $0.code == fromCode }), accounts.contains(where: { $0.code == toCode }) else {
            errorMessage = i18n.t("accounting.cash.selectAccount")
            return
        }
        guard fromCode != toCode else {
            errorMessage = i18n.t("accounting.cash.differentAccounts")
            return
        }
        if isCheckDeposit {
            guard checks != nil, checksError == nil, !loadingChecks else { return }
            guard !checkedItems.isEmpty else {
                errorMessage = i18n.t("accounting.cash.selectChecks")
                return
            }
        } else if !effectiveAmount.isFinite || effectiveAmount <= 0 {
            errorMessage = i18n.t("accounting.cash.enterPositiveAmount")
            return
        }
        let feeValue = fee.isEmpty ? 0 : Double(fee)
        guard let feeValue, feeValue.isFinite, feeValue >= 0 else {
            errorMessage = i18n.t("accounting.cash.enterValidFee")
            return
        }
        // Validate against the live shop day as well as the timer-backed view.
        // A suspended app or a tap at midnight cannot reuse yesterday's review.
        let liveToday = CheckDates.string(Date())
        let submittedDraft = currentDraft(asOf: liveToday)
        today = liveToday
        if submittedDraft.needsConfirmation && !(confirmed && submittedDraft.isConfirmed(by: confirmationFor)) {
            errorMessage = nil
            confirmationFor = submittedDraft
            return
        }
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let input = TransferCreateInput(
                fromCode: fromCode,
                toCode: toCode,
                amount: effectiveAmount,
                fee: feeValue,
                note: note.nilIfBlank,
                reference: reference.nilIfBlank,
                paymentIds: isCheckDeposit ? checkedItems.map(\.id).sorted() : nil
            )
            let idempotencyKey = try submissionIdentity.key(for: input)
            _ = try await CashAccountsAPI().createTransfer(input, idempotencyKey: idempotencyKey)
            saving = false
            onDone()
            dismiss()
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? i18n.t("accounting.cash.transferFailed")
            }
        }
    }

    private func startSubmission(confirmed: Bool = false) {
        guard submissionTask == nil, !saving else { return }
        submissionTask = Task { @MainActor in
            await submit(confirmed: confirmed)
            submissionTask = nil
        }
    }
}

private struct RecordExpenseSheet: View {
    let accounts: [CashAccount]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    @State private var expenseAccounts: [ExpenseAccount] = []
    @State private var vendors: [Vendor] = []
    @State private var expenseCode = ""
    @State private var paidFromCode = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var vendorId = ""
    @State private var payee = ""
    @State private var reference = ""
    @State private var note = ""
    @StateObject private var receiptSubmission = ExpenseReceiptSubmission()
    @State private var errorMessage: String?
    @State private var submissionIdentity = FinanceSubmissionIdentity()
    @State private var submissionTask: Task<Void, Never>?
    @State private var preparingReceipt = false
    @State private var confirmingFinishLater = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $expenseCode) {
                        Text("Select...").tag("")
                        ForEach(expenseAccounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                    Picker("Paid from", selection: $paidFromCode) {
                        ForEach(accounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                    TextField("Amount $", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                .disabled(receiptSubmission.createdExpenseId != nil)

                Section("Payee (optional)") {
                    Picker("Vendor", selection: $vendorId) {
                        Text("None").tag("")
                        ForEach(vendors) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    TextField("Payee name", text: $payee)
                }
                .disabled(receiptSubmission.createdExpenseId != nil)

                Section {
                    TextField("Reference (check #, invoice #)", text: $reference)
                    TextField("Note (optional)", text: $note)
                }
                .disabled(receiptSubmission.createdExpenseId != nil)

                Section {
                    ForEach(receiptSubmission.pendingReceipts) { receipt in
                        HStack {
                            Label(receipt.filename, systemImage: "doc")
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                            Button(role: .destructive) {
                                receiptSubmission.pendingReceipts.removeAll { $0.id == receipt.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(i18n.t("expenseReceipt.remove", ["filename": receipt.filename]))
                        }
                    }
                    DocumentUploadSourcePicker(disabled: receiptSubmission.saving, preparing: $preparingReceipt) { receipt in
                        receiptSubmission.pendingReceipts.append(receipt)
                        errorMessage = nil
                    } onError: { message in
                        errorMessage = message
                    }
                } header: {
                    Text(i18n.t("expenseReceipt.optional"))
                } footer: {
                    Text(i18n.t(receiptSubmission.createdExpenseId == nil ? "expenseReceipt.uploadAfterSave" : "expenseReceipt.saved"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Record expense")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(receiptSubmission.saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t(receiptSubmission.createdExpenseId == nil ? "common.cancel" : "expenseReceipt.finishLater")) {
                        if receiptSubmission.createdExpenseId != nil, !receiptSubmission.pendingReceipts.isEmpty {
                            confirmingFinishLater = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(receiptSubmission.saving || preparingReceipt)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitTitle) { startSubmission() }
                        .disabled(receiptSubmission.saving || preparingReceipt)
                }
            }
            .onAppear {
                if paidFromCode.isEmpty { paidFromCode = accounts.first?.code ?? "" }
            }
            .onChange(of: vendorId) {
                if let vendor = vendors.first(where: { $0.id == vendorId }) {
                    payee = vendor.name
                }
            }
            .task {
                if expenseAccounts.isEmpty {
                    do {
                        expenseAccounts = try await AccountingAPI().expenseAccounts()
                        if expenseCode.isEmpty { expenseCode = expenseAccounts.first?.code ?? "" }
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load expense categories."
                    }
                    vendors = (try? await VendorsAPI().list(active: true, pageSize: 200).items) ?? []
                }
            }
            .interactiveDismissDisabled(receiptSubmission.saving || preparingReceipt || (receiptSubmission.createdExpenseId != nil && !receiptSubmission.pendingReceipts.isEmpty))
            .alert(i18n.t("expenseReceipt.finishLaterTitle"), isPresented: $confirmingFinishLater) {
                Button(i18n.t("common.cancel"), role: .cancel) {}
                Button(i18n.t("expenseReceipt.finishLater")) { dismiss() }
            } message: {
                Text(i18n.t("expenseReceipt.finishLaterMessage"))
            }
            .onDisappear {
                if receiptSubmission.saving {
                    submissionTask?.cancel()
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard let value = Double(amount), value.isFinite, value > 0 else {
            errorMessage = "Enter a positive amount"
            return
        }
        guard !expenseCode.isEmpty else {
            errorMessage = "Select a category"
            return
        }
        guard !paidFromCode.isEmpty else {
            errorMessage = "Select the account it was paid from"
            return
        }
        errorMessage = nil

        do {
            try await receiptSubmission.submit {
                let input = ExpenseCreateInput(
                    amount: value,
                    expenseCode: expenseCode,
                    paidFromCode: paidFromCode,
                    date: FinanceDay.string(date),
                    payee: payee.nilIfBlank,
                    vendorId: vendorId.nilIfBlank,
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank
                )
                let idempotencyKey = try submissionIdentity.key(for: input)
                return try await CashAccountsAPI().createExpense(
                    input,
                    idempotencyKey: idempotencyKey
                )
            } upload: { expenseId, receipt in
                _ = try await CashAccountsAPI().uploadExpenseReceipt(
                    expenseId: expenseId,
                    fileURL: receipt.url,
                    fileName: receipt.filename,
                    mimeType: receipt.mimeType
                )
            }
            onDone()
            dismiss()
        } catch {
            if !Task.isCancelled {
                let detail = (error as? LocalizedError)?.errorDescription ?? "Could not record the expense."
                errorMessage = receiptSubmission.createdExpenseId == nil
                    ? detail
                    : i18n.t("expenseReceipt.uploadFailedAfterSave", ["error": detail])
                if receiptSubmission.createdExpenseId != nil { onDone() }
            }
        }
    }

    private var submitTitle: String {
        if receiptSubmission.saving {
            return i18n.t(receiptSubmission.createdExpenseId == nil ? "expenseReceipt.recording" : "expenseReceipt.uploading")
        }
        if receiptSubmission.createdExpenseId != nil {
            return i18n.t(receiptSubmission.pendingReceipts.isEmpty ? "common.done" : "expenseReceipt.retry")
        }
        return i18n.t("expenseReceipt.record")
    }

    private func startSubmission() {
        guard submissionTask == nil else { return }
        submissionTask = Task { @MainActor in
            await submit()
            submissionTask = nil
        }
    }
}

private struct AddPaymentMethodSheet: View {
    let accounts: [CashAccount]
    var editing: PaymentMethod?
    let onDone: () -> Void

    init(accounts: [CashAccount], editing: PaymentMethod? = nil, onDone: @escaping () -> Void) {
        self.accounts = accounts
        self.editing = editing
        self.onDone = onDone
        _name = State(initialValue: editing?.name ?? "")
        _accountCode = State(initialValue: editing?.account.code ?? "")
        _payoutAccountCode = State(initialValue: editing?.payoutAccount?.code ?? "")
        _feeRatePercent = State(initialValue: editing.flatMap { $0.feeRate.flatMap(Double.init) }.map { String(format: "%.2f", $0 * 100) } ?? "")
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var accountCode: String
    @State private var payoutAccountCode: String
    @State private var feeRatePercent: String
    @State private var saving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { editing != nil }

    /// Parsed fee rate (fraction) or `nil` when the field is blank.
    private var feeRateValue: Double? {
        guard let trimmed = feeRatePercent.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { return nil }
        return AppFormat.parseAmount(trimmed).map { $0 / 100 }
    }

    /// True when the fee field has content that can't be parsed as a number or
    /// falls outside the accepted 0–100% range.
    private var feeRateInvalid: Bool {
        let trimmed = feeRatePercent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let value = AppFormat.parseAmount(trimmed) else { return true }
        return value < 0 || value > 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Venmo)", text: $name)
                    Picker("Linked account", selection: $accountCode) {
                        Text("Select...").tag("")
                        ForEach(accounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                    Picker("Pays out to", selection: $payoutAccountCode) {
                        Text("Select...").tag("")
                        ForEach(accounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                    TextField("Fee rate % (optional)", text: $feeRatePercent)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Payments taken with this method post to the linked cash account; outgoing commission/refund payouts use the pays-out-to account.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit payment method" : "Add payment method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : (isEditing ? "Save" : "Add")) { Task { await submit() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || accountCode.isEmpty || feeRateInvalid)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        saving = true
        errorMessage = nil
        do {
            if let editing {
                _ = try await CashAccountsAPI().updateMethod(
                    id: editing.id,
                    body: PaymentMethodPatchInput(
                        name: name.trimmingCharacters(in: .whitespaces),
                        accountCode: accountCode,
                        feeRate: .some(feeRateValue),
                        payoutAccountCode: .some(payoutAccountCode.nilIfBlank)
                    )
                )
            } else {
                _ = try await CashAccountsAPI().createMethod(
                    PaymentMethodCreateInput(
                        name: name.trimmingCharacters(in: .whitespaces),
                        accountCode: accountCode,
                        feeRate: feeRateValue,
                        payoutAccountCode: payoutAccountCode.nilIfBlank
                    )
                )
            }
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the payment method."
        }
        saving = false
    }
}

private struct ExpenseReceiptsSheet: View {
    let expense: ExpensePayment
    let canManage: Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    @State private var receipts: [ExpenseReceipt] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var preparingReceipt = false
    @State private var pendingUpload: DocumentUploadDraft?
    @State private var confirmingDiscardAndClose = false
    @State private var preview: PreviewFile?
    @State private var deleteTarget: ExpenseReceipt?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RowLine(
                        title: expense.expenseName,
                        subtitle: expense.payee?.nilIfBlank,
                        trailing: AppFormat.money(expense.amount)
                    )
                }

                Section("Receipts") {
                    if loaded && receipts.isEmpty {
                        Text("No receipts attached.").foregroundStyle(Theme.muted)
                    }
                    ForEach(receipts) { receipt in
                        Button {
                            Task { await open(receipt) }
                        } label: {
                            RowLine(
                                title: receipt.filename,
                                subtitle: AppFormat.shortDate(receipt.createdAt),
                                trailing: "\(receipt.size / 1024) KB"
                            )
                        }
                        .tint(Theme.text)
                        .swipeActions {
                            if canManage {
                                Button("Delete", role: .destructive) { deleteTarget = receipt }
                                    .disabled(busy || preparingReceipt)
                            }
                        }
                    }
                    if canManage {
                        if let pendingUpload {
                            Text(pendingUpload.filename)
                                .font(.subheadline)
                            if busy {
                                ProgressView(i18n.t("expenseReceipt.uploading"))
                            } else {
                                Button(i18n.t("expenseReceipt.retry")) { Task { await uploadPending() } }
                                Button(i18n.t("expenseReceipt.discard"), role: .destructive) {
                                    self.pendingUpload = nil
                                    errorMessage = nil
                                }
                            }
                        }
                        DocumentUploadSourcePicker(
                            disabled: busy || pendingUpload != nil,
                            preparing: $preparingReceipt
                        ) { receipt in
                            pendingUpload = receipt
                            Task { await uploadPending() }
                        } onError: { message in
                            errorMessage = message
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Expense receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if pendingUpload != nil {
                            confirmingDiscardAndClose = true
                        } else {
                            dismiss()
                            onChanged()
                        }
                    }
                    .disabled(busy || preparingReceipt)
                }
            }
            .interactiveDismissDisabled(busy || preparingReceipt || pendingUpload != nil)
            .sheet(item: $preview) { file in
                QuickLookSheet(url: file.url)
            }
            .alert(i18n.t("documentUpload.leaveTitle"), isPresented: $confirmingDiscardAndClose) {
                Button(i18n.t("common.cancel"), role: .cancel) {}
                Button(i18n.t("documentUpload.discardAndLeave"), role: .destructive) {
                    pendingUpload = nil
                    dismiss()
                    onChanged()
                }
            } message: {
                Text(i18n.t("documentUpload.leaveMessage"))
            }
            .alert("Delete this receipt?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .task { if !loaded { await reload() } }
    }

    @MainActor
    private func reload() async {
        do {
            receipts = try await CashAccountsAPI().expenseReceipts(expenseId: expense.id)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load receipts."
        }
        loaded = true
    }

    @MainActor
    private func open(_ receipt: ExpenseReceipt) async {
        errorMessage = nil
        do {
            let url = try await CashAccountsAPI().downloadExpenseReceipt(receipt)
            preview = PreviewFile(url: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not open the receipt."
        }
    }

    @MainActor
    private func uploadPending() async {
        guard canManage, !busy, let pendingUpload else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            _ = try await CashAccountsAPI().uploadExpenseReceipt(
                expenseId: expense.id,
                fileURL: pendingUpload.url,
                fileName: pendingUpload.filename,
                mimeType: pendingUpload.mimeType
            )
            self.pendingUpload = nil
            await reload()
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not upload the receipt."
        }
    }

    @MainActor
    private func remove() async {
        guard canManage, !busy, !preparingReceipt, let target = deleteTarget else { return }
        deleteTarget = nil
        busy = true
        do {
            _ = try await CashAccountsAPI().deleteExpenseReceipt(id: target.id)
            await reload()
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete the receipt."
        }
        busy = false
    }

}

// MARK: - FET (federal excise tax)

struct FetNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var status: FetStatus?
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var paySheet: FetPayTarget?
    @State private var reverseTarget: FetStatus.Payment?

    private var canManage: Bool { auth.has("accounting.manage") }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, status == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let status {
                content(status)
            }
        }
        .background(Theme.background)
        .task { if !loaded { await load() } }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Record payment") {
                        paySheet = FetPayTarget(quarter: nil)
                    }
                }
            }
        }
        .sheet(item: $paySheet) { target in
            PayFetSheet(payable: status?.payable ?? 0, quarter: target.quarter) {
                Task { await load() }
            }
        }
        .alert("Reverse this FET payment?", isPresented: Binding(
            get: { reverseTarget != nil },
            set: { if !$0 { reverseTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { reverseTarget = nil }
            Button("Reverse", role: .destructive) { Task { await reverse() } }
        }
    }

    private func content(_ status: FetStatus) -> some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("FET OWED TO THE IRS")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.muted)
                    Text(AppFormat.money(status.payable))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(status.payable > 0.005 ? .orange : status.payable < -0.005 ? .red : .green)
                }
                .padding(.vertical, Theme.Space.xs)
            } footer: {
                Text("Federal excise tax accrues on each taxable tire sold and is reported quarterly on IRS Form 720.")
            }

            Section("Form 720 quarters") {
                if status.quarters.isEmpty {
                    Text("No FET accrued yet.").foregroundStyle(Theme.muted)
                }
                ForEach(status.quarters, id: \.key) { quarter in
                    quarterRow(quarter, status: status)
                }
            }

            Section("Payment history") {
                if status.payments.isEmpty {
                    Text("No FET payments recorded.").foregroundStyle(Theme.muted)
                }
                ForEach(status.payments) { payment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(AppFormat.shortDate(payment.date))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text(AppFormat.money(payment.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Text(payment.memo ?? "—")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                    }
                    .swipeActions {
                        if canManage {
                            Button("Reverse", role: .destructive) { reverseTarget = payment }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private func quarterRow(_ quarter: FetQuarter, status: FetStatus) -> some View {
        let overdue = quarter.fetDue > 0.005 && quarter.formDueDate < FinanceDay.todayString
        let paid = (status.paidPerQuarter[quarter.key] ?? 0) >= quarter.fetDue - 0.005
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(quarter.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(AppFormat.money(quarter.fetDue))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text("\(FinanceDay.calendar(quarter.periodStart)) – \(FinanceDay.calendar(quarter.periodEnd))")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            HStack {
                Text("Form 720 due \(FinanceDay.calendar(quarter.formDueDate))\(overdue ? " — OVERDUE" : "")")
                    .font(.caption)
                    .foregroundStyle(overdue ? .red : Theme.muted)
                Spacer()
                Text(quarter.depositRequired ? "Semimonthly EFTPS deposits" : "Pay with return")
                    .font(.caption)
                    .foregroundStyle(quarter.depositRequired ? .orange : Theme.muted)
            }
            if canManage && quarter.fetDue > 0.005 {
                if paid {
                    Text("Paid")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                } else {
                    Button("Pay this quarter") {
                        paySheet = FetPayTarget(quarter: quarter)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            status = try await FetAPI().status()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load FET status."
        }
        loaded = true
    }

    @MainActor
    private func reverse() async {
        guard let target = reverseTarget else { return }
        reverseTarget = nil
        do {
            _ = try await FetAPI().reversePayment(refId: target.refId)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reverse the payment."
        }
    }
}

private struct FetPayTarget: Identifiable {
    let quarter: FetQuarter?
    var id: String { quarter?.key ?? "full" }
}

private struct PayFetSheet: View {
    let payable: Double
    let quarter: FetQuarter?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date()
    @State private var reference = ""
    @State private var note = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var submissionIdentity = FinanceSubmissionIdentity()
    @State private var submissionTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount $", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Payment date", selection: $date, displayedComponents: .date)
                    if payable > 0.005 {
                        Button("Pay full balance (\(AppFormat.money(payable)))") {
                            amount = String(format: "%.2f", payable)
                        }
                    }
                }

                Section {
                    TextField("Reference (EFTPS confirmation #)", text: $reference)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Posts a journal entry moving the amount out of the bank and clearing the FET payable.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle(quarter.map { "Pay \($0.label)" } ?? "Record FET payment")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Recording..." : "Record") { startSubmission() }
                        .disabled(saving)
                }
            }
            .onAppear {
                if amount.isEmpty {
                    if let quarter {
                        amount = String(format: "%.2f", quarter.fetDue)
                        reference = "IRS Form 720 — \(quarter.label)"
                    } else if payable > 0 {
                        amount = String(format: "%.2f", payable)
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .onDisappear {
                if saving {
                    submissionTask?.cancel()
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard let value = Double(amount), value > 0 else {
            errorMessage = "Enter a positive amount"
            return
        }
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let input = FetPayInput(
                amount: value,
                date: FinanceDay.string(date),
                reference: reference.nilIfBlank,
                note: note.nilIfBlank,
                quarterKey: quarter?.key
            )
            let idempotencyKey = try submissionIdentity.key(for: input)
            _ = try await FetAPI().pay(
                input,
                idempotencyKey: idempotencyKey
            )
            saving = false
            onDone()
            dismiss()
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
            }
        }
    }

    private func startSubmission() {
        guard submissionTask == nil else { return }
        submissionTask = Task { @MainActor in
            await submit()
            submissionTask = nil
        }
    }
}

// MARK: - End of day report

struct EodNativeView: View {
    @State private var date = Date()
    @State private var report: EodReport?
    @State private var loading = false
    @State private var errorMessage: String?

    private var requestDay: String {
        FinanceDay.string(date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                DatePicker("Report date", selection: $date, in: ...Date(), displayedComponents: .date)

                if loading {
                    HStack {
                        ProgressView()
                        Text("Loading...").foregroundStyle(Theme.muted)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                if let report, !loading {
                    StatGrid(stats: [
                        ("Sales invoiced", AppFormat.money(report.sales.summary.total)),
                        ("Payments collected", AppFormat.money(report.payments.summary.total)),
                        ("Expenses paid", AppFormat.money(report.expenses.total)),
                        ("Net income", AppFormat.money(report.pnl.netIncome))
                    ])

                    salesPanel(report)
                    paymentsPanel(report)
                    expensesPanel(report)
                    pnlPanel(report)
                    if !report.cashMovement.isEmpty {
                        cashMovementPanel(report)
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.background)
        .task(id: requestDay) { await load(requestDay) }
        .refreshable { await load(requestDay) }
    }

    private func panel<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border))
    }

    private func salesPanel(_ report: EodReport) -> some View {
        panel(
            "Sales",
            subtitle: "\(report.sales.summary.count) invoice(s) · subtotal \(AppFormat.money(report.sales.summary.subtotal)) · tax \(AppFormat.money(report.sales.summary.tax))"
        ) {
            if report.sales.items.isEmpty {
                Text("No sales this day.").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.sales.items.enumerated()), id: \.offset) { _, sale in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(sale.saleRef ?? "—")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(AppFormat.money(sale.total))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text("\(AppFormat.dateTime(sale.at)) · \(sale.customer) · \(sale.soldBy)")
                                    .lineLimit(1)
                                Spacer()
                                Text(sale.status)
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, Theme.Space.xs)
                        Divider()
                    }
                    HStack {
                        Text("Total").fontWeight(.semibold)
                        Spacer()
                        Text(AppFormat.money(report.sales.summary.total)).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .padding(.top, Theme.Space.xs)
                }
            }
        }
    }

    private func paymentsPanel(_ report: EodReport) -> some View {
        panel(
            "Payments",
            subtitle: "\(report.payments.summary.count) payment(s) · \(AppFormat.money(report.payments.summary.total))"
        ) {
            if report.payments.items.isEmpty {
                Text("No payments this day.").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(report.payments.byMethod, id: \.method) { m in
                            Text("\(m.method): \(AppFormat.money(m.amount)) (\(m.count))")
                                .font(.caption)
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, 4)
                                .background(Theme.background)
                                .clipShape(Capsule())
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(report.payments.items.enumerated()), id: \.offset) { _, payment in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payment.method)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(AppFormat.dateTime(payment.at))\(payment.reference.map { " · \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AppFormat.money(payment.amount))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if payment.surcharge > 0 {
                                    Text("+\(AppFormat.money(payment.surcharge)) fee")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                        Divider()
                    }
                }
            }
        }
    }

    private func expensesPanel(_ report: EodReport) -> some View {
        panel(
            "Expenses",
            subtitle: "\(report.expenses.items.count) payment(s) · \(AppFormat.money(report.expenses.total))"
        ) {
            if report.expenses.items.isEmpty {
                Text("No expenses this day.").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.expenses.items.enumerated()), id: \.offset) { _, expense in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.memo ?? "—")
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(AppFormat.dateTime(expense.at))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(AppFormat.money(expense.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, Theme.Space.xs)
                        Divider()
                    }
                }
            }
        }
    }

    private func pnlPanel(_ report: EodReport) -> some View {
        panel("Profit & loss") {
            pnlList("Revenue", rows: report.pnl.revenue, total: report.pnl.revenueTotal)
            pnlList("Expenses (incl. COGS)", rows: report.pnl.expenses, total: report.pnl.expensesTotal)
            Divider()
            HStack {
                Text("Net income").fontWeight(.bold)
                Spacer()
                Text(AppFormat.money(report.pnl.netIncome))
                    .fontWeight(.bold)
                    .foregroundStyle(report.pnl.netIncome >= 0 ? Color.green : Color.red)
            }
        }
    }

    private func pnlList(_ title: String, rows: [Pnl.Line], total: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if rows.isEmpty {
                Text("No activity.").font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(rows, id: \.code) { row in
                HStack {
                    Text("\(row.code) \(row.name)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(AppFormat.money(row.total))
                        .font(.caption)
                }
            }
            HStack {
                Text("Total \(title.lowercased())")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(AppFormat.money(total))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }

    private func cashMovementPanel(_ report: EodReport) -> some View {
        panel("Cash movement") {
            VStack(spacing: 0) {
                ForEach(report.cashMovement, id: \.code) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(row.code) · in \(AppFormat.money(row.incoming)) · out \(AppFormat.money(row.out))")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(AppFormat.money(row.net))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(row.net >= 0 ? Color.green : Color.red)
                    }
                    .padding(.vertical, Theme.Space.xs)
                    Divider()
                }
            }
        }
    }

    @MainActor
    private func load(_ day: String) async {
        loading = true
        errorMessage = nil
        do {
            let loaded = try await EodAPI().report(date: day)
            guard day == requestDay, !Task.isCancelled else { return }
            report = loaded
            loading = false
        } catch {
            guard day == requestDay, !Task.isCancelled, !isFinanceRequestCancellation(error) else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the report."
            report = nil
            loading = false
        }
    }
}

private func isFinanceRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }

    return (error as? URLError)?.code == .cancelled
}

private func financeResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) }
    catch { return .failure(error) }
}
