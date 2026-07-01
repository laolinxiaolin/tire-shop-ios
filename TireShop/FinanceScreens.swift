import SwiftUI

// Full-featured finance screens ported from the web UI:
// apps/web/app/{money,accounting,accounting/cash,accounting/fet,accounting/eod}.
// Money = AR/AP ledgers + numbered settlement documents; Accounting = P&L /
// trial balance / journal; Cash = balances, transfers, expenses, methods.

// MARK: - Shared helpers

private enum FinanceDay {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }

    static var todayString: String { string(Date()) }

    static var monthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    /// Format a plain calendar date (yyyy-MM-dd) without any timezone shift.
    static func calendar(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count == 3 else { return s }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)/\(parts[0])"
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

private struct AgingBuckets {
    var current = 0.0
    var b30 = 0.0
    var b60 = 0.0
    var b90 = 0.0
}

/// Split rows into aging buckets (current / 31-60 / 61-90 / 90+) by ageDays.
private func bucketize<T>(_ rows: [T], age: (T) -> Int, amount: (T) -> Double) -> AgingBuckets {
    var b = AgingBuckets()
    for r in rows {
        let a = amount(r)
        switch age(r) {
        case ..<31: b.current += a
        case ..<61: b.b30 += a
        case ..<91: b.b60 += a
        default: b.b90 += a
        }
    }
    return b
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
    let buckets: AgingBuckets

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
        case receivables = "Receivables"
        case payables = "Payables"
        case history = "History"
    }

    @EnvironmentObject private var auth: AuthStore
    @State private var tab: Tab = .receivables

    private var tabs: [Tab] {
        var available: [Tab] = []
        if auth.has("receivables.view") { available.append(.receivables) }
        if auth.has("payables.view") { available.append(.payables) }
        if !available.isEmpty { available.append(.history) }
        return available
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("Section", selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.sm)
            }

            switch tab {
            case .receivables: ReceivablesTabView()
            case .payables: PayablesTabView()
            case .history: MoneyDocumentsTabView()
            }
        }
        .background(Theme.background)
        .onAppear {
            if !tabs.contains(tab), let first = tabs.first { tab = first }
        }
    }
}

