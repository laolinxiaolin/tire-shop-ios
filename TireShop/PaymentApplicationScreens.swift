import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

private let paymentApplicationUploadTypes: [UTType] = [.pdf, .jpeg, .png, .webP, .heic, .heif]
    + [UTType(filenameExtension: "docx"), UTType(filenameExtension: "xlsx")].compactMap { $0 }

// Payment applications are intentionally rendered like compact ledger cards:
// the document number anchors each row, status is always visible, and money is
// set apart from supporting metadata. This keeps the approval queue scannable
// without recreating the web console's wide tables on a phone.

private let paymentApplicationStatuses = [
    "DRAFT",
    "PENDING_APPROVAL",
    "APPROVED",
    "PARTIALLY_PAID",
    "PAID",
    "REJECTED",
    "VOID"
]

private let paymentApplicationPurposes = [
    "GOODS",
    "LOGISTICS",
    "CUSTOMS",
    "WAREHOUSING",
    "OTHER"
]

private func paymentApplicationLabel(_ value: String) -> String {
    switch value {
    case "PENDING_APPROVAL": return "Pending approval"
    case "PARTIALLY_PAID": return "Partially paid"
    default: return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func paymentApplicationMoney(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.uppercased()
    formatter.locale = Locale(identifier: "en_US")
    return formatter.string(from: NSNumber(value: amount))
        ?? "\(currency.uppercased()) \(String(format: "%.2f", amount))"
}

/// Keeps an ambiguous payment/email attempt stable across sheet dismissal or
/// app termination. Only a SHA-256 fingerprint and UUID are persisted; no bank,
/// recipient, note, or reference data is written to UserDefaults.
///
/// Once an attempt exists it stays locked to its key until the caller receives
/// a definitive outcome and clears it. A changed form is intentionally sent
/// with that same key first: the server can then replay the original operation
/// or reject the mismatch without performing a second financial side effect.
struct PaymentApplicationSubmissionIdentity {
    private struct Stored: Codable {
        let fingerprint: String
        let idempotencyKey: String
    }

    private let storageKey: String
    private let defaults: UserDefaults

    init(
        kind: String,
        applicationID: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        storageKey = [
            "payment-application-attempt",
            kind,
            userID ?? "unknown-user",
            applicationID
        ].joined(separator: ":")
        self.defaults = defaults
    }

    func key<Body: Encodable>(for body: Body) throws -> String {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            return stored.idempotencyKey
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = SHA256.hash(data: try encoder.encode(body))
            .map { String(format: "%02x", $0) }
            .joined()

        let key = UUID().uuidString
        let stored = Stored(fingerprint: fingerprint, idempotencyKey: key)
        defaults.set(try JSONEncoder().encode(stored), forKey: storageKey)
        return key
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}

private struct PaymentApplicationStatusBadge: View {
    let status: PaymentApplicationStatus

    private var color: Color {
        switch status {
        case "APPROVED": return .blue
        case "PARTIALLY_PAID": return .orange
        case "PAID": return Theme.success
        case "REJECTED", "VOID": return Theme.danger
        case "PENDING_APPROVAL": return .purple
        default: return Theme.muted
        }
    }

    var body: some View {
        Text(paymentApplicationLabel(status).uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct PaymentApplicationsNativeView: View {
    private enum Scope: String, CaseIterable {
        case mine = "Mine"
        case all = "All"
    }

    @EnvironmentObject private var auth: AuthStore

    @State private var scope: Scope = .mine
    @State private var status = ""
    @State private var q = ""
    @State private var page = 1
    @State private var data: Paged<PaymentApplicationRow>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var requestID = 0

    private let pageSize = 30

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Space.sm) {
                Picker("View", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: Theme.Space.sm) {
                    Picker("Status", selection: $status) {
                        Text("All statuses").tag("")
                        ForEach(paymentApplicationStatuses, id: \.self) { value in
                            Text(paymentApplicationLabel(value)).tag(value)
                        }
                    }

                    if auth.has("paymentapps.manage") {
                        NavigationLink(value: AppRoute.paymentApplicationEditor(id: nil, vendorId: nil)) {
                            Label("New", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.background)

            Group {
                if loading && data == nil {
                    LoadingView(label: "Loading payment applications...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: "No payment applications match these filters.")
                } else if let data {
                    List {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.danger)
                        }

                        ForEach(data.items) { application in
                            NavigationLink(value: AppRoute.paymentApplicationDetail(application.id)) {
                                PaymentApplicationListRow(application: application)
                            }
                        }

                        if data.total > data.pageSize {
                            HStack {
                                Button("Previous") {
                                    page = max(1, page - 1)
                                    Task { await load() }
                                }
                                .disabled(page <= 1 || loading)
                                Spacer()
                                Text("Page \(data.page) of \(totalPages)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                Spacer()
                                Button("Next") {
                                    page = min(totalPages, page + 1)
                                    Task { await load() }
                                }
                                .disabled(page >= totalPages || loading)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    LoadingView(label: "Loading payment applications...")
                }
            }
        }
        .searchable(text: $q, prompt: "Reference or payee")
        .task { if data == nil { await load() } }
        .onSubmit(of: .search) {
            page = 1
            Task { await load() }
        }
        .onChange(of: scope) { _, _ in
            page = 1
            Task { await load() }
        }
        .onChange(of: status) { _, _ in
            page = 1
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .paymentApplicationsChanged)) { _ in
            Task { await load() }
        }
    }

    @MainActor
    private func load() async {
        requestID += 1
        let currentRequest = requestID
        loading = true
        do {
            let result = try await PaymentApplicationsAPI().list(
                view: scope.rawValue.lowercased(),
                q: q.nilIfBlank,
                status: status.nilIfBlank,
                page: page,
                pageSize: pageSize
            )
            guard currentRequest == requestID else { return }
            data = result
            errorMessage = nil
        } catch {
            guard currentRequest == requestID else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load payment applications."
        }
        if currentRequest == requestID { loading = false }
    }
}

/// The one-line identification the reject sheet shows above the reason field.
func paymentApplicationSummary(_ row: PaymentApplicationRow) -> String {
    "\(row.ref) · \(row.vendor) · \(paymentApplicationMoney(row.totalAmount, currency: row.currency))"
}

/// One payment application waiting on a signature, as it appears in the shop's
/// single approval queue on Approvals.
///
/// These documents run their own PENDING_APPROVAL state machine rather than an
/// `ApprovalRequest` row, so they are loaded from their own endpoint and merged
/// into that screen rather than arriving with the generic queue.
struct PaymentApplicationApprovalCard: View {
    let row: PaymentApplicationRow
    let canDecide: Bool
    let deciding: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Text("Approve payment application")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                PaymentApplicationStatusBadge(status: row.status)
                Spacer(minLength: 0)
            }

            Text("\(row.ref) · \(row.vendor) · \(paymentApplicationMoney(row.totalAmount, currency: row.currency))")
                .font(.subheadline)
                .foregroundStyle(Theme.text)

            Text("Requested by \(row.requestedBy) · \(AppFormat.calendarDate(row.requestedAt))")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 2) {
                metaRow("Purpose", paymentApplicationLabel(row.purpose))
                metaRow("Bills to pay", "\(row.lineCount)")
                metaRow("Attachments", "\(row.attachmentCount)")
                if row.plannedPayAt != nil {
                    metaRow("Planned pay", AppFormat.calendarDate(row.plannedPayAt))
                }
            }

            HStack(spacing: Theme.Space.sm) {
                // The bills and the bank snapshot frozen at submit are what an
                // approver actually signs; Back returns to the queue.
                NavigationLink(value: AppRoute.paymentApplicationDetail(row.id)) {
                    Text("Details").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                if canDecide {
                    Button(action: onApprove) {
                        Text("Approve").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive, action: onReject) {
                        Text("Reject").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                if deciding { ProgressView() }
            }
            .disabled(deciding)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.text)
        }
    }
}

private struct PaymentApplicationListRow: View {
    let application: PaymentApplicationRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(application.ref)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                PaymentApplicationStatusBadge(status: application.status)
            }

            Text(application.vendor)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(paymentApplicationLabel(application.purpose))
                    Text("Requested by \(application.requestedBy) · \(AppFormat.calendarDate(application.requestedAt))")
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(paymentApplicationMoney(application.totalAmount, currency: application.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if application.paidAmount > 0 {
                        Text("\(paymentApplicationMoney(application.totalAmount - application.paidAmount, currency: application.currency)) left")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

struct PaymentApplicationEditorNativeView: View {
    @Environment(\.dismiss) private var dismiss

    let id: String?
    let presetVendorId: String?

    @State private var vendorOptions: [PaymentApplicationOpenBillVendor] = []
    @State private var vendorId: String
    @State private var vendorName = ""
    @State private var bills: [PaymentApplicationOpenBill] = []
    @State private var bankOptions: [PaymentApplicationBankOption] = []
    @State private var bankAccountId = ""
    @State private var currency = "USD"
    @State private var purpose = "GOODS"
    @State private var requestedAt = Date()
    @State private var plannedPayAt = Date()
    @State private var hasPlannedPayAt = false
    @State private var note = ""
    @State private var selectedBillIDs = Set<String>()
    @State private var amounts: [String: String] = [:]
    @State private var lineNotes: [String: String] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var bankRequestID = 0
    @State private var billRequestID = 0

    private var isEditing: Bool { id != nil }

    private var total: Double {
        selectedBillIDs.reduce(0) { result, billID in
            result + (AppFormat.parseAmount(amounts[billID] ?? "") ?? 0)
        }
    }

    init(id: String?, presetVendorId: String?) {
        self.id = id
        self.presetVendorId = presetVendorId
        _vendorId = State(initialValue: presetVendorId ?? "")
    }

    var body: some View {
        Group {
            if loading {
                LoadingView(label: isEditing ? "Loading draft..." : "Loading open bills...")
            } else {
                Form {
                    Section("Application") {
                        if isEditing {
                            LabeledContent("Payee", value: vendorName)
                        } else {
                            Picker("Payee", selection: $vendorId) {
                                Text("Select payee").tag("")
                                ForEach(vendorOptions) { option in
                                    Text("\(option.vendor ?? option.vendorId) · \(paymentApplicationMoney(option.applicable, currency: currency))")
                                        .tag(option.vendorId)
                                }
                            }
                        }

                        Picker("Purpose", selection: $purpose) {
                            ForEach(paymentApplicationPurposes, id: \.self) { value in
                                Text(paymentApplicationLabel(value)).tag(value)
                            }
                        }

                        TextField("Currency", text: $currency)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: currency) { _, value in
                                let normalized = String(value.uppercased().prefix(8))
                                if normalized != value { currency = normalized }
                            }

                        DatePicker("Request date", selection: $requestedAt, displayedComponents: .date)
                        Toggle("Plan a payment date", isOn: $hasPlannedPayAt)
                        if hasPlannedPayAt {
                            DatePicker("Planned payment", selection: $plannedPayAt, displayedComponents: .date)
                        }

                        Picker("Pay to", selection: $bankAccountId) {
                            Text(bankOptions.isEmpty ? "No active account" : "Select account").tag("")
                            ForEach(bankOptions) { account in
                                Text("\(account.label?.nilIfBlank ?? account.bankName) · \(account.accountMasked)")
                                    .tag(account.id)
                            }
                        }
                    }

                    Section("Bills") {
                        if vendorId.isEmpty {
                            Text("Choose a payee to see open bills.")
                                .foregroundStyle(Theme.muted)
                        } else if bills.isEmpty {
                            Text("This payee has no applicable open bills.")
                                .foregroundStyle(Theme.muted)
                        }

                        ForEach(bills) { bill in
                            PaymentApplicationBillDraftRow(
                                bill: bill,
                                currency: currency,
                                selected: Binding(
                                    get: { selectedBillIDs.contains(bill.id) },
                                    set: { selected in toggle(bill, selected: selected) }
                                ),
                                amount: Binding(
                                    get: { amounts[bill.id] ?? "" },
                                    set: { amounts[bill.id] = $0 }
                                ),
                                note: Binding(
                                    get: { lineNotes[bill.id] ?? "" },
                                    set: { lineNotes[bill.id] = $0 }
                                )
                            )
                        }
                    }

                    Section("Summary") {
                        LabeledContent("Requested total", value: paymentApplicationMoney(total, currency: currency))
                        TextField("Note (optional)", text: $note, axis: .vertical)
                            .lineLimit(2...6)
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit application" : "New application")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saving ? "Saving..." : "Save") { Task { await save() } }
                    .disabled(saving || loading)
            }
        }
        .task { await initialLoad() }
        .onChange(of: vendorId) { oldValue, newValue in
            guard oldValue != newValue, !loading else { return }
            selectedBillIDs = []
            amounts = [:]
            lineNotes = [:]
            Task { await loadVendorResources() }
        }
        .onChange(of: currency) { oldValue, newValue in
            guard oldValue != newValue, !loading, !vendorId.isEmpty else { return }
            Task { await loadBanks() }
        }
    }

    @MainActor
    private func initialLoad() async {
        loading = true
        errorMessage = nil
        do {
            async let vendorsTask = PaymentApplicationsAPI().openBillVendors()
            if let id {
                async let draftTask = PaymentApplicationsAPI().get(id: id)
                let (loadedVendors, draft) = try await (vendorsTask, draftTask)
                vendorOptions = loadedVendors
                vendorId = draft.vendor.id
                vendorName = draft.vendor.name
                currency = draft.currency
                purpose = draft.purpose
                requestedAt = AppFormat.date(draft.requestedAt) ?? Date()
                if let value = AppFormat.date(draft.plannedPayAt) {
                    plannedPayAt = value
                    hasPlannedPayAt = true
                }
                note = draft.note ?? ""
                selectedBillIDs = Set(draft.lines.map(\.containerCostId))
                amounts = Dictionary(uniqueKeysWithValues: draft.lines.map {
                    ($0.containerCostId, String(format: "%.2f", $0.amount))
                })
                lineNotes = Dictionary(uniqueKeysWithValues: draft.lines.map {
                    ($0.containerCostId, $0.note ?? "")
                })
                let open = try await PaymentApplicationsAPI().openBills(vendorId: draft.vendor.id)
                var known = Dictionary(uniqueKeysWithValues: open.map { ($0.id, $0) })
                for line in draft.lines where known[line.containerCostId] == nil {
                    known[line.containerCostId] = PaymentApplicationOpenBill(
                        id: line.containerCostId,
                        vendor: draft.vendor.name,
                        vendorId: draft.vendor.id,
                        category: line.category,
                        description: line.description ?? line.cost.description,
                        reference: line.vendorRef ?? line.cost.reference,
                        poReference: line.poReference,
                        amount: line.billAmount,
                        amountPaid: line.cost.amountPaid,
                        committed: 0,
                        applicable: max(0, line.amount - line.paidAmount),
                        occurredAt: draft.requestedAt,
                        dueAt: nil,
                        createdAt: draft.requestedAt
                    )
                }
                bills = known.values.sorted { $0.occurredAt < $1.occurredAt }
                bankOptions = try await PaymentApplicationsAPI().bankOptions(
                    vendorId: draft.vendor.id,
                    currency: draft.currency
                )
                bankAccountId = draft.bank.accountId ?? bankOptions.first(where: \.isDefault)?.id ?? bankOptions.first?.id ?? ""
            } else {
                vendorOptions = try await vendorsTask
                if !vendorId.isEmpty { await loadVendorResources() }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not prepare the application."
        }
        loading = false
    }

    @MainActor
    private func loadVendorResources() async {
        guard !vendorId.isEmpty else {
            bills = []
            bankOptions = []
            bankAccountId = ""
            return
        }
        async let billsTask: Void = loadBills()
        async let banksTask: Void = loadBanks()
        _ = await (billsTask, banksTask)
    }

    @MainActor
    private func loadBills() async {
        billRequestID += 1
        let current = billRequestID
        do {
            let result = try await PaymentApplicationsAPI().openBills(vendorId: vendorId)
            guard current == billRequestID else { return }
            bills = result
            errorMessage = nil
        } catch {
            guard current == billRequestID else { return }
            bills = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load open bills."
        }
    }

    @MainActor
    private func loadBanks() async {
        bankRequestID += 1
        let current = bankRequestID
        do {
            let result = try await PaymentApplicationsAPI().bankOptions(vendorId: vendorId, currency: currency)
            guard current == bankRequestID else { return }
            bankOptions = result
            if !result.contains(where: { $0.id == bankAccountId }) {
                bankAccountId = result.first(where: \.isDefault)?.id ?? result.first?.id ?? ""
            }
        } catch {
            guard current == bankRequestID else { return }
            bankOptions = []
            bankAccountId = ""
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load bank accounts."
        }
    }

    private func toggle(_ bill: PaymentApplicationOpenBill, selected: Bool) {
        if selected {
            selectedBillIDs.insert(bill.id)
            if amounts[bill.id]?.nilIfBlank == nil {
                amounts[bill.id] = String(format: "%.2f", bill.applicable)
            }
        } else {
            selectedBillIDs.remove(bill.id)
        }
    }

    @MainActor
    private func save() async {
        guard !vendorId.isEmpty else { errorMessage = "Select a payee."; return }
        guard !bankAccountId.isEmpty else { errorMessage = "Add or select an active bank account."; return }
        guard !selectedBillIDs.isEmpty else { errorMessage = "Select at least one bill."; return }

        var lines: [PaymentApplicationLineInput] = []
        for billID in selectedBillIDs.sorted() {
            guard let amount = AppFormat.parseAmount(amounts[billID] ?? ""), amount > 0 else {
                errorMessage = "Every selected bill needs a positive amount."
                return
            }
            if let bill = bills.first(where: { $0.id == billID }), amount > bill.applicable + 0.005, !isEditing {
                errorMessage = "An amount exceeds the bill's applicable balance."
                return
            }
            lines.append(PaymentApplicationLineInput(
                containerCostId: billID,
                amount: amount,
                note: lineNotes[billID]?.nilIfBlank
            ))
        }

        saving = true
        errorMessage = nil
        do {
            if let id {
                _ = try await PaymentApplicationsAPI().update(
                    id: id,
                    body: PaymentApplicationUpdateInput(
                        bankAccountId: bankAccountId,
                        currency: currency,
                        purpose: purpose,
                        requestedAt: ShopClock.dayString(from: requestedAt),
                        plannedPayAt: hasPlannedPayAt ? ShopClock.dayString(from: plannedPayAt) : nil,
                        note: note.nilIfBlank,
                        lines: lines
                    )
                )
            } else {
                _ = try await PaymentApplicationsAPI().create(PaymentApplicationCreateInput(
                    vendorId: vendorId,
                    bankAccountId: bankAccountId,
                    currency: currency,
                    purpose: purpose,
                    requestedAt: ShopClock.dayString(from: requestedAt),
                    plannedPayAt: hasPlannedPayAt ? ShopClock.dayString(from: plannedPayAt) : nil,
                    note: note.nilIfBlank,
                    lines: lines
                ))
            }
            NotificationCenter.default.post(name: .paymentApplicationsChanged, object: nil)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the application."
        }
        saving = false
    }
}

private struct PaymentApplicationBillDraftRow: View {
    let bill: PaymentApplicationOpenBill
    let currency: String
    @Binding var selected: Bool
    @Binding var amount: String
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Toggle(isOn: $selected) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.description?.nilIfBlank ?? paymentApplicationLabel(bill.category))
                        .font(.subheadline.weight(.semibold))
                    Text([bill.poReference, bill.reference].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            HStack {
                Text("Bill \(AppFormat.calendarDate(bill.occurredAt))")
                Text("·")
                Text(dueLabel(bill.dueAt))
                Spacer()
                Text("Available \(paymentApplicationMoney(bill.applicable, currency: currency))")
            }
            .font(.caption2)
            .foregroundStyle(Theme.muted)

            if selected {
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                TextField("Line note (optional)", text: $note)
            }
        }
        .padding(.vertical, 2)
    }

    private func dueLabel(_ value: String?) -> String {
        guard let value, let due = ShopClock.date(fromDayString: String(value.prefix(10))) else {
            return "No due date"
        }
        let today = ShopClock.startOfDay()
        let days = ShopClock.calendar.dateComponents([.day], from: today, to: due).day ?? 0
        switch days {
        case 0: return "Due today"
        case 1: return "1 day left"
        case 2...: return "\(days) days left"
        case -1: return "1 day overdue"
        default: return "\(abs(days)) days overdue"
        }
    }
}

extension Notification.Name {
    static let paymentApplicationsChanged = Notification.Name("paymentApplicationsChanged")
}

struct PaymentApplicationDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.dismiss) private var dismiss

    let id: String

    @State private var application: PaymentApplicationDetail?
    @State private var loading = false
    @State private var actionLoading = false
    @State private var errorMessage: String?
    @State private var requestID = 0
    @State private var paymentPresented = false
    @State private var emailPresented = false
    @State private var preparingAttachment = false
    @State private var pendingAttachment: DocumentUploadDraft?
    @State private var confirmingDiscardAndLeave = false
    @State private var preview: PreviewFile?
    @State private var removeAttachmentTarget: PaymentApplicationAttachment?
    @State private var confirmingAction: String?

    private var canManage: Bool { auth.has("paymentapps.manage") }
    private var canApprove: Bool {
        auth.has("paymentapps.view")
            && auth.has("paymentapps.viewAll")
            && auth.has("paymentapps.approve")
    }
    private var canPay: Bool { auth.has("paymentapps.pay") }
    private var canRegister: Bool { canPay && auth.has("payables.pay") }
    private var canSend: Bool { auth.has("paymentapps.send") }
    private var canVoid: Bool { auth.has("paymentapps.void") }

    var body: some View {
        Group {
            if loading && application == nil {
                LoadingView(label: "Loading application...")
            } else if let errorMessage, application == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let application {
                content(application)
            } else {
                LoadingView(label: "Loading application...")
            }
        }
        .background(Theme.background)
        .navigationTitle(application?.ref ?? "Payment application")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(preparingAttachment || pendingAttachment != nil)
        .interactiveDismissDisabled(preparingAttachment || pendingAttachment != nil)
        .toolbar {
            if preparingAttachment || pendingAttachment != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        confirmingDiscardAndLeave = true
                    } label: {
                        Label(i18n.t("common.back"), systemImage: "chevron.left")
                    }
                    .disabled(actionLoading || preparingAttachment)
                }
            }
            if let application {
                AppOverflowMenu(
                    title: i18n.t("common.actions"),
                    isLoading: actionLoading,
                    isDisabled: preparingAttachment || pendingAttachment != nil
                ) {
                    actionMenu(application)
                }
            }
        }
        .task { if application == nil { await load() } }
        .refreshable { await load() }
        .sheet(isPresented: $paymentPresented) {
            if let application {
                PaymentApplicationPaymentSheet(application: application) {
                    paymentPresented = false
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $emailPresented) {
            if let application {
                PaymentApplicationEmailSheet(application: application) {
                    emailPresented = false
                    Task { await load() }
                }
            }
        }
        .sheet(item: $preview) { file in
            QuickLookSheet(url: file.url)
        }
        .alert(i18n.t("documentUpload.leaveTitle"), isPresented: $confirmingDiscardAndLeave) {
            Button(i18n.t("common.cancel"), role: .cancel) {}
            Button(i18n.t("documentUpload.discardAndLeave"), role: .destructive) {
                pendingAttachment = nil
                dismiss()
            }
        } message: {
            Text(i18n.t("documentUpload.leaveMessage"))
        }
        .alert("Remove this document?", isPresented: Binding(
            get: { removeAttachmentTarget != nil },
            set: { if !$0 { removeAttachmentTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { removeAttachmentTarget = nil }
            Button("Remove", role: .destructive) { Task { await removeAttachment() } }
        } message: {
            Text("The document stays in prior email history, but is removed from this application.")
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingAction != nil },
                set: { if !$0 { confirmingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = confirmingAction {
                Button(confirmationButton(action), role: action == "void" ? .destructive : nil) {
                    confirmingAction = nil
                    Task { await runAction(action) }
                }
                Button("Cancel", role: .cancel) { confirmingAction = nil }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    @ViewBuilder
    private func actionMenu(_ application: PaymentApplicationDetail) -> some View {
        let status = application.status
        if canManage && status == "DRAFT" {
            NavigationLink(value: AppRoute.paymentApplicationEditor(id: application.id, vendorId: nil)) {
                Label("Edit draft", systemImage: "pencil")
            }
            Button { confirmingAction = "submit" } label: {
                Label("Submit for approval", systemImage: "paperplane")
            }
        }
        if canManage && status == "PENDING_APPROVAL" {
            Button { confirmingAction = "withdraw" } label: {
                Label("Withdraw", systemImage: "arrow.uturn.backward")
            }
        }
        // Signing off happens in the shop's one approval queue, not here.
        if canApprove && status == "PENDING_APPROVAL" {
            NavigationLink(value: AppRoute.module("approvals")) {
                Label("Decide in Approvals", systemImage: "checkmark.seal")
            }
        }
        if canManage && status == "REJECTED" {
            Button { Task { await runAction("reopen") } } label: {
                Label("Reopen as draft", systemImage: "arrow.counterclockwise")
            }
        }
        if canRegister && ["APPROVED", "PARTIALLY_PAID"].contains(status) {
            Button { paymentPresented = true } label: {
                Label("Register payment", systemImage: "banknote")
            }
        }
        if canPay && status == "PARTIALLY_PAID" {
            Button { confirmingAction = "cancel-remaining" } label: {
                Label("Cancel remaining", systemImage: "slash.circle")
            }
        }
        if canPay && status == "PAID" && application.remainingCancelledAt != nil {
            Button { confirmingAction = "restore-remaining" } label: {
                Label("Restore remaining", systemImage: "arrow.clockwise")
            }
        }
        if canSend && ["APPROVED", "PARTIALLY_PAID", "PAID"].contains(status) {
            Button { emailPresented = true } label: {
                Label("Email payee", systemImage: "envelope")
            }
        }
        Button { Task { await downloadPDF(application, variant: "application") } } label: {
            Label("Application PDF", systemImage: "doc.richtext")
        }
        if ["APPROVED", "PARTIALLY_PAID", "PAID"].contains(status) {
            Button { Task { await downloadPDF(application, variant: "notice") } } label: {
                Label("Payment notice PDF", systemImage: "doc.text")
            }
        }
        if canVoid && ["DRAFT", "REJECTED", "APPROVED"].contains(status) {
            Button(role: .destructive) { confirmingAction = "void" } label: {
                Label("Void application", systemImage: "nosign")
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmingAction {
        case "submit": return "Submit for approval?"
        case "withdraw": return "Withdraw this application?"
        case "cancel-remaining": return "Cancel the remaining balance?"
        case "restore-remaining": return "Restore the remaining balance?"
        case "void": return "Void this application?"
        default: return "Confirm action"
        }
    }

    private var confirmationMessage: String {
        switch confirmingAction {
        case "submit":
            return "The bills, amount, and bank snapshot will be frozen for an approver to review."
        case "withdraw":
            return "The application returns to draft so it can be edited and submitted again."
        case "cancel-remaining":
            return "The unpaid approved balance will be released back to Accounts Payable."
        case "restore-remaining":
            return "The server will reclaim the released balance if it is still available."
        case "void":
            return "This retires the application and releases any balance it still holds."
        default:
            return ""
        }
    }

    private func confirmationButton(_ action: String) -> String {
        switch action {
        case "submit": return "Submit"
        case "withdraw": return "Withdraw"
        case "cancel-remaining": return "Cancel remaining"
        case "restore-remaining": return "Restore"
        case "void": return "Void"
        default: return "Continue"
        }
    }

    private func content(_ application: PaymentApplicationDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Text(application.ref)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                        Spacer()
                        PaymentApplicationStatusBadge(status: application.status)
                    }
                    Text(application.vendor.name)
                        .font(.title2.weight(.bold))
                    Text("Requested by \(application.requestedBy.fullName) · \(AppFormat.calendarDate(application.requestedAt))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.md)
                        .background(Theme.danger.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                PaymentApplicationAmountRail(application: application)

                PaymentApplicationInfoCard(title: "Purpose & timing", systemImage: "calendar") {
                    paymentApplicationInfoRow("Purpose", paymentApplicationLabel(application.purpose))
                    paymentApplicationInfoRow("Requested", AppFormat.calendarDate(application.requestedAt))
                    paymentApplicationInfoRow("Planned payment", AppFormat.calendarDate(application.plannedPayAt))
                    if let note = application.note?.nilIfBlank {
                        Divider()
                        Text(note).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if let decisionNote = application.decisionNote?.nilIfBlank {
                        Divider()
                        Text("Decision note: \(decisionNote)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }

                PaymentApplicationInfoCard(title: "Payee bank", systemImage: "building.columns") {
                    if application.bank.bankName == nil {
                        Text("Bank details are selected and frozen when the draft is submitted.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    } else {
                        paymentApplicationInfoRow("Beneficiary", application.bank.beneficiaryName ?? "—")
                        paymentApplicationInfoRow("Bank", application.bank.bankName ?? "—")
                        paymentApplicationInfoRow("Account", application.bank.accountNumber ?? application.bank.accountMasked ?? "—")
                        paymentApplicationInfoRow("Routing", application.bank.routingNumber ?? "—")
                        paymentApplicationInfoRow("SWIFT", application.bank.swift ?? "—")
                        paymentApplicationInfoRow("Finance email", application.bank.financeEmail ?? "—")
                    }
                }

                SectionHeader("Bills")
                VStack(spacing: 0) {
                    ForEach(application.lines) { line in
                        PaymentApplicationLineRow(line: line, currency: application.currency)
                        if line.id != application.lines.last?.id { Divider() }
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border))

                paymentHistory(application)
                attachments(application)
                approvalHistory(application)
                emailHistory(application)
            }
            .padding(Theme.Space.lg)
        }
    }

    private func paymentHistory(_ application: PaymentApplicationDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Payment history")
            let payments = application.supplierPayments ?? []
            if payments.isEmpty {
                Text("No payments registered.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(payments, id: \.stableID) { payment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(payment.ref).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            Spacer()
                            Text(paymentApplicationMoney(payment.total, currency: application.currency))
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("\(AppFormat.calendarDate(payment.paidAt)) · \(payment.method ?? "Payment")")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        if let account = payment.fundingAccount {
                            Text("\(account.code) · \(account.name)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(Theme.Space.md)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
        }
    }

    private func attachments(_ application: PaymentApplicationDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                SectionHeader("Documents")
                Spacer()
                if canChangeAttachments(application) {
                    DocumentUploadSourcePicker(
                        disabled: actionLoading || pendingAttachment != nil,
                        preparing: $preparingAttachment,
                        onPrepared: { document in
                            pendingAttachment = document
                            Task { await uploadPendingAttachment() }
                        },
                        onError: { errorMessage = $0 },
                        titleKey: "pa.uploadAttachment",
                        filenamePrefix: "Payment application document",
                        allowedContentTypes: paymentApplicationUploadTypes
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }

            if let pendingAttachment {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label(pendingAttachment.filename, systemImage: "doc.badge.clock")
                        .font(.subheadline)
                    if actionLoading {
                        ProgressView(i18n.t("documentUpload.uploading"))
                    } else {
                        HStack {
                            if canChangeAttachments(application) {
                                Button(i18n.t("expenseReceipt.retry")) {
                                    Task { await uploadPendingAttachment() }
                                }
                            }
                            Button(i18n.t("documentUpload.discard"), role: .destructive) {
                                self.pendingAttachment = nil
                                errorMessage = nil
                            }
                        }
                    }
                }
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            if application.attachments.isEmpty {
                Text("No documents attached.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(application.attachments) { attachment in
                Button { Task { await openAttachment(application, attachment: attachment) } } label: {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: attachment.kind == "PAYMENT_PROOF" ? "checkmark.seal" : "doc")
                            .foregroundStyle(Theme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text("\(paymentApplicationLabel(attachment.kind)) · \(attachment.sizeBytes / 1024) KB")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(Theme.Space.md)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canChangeAttachments(application) {
                        Button("Remove", role: .destructive) { removeAttachmentTarget = attachment }
                            .disabled(actionLoading || preparingAttachment)
                    }
                }
            }
        }
    }

    private func approvalHistory(_ application: PaymentApplicationDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Decision history")
            if application.approvals.isEmpty {
                Text("No approval decisions yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(application.approvals) { approval in
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Circle()
                        .fill(approval.decision == "APPROVED" ? Theme.success : Theme.danger)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Round \(approval.round) · \(paymentApplicationLabel(approval.decision))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(approval.decidedBy) · \(AppFormat.dateTime(approval.decidedAt))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        if let comment = approval.comment?.nilIfBlank {
                            Text(comment).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private func emailHistory(_ application: PaymentApplicationDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Email history")
            if application.emails.isEmpty {
                Text("No payment emails sent.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(application.emails) { email in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(email.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(email.status)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(emailStatusColor(email.status))
                    }
                    Text("To \(email.toAddress) · \(AppFormat.dateTime(email.sentAt))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    if let documents = email.extraAttachments, !documents.isEmpty {
                        Text("Included: \(documents.map(\.filename).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(Theme.Space.md)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private func emailStatusColor(_ status: String) -> Color {
        switch status {
        case "SENT": Theme.success
        case "FAILED": Theme.danger
        default: .orange
        }
    }

    private func canChangeAttachments(_ application: PaymentApplicationDetail) -> Bool {
        canManage && !["PENDING_APPROVAL", "REJECTED"].contains(application.status)
    }

    @MainActor
    private func load() async {
        requestID += 1
        let current = requestID
        loading = true
        do {
            let result = try await PaymentApplicationsAPI().get(id: id)
            guard current == requestID else { return }
            application = result
            errorMessage = nil
        } catch {
            guard current == requestID else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load the application."
        }
        if current == requestID { loading = false }
    }

    @MainActor
    private func runAction(_ action: String) async {
        actionLoading = true
        errorMessage = nil
        do {
            application = try await PaymentApplicationsAPI().action(id: id, name: action)
            NotificationCenter.default.post(name: .paymentApplicationsChanged, object: nil)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The action could not be completed."
        }
        actionLoading = false
    }

    @MainActor
    private func downloadPDF(_ application: PaymentApplicationDetail, variant: String) async {
        actionLoading = true
        do {
            let url = try await PaymentApplicationsAPI().downloadPDF(
                id: application.id,
                ref: application.ref,
                variant: variant
            )
            preview = PreviewFile(url: url)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not prepare the PDF."
        }
        actionLoading = false
    }

    @MainActor
    private func openAttachment(
        _ application: PaymentApplicationDetail,
        attachment: PaymentApplicationAttachment
    ) async {
        do {
            let url = try await PaymentApplicationsAPI().downloadAttachment(
                id: application.id,
                attachment: attachment
            )
            preview = PreviewFile(url: url)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not open the document."
        }
    }

    @MainActor
    private func uploadPendingAttachment() async {
        guard let application, canChangeAttachments(application), !actionLoading,
              let document = pendingAttachment else { return }
        defer { withExtendedLifetime(document) {} }
        actionLoading = true
        errorMessage = nil
        defer { actionLoading = false }
        do {
            _ = try await PaymentApplicationsAPI().uploadAttachment(
                id: application.id,
                fileURL: document.url,
                fileName: document.filename,
                mimeType: document.mimeType
            )
            pendingAttachment = nil
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not upload the document."
        }
    }

    @MainActor
    private func removeAttachment() async {
        guard let target = removeAttachmentTarget else { return }
        removeAttachmentTarget = nil
        actionLoading = true
        do {
            _ = try await PaymentApplicationsAPI().removeAttachment(id: id, attachmentId: target.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not remove the document."
        }
        actionLoading = false
    }
}

private struct PaymentApplicationAmountRail: View {
    let application: PaymentApplicationDetail

    var body: some View {
        HStack(spacing: 0) {
            amount("Approved", application.totalAmount, color: Theme.text)
            Divider().frame(height: 50)
            amount("Paid", application.paidAmount, color: Theme.success)
            Divider().frame(height: 50)
            amount("Remaining", application.remaining, color: application.remaining > 0 ? .orange : Theme.success)
        }
        .padding(.vertical, Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border))
    }

    private func amount(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.muted)
            Text(paymentApplicationMoney(value, currency: application.currency))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaymentApplicationInfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.text)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border))
    }
}

private func paymentApplicationInfoRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(label).font(.caption).foregroundStyle(Theme.muted)
        Spacer()
        Text(value).font(.subheadline).multilineTextAlignment(.trailing)
    }
}

private struct PaymentApplicationLineRow: View {
    let line: PaymentApplicationLine
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.description?.nilIfBlank ?? line.cost.description?.nilIfBlank ?? paymentApplicationLabel(line.category))
                        .font(.subheadline.weight(.semibold))
                    Text([line.companyRef, line.poReference, line.vendorRef].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(paymentApplicationMoney(line.amount, currency: currency))
                    .font(.subheadline.weight(.semibold))
            }
            if line.paidAmount > 0 {
                ProgressView(value: min(1, line.paidAmount / max(line.amount, 0.01)))
                    .tint(Theme.success)
                Text("Paid \(paymentApplicationMoney(line.paidAmount, currency: currency))")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            if let note = line.note?.nilIfBlank {
                Text(note).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(Theme.Space.md)
    }
}

struct PaymentApplicationRejectSheet: View {
    @Environment(\.dismiss) private var dismiss

    let id: String
    let summary: String
    let onDone: () -> Void

    @State private var comment = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    TextField("Reason for rejection", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("The applicant will see this reason and can reopen the document as a draft.")
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle("Reject application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Rejecting..." : "Reject", role: .destructive) {
                        Task { await reject() }
                    }
                    .disabled(saving || comment.nilIfBlank == nil)
                }
            }
        }
    }

    @MainActor
    private func reject() async {
        guard let comment = comment.nilIfBlank else { return }
        saving = true
        do {
            _ = try await PaymentApplicationsAPI().reject(id: id, comment: comment)
            NotificationCenter.default.post(name: .paymentApplicationsChanged, object: nil)
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reject the application."
        }
        saving = false
    }
}

private struct PaymentRegistrationFingerprint: Codable {
    let amount: Double
    let paidAt: String
    let accountId: String
    let method: String?
    let reference: String?
    let note: String?
}

private struct PaymentApplicationPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let application: PaymentApplicationDetail
    let onDone: () -> Void

    @State private var accounts: [PaymentFundingAccount] = []
    @State private var accountId = ""
    @State private var amount: String
    @State private var paidAt = Date()
    @State private var method = ""
    @State private var reference = ""
    @State private var note = ""
    @State private var proof: DocumentUploadDraft?
    @State private var preparingProof = false
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    init(application: PaymentApplicationDetail, onDone: @escaping () -> Void) {
        self.application = application
        self.onDone = onDone
        _amount = State(initialValue: String(format: "%.2f", application.remaining))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    LabeledContent("Remaining", value: paymentApplicationMoney(application.remaining, currency: application.currency))
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("Paid on", selection: $paidAt, displayedComponents: .date)
                    Picker("Paid from", selection: $accountId) {
                        Text(loading ? "Loading accounts..." : "Select account").tag("")
                        ForEach(accounts) { account in
                            Text("\(account.code) · \(account.name)").tag(account.id)
                        }
                    }
                    TextField("Method (wire, ACH, check)", text: $method)
                    TextField("Reference / confirmation #", text: $reference)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    if let proof {
                        Label(proof.filename, systemImage: "doc.badge.checkmark")
                            .foregroundStyle(Theme.success)
                    }
                    DocumentUploadSourcePicker(
                        disabled: saving,
                        preparing: $preparingProof,
                        onPrepared: { document in
                            proof = document
                            errorMessage = nil
                        },
                        onError: { errorMessage = $0 },
                        titleKey: proof == nil ? "documentUpload.chooseProof" : "documentUpload.replace",
                        filenamePrefix: "Payment proof",
                        allowedContentTypes: paymentApplicationUploadTypes
                    )
                } header: {
                    Text("Payment proof")
                } footer: {
                    Text("A PDF, image, Word document, or spreadsheet is required before money can be registered.")
                }

                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Theme.danger)
                }
            }
            .disabled(saving)
            .navigationTitle("Register payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving || preparingProof)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Registering..." : "Register") { Task { await submit() } }
                        .disabled(saving || loading || preparingProof)
                }
            }
        }
        .interactiveDismissDisabled(saving || preparingProof)
        .task { if accounts.isEmpty { await loadAccounts() } }
    }

    @MainActor
    private func loadAccounts() async {
        loading = true
        do {
            accounts = try await PaymentApplicationsAPI().payoutAccounts()
            if accountId.isEmpty {
                accountId = accounts.first(where: { $0.code == "1020" })?.id ?? accounts.first?.id ?? ""
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load payout accounts."
        }
        loading = false
    }

    @MainActor
    private func submit() async {
        guard !saving, !preparingProof else { return }
        guard let amount = AppFormat.parseAmount(amount), amount > 0 else {
            errorMessage = "Enter a positive amount."
            return
        }
        guard amount <= application.remaining + 0.005 else {
            errorMessage = "The amount exceeds the approved remaining balance."
            return
        }
        guard !accountId.isEmpty else {
            errorMessage = "Select a funding account."
            return
        }
        guard let proof else {
            errorMessage = "Choose the payment proof or bank receipt."
            return
        }

        saving = true
        do {
            let paidAtValue = ShopClock.dayString(from: paidAt)
            let identity = PaymentApplicationSubmissionIdentity(
                kind: "register-payment",
                applicationID: application.id,
                userID: auth.user?.id
            )
            let fingerprint = PaymentRegistrationFingerprint(
                amount: amount,
                paidAt: paidAtValue,
                accountId: accountId,
                method: method.nilIfBlank,
                reference: reference.nilIfBlank,
                note: note.nilIfBlank
            )
            let idempotencyKey = try identity.key(for: fingerprint)
            _ = try await PaymentApplicationsAPI().registerPayment(
                id: application.id,
                proofURL: proof.url,
                fileName: proof.filename,
                mimeType: proof.mimeType,
                idempotencyKey: idempotencyKey,
                amount: amount,
                paidAt: paidAtValue,
                accountId: accountId,
                method: method.nilIfBlank,
                reference: reference.nilIfBlank,
                note: note.nilIfBlank
            )
            identity.clear()
            NotificationCenter.default.post(name: .paymentApplicationsChanged, object: nil)
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not register the payment."
            // A definite client-side rejection did not move money. Give the
            // corrected payload a fresh identity; transport failures keep the
            // key so an exact retry cannot double-pay.
            if let apiError = error as? APIError, (400..<500).contains(apiError.status), apiError.status != 408, apiError.status != 409 {
                PaymentApplicationSubmissionIdentity(
                    kind: "register-payment",
                    applicationID: application.id,
                    userID: auth.user?.id
                ).clear()
            }
        }
        saving = false
    }
}

private struct PaymentApplicationEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let application: PaymentApplicationDetail
    let onDone: () -> Void

    @State private var preview: PaymentApplicationEmailPreview?
    @State private var to = ""
    @State private var cc = ""
    @State private var variant = "application"
    @State private var subject = ""
    @State private var message = ""
    @State private var selectedDocumentIDs = Set<String>()
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingView(label: "Preparing email...")
                } else {
                    Form {
                        Section("Message") {
                            LabeledContent(
                                "Document",
                                value: variant == "notice" ? "Payment notice" : "Application"
                            )
                            TextField("To", text: $to)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("CC (optional)", text: $cc)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Subject", text: $subject)
                            TextField("Message", text: $message, axis: .vertical)
                                .lineLimit(5...12)
                        }

                        if let documents = preview?.documents, !documents.isEmpty {
                            Section {
                                ForEach(documents) { document in
                                    Button { toggle(document.id) } label: {
                                        HStack {
                                            Image(systemName: selectedDocumentIDs.contains(document.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedDocumentIDs.contains(document.id) ? Theme.primary : Theme.muted)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(document.filename).foregroundStyle(Theme.text)
                                                Text("\(paymentApplicationLabel(document.kind)) · \(document.sizeBytes / 1024) KB")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.muted)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                Text("Supporting documents")
                            } footer: {
                                Text("Selected documents are emailed alongside the generated PDF and recorded in email history.")
                            }
                        }

                        if preview?.documentsTruncated == true {
                            Text("Only the newest supporting documents are shown.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.subheadline).foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
            .navigationTitle("Email payee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Sending..." : "Send") { Task { await send() } }
                        .disabled(saving || loading)
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .task { await loadPreview() }
    }

    @MainActor
    private func loadPreview() async {
        loading = true
        do {
            let result = try await PaymentApplicationsAPI().emailPreview(id: application.id)
            preview = result
            to = result.to
            cc = result.cc ?? ""
            // Variant and compose defaults are one server-authored snapshot.
            // Letting the client change only the variant paired a notice PDF
            // with the application subject and body.
            variant = result.variant
            subject = result.subject
            message = result.body
            selectedDocumentIDs = selectedDocumentIDs.intersection(Set((result.documents ?? []).map(\.id)))
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not prepare the email."
        }
        loading = false
    }

    private func toggle(_ id: String) {
        if selectedDocumentIDs.contains(id) {
            selectedDocumentIDs.remove(id)
        } else if selectedDocumentIDs.count < (preview?.maxAttachments ?? 20) {
            selectedDocumentIDs.insert(id)
        }
    }

    @MainActor
    private func send() async {
        guard to.nilIfBlank != nil else { errorMessage = "Enter the payee's email address."; return }
        guard let subject = subject.nilIfBlank else { errorMessage = "Enter an email subject."; return }
        guard let message = message.nilIfBlank else { errorMessage = "Enter an email message."; return }
        saving = true
        do {
            let attachmentIds = selectedDocumentIDs.isEmpty
                ? nil
                : (preview?.documents ?? [])
                    .filter { selectedDocumentIDs.contains($0.id) }
                    .map(\.id)
            let fingerprint = PaymentApplicationEmailFingerprint(
                to: to.nilIfBlank,
                cc: cc.nilIfBlank,
                variant: variant,
                subject: subject,
                body: message,
                attachmentIds: attachmentIds
            )
            let identity = PaymentApplicationSubmissionIdentity(
                kind: "send-email",
                applicationID: application.id,
                userID: auth.user?.id
            )
            let idempotencyKey = try identity.key(for: fingerprint)
            let result = try await PaymentApplicationsAPI().sendEmail(
                id: application.id,
                body: PaymentApplicationEmailInput(
                    idempotencyKey: idempotencyKey,
                    to: to.nilIfBlank,
                    cc: cc.nilIfBlank,
                    variant: variant,
                    subject: subject,
                    body: message,
                    attachmentIds: attachmentIds
                )
            )
            guard result.status == "SENT", result.warning == nil else {
                let message = result.warning
                    ?? (result.status == "FAILED"
                        ? "Delivery failed. Review the message and try a new attempt."
                        : "Delivery is still pending. Retry with the same message to check it.")
                if result.status == "FAILED" {
                    identity.clear()
                    await loadPreview()
                }
                errorMessage = message
                saving = false
                return
            }
            identity.clear()
            NotificationCenter.default.post(name: .paymentApplicationsChanged, object: nil)
            onDone()
            dismiss()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not send the email."
            if let apiError = error as? APIError,
               (400..<500).contains(apiError.status),
               apiError.status != 408
            {
                // Email preparation rejects stale document state with 409
                // before transport. It is therefore safe to start a new
                // identity, but only from a fresh status-sensitive preview.
                PaymentApplicationSubmissionIdentity(
                    kind: "send-email",
                    applicationID: application.id,
                    userID: auth.user?.id
                ).clear()
                await loadPreview()
            }
            errorMessage = message
        }
        saving = false
    }
}

private struct PaymentApplicationEmailFingerprint: Codable {
    let to: String?
    let cc: String?
    let variant: String
    let subject: String?
    let body: String?
    let attachmentIds: [String]?
}

struct VendorBankAccountsSection: View {
    @EnvironmentObject private var auth: AuthStore

    let vendorId: String

    @State private var accounts: [VendorBankAccount] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var editing: VendorBankAccountEditorTarget?
    @State private var deactivateTarget: VendorBankAccount?

    private var canManage: Bool { auth.has("paymentapps.bank.manage") }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                SectionHeader("Pay to")
                Spacer()
                if canManage {
                    Button { editing = VendorBankAccountEditorTarget(account: nil) } label: {
                        Label("Add account", systemImage: "plus")
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(busy)
                }
            }

            if !loaded {
                HStack { ProgressView(); Text("Loading bank accounts...") }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else if accounts.isEmpty {
                Text(canManage
                    ? "Add an active bank account before creating a payment application for this payee."
                    : "No bank accounts are on file.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(accounts) { account in
                Button { editing = VendorBankAccountEditorTarget(account: account) } label: {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Image(systemName: "building.columns")
                            .foregroundStyle(account.active ? Theme.primary : Theme.muted)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(account.label?.nilIfBlank ?? account.bankName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                if account.isDefault {
                                    Text("DEFAULT")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(Theme.primary)
                                        .background(Theme.primary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(account.beneficiaryName) · \(account.accountMasked)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            Text("\(account.currency) · \(account.bankCountry ?? "—")\(account.swift.map { " · SWIFT \($0)" } ?? "")")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if !account.active {
                            Text("INACTIVE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(Theme.Space.md)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .disabled(!canManage)
                .contextMenu {
                    if canManage && account.active && !account.isDefault {
                        Button("Make default") { Task { await setDefault(account) } }
                    }
                    if canManage && account.active {
                        Button("Deactivate", role: .destructive) { deactivateTarget = account }
                    }
                }
                .opacity(account.active ? 1 : 0.55)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            }
        }
        .task { if !loaded { await load() } }
        .sheet(item: $editing) { target in
            VendorBankAccountEditor(vendorId: vendorId, account: target.account) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Deactivate bank account?", isPresented: Binding(
            get: { deactivateTarget != nil },
            set: { if !$0 { deactivateTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deactivateTarget = nil }
            Button("Deactivate", role: .destructive) { Task { await deactivate() } }
        } message: {
            Text("Existing payment applications keep their frozen bank snapshot. New applications cannot select this account.")
        }
    }

    @MainActor
    private func load() async {
        do {
            accounts = try await VendorBankAccountsAPI().list(vendorId: vendorId)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load bank accounts."
        }
        loaded = true
    }

    @MainActor
    private func setDefault(_ account: VendorBankAccount) async {
        busy = true
        do {
            _ = try await VendorBankAccountsAPI().setDefault(vendorId: vendorId, id: account.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not set the default account."
        }
        busy = false
    }

    @MainActor
    private func deactivate() async {
        guard let target = deactivateTarget else { return }
        deactivateTarget = nil
        busy = true
        do {
            _ = try await VendorBankAccountsAPI().deactivate(vendorId: vendorId, id: target.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not deactivate the account."
        }
        busy = false
    }
}

private struct VendorBankAccountEditorTarget: Identifiable {
    let id = UUID()
    let account: VendorBankAccount?
}

private struct VendorBankAccountEditor: View {
    @Environment(\.dismiss) private var dismiss

    let vendorId: String
    let account: VendorBankAccount?
    let onSaved: () -> Void

    @State private var label: String
    @State private var beneficiaryName: String
    @State private var bankName: String
    @State private var accountNumber = ""
    @State private var bankCountry: String
    @State private var currency: String
    @State private var routingNumber: String
    @State private var swift: String
    @State private var bankAddress: String
    @State private var intermediaryBankName: String
    @State private var intermediarySwift: String
    @State private var intermediaryAccount = ""
    @State private var financeContactName: String
    @State private var financeContactEmail: String
    @State private var isDefault: Bool
    @State private var note: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(vendorId: String, account: VendorBankAccount?, onSaved: @escaping () -> Void) {
        self.vendorId = vendorId
        self.account = account
        self.onSaved = onSaved
        _label = State(initialValue: account?.label ?? "")
        _beneficiaryName = State(initialValue: account?.beneficiaryName ?? "")
        _bankName = State(initialValue: account?.bankName ?? "")
        _bankCountry = State(initialValue: account?.bankCountry ?? "US")
        _currency = State(initialValue: account?.currency ?? "USD")
        _routingNumber = State(initialValue: account?.routingNumber ?? "")
        _swift = State(initialValue: account?.swift ?? "")
        _bankAddress = State(initialValue: account?.bankAddress ?? "")
        _intermediaryBankName = State(initialValue: account?.intermediaryBankName ?? "")
        _intermediarySwift = State(initialValue: account?.intermediarySwift ?? "")
        _financeContactName = State(initialValue: account?.financeContactName ?? "")
        _financeContactEmail = State(initialValue: account?.financeContactEmail ?? "")
        _isDefault = State(initialValue: account?.isDefault ?? false)
        _note = State(initialValue: account?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Beneficiary") {
                    TextField("Label (optional)", text: $label)
                    TextField("Beneficiary name", text: $beneficiaryName)
                    TextField("Bank name", text: $bankName)
                    TextField(account == nil ? "Account number" : "New account number (blank keeps current)", text: $accountNumber)
                        .textInputAutocapitalization(.characters)
                    if let account {
                        LabeledContent("Current account", value: account.accountNumber ?? account.accountMasked)
                    }
                    HStack {
                        TextField("Country", text: $bankCountry)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: bankCountry) { _, value in bankCountry = String(value.uppercased().prefix(2)) }
                        TextField("Currency", text: $currency)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: currency) { _, value in currency = String(value.uppercased().prefix(8)) }
                    }
                    Toggle("Default for this currency", isOn: $isDefault)
                }

                Section("Routing") {
                    TextField("Routing number", text: $routingNumber)
                    TextField("SWIFT / BIC", text: $swift)
                        .textInputAutocapitalization(.characters)
                    TextField("Bank address", text: $bankAddress, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Intermediary bank") {
                    TextField("Bank name", text: $intermediaryBankName)
                    TextField("SWIFT / BIC", text: $intermediarySwift)
                        .textInputAutocapitalization(.characters)
                    TextField(account == nil ? "Account number" : "New account number (blank keeps current)", text: $intermediaryAccount)
                }

                Section("Finance contact") {
                    TextField("Name", text: $financeContactName)
                    TextField("Email", text: $financeContactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(account == nil ? "Add bank account" : "Edit bank account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    @MainActor
    private func save() async {
        guard beneficiaryName.nilIfBlank != nil else { errorMessage = "Beneficiary name is required."; return }
        guard bankName.nilIfBlank != nil else { errorMessage = "Bank name is required."; return }
        guard bankCountry.count == 2 else { errorMessage = "Use a two-letter bank country code."; return }
        guard currency.nilIfBlank != nil else { errorMessage = "Currency is required."; return }
        if account == nil, accountNumber.nilIfBlank == nil {
            errorMessage = "Account number is required."
            return
        }

        saving = true
        do {
            if let account {
                _ = try await VendorBankAccountsAPI().update(
                    vendorId: vendorId,
                    id: account.id,
                    body: VendorBankAccountPatchInput(
                        label: label.nilIfBlank,
                        beneficiaryName: beneficiaryName,
                        bankName: bankName,
                        accountNumber: accountNumber.nilIfBlank,
                        bankCountry: bankCountry,
                        currency: currency,
                        routingNumber: routingNumber.nilIfBlank,
                        swift: swift.nilIfBlank,
                        bankAddress: bankAddress.nilIfBlank,
                        intermediaryBankName: intermediaryBankName.nilIfBlank,
                        intermediarySwift: intermediarySwift.nilIfBlank,
                        intermediaryAccount: intermediaryAccount.nilIfBlank,
                        financeContactName: financeContactName.nilIfBlank,
                        financeContactEmail: financeContactEmail.nilIfBlank,
                        isDefault: isDefault,
                        note: note.nilIfBlank
                    )
                )
            } else {
                _ = try await VendorBankAccountsAPI().create(
                    vendorId: vendorId,
                    body: VendorBankAccountCreateInput(
                        label: label.nilIfBlank,
                        beneficiaryName: beneficiaryName,
                        bankName: bankName,
                        accountNumber: accountNumber,
                        bankCountry: bankCountry,
                        currency: currency,
                        routingNumber: routingNumber.nilIfBlank,
                        swift: swift.nilIfBlank,
                        bankAddress: bankAddress.nilIfBlank,
                        intermediaryBankName: intermediaryBankName.nilIfBlank,
                        intermediarySwift: intermediarySwift.nilIfBlank,
                        intermediaryAccount: intermediaryAccount.nilIfBlank,
                        financeContactName: financeContactName.nilIfBlank,
                        financeContactEmail: financeContactEmail.nilIfBlank,
                        isDefault: isDefault,
                        note: note.nilIfBlank
                    )
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the bank account."
        }
        saving = false
    }
}
