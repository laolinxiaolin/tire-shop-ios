import SwiftUI
import UIKit

enum CheckDisplay {
    static func received(_ value: String, locale: Locale, includeTime: Bool = false) -> String {
        guard let date = AppFormat.date(value) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = ShopClock.calendar
        formatter.timeZone = ShopClock.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        return formatter.string(from: date)
    }
}

struct CheckReminderBanner: View {
    @EnvironmentObject private var store: CheckReminderStore
    @EnvironmentObject private var i18n: I18nStore
    let openChecks: () -> Void

    var body: some View {
        if store.failed {
            HStack {
                Text(i18n.t("checks.reminderFailed")).font(.caption)
                Spacer()
                Button(i18n.t("common.retry")) { Task { await store.refresh() } }
                    .font(.caption)
            }
            .padding(Theme.Space.sm)
            .background(Theme.card)
        } else if let summary = store.summary,
                  summary.dueTodayCount + summary.overdueCount + summary.unscheduledCount > 0 {
            Button(action: openChecks) {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    Image(systemName: "banknote")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i18n.t("checks.reminderTitle")).font(.subheadline.weight(.semibold))
                        Text(reminderText(summary)).font(.caption)
                        Text(i18n.t("checks.dueAmount", ["amount": AppFormat.money(summary.totalAmount)]))
                            .font(.caption.weight(.medium))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(Theme.text)
                .padding(Theme.Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
            }
            .buttonStyle(.plain)
            .accessibilityHint(i18n.t("checks.viewChecks"))
        }
    }

    private func reminderText(_ summary: CheckReminderSummary) -> String {
        var parts: [String] = []
        if summary.dueTodayCount > 0 { parts.append(i18n.t("checks.dueTodayCount", ["n": summary.dueTodayCount])) }
        if summary.overdueCount > 0 { parts.append(i18n.t("checks.overdueCount", ["n": summary.overdueCount])) }
        if summary.unscheduledCount > 0 { parts.append(i18n.t("checks.unscheduledCount", ["n": summary.unscheduledCount])) }
        return parts.joined(separator: " · ")
    }
}