private struct ReceivablesTabView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var items: [ReceivableCustomer] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var q = ""
    @State private var collectTarget: ReceivableCustomer?
    @State private var emailTarget: ReceivableCustomer?
    @State private var statementPreview: PreviewFile?
    @State private var downloadingStatement = false

    private let pageSize = 50

    private var filtered: [ReceivableCustomer] {
        guard let term = q.nilIfBlank?.lowercased() else { return items }
        return items.filter {
            $0.customer.name.lowercased().contains(term)
                || ($0.customer.company ?? "").lowercased().contains(term)
                || String(format: "%.2f", $0.openBalance).contains(term)
        }
    }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else {
                List {
                    Section {
                        summaryHeader
                    }

                    Section {
                        if items.isEmpty {
                            Text("Nothing outstanding. Every invoice is paid.")
                                .foregroundStyle(Theme.muted)
                        } else if filtered.isEmpty {
                            Text("No customers match \"\(q)\".")
                                .foregroundStyle(Theme.muted)
                        }

                        ForEach(filtered, id: \.customer.id) { row in
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
                .searchable(text: $q, prompt: "Search customers")
            }
        }
        .task { if !loaded { await reload() } }
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

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(q.nilIfBlank == nil ? "TOTAL OPEN A/R" : "FILTERED OPEN A/R")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.muted)
            Text(AppFormat.money(filtered.reduce(0) { $0 + $1.openBalance }))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.text)
            Text("Across \(filtered.count) customer\(filtered.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            AgingStripView(buckets: bucketize(filtered, age: \.ageDays, amount: \.openBalance))
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
        do {
            let page = try await MoneyAPI().receivables(page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load receivables."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = items.count / pageSize + 1
        if let page = try? await MoneyAPI().receivables(page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
        }
        loadingMore = false
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
    @Environment(\.dismiss) private var dismiss

    @State private var detail: ReceivableCustomerDetail?
    @State private var methods: [PaymentMethod] = []
    @State private var paymentMethodId = ""
    @State private var reference = ""
    @State private var note = ""
    @State private var bulkAmount = ""
    @State private var allocations: [String: String] = [:]
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var postedRef: String?

    private var canCollect: Bool { auth.has("payments.collect") }

    private var totalApplied: Double {
        allocations.values.reduce(0) { $0 + (Double($1) ?? 0) }
    }

    private var applications: [ReceivableApplication] {
        (detail?.openInvoices ?? []).compactMap { inv in
            let amount = Double(allocations[inv.id] ?? "") ?? 0
            return amount > 0 ? ReceivableApplication(invoiceId: inv.id, amount: amount) : nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    form(detail)
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading open invoices...")
                }
            }
            .navigationTitle(customer.company?.nilIfBlank ?? customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if canCollect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Posting..." : "Collect") { Task { await submit() } }
                            .disabled(busy || totalApplied <= 0)
                    }
                }
            }
            .alert("Payment recorded", isPresented: Binding(
                get: { postedRef != nil },
                set: { if !$0 { postedRef = nil; onPaid(); dismiss() } }
            )) {
                Button("OK") {}
            } message: {
                Text("Receipt # \(postedRef ?? "")")
            }
        }
        .task { if detail == nil { await load() } }
    }

    private func form(_ detail: ReceivableCustomerDetail) -> some View {
        Form {
            if canCollect {
                Section("Payment") {
                    Picker("Method", selection: $paymentMethodId) {
                        ForEach(methods) { m in
                            Text(m.name).tag(m.id)
                        }
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
                    Text("Or type an amount on each invoice below.")
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
                                    set: { allocations[inv.id] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if canCollect {
                    HStack {
                        Text("Total applied")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(AppFormat.money(totalApplied))
                            .fontWeight(.semibold)
                    }
                }
            }

            if canCollect, let fee = feeNote {
                Section {
                    Text(fee)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
        }
    }

    private var feeNote: String? {
        guard let method = methods.first(where: { $0.id == paymentMethodId }),
              let rate = method.feeRate.flatMap(Double.init), rate > 0, totalApplied > 0
        else { return nil }
        let fee = (totalApplied * rate * 100).rounded() / 100
        return "A \(String(format: "%.1f", rate * 100))% card fee applies: +\(AppFormat.money(fee)) (customer pays \(AppFormat.money(totalApplied + fee)))."
    }

    private func collectAllInFull(_ detail: ReceivableCustomerDetail) {
        bulkAmount = String(format: "%.2f", detail.totalBalance)
        split(detail, total: detail.totalBalance)
    }

    private func applyOldestFirst(_ detail: ReceivableCustomerDetail) {
        guard let total = Double(bulkAmount), total > 0 else {
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
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            async let d = MoneyAPI().receivable(customerId: customer.id)
            async let ms = CashAccountsAPI().methods()
            let (loadedDetail, loadedMethods) = try await (d, ms)
            detail = loadedDetail
            methods = loadedMethods.filter(\.isActive)
            if paymentMethodId.isEmpty { paymentMethodId = methods.first?.id ?? "" }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load invoices."
        }
    }

    @MainActor
    private func submit() async {
        guard !applications.isEmpty else {
            errorMessage = "Enter an amount for at least one invoice."
            return
        }
        busy = true
        errorMessage = nil
        do {
            let result = try await MoneyAPI().payReceivables(
                ReceivablesPayInput(
                    customerId: customer.id,
                    paymentMethodId: paymentMethodId,
                    applications: applications,
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank
                )
            )
            if let ref = result.ref {
                postedRef = ref
            } else {
                onPaid()
                dismiss()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
        }
        busy = false
    }
}

private struct PayablesTabView: View {
    @State private var items: [PayableVendor] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var q = ""
    @State private var payTarget: PayableVendor?

    private let pageSize = 50

    private var filtered: [PayableVendor] {
        guard let term = q.nilIfBlank?.lowercased() else { return items }
        return items.filter {
            ($0.vendor ?? "").lowercased().contains(term)
                || String(format: "%.2f", $0.totalDue).contains(term)
        }
    }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, items.isEmpty {
                RetryView(message: errorMessage) { Task { await reload() } }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text(q.nilIfBlank == nil ? "TOTAL OPEN A/P" : "FILTERED OPEN A/P")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.muted)
                            Text(AppFormat.money(filtered.reduce(0) { $0 + $1.totalDue }))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.text)
                            Text("Across \(filtered.count) vendor\(filtered.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            AgingStripView(buckets: bucketize(filtered, age: \.ageDays, amount: \.totalDue))
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }

                    Section {
                        if items.isEmpty {
                            Text("Nothing owed. All container costs are settled.")
                                .foregroundStyle(Theme.muted)
                        } else if filtered.isEmpty {
                            Text("No vendors match \"\(q)\".")
                                .foregroundStyle(Theme.muted)
                        }

                        ForEach(filtered, id: \.vendorKey) { row in
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
                            .onAppear {
                                if row.vendorKey == items.last?.vendorKey { Task { await loadMore() } }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await reload() }
                .searchable(text: $q, prompt: "Search vendors")
            }
        }
        .task { if !loaded { await reload() } }
        .sheet(item: $payTarget) { target in
            PayVendorSheet(vendorKey: target.vendorKey) {
                Task { await reload() }
            }
        }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        do {
            let page = try await MoneyAPI().payables(page: 1, pageSize: pageSize)
            items = page.items
            total = page.total
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load payables."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = items.count / pageSize + 1
        if let page = try? await MoneyAPI().payables(page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
        }
        loadingMore = false
    }
}

extension PayableVendor: Identifiable {
    var id: String { vendorKey }
}

private struct PayVendorSheet: View {
    let vendorKey: String
    let onPaid: () -> Void

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

    private var applications: [PayableApplication] {
        (detail?.items ?? []).compactMap { item in
            let amount = Double(amounts[item.id] ?? "") ?? 0
            return amount > 0 ? PayableApplication(costId: item.id, amount: amount) : nil
        }
    }

    private var totalSelected: Double {
        applications.reduce(0) { $0 + $1.amount }
    }

    private var overpaidRows: Set<String> {
        var rows = Set<String>()
        for item in detail?.items ?? [] where (Double(amounts[item.id] ?? "") ?? 0) - item.remaining > 0.01 {
            rows.insert(item.id)
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    form(detail)
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
            .navigationTitle(detail?.vendor ?? "Pay vendor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving..." : "Pay \(AppFormat.money(totalSelected))") { Task { await submit() } }
                        .disabled(busy || totalSelected <= 0 || !overpaidRows.isEmpty || pendingApproval)
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
    }

    private func form(_ detail: PayableVendorDetail) -> some View {
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
                        Text("\(item.container.ref ?? item.container.id) · \(item.container.supplier.name)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
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
                        if overpaidRows.contains(item.id) {
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
                    Text(AppFormat.money(totalSelected))
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
        busy = true
        errorMessage = nil
        do {
            let result = try await MoneyAPI().payPayables(
                PayablesPayInput(
                    applications: applications,
                    paidAt: FinanceDay.string(paidAt),
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank,
                    accountId: accountId.nilIfBlank
                )
            )
            if result.approvalRequest != nil {
                approvalQueued = true
            } else if let ref = result.ref {
                postedRef = ref
            } else {
                onPaid()
                dismiss()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
        }
        busy = false
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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load receipts."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = items.count / pageSize + 1
        if let page = try? await MoneyAPI().receipts(page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load supplier payments."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = items.count / pageSize + 1
        if let page = try? await MoneyAPI().supplierPayments(page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
        }
        loadingMore = false
    }
}

private struct SupplierPaymentDetailSheet: View {
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
                                    subtitle: line.container.ref ?? line.container.id,
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

private struct PnlTabView: View {
    @State private var from = FinanceDay.monthStart
    @State private var to = Date()
    @State private var pnl: Pnl?
    @State private var loading = false
    @State private var errorMessage: String?

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
        .refreshable { await load() }
        .task { if pnl == nil { await load() } }
        .onChange(of: from) { Task { await load() } }
        .onChange(of: to) { Task { await load() } }
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
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            pnl = try await AccountingAPI().pnl(from: FinanceDay.string(from), to: FinanceDay.string(to))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the P&L."
        }
        loading = false
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
    return nil
}

private struct JournalTabView: View {
    @State private var items: [JournalEntry] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loadingMore = false
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
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the journal."
        }
        loaded = true
    }

    @MainActor
    private func loadMore() async {
        guard !loadingMore, items.count < total else { return }
        loadingMore = true
        let nextPage = items.count / pageSize + 1
        if let page = try? await AccountingAPI().journal(page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
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

    @State private var accounts: [CashAccount] = []
    @State private var transfers: [CashTransfer] = []
    @State private var methods: [PaymentMethod] = []
    @State private var expenses: [ExpensePayment] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    @State private var showingTransfer = false
    @State private var showingExpense = false
    @State private var showingAddMethod = false
    @State private var historyAccount: CashAccount?
    @State private var receiptsExpense: ExpensePayment?
    @State private var reverseTransferTarget: CashTransfer?
    @State private var reverseExpenseTarget: ExpensePayment?
    @State private var deleteMethodTarget: PaymentMethod?

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
                        Button { showingTransfer = true } label: { Label("Transfer funds", systemImage: "arrow.left.arrow.right") }
                        Button { showingExpense = true } label: { Label("Record expense", systemImage: "minus.circle") }
                        Button { showingAddMethod = true } label: { Label("Add payment method", systemImage: "creditcard") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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

            Section("Transfer history") {
                if transfers.isEmpty {
                    Text("No transfers yet.").foregroundStyle(Theme.muted)
                }
                ForEach(transfers) { transfer in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(transfer.fromAccount.name) → \(transfer.toAccount.name)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Spacer()
                            Text(AppFormat.money(transfer.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text(AppFormat.shortDate(transfer.createdAt))
                            if let fee = Double(transfer.fee), fee > 0 {
                                Text("· fee \(AppFormat.money(fee))")
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
                        if canManage {
                            Button("Reverse", role: .destructive) { reverseTransferTarget = transfer }
                        }
                    }
                }
            }

            Section("Operating expenses") {
                if expenses.isEmpty {
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
                                Text(FinanceDay.calendar(String(expense.date.prefix(10))))
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
                }
            }

            Section("Payment methods") {
                if methods.isEmpty {
                    Text("No payment methods.").foregroundStyle(Theme.muted)
                }
                ForEach(methods) { method in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("\(method.account.code) \(method.account.name)\(feeLabel(method))")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
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
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private func feeLabel(_ method: PaymentMethod) -> String {
        guard let rate = method.feeRate.flatMap(Double.init), rate > 0 else { return "" }
        return String(format: " · %.2f%% fee", rate * 100)
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            async let a = CashAccountsAPI().list()
            async let t = CashAccountsAPI().transfers(limit: 50)
            async let m = CashAccountsAPI().methods()
            async let x = CashAccountsAPI().expenses(limit: 50)
            (accounts, transfers, methods, expenses) = try await (a, t, m, x)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load cash accounts."
        }
        loaded = true
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
        let nextPage = items.count / pageSize + 1
        if let page = try? await AccountingAPI().accountHistory(code: account.code, page: nextPage, pageSize: pageSize) {
            items.append(contentsOf: page.items)
            total = page.total
        }
        loadingMore = false
    }
}

private struct TransferFundsSheet: View {
    let accounts: [CashAccount]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fromCode = ""
    @State private var toCode = ""
    @State private var amount = ""
    @State private var fee = ""
    @State private var note = ""
    @State private var checks: UndepositedChecks?
    @State private var checkedIds = Set<String>()
    @State private var saving = false
    @State private var errorMessage: String?

    // When transferring out of the Undeposited Checks account, the operator
    // picks the specific checks being deposited instead of typing an amount.
    private var isCheckDeposit: Bool {
        guard let checks else { return false }
        return fromCode == checks.accountCode && !checks.items.isEmpty
    }

    private var checkedTotal: Double {
        (checks?.items ?? []).filter { checkedIds.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    private var effectiveAmount: Double {
        isCheckDeposit ? checkedTotal : (Double(amount) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $fromCode) {
                        ForEach(accounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                    Picker("To", selection: $toCode) {
                        ForEach(accounts) { a in
                            Text("\(a.code) — \(a.name)").tag(a.code)
                        }
                    }
                }

                if isCheckDeposit, let checks {
                    Section {
                        Button(checkedIds.count == checks.items.count ? "Deselect all" : "Select all") {
                            if checkedIds.count == checks.items.count {
                                checkedIds = []
                            } else {
                                checkedIds = Set(checks.items.map(\.id))
                            }
                        }
                        ForEach(checks.items) { check in
                            Button {
                                if checkedIds.contains(check.id) {
                                    checkedIds.remove(check.id)
                                } else {
                                    checkedIds.insert(check.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: checkedIds.contains(check.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checkedIds.contains(check.id) ? Theme.primary : Theme.muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(check.customerName + (check.reference.map { " · #\($0)" } ?? ""))
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                        Text("\(AppFormat.shortDate(check.createdAt))\(check.invoiceRef.map { " · \($0)" } ?? "")")
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(AppFormat.money(check.amount))
                                        .font(.subheadline)
                                }
                            }
                        }
                        HStack {
                            Text("\(checkedIds.count) check\(checkedIds.count == 1 ? "" : "s") selected")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(AppFormat.money(checkedTotal))
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Checks to deposit")
                    }
                } else {
                    Section {
                        TextField("Amount $", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    TextField("Fee $ (optional)", text: $fee)
                        .keyboardType(.decimalPad)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if let feeValue = Double(fee), feeValue > 0, effectiveAmount > 0 {
                        Text("\(AppFormat.money(effectiveAmount - feeValue)) arrives after the \(AppFormat.money(feeValue)) fee.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle(isCheckDeposit ? "Deposit checks" : "Transfer funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Transfer") { Task { await submit() } }
                        .disabled(saving)
                }
            }
            .onAppear {
                if fromCode.isEmpty { fromCode = accounts.first?.code ?? "" }
                if toCode.isEmpty { toCode = accounts.dropFirst().first?.code ?? "" }
            }
            .task {
                if checks == nil {
                    checks = (try? await CashAccountsAPI().undepositedChecks()) ?? UndepositedChecks(accountCode: "", items: [])
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard fromCode != toCode else {
            errorMessage = "From and To accounts must be different"
            return
        }
        if isCheckDeposit && checkedIds.isEmpty {
            errorMessage = "Select at least one check to deposit"
            return
        }
        if !isCheckDeposit && effectiveAmount <= 0 {
            errorMessage = "Enter a positive amount"
            return
        }
        saving = true
        errorMessage = nil
        do {
            _ = try await CashAccountsAPI().createTransfer(
                TransferCreateInput(
                    fromCode: fromCode,
                    toCode: toCode,
                    amount: effectiveAmount,
                    fee: Double(fee) ?? 0,
                    note: note.nilIfBlank,
                    paymentIds: isCheckDeposit ? Array(checkedIds) : nil
                )
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the transfer."
        }
        saving = false
    }
}

private struct RecordExpenseSheet: View {
    let accounts: [CashAccount]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
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
    @State private var saving = false
    @State private var errorMessage: String?

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

                Section("Payee (optional)") {
                    Picker("Vendor", selection: $vendorId) {
                        Text("None").tag("")
                        ForEach(vendors) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    TextField("Payee name", text: $payee)
                }

                Section {
                    TextField("Reference (check #, invoice #)", text: $reference)
                    TextField("Note (optional)", text: $note)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Record expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Recording..." : "Record") { Task { await submit() } }
                        .disabled(saving)
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
        }
    }

    @MainActor
    private func submit() async {
        guard let value = Double(amount), value > 0 else {
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
        saving = true
        errorMessage = nil
        do {
            _ = try await CashAccountsAPI().createExpense(
                ExpenseCreateInput(
                    amount: value,
                    expenseCode: expenseCode,
                    paidFromCode: paidFromCode,
                    date: FinanceDay.string(date),
                    payee: payee.nilIfBlank,
                    vendorId: vendorId.nilIfBlank,
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank
                )
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the expense."
        }
        saving = false
    }
}

private struct AddPaymentMethodSheet: View {
    let accounts: [CashAccount]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountCode = ""
    @State private var feeRatePercent = ""
    @State private var saving = false
    @State private var errorMessage: String?

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
                    TextField("Fee rate % (optional)", text: $feeRatePercent)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Payments taken with this method post to the linked cash account.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add payment method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Adding..." : "Add") { Task { await submit() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || accountCode.isEmpty)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        saving = true
        errorMessage = nil
        do {
            _ = try await CashAccountsAPI().createMethod(
                PaymentMethodCreateInput(
                    name: name.trimmingCharacters(in: .whitespaces),
                    accountCode: accountCode,
                    feeRate: Double(feeRatePercent).map { $0 / 100 }
                )
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not add the payment method."
        }
        saving = false
    }
}

private struct ExpenseReceiptsSheet: View {
    let expense: ExpensePayment
    let canManage: Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [ExpenseReceipt] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var importing = false
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
                            }
                        }
                    }
                    if canManage {
                        Button {
                            importing = true
                        } label: {
                            Label(busy ? "Working..." : "Upload receipt", systemImage: "paperclip")
                        }
                        .disabled(busy)
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
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss(); onChanged() } }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.pdf, .jpeg, .png, .webP],
                allowsMultipleSelection: false
            ) { result in
                Task { await upload(result) }
            }
            .sheet(item: $preview) { file in
                QuickLookSheet(url: file.url)
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
    private func upload(_ result: Result<[URL], Error>) async {
        busy = true
        errorMessage = nil
        var tempURL: URL?
        do {
            guard let source = try result.get().first else {
                busy = false
                return
            }
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("expense-receipt-\(UUID().uuidString)-\(source.lastPathComponent)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            tempURL = destination

            _ = try await CashAccountsAPI().uploadExpenseReceipt(
                expenseId: expense.id,
                fileURL: destination,
                fileName: source.lastPathComponent,
                mimeType: mimeType(for: source)
            )
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not upload the receipt."
        }
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        busy = false
    }

    @MainActor
    private func remove() async {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        busy = true
        do {
            _ = try await CashAccountsAPI().deleteExpenseReceipt(id: target.id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete the receipt."
        }
        busy = false
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Recording..." : "Record") { Task { await submit() } }
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
        do {
            _ = try await FetAPI().pay(
                FetPayInput(
                    amount: value,
                    date: FinanceDay.string(date),
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank,
                    quarterKey: quarter?.key
                )
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record the payment."
        }
        saving = false
    }
}

// MARK: - End of day report

struct EodNativeView: View {
    @State private var date = Date()
    @State private var report: EodReport?
    @State private var loading = false
    @State private var errorMessage: String?

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
        .task { if report == nil { await load() } }
        .refreshable { await load() }
        .onChange(of: date) { Task { await load() } }
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
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            report = try await EodAPI().report(date: FinanceDay.string(date))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the report."
            report = nil
        }
        loading = false
    }
}
