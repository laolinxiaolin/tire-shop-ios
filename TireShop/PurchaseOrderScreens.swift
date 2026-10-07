import SwiftUI
import UniformTypeIdentifiers

/// Supplier agreements own shared terms and documents. Inventory, freight,
/// receipts and bills continue to be managed on each individual container.
struct PurchaseOrdersListNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    var supplierId: String? = nil

    @State private var search = ""
    @State private var data: Paged<PurchaseOrder>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var requestID = 0
    @State private var showingNew = false
    @State private var downloading = false
    @State private var exportPreview: PreviewFile?
    @State private var createdOrderId: String?
    @State private var visible = true

    private let pageSize = 25

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField(i18n.t("purchasing.po.search"), text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await load(page: 1) } }
                    .onChange(of: search) { _, value in
                        if value.count > 200 { search = String(value.prefix(200)) }
                    }
            }
            .padding(Theme.Space.md)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.sm)

            if let errorMessage {
                InlineErrorText(message: errorMessage)
                Button(i18n.t("common.retry")) { Task { await load(page: data?.page ?? 1) } }
                    .disabled(loading)
            }

            if loading && data == nil {
                LoadingView(label: i18n.t("common.loading"))
            } else {
                List {
                    if let data, data.items.isEmpty {
                        Text(i18n.t(search.nilIfBlank == nil && supplierId == nil ? "purchasing.po.empty" : "purchasing.po.noMatch"))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(data?.items ?? []) { order in
                        NavigationLink(value: AppRoute.purchaseOrderDetail(order.id)) {
                            PurchaseOrderRegisterRow(order: order)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load(page: data?.page ?? 1) }
            }

            if let data, data.total > 0 {
                PagedFooter(
                    page: data.page,
                    totalPages: max(1, (data.total + pageSize - 1) / pageSize),
                    total: data.total,
                    label: i18n.t("purchasing.purchaseOrders"),
                    singularLabel: i18n.t("purchasing.purchaseOrder"),
                    loading: loading
                ) {
                    Task { await load(page: max(1, data.page - 1)) }
                } onNext: {
                    Task { await load(page: data.page + 1) }
                }
            }
        }
        .background(Theme.background)
        .task(id: search) {
            if data != nil { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            await load(page: 1)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await export() } } label: {
                    if downloading { ProgressView() }
                    else { Label(i18n.t("purchasing.po.export"), systemImage: "square.and.arrow.up") }
                }
                .disabled(downloading)
                if auth.has("purchasing.manage") {
                    Button { showingNew = true } label: {
                        Label(i18n.t("purchasing.po.newTitle"), systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            PurchaseOrderHeaderSheet(order: nil, supplierId: supplierId) { order in
                showingNew = false
                createdOrderId = order.id
                Task { await load(page: 1) }
            }
        }
        .sheet(item: $exportPreview) { preview in QuickLookSheet(url: preview.url) }
        .navigationDestination(isPresented: Binding(
            get: { createdOrderId != nil },
            set: { if !$0 { createdOrderId = nil } }
        )) {
            if let createdOrderId { PurchaseOrderDetailNativeView(id: createdOrderId) }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; requestID += 1 }
    }

    @MainActor
    private func load(page: Int) async {
        let session = AppSessionIdentity(auth)
        requestID += 1
        let request = requestID
        loading = true
        errorMessage = nil
        do {
            let result = try await PurchaseOrdersAPI().list(q: search.nilIfBlank, supplierId: supplierId, page: page, pageSize: pageSize)
            try Task.checkCancellation()
            guard request == requestID, visible, session.isCurrent(auth), auth.has("purchasing.view") else { return }
            data = result
        } catch {
            guard request == requestID, visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if request == requestID { loading = false }
    }

    @MainActor
    private func export() async {
        guard !downloading else { return }
        let session = AppSessionIdentity(auth)
        downloading = true
        defer { downloading = false }
        do {
            let url = try await PurchaseOrdersAPI().export(q: search.nilIfBlank, supplierId: supplierId)
            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.view") else {
                TemporaryDownloadStore.remove(url)
                return
            }
            exportPreview = PreviewFile(url: url)
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseOrderRegisterRow: View {
    @EnvironmentObject private var i18n: I18nStore
    let order: PurchaseOrder

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(order.ref).fontWeight(.semibold)
                Spacer()
                PurchaseOrderStatusBadge(status: order.summary.status)
            }
            Text([order.supplier.name, order.supplierReference].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Theme.muted)
            Text(i18n.t("purchasing.po.progress", ["received": order.summary.receivedCount, "planned": order.summary.plannedCount]))
                .font(.caption)
            HStack {
                Text(i18n.t("purchasing.po.manifested"))
                Spacer()
                Text(AppFormat.money(order.summary.manifestedGoodsAmount))
            }
            HStack {
                Text(i18n.t("purchasing.po.paid"))
                Spacer()
                Text(AppFormat.money(order.summary.supplierPaid))
            }
            .font(.caption).foregroundStyle(Theme.muted)
            if let eta = order.summary.nextEtaAt {
                Text("\(i18n.t("purchasing.po.nextEta")): \(AppFormat.shortDate(eta))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if order.summary.missingEtaCount > 0 {
                Text(i18n.t("purchasing.po.missingEta", ["n": order.summary.missingEtaCount]))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if order.summary.lateCount > 0 {
                Text(i18n.t("purchasing.po.late", ["n": order.summary.lateCount]))
                    .font(.caption).foregroundStyle(.orange)
            }
            if order.summary.cancelledCount > 0 {
                Text(i18n.t("purchasing.po.cancelled", ["n": order.summary.cancelledCount]))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .font(.subheadline)
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct PurchaseOrderStatusBadge: View {
    @EnvironmentObject private var i18n: I18nStore
    let status: String

    private var color: Color {
        switch status {
        case "RECEIVED": Theme.success
        case "CANCELLED": Theme.danger
        case "PARTIALLY_RECEIVED": .orange
        default: Theme.primary
        }
    }

    var body: some View {
        Text(i18n.t("purchasing.po.status.\(status)"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private enum PurchaseOrderDetailTab: String, CaseIterable, Identifiable {
    case containers, payments, documents, history
    var id: String { rawValue }
    var key: String { self == .containers ? "purchasing.containers" : "purchasing.po.\(rawValue)" }
}

private enum PurchaseOrderEditor: String, Identifiable {
    case header, containers, membership, document
    var id: String { rawValue }
}

struct PurchaseOrderDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let id: String

    @State private var order: PurchaseOrder?
    @State private var loading = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var requestID = 0
    @State private var tab: PurchaseOrderDetailTab = .containers
    @State private var editor: PurchaseOrderEditor?
    @State private var editorSnapshot: PurchaseOrder?
    @State private var preview: PreviewFile?
    @State private var removeContainerTarget: PurchaseOrderContainer?
    @State private var removeContainerVersion: Int?
    @State private var removeDocumentTarget: PurchaseOrderAttachment?
    @State private var payments: [PurchaseOrderPayment]?
    @State private var paymentsError: String?
    @State private var paymentsLoading = false
    @State private var paymentsRequestID = 0
    @State private var paymentTarget: PurchaseOrderPayment?
    @State private var reloadToken = 0
    @State private var visible = true

    var body: some View {
        Group {
            if let order { content(order) }
            else if let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else { LoadingView(label: i18n.t("common.loading")) }
        }
        .navigationTitle(order?.ref ?? i18n.t("purchasing.purchaseOrder"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    Label(i18n.t("purchasing.po.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(busy || loading)
            }
        }
        .sheet(item: $editor) { editor in
            if let snapshot = editorSnapshot {
                switch editor {
                case .header:
                    PurchaseOrderHeaderSheet(order: snapshot) { _ in completed() }
                case .containers:
                    PurchaseOrderAddContainersSheet(order: snapshot) { completed() }
                case .membership:
                    PurchaseOrderMembershipSheet(order: snapshot) { completed() }
                case .document:
                    PurchaseOrderDocumentSheet(orderId: snapshot.id) { completed() }
                }
            }
        }
        .sheet(item: $preview) { file in QuickLookSheet(url: file.url) }
        .sheet(item: $paymentTarget) { payment in
            SupplierPaymentDetailSheet(id: payment.id, canReverse: auth.has("payables.pay")) {
                Task { await load() }
            }
        }
        .alert(i18n.t("purchasing.po.removeDraft"), isPresented: Binding(
            get: { removeContainerTarget != nil },
            set: { if !$0 { removeContainerTarget = nil } }
        ), presenting: removeContainerTarget) { container in
            Button(i18n.t("common.cancel"), role: .cancel) { removeContainerTarget = nil }
            Button(i18n.t("common.delete"), role: .destructive) {
                guard let version = removeContainerVersion else { return }
                Task { await mutate { _ = try await PurchaseOrdersAPI().removeContainer(id: id, containerId: container.id, expectedVersion: version) } }
            }
        } message: { container in
            Text(i18n.t("purchasing.po.removeDraftConfirm", ["ref": container.ref ?? container.id]))
        }
        .alert(i18n.t("purchasing.po.removeDocument"), isPresented: Binding(
            get: { removeDocumentTarget != nil },
            set: { if !$0 { removeDocumentTarget = nil } }
        ), presenting: removeDocumentTarget) { attachment in
            Button(i18n.t("common.cancel"), role: .cancel) { removeDocumentTarget = nil }
            Button(i18n.t("common.delete"), role: .destructive) {
                Task { await mutate { _ = try await PurchaseOrdersAPI().deleteAttachment(id: id, attachmentId: attachment.id) } }
            }
        }
        .task(id: "\(tab.rawValue)-\(reloadToken)") {
            if tab == .payments && auth.has("payables.view") { await loadPayments() }
        }
        .onChange(of: auth.has("payables.view")) { _, allowed in
            if !allowed {
                paymentsRequestID += 1
                payments = nil
                paymentsError = nil
                paymentTarget = nil
                if tab == .payments { tab = .containers }
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; requestID += 1; paymentsRequestID += 1 }
    }

    private func content(_ order: PurchaseOrder) -> some View {
        List {
            Section {
                HStack {
                    Text(order.ref).font(.headline)
                    Spacer()
                    PurchaseOrderStatusBadge(status: order.summary.status)
                }
                NavigationLink(value: AppRoute.supplierDetail(order.supplierId)) {
                    RowLine(title: i18n.t("purchasing.supplier"), trailing: order.supplier.name)
                }
                if let reference = order.supplierReference {
                    RowLine(title: i18n.t("purchasing.po.supplierReference"), trailing: reference)
                }
                if let orderedAt = order.orderedAt {
                    RowLine(title: i18n.t("status.ORDERED"), trailing: AppFormat.shortDate(orderedAt))
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(i18n.t("purchasing.po.paymentTerms")).fontWeight(.semibold)
                    Text(order.paymentTerms ?? "—").foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notes = order.notes { Text(notes).font(.subheadline) }
            }
            if let errorMessage { Section { PurchaseOrderMutationError(message: errorMessage) } }
            summarySection(order)
            progressSection(order.summary)
            if auth.has("purchasing.manage") { actionsSection(order) }

            Section {
                Picker(i18n.t("purchaseOrders.section"), selection: $tab) {
                    ForEach(PurchaseOrderDetailTab.allCases.filter { $0 != .payments || auth.has("payables.view") }) { tab in
                        Text(i18n.t(tab.key)).tag(tab)
                    }
                }
            }
            switch tab {
            case .containers: containersSection(order)
            case .payments: if auth.has("payables.view") { paymentsSection }
            case .documents: documentsSection(order)
            case .history: historySection(order)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func summarySection(_ order: PurchaseOrder) -> some View {
        let summary = order.summary
        return Section {
            RowLine(title: i18n.t("purchasing.po.goods"), subtitle: i18n.t(summary.goodsAmountSource == "AGREEMENT" ? "purchasing.po.agreementSource" : summary.goodsAmountSource == "MANIFEST" ? "purchasing.po.manifestSource" : "purchasing.po.incomplete"), trailing: amount(summary.goodsAmount))
            RowLine(title: i18n.t("purchasing.po.manifested"), subtitle: summary.manifestComplete ? nil : i18n.t("purchasing.po.incomplete"), trailing: AppFormat.money(summary.manifestedGoodsAmount))
            RowLine(title: i18n.t("purchasing.po.paid"), trailing: AppFormat.money(summary.supplierPaid))
            RowLine(title: i18n.t("purchasing.po.remaining"), subtitle: i18n.t("purchasing.po.remainingHelp"), trailing: amount(summary.goodsRemaining))
            RowLine(title: i18n.t("purchasing.po.openPayable"), trailing: AppFormat.money(summary.openPayable))
            RowLine(title: i18n.t("purchasing.po.dueNow"), trailing: AppFormat.money(summary.dueNow))
            RowLine(title: i18n.t("purchasing.po.futureDue"), trailing: AppFormat.money(summary.futureDue ?? 0))
            RowLine(title: i18n.t("purchasing.po.undated"), trailing: AppFormat.money(summary.undatedPayable ?? 0))
            if summary.legacySupplierPaid > 0 {
                warning("purchasing.po.legacyPaid", ["amount": AppFormat.money(summary.legacySupplierPaid)])
            }
            if let cancelled = summary.cancelledSupplierPaid, cancelled > 0 {
                warning("purchasing.po.cancelledPaid", ["amount": AppFormat.money(cancelled)])
            }
            if let count = summary.paidDiscrepancyCount, count > 0 {
                warning("purchasing.po.paidDiscrepancy", ["n": count])
            }
            if let excluded = summary.excludedOpenPayable, excluded > 0 {
                warning("purchasing.po.excludedObligations", ["amount": AppFormat.money(excluded)])
            }
            if let agreed = order.agreedGoodsAmount, summary.manifestComplete,
               abs(agreed - summary.manifestedGoodsAmount) > 0.005 {
                warning("purchasing.po.manifestMismatch")
            }
            if let remaining = summary.goodsRemaining, remaining < 0 { warning("purchasing.po.credit") }
        }
    }

    private func progressSection(_ summary: PurchaseOrderSummary) -> some View {
        Section {
            Text(i18n.t("purchasing.po.progress", ["received": summary.receivedCount, "planned": summary.plannedCount]))
                .font(.headline)
            ProgressView(value: Double(summary.receivedCount), total: Double(max(1, summary.plannedCount)))
                .tint(Theme.success)
                .accessibilityLabel(i18n.t("purchasing.containerCount"))
            Text(i18n.t("purchasing.po.quantities", ["received": summary.receivedQty, "total": summary.totalQty]))
                .font(.caption).foregroundStyle(Theme.muted)
            RowLine(title: i18n.t("purchasing.po.nextEta"), trailing: summary.nextEtaAt.map(AppFormat.shortDate) ?? "—")
            if summary.missingEtaCount > 0 { warning("purchasing.po.missingEta", ["n": summary.missingEtaCount]) }
            if summary.lateCount > 0 { warning("purchasing.po.late", ["n": summary.lateCount]) }
            if summary.cancelledCount > 0 { warning("purchasing.po.cancelled", ["n": summary.cancelledCount]) }
            if summary.unassignedCount > 0 { warning("purchasing.po.unassigned", ["n": summary.unassignedCount]) }
        }
    }

    private func actionsSection(_ order: PurchaseOrder) -> some View {
        Section {
            Button(i18n.t("purchasing.po.edit")) { open(.header, order: order) }
            if order.orderedAt == nil && order.summary.status != "CANCELLED" {
                Button(i18n.t("purchasing.po.issue")) {
                    Task { await mutate { _ = try await PurchaseOrdersAPI().issue(id: id, expectedVersion: order.version) } }
                }
                Text(i18n.t("purchasing.po.issueHelp")).font(.caption).foregroundStyle(Theme.muted)
            }
            Button(i18n.t("purchasing.po.add")) { open(.containers, order: order) }
            Button(i18n.t("purchasing.po.link")) { open(.membership, order: order) }
        }
        .disabled(busy || loading)
    }

    private func containersSection(_ order: PurchaseOrder) -> some View {
        Section(i18n.t("purchasing.containers")) {
            ForEach(order.containers) { container in
                NavigationLink(value: AppRoute.containerDetail(container.id)) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        RowLine(title: container.ref ?? container.id, subtitle: [container.reference, container.bolNumber].compactMap { $0?.nilIfBlank }.joined(separator: " · "), trailing: i18n.t("status.\(container.status)"))
                        Text("\(container.location) · \(container.totalQty) \(i18n.t("purchasing.totalTires")) · \(AppFormat.money(container.goodsAmount))")
                            .font(.caption).foregroundStyle(Theme.muted)
                        if let receivedAt = container.receivedAt {
                            Text("\(i18n.t("status.RECEIVED")) · \(AppFormat.shortDate(receivedAt))")
                                .font(.caption).foregroundStyle(Theme.success)
                        } else if let eta = container.etaAt {
                            Text("\(i18n.t("purchasing.eta")): \(AppFormat.shortDate(eta))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if auth.has("purchasing.manage") && container.canRemove == true {
                    Button(i18n.t("purchasing.po.removeDraft"), role: .destructive) {
                        removeContainerVersion = order.version
                        removeContainerTarget = container
                    }
                        .disabled(busy)
                }
            }
        }
    }

    private var paymentsSection: some View {
        Section(i18n.t("purchasing.po.payments")) {
            if let paymentsError {
                Text(paymentsError).foregroundStyle(Theme.danger)
                Button(i18n.t("common.retry")) { Task { await loadPayments() } }
            }
            if paymentsLoading && payments == nil { ProgressView() }
            if payments?.isEmpty == true { Text(i18n.t("purchasing.po.noPayments")).foregroundStyle(Theme.muted) }
            ForEach(payments ?? []) { payment in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Button { paymentTarget = payment } label: {
                        RowLine(title: payment.ref ?? payment.reference ?? payment.id, subtitle: "\(AppFormat.shortDate(payment.paidAt)) · \(payment.method ?? "—")", trailing: AppFormat.money(payment.poAllocatedAmount))
                    }
                    Text(i18n.t("purchasing.po.paymentAllocation")).font(.caption).foregroundStyle(Theme.muted)
                    ForEach(payment.allocations) { allocation in
                        NavigationLink(value: AppRoute.containerDetail(allocation.containerId)) {
                            RowLine(title: allocation.containerRef ?? allocation.containerId, subtitle: allocation.surviving ? i18n.t("purchasing.costCategory.\(allocation.category)") : i18n.t("purchasing.po.reversed"), trailing: AppFormat.money(allocation.amount))
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }

    private func documentsSection(_ order: PurchaseOrder) -> some View {
        Section(i18n.t("purchasing.po.documents")) {
            if auth.has("purchasing.manage") {
                Button(i18n.t("purchasing.po.upload")) { open(.document, order: order) }.disabled(busy)
            }
            if (order.attachments ?? []).isEmpty { Text(i18n.t("purchasing.po.noDocuments")).foregroundStyle(Theme.muted) }
            ForEach(order.attachments ?? []) { attachment in
                Button {
                    Task {
                        let session = AppSessionIdentity(auth)
                        do {
                            let url = try await PurchaseOrdersAPI().downloadAttachment(id: id, attachment: attachment)
                            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.view") else {
                                TemporaryDownloadStore.remove(url)
                                return
                            }
                            preview = PreviewFile(url: url)
                        } catch {
                            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    RowLine(title: attachment.filename, subtitle: "\(i18n.t("purchasing.po.kind.\(attachment.kind)")) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file)) · \(AppFormat.shortDate(attachment.createdAt))", trailing: nil)
                }
                if let note = attachment.note { Text(note).font(.caption).foregroundStyle(Theme.muted) }
                if auth.has("purchasing.manage") {
                    Button(i18n.t("common.delete"), role: .destructive) { removeDocumentTarget = attachment }.disabled(busy)
                }
            }
        }
    }

    private func historySection(_ order: PurchaseOrder) -> some View {
        Section(i18n.t("purchasing.po.history")) {
            if (order.auditHistory ?? []).isEmpty { Text(i18n.t("purchasing.po.noHistory")).foregroundStyle(Theme.muted) }
            ForEach(order.auditHistory ?? []) { entry in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(i18n.t(Self.auditKeys[entry.action] ?? "purchasing.po.amended")).fontWeight(.semibold)
                    Text([AppFormat.dateTime(entry.createdAt), entry.user?.fullName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let reason = entry.data?["reason"]?.purchaseOrderString, entry.action != "purchaseOrder.container.remove" {
                        Text(reason).font(.subheadline)
                    }
                    if entry.action == "purchaseOrder.container.move" {
                        if let containerRef = entry.data?["containerRef"]?.purchaseOrderString { Text(containerRef).font(.caption) }
                        auditOrderLink(entry, idKey: "fromPurchaseOrderId", refKey: "fromPurchaseOrderRef", labelKey: "purchasing.po.previousOrder")
                        auditOrderLink(entry, idKey: "toPurchaseOrderId", refKey: "toPurchaseOrderRef", labelKey: "purchasing.po.newOrder")
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }

    @ViewBuilder
    private func auditOrderLink(_ entry: PurchaseOrderAuditEntry, idKey: String, refKey: String, labelKey: String) -> some View {
        if let orderId = entry.data?[idKey]?.purchaseOrderString {
            NavigationLink(value: AppRoute.purchaseOrderDetail(orderId)) {
                RowLine(title: i18n.t(labelKey), trailing: entry.data?[refKey]?.purchaseOrderString ?? orderId)
            }
        } else {
            RowLine(title: i18n.t(labelKey), trailing: i18n.t("purchasing.po.unlinked"))
        }
    }

    private static let auditKeys: [String: String] = [
        "purchaseOrder.create": "purchasing.po.audit.create", "purchaseOrder.update": "purchasing.po.audit.update",
        "purchaseOrder.issue": "purchasing.po.audit.issue", "purchaseOrder.containers.add": "purchasing.po.audit.containers.add",
        "purchaseOrder.container.move": "purchasing.po.audit.container.move", "purchaseOrder.container.remove": "purchasing.po.audit.container.remove",
        "purchaseOrder.attachment.add": "purchasing.po.audit.attachment.add", "purchaseOrder.attachment.remove": "purchasing.po.audit.attachment.remove",
        "purchaseOrder.supplier.change": "purchasing.po.audit.supplier.change",
    ]

    private func warning(_ key: String, _ parameters: [String: CustomStringConvertible] = [:]) -> some View {
        Text(i18n.t(key, parameters)).font(.caption).foregroundStyle(.orange)
    }

    private func amount(_ value: Double?) -> String { value.map(AppFormat.money) ?? i18n.t("purchasing.po.incomplete") }

    private func open(_ editor: PurchaseOrderEditor, order: PurchaseOrder) {
        editorSnapshot = order
        self.editor = editor
    }

    private func completed() {
        editor = nil
        editorSnapshot = nil
        Task { await load() }
    }

    @MainActor
    private func load() async {
        let session = AppSessionIdentity(auth)
        requestID += 1
        let request = requestID
        loading = true
        errorMessage = nil
        do {
            let result = try await PurchaseOrdersAPI().get(id: id)
            try Task.checkCancellation()
            guard request == requestID, visible, session.isCurrent(auth), auth.has("purchasing.view") else { return }
            order = result
            reloadToken += 1
        } catch {
            guard request == requestID, visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if request == requestID { loading = false }
    }

    @MainActor
    private func mutate(_ action: () async throws -> Void) async {
        guard !busy, auth.has("purchasing.manage") else { return }
        let session = AppSessionIdentity(auth)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await action()
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            await load()
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadPayments() async {
        guard auth.has("payables.view") else { return }
        let session = AppSessionIdentity(auth)
        paymentsRequestID += 1
        let request = paymentsRequestID
        paymentsLoading = true
        paymentsError = nil
        do {
            let result = try await PurchaseOrdersAPI().payments(id: id)
            try Task.checkCancellation()
            guard request == paymentsRequestID, visible, session.isCurrent(auth), auth.has("payables.view") else { return }
            payments = result
        } catch {
            guard request == paymentsRequestID, visible, session.isCurrent(auth), !Task.isCancelled else { return }
            paymentsError = error.localizedDescription
        }
        if request == paymentsRequestID { paymentsLoading = false }
    }
}

private extension JSONValue {
    var purchaseOrderString: String? { if case .string(let value) = self { return value }; return nil }
}

private struct PurchaseOrderMutationError: View {
    @EnvironmentObject private var i18n: I18nStore
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(message).foregroundStyle(Theme.danger)
            Text(i18n.t("purchasing.po.conflictHelp")).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

/// Validate the accounting amount before converting it to a JSON number.
/// Blank is an intentional clear; malformed or over-precision input is rejected.
struct PurchaseOrderHeaderDraft: Equatable {
    var supplierReference = ""
    var plannedContainerCount = "1"
    var paymentTerms = ""
    var agreedGoodsAmount = ""
    var notes = ""

    init(order: PurchaseOrder? = nil) {
        guard let order else { return }
        supplierReference = order.supplierReference ?? ""
        plannedContainerCount = String(order.plannedContainerCount)
        paymentTerms = order.paymentTerms ?? ""
        agreedGoodsAmount = order.agreedGoodsAmount.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
        notes = order.notes ?? ""
    }

    var amount: Double? { Double(agreedGoodsAmount.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var validAmount: Bool {
        let value = agreedGoodsAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return true }
        guard value.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let number = Double(value), number.isFinite else { return false }
        return number >= 0 && number <= 999_999_999_999.99
    }

    func validCount(minimumCount: Int, maximumCount: Int) -> Bool {
        guard maximumCount >= minimumCount, let count = Int(plannedContainerCount),
              (minimumCount...maximumCount).contains(count) else { return false }
        return true
    }

    func valid(minimumCount: Int, maximumCount: Int) -> Bool {
        validCount(minimumCount: minimumCount, maximumCount: maximumCount)
            && validAmount && supplierReference.count <= 200 && paymentTerms.count <= 4000 && notes.count <= 10000
    }

    func createInput(supplierId: String, idempotencyKey: String) -> PurchaseOrderCreateInput? {
        guard supplierId.nilIfBlank != nil, valid(minimumCount: 1, maximumCount: 100), let count = Int(plannedContainerCount) else { return nil }
        return PurchaseOrderCreateInput(supplierId: supplierId, supplierReference: supplierReference.nilIfBlank, plannedContainerCount: count, agreedGoodsAmount: amount, paymentTerms: paymentTerms.nilIfBlank, notes: notes.nilIfBlank, idempotencyKey: idempotencyKey)
    }

    func updateInput(order: PurchaseOrder) -> PurchaseOrderUpdateInput? {
        guard valid(minimumCount: max(1, order.summary.containerCount), maximumCount: 10000), let count = Int(plannedContainerCount) else { return nil }
        return PurchaseOrderUpdateInput(expectedVersion: order.version, supplierReference: supplierReference.nilIfBlank, plannedContainerCount: count, agreedGoodsAmount: amount, paymentTerms: paymentTerms.nilIfBlank, notes: notes.nilIfBlank)
    }
}

private struct PurchaseOrderHeaderFields: View {
    @EnvironmentObject private var i18n: I18nStore
    @Binding var draft: PurchaseOrderHeaderDraft

    var body: some View {
        TextField(i18n.t("purchasing.po.supplierReference"), text: $draft.supplierReference)
            .onChange(of: draft.supplierReference) { _, value in
                if value.count > 200 { draft.supplierReference = String(value.prefix(200)) }
            }
        TextField(i18n.t("purchasing.po.plannedCount"), text: $draft.plannedContainerCount).keyboardType(.numberPad)
        TextField(i18n.t("purchasing.po.paymentTerms"), text: $draft.paymentTerms, axis: .vertical).lineLimit(2...5)
            .onChange(of: draft.paymentTerms) { _, value in
                if value.count > 4000 { draft.paymentTerms = String(value.prefix(4000)) }
            }
        TextField(i18n.t("purchasing.po.agreedGoodsAmount"), text: $draft.agreedGoodsAmount).keyboardType(.decimalPad)
        Text(i18n.t("purchasing.po.amountHelp")).font(.caption).foregroundStyle(Theme.muted)
        if !draft.validAmount { Text(i18n.t("purchaseOrders.invalidAmount")).font(.caption).foregroundStyle(Theme.danger) }
        TextField(i18n.t("purchasing.notesField"), text: $draft.notes, axis: .vertical).lineLimit(2...5)
            .onChange(of: draft.notes) { _, value in
                if value.count > 10000 { draft.notes = String(value.prefix(10000)) }
            }
    }
}

private struct PurchaseOrderHeaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let order: PurchaseOrder?
    let onSaved: (PurchaseOrder) -> Void

    @State private var supplierId: String
    @State private var draft: PurchaseOrderHeaderDraft
    @State private var suppliers: [Supplier] = []
    @State private var busy = false
    @State private var errorMessage: String?
    // An uncertain network response can be retried without creating another PO.
    @State private var idempotencyKey = UUID().uuidString
    @State private var visible = true

    init(order: PurchaseOrder?, supplierId: String? = nil, onSaved: @escaping (PurchaseOrder) -> Void) {
        self.order = order
        self.onSaved = onSaved
        _supplierId = State(initialValue: order?.supplierId ?? supplierId ?? "")
        _draft = State(initialValue: PurchaseOrderHeaderDraft(order: order))
    }

    private var valid: Bool {
        !supplierId.isEmpty && draft.valid(minimumCount: max(1, order?.summary.containerCount ?? 1), maximumCount: order == nil ? 100 : 10000)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let order { Text(order.supplier.name).fontWeight(.semibold) }
                    else {
                        Picker(i18n.t("purchasing.supplier"), selection: $supplierId) {
                            Text(i18n.t("purchasing.pickSupplier")).tag("")
                            ForEach(suppliers) { supplier in Text(supplier.name).tag(supplier.id) }
                        }
                    }
                    PurchaseOrderHeaderFields(draft: $draft)
                }
                .disabled(busy)
                if !draft.validCount(minimumCount: max(1, order?.summary.containerCount ?? 1), maximumCount: order == nil ? 100 : 10000) {
                    Section {
                        Text(i18n.t("purchaseOrders.validCount", ["min": max(1, order?.summary.containerCount ?? 1), "max": order == nil ? 100 : 10000]))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                if let errorMessage { Section { PurchaseOrderMutationError(message: errorMessage) } }
                Section {
                    PrimaryButton(title: i18n.t(order == nil ? "purchasing.po.newTitle" : "common.save"), loading: busy) { Task { await save() } }
                        .disabled(!valid || !auth.has("purchasing.manage"))
                }
            }
            .navigationTitle(i18n.t(order == nil ? "purchasing.po.newTitle" : "purchasing.po.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(i18n.t("common.cancel")) { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                if order == nil {
                    let session = AppSessionIdentity(auth)
                    do {
                        let result = try await SuppliersAPI().list(pageSize: 1000).items
                        guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
                        suppliers = result
                    } catch {
                        guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
        }
    }

    @MainActor
    private func save() async {
        guard !busy, valid, auth.has("purchasing.manage") else { return }
        let session = AppSessionIdentity(auth)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let result: PurchaseOrder
            if let order, let input = draft.updateInput(order: order) {
                result = try await PurchaseOrdersAPI().update(id: order.id, body: input)
            } else if order == nil, let input = draft.createInput(supplierId: supplierId, idempotencyKey: idempotencyKey) {
                result = try await PurchaseOrdersAPI().create(body: input)
            } else { return }
            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.manage") else { return }
            onSaved(result)
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseOrderAddContainersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let order: PurchaseOrder
    let onSaved: () -> Void

    @State private var count = "1"
    @State private var copyFrom = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var visible = true

    private var valid: Bool { Int(count).map { (1...100).contains($0) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(order.ref) · \(order.supplier.name)").fontWeight(.semibold)
                    TextField(i18n.t("purchasing.po.batchCount"), text: $count).keyboardType(.numberPad)
                    if !valid {
                        Text(i18n.t("purchaseOrders.validCount", ["min": 1, "max": 100]))
                            .font(.caption).foregroundStyle(Theme.danger)
                    }
                    Picker(i18n.t("purchasing.po.copyManifest"), selection: $copyFrom) {
                        Text(i18n.t("purchasing.po.emptyManifest")).tag("")
                        ForEach(order.containers.filter { $0.totalQty > 0 }) { container in
                            Text("\(container.ref ?? container.id) · \(container.totalQty)").tag(container.id)
                        }
                    }
                    Text(i18n.t("purchasing.po.batchHelp")).font(.caption).foregroundStyle(Theme.muted)
                }
                .disabled(busy)
                if let errorMessage { Section { PurchaseOrderMutationError(message: errorMessage) } }
                Section {
                    PrimaryButton(title: i18n.t("purchasing.po.batchCreate"), loading: busy) { Task { await save() } }
                        .disabled(!valid || !auth.has("purchasing.manage"))
                }
            }
            .navigationTitle(i18n.t("purchasing.po.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(i18n.t("common.cancel")) { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .onAppear { visible = true }
            .onDisappear { visible = false }
        }
    }

    @MainActor
    private func save() async {
        guard !busy, valid, let count = Int(count), auth.has("purchasing.manage") else { return }
        let session = AppSessionIdentity(auth)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            _ = try await PurchaseOrdersAPI().addContainers(id: order.id, body: PurchaseOrderAddContainersInput(expectedVersion: order.version, count: count, copyFromContainerId: copyFrom.nilIfBlank))
            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.manage") else { return }
            onSaved()
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseOrderMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let order: PurchaseOrder
    let onSaved: () -> Void

    @State private var search = ""
    @State private var candidates: [ContainerListItem] = []
    @State private var selectedId = ""
    @State private var reason = ""
    @State private var increaseSlots = false
    @State private var loading = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var requestID = 0
    @State private var visible = true

    private var selected: ContainerListItem? { candidates.first { $0.id == selectedId } }
    private var needsSlot: Bool { order.summary.containerCount + 1 > order.plannedContainerCount }
    private var valid: Bool {
        guard let selected, let reason = reason.nilIfBlank, reason.count <= 1000,
              (selected.purchaseOrderId ?? selected.purchaseOrder?.id) == nil || selected.purchaseOrder?.version != nil else { return false }
        return (!needsSlot || increaseSlots) && !loading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(order.ref) · \(order.supplier.name)").fontWeight(.semibold)
                    TextField(i18n.t("purchasing.po.searchContainer"), text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: search) { _, _ in selectedId = "" }
                    Picker(i18n.t("purchasing.containers"), selection: $selectedId) {
                        Text(loading ? i18n.t("common.loading") : "—").tag("")
                        ForEach(candidates) { container in
                            Text("\(container.ref ?? container.id) · \(i18n.t("status.\(container.status)")) · \(container.reference ?? "")").tag(container.id)
                        }
                    }
                    if loading { ProgressView() }
                }
                .disabled(busy)
                if let selected {
                    Section {
                        RowLine(title: i18n.t("purchasing.po.currentOrder"), trailing: selected.purchaseOrder?.ref ?? i18n.t("purchasing.po.unlinked"))
                        RowLine(title: i18n.t("purchasing.po.newOrder"), trailing: order.ref)
                        RowLine(title: i18n.t("purchasing.refBol"), subtitle: selected.reference, trailing: selected.bolNumber ?? "—")
                        Text(i18n.t("status.\(selected.status)"))
                        TextField(i18n.t("purchasing.po.reason"), text: $reason, axis: .vertical).lineLimit(2...5)
                            .onChange(of: reason) { _, value in
                                if value.count > 1000 { reason = String(value.prefix(1000)) }
                            }
                        if needsSlot { Toggle(i18n.t("purchasing.po.increaseSlots", ["n": order.summary.containerCount + 1]), isOn: $increaseSlots) }
                        Text(i18n.t("purchasing.po.linkHelp")).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .disabled(busy)
                }
                if let errorMessage { Section { PurchaseOrderMutationError(message: errorMessage) } }
                Section {
                    PrimaryButton(title: i18n.t("purchasing.po.linkConfirm"), loading: busy) { Task { await save() } }
                        .disabled(!valid || !auth.has("purchasing.manage"))
                }
            }
            .navigationTitle(i18n.t("purchasing.po.linkTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(i18n.t("common.cancel")) { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task(id: search) { await searchCandidates() }
            .onAppear { visible = true }
            .onDisappear { visible = false; requestID += 1 }
        }
    }

    @MainActor
    private func searchCandidates() async {
        let session = AppSessionIdentity(auth)
        requestID += 1
        let request = requestID
        loading = true
        defer { if request == requestID { loading = false } }
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = try await PurchaseOrdersAPI().candidates(supplierId: order.supplierId, excludingOrderId: order.id, q: search.nilIfBlank)
            try Task.checkCancellation()
            guard request == requestID, visible, session.isCurrent(auth), auth.has("purchasing.manage") else { return }
            candidates = result
            errorMessage = nil
        } catch {
            guard request == requestID, visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard !busy, valid, let selected, let reason = reason.nilIfBlank, auth.has("purchasing.manage") else { return }
        let session = AppSessionIdentity(auth)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let sourceOrderId = selected.purchaseOrderId ?? selected.purchaseOrder?.id
            let input = PurchaseOrderMoveContainerInput(
                purchaseOrderId: order.id,
                expectedPurchaseOrderId: sourceOrderId,
                expectedVersion: order.version,
                expectedSourceVersion: sourceOrderId == nil ? nil : selected.purchaseOrder?.version,
                plannedContainerCount: needsSlot ? order.summary.containerCount + 1 : nil,
                reason: reason
            )
            _ = try await PurchaseOrdersAPI().moveContainer(containerId: selected.id, body: input)
            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.manage") else { return }
            onSaved()
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseOrderDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let orderId: String
    let onSaved: () -> Void

    @State private var kind = "OTHER"
    @State private var note = ""
    @State private var file: URL?
    @State private var filename = ""
    @State private var showingImporter = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var visible = true

    private static let allowedTypes: [UTType] = ["pdf", "jpg", "jpeg", "png", "webp", "heic", "heif", "docx", "xlsx"].compactMap { UTType(filenameExtension: $0) }
    private let kinds = ["RECEIPT", "BOL", "PACKING_LIST", "INVOICE", "PHOTO", "OTHER"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(i18n.t("purchasing.po.documentKind"), selection: $kind) {
                        ForEach(kinds, id: \.self) { kind in Text(i18n.t("purchasing.po.kind.\(kind)")).tag(kind) }
                    }
                    Button { showingImporter = true } label: {
                        Label(filename.isEmpty ? i18n.t("purchasing.po.documentFile") : filename, systemImage: "folder")
                    }
                    TextField(i18n.t("purchasing.notesField"), text: $note, axis: .vertical).lineLimit(2...5)
                        .onChange(of: note) { _, value in
                            if value.count > 4000 { note = String(value.prefix(4000)) }
                        }
                }
                .disabled(busy)
                if let errorMessage { Section { PurchaseOrderMutationError(message: errorMessage) } }
                Section {
                    PrimaryButton(title: i18n.t("purchasing.po.upload"), loading: busy) { Task { await save() } }
                        .disabled(file == nil || note.count > 4000 || !auth.has("purchasing.manage"))
                }
            }
            .navigationTitle(i18n.t("purchasing.po.upload"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(i18n.t("common.cancel")) { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.allowedTypes) { result in
                do {
                    let source = try result.get()
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let values = try source.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
                        errorMessage = i18n.t("purchaseOrders.uploadLimit")
                        return
                    }
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent("po-document-\(UUID().uuidString).\(source.pathExtension)")
                    try FileManager.default.copyItem(at: source, to: target)
                    if let file { try? FileManager.default.removeItem(at: file) }
                    file = target
                    filename = source.lastPathComponent
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
            .onAppear { visible = true }
            .onDisappear {
                visible = false
                if let file { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    @MainActor
    private func save() async {
        guard !busy, let file, note.count <= 4000, auth.has("purchasing.manage") else { return }
        let session = AppSessionIdentity(auth)
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            _ = try await PurchaseOrdersAPI().uploadAttachment(id: orderId, fileURL: file, fileName: filename, mimeType: mime, kind: kind, note: note.nilIfBlank)
            guard visible, session.isCurrent(auth), !Task.isCancelled, auth.has("purchasing.manage") else { return }
            onSaved()
        } catch {
            guard visible, session.isCurrent(auth), !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