struct ChecksNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ChecksListStore()
    @State private var tab = "undeposited"
    @State private var cutoff = ShopClock.dayString(from: Date())
    @State private var today = ShopClock.dayString(from: Date())
    @State private var editing: String?
    @State private var plannedDate = Date()
    @State private var depositAccounts: [CashAccount] = []
    @State private var showDeposit = false
    @State private var openingDeposit = false
    @State private var exporting = false
    @State private var actionError: String?
    @State private var exportFile: CheckExportFile?

    private var canReport: Bool { auth.has("accounting.view") }
    private var canEdit: Bool { auth.has("payments.collect") || auth.has("accounting.manage") }
    private var canView: Bool { canReport || auth.has("payments.collect") }
    private var isCurrent: Bool { cutoff == today }

    @MainActor
    init(store: ChecksListStore? = nil) {
        _store = StateObject(wrappedValue: store ?? ChecksListStore())
    }

    var body: some View {
        Group {
            if !canView {
                EmptyStateView(text: i18n.t("checks.noAccess"))
            } else {
                VStack(spacing: 0) {
                    if canReport {
                        Picker(i18n.t("checks.title"), selection: $tab) {
                            Text(i18n.t("checks.undepositedTab")).tag("undeposited")
                            Text(i18n.t("checks.depositsTab")).tag("deposits")
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .disabled(store.saving)
                    }
                    if tab == "deposits", canReport {
                        CheckDepositHistoryView()
                    } else {
                        outstandingList
                    }
                }
            }
        }
        .background(Theme.background)
        .navigationTitle(i18n.t("checks.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canView && auth.has("accounting.manage") {
                ToolbarItem(placement: .primaryAction) {
                    Button(i18n.t("checks.depositAction")) { Task { await openDeposit() } }
                        .disabled(openingDeposit || store.saving)
                }
            }
        }
        .sheet(isPresented: $showDeposit) {
            TransferFundsSheet(accounts: depositAccounts, initialFromCode: "1010", initialToCode: "1020") {
                editing = nil
                Task { await reload() }
            }
        }
        .sheet(item: $exportFile) { file in
            CheckExportShareSheet(url: file.url)
        }
        .task(id: "\(cutoff):\(tab):\(canReport)") {
            editing = nil
            await reload()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            backgroundRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { backgroundRefresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkRegisterDidChange)) { _ in
            if !store.saving { Task { await reload() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCurrentChecks)) { _ in
            guard !store.saving else { return }
            today = ShopClock.dayString(from: Date())
            cutoff = today
            tab = "undeposited"
            editing = nil
            Task { await reload() }
        }
        .onChange(of: cutoff) { _, _ in exportFile = nil; actionError = nil }
        .onChange(of: canReport) { _, allowed in
            if !allowed { tab = "undeposited"; cutoff = today }
        }
        .alert(i18n.t("checks.title"), isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button(i18n.t("common.ok"), role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var outstandingList: some View {
        List {
            Section {
                DisclosureGroup(i18n.t("checks.about")) {
                    Text(i18n.t(canReport ? "checks.listHint" : "checks.currentHint"))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .font(.subheadline)
                if canReport {
                    DatePicker(i18n.t("checks.asOf"), selection: Binding(
                        get: { CheckDates.date(cutoff) ?? Date() },
                        set: { cutoff = CheckDates.string($0) }
                    ), in: ...Date(), displayedComponents: .date)
                    .disabled(store.saving)
                }
                HStack {
                    if canReport {
                        Button {
                            Task { await exportReport() }
                        } label: {
                            Label(i18n.t(exporting ? "common.exporting" : "checks.exportExcel"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(exporting || !store.ready || store.loading || store.saving)
                        Spacer()
                    }
                    Button(i18n.t("checks.refresh")) {
                        editing = nil
                        Task { await reload(resort: true) }
                    }
                    .disabled(store.loading || store.saving)
                }
                .buttonStyle(.borderless)
                Text(i18n.t(isCurrent ? "checks.orderHint" : "checks.historicalHint"))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let error = store.errorMessage {
                Section {
                    Text(error).foregroundStyle(Theme.danger)
                    Button(i18n.t("common.retry")) { Task { await reload() } }
                        .disabled(store.loading || store.saving)
                }
            }
            if store.loading {
                ProgressView(i18n.t("common.loading"))
            }
            if store.ready {
                Section {
                    LabeledContent(i18n.t("checks.count", ["n": store.items.count]), value: AppFormat.money(store.totalAmount))
                        .fontWeight(.semibold)
                    Text(store.timezone).font(.caption).foregroundStyle(Theme.muted)
                } header: {
                    Text(i18n.t("checks.cutoffSummary", ["date": cutoff]))
                }
                if store.items.isEmpty {
                    Text(i18n.t("checks.empty")).foregroundStyle(Theme.muted)
                }
                ForEach(store.items) { row in
                    Section {
                        checkRow(row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload(resort: true) }
    }

    private func checkRow(_ row: CheckRegisterItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.customerName ?? "—").font(.headline)
                Spacer()
                Text(AppFormat.money(row.amount)).font(.headline).monospacedDigit()
            }
            checkField("checks.checkNumber", row.reference)
            checkField("checks.receipt", row.receiptRef)
            checkField("checks.invoice", row.invoiceRef)
            checkField("checks.received", CheckDisplay.received(row.createdAt, locale: i18n.language.locale))
            if editing == row.id {
                DatePicker(i18n.t("checks.plannedDate"), selection: $plannedDate, displayedComponents: .date)
                    .disabled(store.saving)
                HStack {
                    Button(i18n.t("common.save")) {
                        Task {
                            if await store.saveDate(for: row, date: CheckDates.string(plannedDate)) { editing = nil }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(i18n.t("common.cancel")) { editing = nil }
                        .buttonStyle(.bordered)
                }
                .disabled(store.saving)
            } else {
                LabeledContent {
                    CheckDepositDateLabel(plannedDepositDate: row.plannedDepositDate, asOf: cutoff)
                } label: {
                    Text(i18n.t("checks.plannedDate"))
                }
                .font(.subheadline)
                if isCurrent, let date = row.plannedDepositDate, date <= today {
                    Text(i18n.t(date == today ? "checks.dueToday" : "checks.overdue"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if isCurrent && canEdit, row.paymentId != nil {
                    Button(i18n.t(row.plannedDepositDate == nil ? "checks.setDate" : "checks.changeDate")) {
                        plannedDate = row.plannedDepositDate.flatMap { CheckDates.date($0) } ?? Date()
                        editing = row.id
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.saving || store.loading)
                }
            }
            if let note = row.note, !note.isEmpty { checkField("checks.note", note) }
        }
        .padding(.vertical, Theme.Space.xs)
        .textSelection(.enabled)
    }

    private func checkField(_ key: String, _ value: String?) -> some View {
        LabeledContent(i18n.t(key), value: value ?? "—").font(.subheadline)
    }

    private func reload(resort: Bool = false) async {
        guard canView, tab == "undeposited" else { return }
        await store.load(asOf: canReport ? cutoff : today, today: today, canReport: canReport, resort: resort)
    }

    private func backgroundRefresh() {
        guard scenePhase == .active else { return }
        let nextToday = ShopClock.dayString(from: Date())
        if today != nextToday {
            if cutoff == today { cutoff = nextToday }
            today = nextToday
        }
        if editing == nil && isCurrent { Task { await reload() } }
    }

    private func openDeposit() async {
        guard !openingDeposit else { return }
        openingDeposit = true
        defer { openingDeposit = false }
        do {
            depositAccounts = try await CashAccountsAPI().list()
            showDeposit = true
        } catch { actionError = error.localizedDescription }
    }

    private func exportReport() async {
        guard !exporting, canReport else { return }
        exporting = true
        let requestedCutoff = cutoff
        defer { exporting = false }
        do {
            let url = try await AccountingAPI().exportUndepositedChecks(asOf: requestedCutoff)
            guard requestedCutoff == cutoff, canReport else {
                TemporaryDownloadStore.remove(url)
                return
            }
            exportFile = CheckExportFile(url: url)
        } catch { actionError = error.localizedDescription }
    }
}

private final class CheckExportFile: Identifiable {
    let id = UUID()
    let url: URL
    init(url: URL) { self.url = url }
    deinit { TemporaryDownloadStore.remove(url) }
}

private struct CheckExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct CheckDepositHistoryView: View {
    @EnvironmentObject private var i18n: I18nStore
    @State private var data: Paged<CashTransferDetail>?
    @State private var page = 1
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selected: CashTransferDetail?
    @State private var generation = 0
    private let pageSize = 20

    var body: some View {
        List {
            Text(i18n.t("checks.depositHistoryHint")).font(.footnote).foregroundStyle(Theme.muted)
            Button(i18n.t("checks.refresh")) { Task { await load() } }.disabled(loading)
            if loading { ProgressView(i18n.t("common.loading")) }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.danger)
                Button(i18n.t("common.retry")) { Task { await load() } }.disabled(loading)
            }
            if let data, data.page == page {
                if data.items.isEmpty { Text(i18n.t("checks.depositHistoryEmpty")) }
                ForEach(data.items) { transfer in
                    Section {
                        Button {
                            selected = transfer
                        } label: {
                            HStack {
                                Text(transfer.ref).font(.headline)
                                Spacer()
                                Text(AppFormat.money(transfer.amount)).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }
                        CheckTransferSummary(transfer: transfer)
                        ForEach(transfer.checks) { check in
                            CheckDepositSnapshotView(check: check)
                        }
                    }
                }
                HStack {
                    Button(i18n.t("common.prev")) { page -= 1 }.disabled(page <= 1 || loading)
                    Spacer()
                    Text(i18n.t("checks.page", ["page": page, "total": max(1, (data.total + pageSize - 1) / pageSize)]))
                        .font(.caption)
                    Spacer()
                    Button(i18n.t("common.next")) { page += 1 }.disabled(page * pageSize >= data.total || loading)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: page) { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .checkRegisterDidChange)) { _ in Task { await load() } }
        .sheet(item: $selected) { transfer in
            CheckTransferDetailSheet(transfer: transfer)
        }
    }

    private func load() async {
        generation += 1
        let request = generation
        loading = true
        errorMessage = nil
        defer { if request == generation { loading = false } }
        do {
            let result = try await CashAccountsAPI().checkDeposits(page: page, pageSize: pageSize)
            try Task.checkCancellation()
            guard request == generation else { return }
            let lastPage = max(1, (result.total + pageSize - 1) / pageSize)
            if page > lastPage { page = lastPage; return }
            data = result
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct CheckTransferSummary: View {
    @EnvironmentObject private var i18n: I18nStore
    let transfer: CashTransferDetail
    var body: some View {
        Group {
            LabeledContent(i18n.t("checks.depositDate"), value: CheckDisplay.received(transfer.createdAt, locale: i18n.language.locale, includeTime: true))
            LabeledContent(i18n.t("checks.depositBank"), value: "\(transfer.toAccount.code) · \(transfer.toAccount.name)")
            Text(i18n.t(transfer.reversedAt == nil ? "checks.deposited" : "accounting.cash.reversed"))
                .font(.subheadline.weight(.semibold))
            if let reversed = transfer.reversedAt {
                Text(CheckDisplay.received(reversed, locale: i18n.language.locale, includeTime: true)).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .font(.subheadline)
    }
}

private struct CheckDepositSnapshotView: View {
    @EnvironmentObject private var i18n: I18nStore
    let check: CashTransferCheck
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            LabeledContent(check.customerName ?? "—", value: AppFormat.money(check.amount)).fontWeight(.semibold)
            LabeledContent(i18n.t("checks.checkNumber"), value: check.checkNumber ?? "—")
            LabeledContent(i18n.t("checks.receipt"), value: check.receiptRef ?? "—")
            LabeledContent(i18n.t("checks.invoice"), value: check.invoiceRef ?? "—")
            if let method = check.methodName { LabeledContent(i18n.t("checks.method"), value: method) }
            if let note = check.note { LabeledContent(i18n.t("checks.note"), value: note) }
        }
        .font(.subheadline)
        .padding(.vertical, Theme.Space.xs)
        .textSelection(.enabled)
    }
}

private struct CheckTransferDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    let transfer: CashTransferDetail
    var body: some View {
        NavigationStack {
            List {
                Section {
                    CheckTransferSummary(transfer: transfer)
                    LabeledContent(i18n.t("accounting.cash.fromAccount"), value: "\(transfer.fromAccount.code) · \(transfer.fromAccount.name)")
                    LabeledContent(i18n.t("checks.amount"), value: AppFormat.money(transfer.amount))
                    LabeledContent(i18n.t("checks.fee"), value: AppFormat.money(transfer.fee))
                    LabeledContent(i18n.t("checks.netAmount"), value: AppFormat.money(transfer.netAmount))
                    if let reference = transfer.reference { LabeledContent(i18n.t("checks.depositReference"), value: reference) }
                    if let name = transfer.createdByName { LabeledContent(i18n.t("checks.recordedBy"), value: name) }
                    if let note = transfer.note { LabeledContent(i18n.t("checks.note"), value: note) }
                }
                Section(i18n.t("checks.depositInvoices")) {
                    ForEach(transfer.checks) { check in CheckDepositSnapshotView(check: check) }
                }
            }
            .navigationTitle(transfer.ref)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(i18n.t("common.close")) { dismiss() } } }
        }
    }
}
