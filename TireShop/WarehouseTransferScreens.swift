import Foundation
import SwiftUI

// MARK: - Warehouses

struct WarehousesNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var warehouses: [Warehouse] = []
    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editorTarget: WarehouseEditorTarget?
    @State private var warehouseToDeactivate: Warehouse?
    @State private var workingWarehouseId: String?

    private var canManage: Bool { auth.has("warehouses.manage") }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading warehouses...")
            } else if let errorMessage, warehouses.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                List {
                    Section {
                        Text("Warehouses are the stock locations used by sales, counts, purchasing, and transfers. The default is used when no location is selected.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    if warehouses.isEmpty {
                        Section {
                            Text("No warehouses found.")
                                .foregroundStyle(Theme.muted)
                        }
                    } else {
                        Section("Locations") {
                            ForEach(warehouses) { warehouse in
                                WarehouseRow(
                                    warehouse: warehouse,
                                    working: workingWarehouseId == warehouse.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard canManage else { return }
                                    editorTarget = WarehouseEditorTarget(warehouse: warehouse)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canManage {
                                        Button {
                                            editorTarget = WarehouseEditorTarget(warehouse: warehouse)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Theme.primary)

                                        if !warehouse.isDefault {
                                            Button {
                                                if warehouse.active {
                                                    warehouseToDeactivate = warehouse
                                                } else {
                                                    Task { await setActive(warehouse, active: true) }
                                                }
                                            } label: {
                                                Label(
                                                    warehouse.active ? "Deactivate" : "Reactivate",
                                                    systemImage: warehouse.active ? "pause.circle" : "play.circle"
                                                )
                                            }
                                            .tint(warehouse.active ? Theme.danger : Theme.success)
                                        }
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if canManage, warehouse.active, !warehouse.isDefault {
                                        Button {
                                            Task { await makeDefault(warehouse) }
                                        } label: {
                                            Label("Make default", systemImage: "star")
                                        }
                                        .tint(Theme.success)
                                    }
                                }
                            }
                        }

                        Section("Inventory totals") {
                            LabeledContent("On hand", value: warehouses.reduce(0) { $0 + $1.qtyOnHand }.formatted())
                            LabeledContent("Reserved", value: warehouses.reduce(0) { $0 + $1.qtyReserved }.formatted())
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .background(Theme.background)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = WarehouseEditorTarget(warehouse: nil)
                    } label: {
                        Label("New warehouse", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            WarehouseEditorNativeView(warehouse: target.warehouse) {
                Task { await load() }
            }
        }
        .alert(
            "Deactivate warehouse?",
            isPresented: Binding(
                get: { warehouseToDeactivate != nil },
                set: { if !$0 { warehouseToDeactivate = nil } }
            ),
            presenting: warehouseToDeactivate
        ) { warehouse in
            Button("Deactivate", role: .destructive) {
                warehouseToDeactivate = nil
                Task { await setActive(warehouse, active: false) }
            }
            Button("Cancel", role: .cancel) {
                warehouseToDeactivate = nil
            }
        } message: { warehouse in
            Text("\(warehouse.code) will disappear from pickers. Existing history will be kept.")
        }
        .task {
            if !loaded { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer {
            loaded = true
            loading = false
        }

        do {
            warehouses = try await WarehousesAPI().list()
            errorMessage = nil
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not load warehouses.")
        }
    }

    @MainActor
    private func makeDefault(_ warehouse: Warehouse) async {
        workingWarehouseId = warehouse.id
        errorMessage = nil
        defer { workingWarehouseId = nil }

        do {
            _ = try await WarehousesAPI().setDefault(id: warehouse.id)
            await load()
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not change the default warehouse.")
        }
    }

    @MainActor
    private func setActive(_ warehouse: Warehouse, active: Bool) async {
        workingWarehouseId = warehouse.id
        errorMessage = nil
        defer { workingWarehouseId = nil }

        do {
            _ = try await WarehousesAPI().update(
                id: warehouse.id,
                body: WarehousePatchInput(name: nil, notes: nil, active: active)
            )
            await load()
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not update the warehouse.")
        }
    }
}

private struct WarehouseEditorTarget: Identifiable {
    let id: String
    let warehouse: Warehouse?

    init(warehouse: Warehouse?) {
        self.warehouse = warehouse
        id = warehouse?.id ?? "new"
    }
}

private struct WarehouseRow: View {
    let warehouse: Warehouse
    let working: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: warehouse.isDefault ? "building.2.fill" : "building.2")
                .font(.title3)
                .foregroundStyle(warehouse.active ? Theme.primary : Theme.muted)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.sm) {
                    Text(warehouse.code)
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundStyle(Theme.text)

                    if warehouse.isDefault {
                        TransferBadge(text: "Default", color: Theme.success)
                    }

                    if !warehouse.active {
                        TransferBadge(text: "Inactive", color: Theme.muted)
                    }
                }

                Text(warehouse.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)

                if let notes = warehouse.notes?.nilIfBlank {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

            Spacer()

            if working {
                ProgressView()
            } else {
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    Text("\(warehouse.qtyOnHand) on hand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(warehouse.qtyReserved) reserved")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct WarehouseEditorNativeView: View {
    let warehouse: Warehouse?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var name: String
    @State private var notes: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(warehouse: Warehouse?, onSaved: @escaping () -> Void) {
        self.warehouse = warehouse
        self.onSaved = onSaved
        _code = State(initialValue: warehouse?.code ?? "")
        _name = State(initialValue: warehouse?.name ?? "")
        _notes = State(initialValue: warehouse?.notes ?? "")
    }

    private var editing: Bool { warehouse != nil }
    private var cleanCode: String {
        code.uppercased().filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".contains($0) }
    }
    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        !cleanName.isEmpty && (editing || (2...16).contains(cleanCode.count))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(editing)
                        .onChange(of: code) { _, value in
                            let sanitized = String(value.uppercased().filter {
                                "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".contains($0)
                            }.prefix(16))
                            if sanitized != value { code = sanitized }
                        }

                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text(editing
                         ? "The warehouse code is permanent because inventory history uses it."
                         : "Use 2–16 letters, numbers, hyphens, or underscores. The code cannot be changed after creation.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(editing ? "Edit warehouse" : "New warehouse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave || saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            if let warehouse {
                _ = try await WarehousesAPI().update(
                    id: warehouse.id,
                    body: WarehousePatchInput(
                        name: cleanName,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        active: nil
                    )
                )
            } else {
                _ = try await WarehousesAPI().create(
                    WarehouseCreateInput(
                        code: cleanCode,
                        name: cleanName,
                        notes: notes.nilIfBlank
                    )
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not save the warehouse.")
        }
    }
}

// MARK: - Stock transfer list

struct StockTransfersListNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var status = ""
    @State private var currentPage = 1
    @State private var data: Paged<StockTransfer>?
    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var loadGeneration = 0

    private let pageSize = 50

    private var canCreate: Bool { auth.has("transfers.manage") }
    private var totalPages: Int {
        guard let data else { return 1 }
        return max(1, Int(ceil(Double(data.total) / Double(data.pageSize))))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)

                Picker("Status", selection: Binding(
                    get: { status },
                    set: { next in
                        status = next
                        currentPage = 1
                    }
                )) {
                    Text("All").tag("")
                    Text("Draft").tag("DRAFT")
                    Text("Posted").tag("POSTED")
                    Text("Voided").tag("VOIDED")
                }
                .pickerStyle(.menu)

                Spacer()

                if loading, loaded {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.card)

            Divider()

            Group {
                if !loaded {
                    LoadingView(label: "Loading transfers...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: status.isEmpty ? "No transfers yet." : "No \(status.lowercased()) transfers.")
                } else if let data {
                    List {
                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.danger)
                            }
                        }

                        Section {
                            ForEach(data.items) { transfer in
                                NavigationLink(value: AppRoute.transferDetail(transfer.id)) {
                                    StockTransferRow(transfer: transfer)
                                }
                            }
                        }

                        if totalPages > 1 {
                            Section {
                                HStack {
                                    Button {
                                        currentPage = max(1, currentPage - 1)
                                    } label: {
                                        Label("Previous", systemImage: "chevron.left")
                                    }
                                    .disabled(currentPage <= 1 || loading)

                                    Spacer()
                                    Text("Page \(currentPage) of \(totalPages)")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.muted)
                                    Spacer()

                                    Button {
                                        currentPage = min(totalPages, currentPage + 1)
                                    } label: {
                                        Label("Next", systemImage: "chevron.right")
                                            .labelStyle(.titleAndIcon)
                                    }
                                    .disabled(currentPage >= totalPages || loading)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .background(Theme.background)
        .toolbar {
            if canCreate {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.newTransfer) {
                        Label("New transfer", systemImage: "plus")
                    }
                }
            }
        }
        .task(id: "\(status):\(currentPage)") {
            await load()
        }
        .onAppear {
            if loaded { Task { await load() } }
        }
    }

    @MainActor
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedStatus = status
        let requestedPage = currentPage

        loading = true
        defer {
            if loadGeneration == generation {
                loaded = true
                loading = false
            }
        }

        do {
            let response = try await TransfersAPI().list(
                status: requestedStatus.nilIfBlank,
                page: requestedPage,
                pageSize: pageSize
            )
            guard
                !Task.isCancelled,
                loadGeneration == generation,
                status == requestedStatus,
                currentPage == requestedPage
            else { return }

            data = response
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            errorMessage = transferErrorMessage(error, fallback: "Could not load transfers.")
        }
    }
}

private struct StockTransferRow: View {
    let transfer: StockTransfer

    private var totalQuantity: Int {
        transfer.lines.reduce(0) { $0 + $1.qty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(transfer.ref ?? String(transfer.id.prefix(8)))
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                TransferStatusBadge(status: transfer.status)
            }

            Label("\(transfer.fromLocation)  →  \(transfer.toLocation)", systemImage: "arrow.right")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)

            HStack {
                Text("\(totalQuantity) tire\(totalQuantity == 1 ? "" : "s")")
                Text("·")
                Text("Freight \(AppFormat.money(transfer.freightAmount))")
                Spacer()
                Text(AppFormat.dateTime(transfer.createdAt))
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

// MARK: - Stock transfer detail

struct StockTransferDetailNativeView: View {
    let id: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    @State private var transfer: StockTransfer?
    @State private var loaded = false
    @State private var loading = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var editingTransfer: StockTransfer?
    @State private var confirmation: TransferConfirmation?
    @State private var showingVoidSheet = false

    private var canManage: Bool { auth.has("transfers.manage") }
    private var canPost: Bool { auth.canActOrRequest("transfers.post") }
    private var canVoid: Bool { auth.has("transfers.post") }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading transfer...")
            } else if let transfer {
                content(transfer)
            } else {
                RetryView(message: errorMessage ?? "Transfer not found.") { Task { await load() } }
            }
        }
        .navigationTitle(transfer?.ref ?? "Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let transfer, transfer.status == "DRAFT", canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTransfer = transfer
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .disabled(working)
                }
            }
        }
        .sheet(item: $editingTransfer) { current in
            NavigationStack {
                StockTransferFormNativeView(transfer: current) { saved in
                    transfer = saved
                    statusMessage = "Draft saved."
                }
            }
        }
        .sheet(isPresented: $showingVoidSheet) {
            TransferVoidNativeView { reason in
                Task { await voidTransfer(reason: reason) }
            }
        }
        .alert(item: $confirmation) { action in
            switch action {
            case .post:
                return Alert(
                    title: Text("Post transfer?"),
                    message: Text(postConfirmationMessage),
                    primaryButton: .default(Text("Post")) { Task { await post() } },
                    secondaryButton: .cancel()
                )
            case .deleteDraft:
                return Alert(
                    title: Text("Delete draft?"),
                    message: Text("This transfer draft will be permanently deleted."),
                    primaryButton: .destructive(Text("Delete")) { Task { await deleteDraft() } },
                    secondaryButton: .cancel()
                )
            }
        }
        .task {
            if !loaded { await load() }
        }
    }

    private var postConfirmationMessage: String {
        guard let transfer else { return "Stock will move immediately." }
        let quantity = transfer.lines.reduce(0) { $0 + $1.qty }
        return "Move \(quantity) tire\(quantity == 1 ? "" : "s") from \(transfer.fromLocation) to \(transfer.toLocation)? Stock moves immediately after posting or approval."
    }

    private func content(_ transfer: StockTransfer) -> some View {
        List {
            Section {
                HStack {
                    Text(transfer.ref ?? String(transfer.id.prefix(8)))
                        .font(.headline.monospaced())
                    Spacer()
                    TransferStatusBadge(status: transfer.status)
                }

                LabeledContent("Route", value: "\(transfer.fromLocation) → \(transfer.toLocation)")
                LabeledContent("Created", value: AppFormat.dateTime(transfer.createdAt))

                if let postedAt = transfer.postedAt {
                    LabeledContent("Posted", value: AppFormat.dateTime(postedAt))
                }

                if let voidedAt = transfer.voidedAt {
                    LabeledContent("Voided", value: AppFormat.dateTime(voidedAt))
                }

                if let notes = transfer.notes?.nilIfBlank {
                    LabeledContent("Notes") {
                        Text(notes)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Freight") {
                LabeledContent("Amount", value: AppFormat.money(transfer.freightAmount))
                LabeledContent("Spread", value: transferSpreadLabel(transfer.costSpread))

                if let vendor = transfer.freightVendor?.name.nilIfBlank ?? transfer.freightVendorName?.nilIfBlank {
                    LabeledContent("Trucking vendor", value: vendor)
                }

                if let dueAt = transfer.freightDueAt {
                    LabeledContent("Due", value: AppFormat.shortDate(dueAt))
                }

                ForEach(transfer.costs) { cost in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text("Payable")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            TransferBadge(text: cost.status.capitalized, color: transferCostColor(cost.status))
                        }
                        Text("\(AppFormat.money(cost.amount)) · \(AppFormat.money(cost.amountPaid)) paid")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Section("Tires · \(transfer.lines.reduce(0) { $0 + $1.qty }) total") {
                ForEach(transfer.lines) { line in
                    StockTransferLineRow(line: line, showCosts: transfer.status != "DRAFT")
                }
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.success)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                }
            }

            if transfer.status == "DRAFT" {
                if canPost {
                    Section {
                        Button {
                            confirmation = .post
                        } label: {
                            Label(
                                auth.has("transfers.post") ? "Post transfer" : "Request posting approval",
                                systemImage: "arrow.up.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(working)
                    } footer: {
                        Text("Posting moves stock out of \(transfer.fromLocation) and into \(transfer.toLocation).")
                    }
                }

                if canManage {
                    Section {
                        Button("Delete draft", role: .destructive) {
                            confirmation = .deleteDraft
                        }
                        .disabled(working)
                    }
                }
            } else if transfer.status == "POSTED", canVoid {
                Section {
                    Button("Void transfer", role: .destructive) {
                        showingVoidSheet = true
                    }
                    .disabled(working)
                } footer: {
                    Text("Voiding returns the stock to the source warehouse and reverses its freight effects.")
                }
            }

            if working {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Working...")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer {
            loaded = true
            loading = false
        }

        do {
            transfer = try await TransfersAPI().get(id: id)
            errorMessage = nil
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not load the transfer.")
        }
    }

    @MainActor
    private func post() async {
        working = true
        errorMessage = nil
        statusMessage = nil
        defer { working = false }

        do {
            let result = try await TransfersAPI().post(id: id)
            switch result {
            case .immediate(let posted):
                transfer = posted
                statusMessage = "Transfer posted. Stock has moved."
            case .approval:
                statusMessage = "Approval requested. The transfer will post after approval."
                if let refreshed = try? await TransfersAPI().get(id: id) {
                    transfer = refreshed
                }
            }
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not post the transfer.")
        }
    }

    @MainActor
    private func deleteDraft() async {
        working = true
        errorMessage = nil
        defer { working = false }

        do {
            _ = try await TransfersAPI().deleteDraft(id: id)
            dismiss()
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not delete the draft.")
        }
    }

    @MainActor
    private func voidTransfer(reason: String?) async {
        working = true
        errorMessage = nil
        statusMessage = nil
        defer { working = false }

        do {
            transfer = try await TransfersAPI().void(id: id, reason: reason)
            statusMessage = "Transfer voided. Stock has returned to the source warehouse."
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not void the transfer.")
        }
    }
}

private enum TransferConfirmation: String, Identifiable {
    case post
    case deleteDraft

    var id: String { rawValue }
}

private struct StockTransferLineRow: View {
    let line: StockTransferLine
    let showCosts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.sku.sku)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(line.sku.brand) \(line.sku.model) · \(line.sku.size)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Text("× \(line.qty)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            if showCosts {
                HStack(spacing: Theme.Space.md) {
                    TransferCostLabel(title: "Cost out", value: transferDecimal(line.unitCostFrom))
                    TransferCostLabel(title: "Freight/unit", value: transferDecimal(line.freightPerUnit))
                    TransferCostLabel(title: "Landed", value: transferDecimal(line.landedUnitCost))
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct TransferCostLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransferVoidNativeView: View {
    let onConfirm: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Stock will return to the source warehouse. Any freight payable and landed-cost effects will be reversed.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                Section("Reason (optional)") {
                    TextField("Why is this transfer being voided?", text: $reason, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Void transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Void", role: .destructive) {
                        onConfirm(reason.nilIfBlank)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Stock transfer create/edit

struct NewStockTransferNativeView: View {
    var body: some View {
        StockTransferFormNativeView(transfer: nil) { _ in }
    }
}

private struct TransferLineDraft: Identifiable {
    let id: UUID
    let skuId: String
    let sku: String
    let description: String
    var quantity: Int
    let available: Int?

    init(
        id: UUID = UUID(),
        skuId: String,
        sku: String,
        description: String,
        quantity: Int,
        available: Int?
    ) {
        self.id = id
        self.skuId = skuId
        self.sku = sku
        self.description = description
        self.quantity = quantity
        self.available = available
    }
}

struct StockTransferFormNativeView: View {
    let transfer: StockTransfer?
    let onSaved: (StockTransfer) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var warehouses: [Warehouse] = []
    @State private var vendors: [Vendor] = []
    @State private var fromLocation: String
    @State private var toLocation: String
    @State private var lines: [TransferLineDraft]
    @State private var freightAmount: String
    @State private var freightVendorId: String
    @State private var freightVendorName: String
    @State private var freightDueAt: String
    @State private var costSpread: String
    @State private var notes: String
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showingSkuPicker = false

    init(transfer: StockTransfer?, onSaved: @escaping (StockTransfer) -> Void) {
        self.transfer = transfer
        self.onSaved = onSaved
        _fromLocation = State(initialValue: transfer?.fromLocation ?? "")
        _toLocation = State(initialValue: transfer?.toLocation ?? "")
        _lines = State(initialValue: (transfer?.lines ?? []).map { line in
            TransferLineDraft(
                skuId: line.skuId,
                sku: line.sku.sku,
                description: "\(line.sku.brand) \(line.sku.model) · \(line.sku.size)",
                quantity: line.qty,
                available: nil
            )
        })

        if let amount = transfer?.freightAmount, Double(amount) ?? 0 > 0 {
            _freightAmount = State(initialValue: String(Double(amount) ?? 0))
        } else {
            _freightAmount = State(initialValue: "")
        }
        _freightVendorId = State(initialValue: transfer?.freightVendorId ?? "")
        _freightVendorName = State(initialValue: transfer?.freightVendorId == nil ? transfer?.freightVendorName ?? "" : "")
        _freightDueAt = State(initialValue: transfer?.freightDueAt.map { String($0.prefix(10)) } ?? "")
        _costSpread = State(initialValue: transfer?.costSpread == "VALUE" ? "VALUE" : "QUANTITY")
        _notes = State(initialValue: transfer?.notes ?? "")
    }

    private var editing: Bool { transfer != nil }
    private var freight: Double? {
        let trimmed = freightAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : Double(trimmed)
    }
    private var totalQuantity: Int {
        lines.reduce(0) { $0 + $1.quantity }
    }
    private var routeUsesActiveWarehouses: Bool {
        warehouses.contains { $0.code == fromLocation }
            && warehouses.contains { $0.code == toLocation }
    }
    private var canSave: Bool {
        loaded
            && !fromLocation.isEmpty
            && !toLocation.isEmpty
            && fromLocation != toLocation
            && routeUsesActiveWarehouses
            && !lines.isEmpty
            && lines.allSatisfy { $0.quantity > 0 }
            && freight != nil
            && (freight ?? -1) >= 0
            && transferDayIsValid(freightDueAt)
            && ((freight ?? 0) <= 0.005 || !freightVendorId.isEmpty || freightVendorName.nilIfBlank != nil)
    }

    var body: some View {
        Form {
            if !loaded {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading warehouses...")
                        Spacer()
                    }
                }
            }

            Section {
                Picker("From warehouse", selection: $fromLocation) {
                    Text("Choose source").tag("")
                    if !fromLocation.isEmpty, !warehouses.contains(where: { $0.code == fromLocation }) {
                        Text("\(fromLocation) (inactive)").tag(fromLocation)
                    }
                    ForEach(warehouses) { warehouse in
                        Text("\(warehouse.code) — \(warehouse.name)").tag(warehouse.code)
                    }
                }

                Picker("To warehouse", selection: $toLocation) {
                    Text("Choose destination").tag("")
                    if !toLocation.isEmpty, !warehouses.contains(where: { $0.code == toLocation }) {
                        Text("\(toLocation) (inactive)").tag(toLocation)
                    }
                    ForEach(warehouses.filter { $0.code != fromLocation }) { warehouse in
                        Text("\(warehouse.code) — \(warehouse.name)").tag(warehouse.code)
                    }
                }
            } header: {
                Text("Route")
            } footer: {
                if fromLocation == toLocation, !fromLocation.isEmpty {
                    Text("Source and destination must be different.")
                        .foregroundStyle(Theme.danger)
                } else if !fromLocation.isEmpty, !toLocation.isEmpty, !routeUsesActiveWarehouses {
                    Text("Choose active source and destination warehouses before saving.")
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                if lines.isEmpty {
                    Text(fromLocation.isEmpty
                         ? "Choose the source warehouse before adding tires."
                         : "No tires added yet.")
                        .foregroundStyle(Theme.muted)
                }

                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.sku)
                                    .font(.subheadline.monospaced().weight(.semibold))
                                Text(line.description)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                lines.removeAll { $0.id == line.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        Stepper(value: $line.quantity, in: 1...9_999) {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                Text(line.quantity.formatted())
                                    .fontWeight(.semibold)
                            }
                        }

                        if let available = line.available {
                            Text("\(available) available at \(fromLocation)")
                                .font(.caption)
                                .foregroundStyle(line.quantity > available ? Theme.danger : Theme.muted)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }

                Button {
                    showingSkuPicker = true
                } label: {
                    Label("Add tire", systemImage: "plus.circle")
                }
                .disabled(fromLocation.isEmpty || !loaded)

                if !lines.isEmpty {
                    LabeledContent("Total tires", value: totalQuantity.formatted())
                }
            } header: {
                Text("Tires")
            } footer: {
                Text("Availability is shown for the source warehouse. Posting performs a final stock check.")
            }

            Section {
                TextField("Amount", text: $freightAmount)
                    .keyboardType(.decimalPad)

                Picker("Trucking vendor", selection: $freightVendorId) {
                    Text("No linked vendor").tag("")
                    ForEach(vendors) { vendor in
                        Text(vendor.name).tag(vendor.id)
                    }
                }

                if freightVendorId.isEmpty {
                    TextField("Vendor name", text: $freightVendorName)
                        .textInputAutocapitalization(.words)
                }

                TextField("Due date (YYYY-MM-DD)", text: $freightDueAt)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: freightDueAt) { _, value in
                        let sanitized = String(value.filter { $0.isNumber || $0 == "-" }.prefix(10))
                        if sanitized != value { freightDueAt = sanitized }
                    }

                Picker("Spread freight", selection: $costSpread) {
                    Text("By quantity").tag("QUANTITY")
                    Text("By value").tag("VALUE")
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Freight")
            } footer: {
                if !transferDayIsValid(freightDueAt) {
                    Text("Enter the due date as YYYY-MM-DD, or leave it blank.")
                        .foregroundStyle(Theme.danger)
                } else if (freight ?? 0) > 0.005, freightVendorId.isEmpty, freightVendorName.nilIfBlank == nil {
                    Text("Choose or enter the vendor who will be owed the freight amount.")
                        .foregroundStyle(Theme.danger)
                } else {
                    Text("Freight is added to receiving cost and booked as a payable to the selected vendor.")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() }
                        Text(editing ? "Save draft" : "Create draft")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!canSave || saving)
            }
        }
        .navigationTitle(editing ? "Edit transfer" : "New transfer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(saving)
            }
        }
        .interactiveDismissDisabled(saving)
        .sheet(isPresented: $showingSkuPicker) {
            TransferSkuPickerNativeView(
                sourceLocation: fromLocation,
                excluding: Set(lines.map(\.skuId))
            ) { line in
                lines.append(line)
            }
        }
        .onChange(of: fromLocation) { _, _ in
            if toLocation == fromLocation { toLocation = "" }
            if !lines.isEmpty {
                lines = lines.map {
                    TransferLineDraft(
                        id: $0.id,
                        skuId: $0.skuId,
                        sku: $0.sku,
                        description: $0.description,
                        quantity: $0.quantity,
                        available: nil
                    )
                }
            }
        }
        .onChange(of: freightVendorId) { _, value in
            if !value.isEmpty { freightVendorName = "" }
        }
        .task { await loadOptions() }
    }

    @MainActor
    private func loadOptions() async {
        do {
            let loadedWarehouses = try await WarehousesAPI().list(activeOnly: true)
            warehouses = loadedWarehouses

            if fromLocation.isEmpty {
                fromLocation = loadedWarehouses.first(where: \.isDefault)?.code ?? ""
            }
        } catch {
            loaded = true
            errorMessage = transferErrorMessage(error, fallback: "Could not load transfer options.")
            return
        }

        // A linked vendor is convenient, but free-text freight vendors are
        // valid too. Keep the transfer form usable if this optional lookup is
        // unavailable to the signed-in role.
        vendors = (try? await VendorsAPI().list(active: true, pageSize: 1_000).items) ?? []
        loaded = true
        errorMessage = nil
    }

    @MainActor
    private func save() async {
        guard canSave, let freight else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }

        let input = StockTransferInput(
            fromLocation: fromLocation,
            toLocation: toLocation,
            lines: lines.map { StockTransferLineInput(skuId: $0.skuId, qty: $0.quantity) },
            costSpread: costSpread,
            freightAmount: freight,
            freightVendorId: freightVendorId.nilIfBlank,
            freightVendorName: freightVendorName.nilIfBlank,
            freightDueAt: freightDueAt.nilIfBlank,
            notes: notes.nilIfBlank
        )

        do {
            let saved: StockTransfer
            if let transfer {
                saved = try await TransfersAPI().update(id: transfer.id, body: input)
            } else {
                saved = try await TransfersAPI().create(input)
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = transferErrorMessage(error, fallback: "Could not save the transfer draft.")
        }
    }
}

private struct TransferSkuPickerNativeView: View {
    let sourceLocation: String
    let excluding: Set<String>
    let onSelect: (TransferLineDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TireSku] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var searchGeneration = 0

    var body: some View {
        NavigationStack {
            Group {
                if loading, !loaded {
                    LoadingView(label: "Loading tires...")
                } else if let errorMessage, results.isEmpty {
                    RetryView(message: errorMessage) { Task { await search(query: query) } }
                } else if results.isEmpty {
                    EmptyStateView(text: query.isEmpty ? "No tires found." : "No tires match your search.")
                } else {
                    List(results) { sku in
                        let available = availability(for: sku)
                        let alreadyAdded = excluding.contains(sku.id)

                        Button {
                            guard !alreadyAdded else { return }
                            onSelect(TransferLineDraft(
                                skuId: sku.id,
                                sku: sku.sku,
                                description: "\(sku.brand) \(sku.model) · \(sku.size)",
                                quantity: 1,
                                available: available
                            ))
                            dismiss()
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text(sku.sku)
                                        .font(.subheadline.monospaced().weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                    Text("\(sku.brand) \(sku.model) · \(sku.size)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }

                                Spacer()

                                if alreadyAdded {
                                    Text("Added")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                } else {
                                    Text("\(available) at \(sourceLocation)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(available > 0 ? Theme.success : Theme.danger)
                                }
                            }
                            .padding(.vertical, Theme.Space.xs)
                        }
                        .disabled(alreadyAdded)
                    }
                    .listStyle(.plain)
                    .refreshable { await search(query: query) }
                }
            }
            .navigationTitle("Add tire")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "SKU, brand, model, or size")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await search(query: query)
            }
        }
    }

    private func availability(for sku: TireSku) -> Int {
        guard let stock = sku.inventory.first(where: { $0.location == sourceLocation }) else { return 0 }
        return max(0, stock.qtyOnHand - stock.qtyReserved)
    }

    @MainActor
    private func search(query requestedQuery: String) async {
        searchGeneration += 1
        let generation = searchGeneration
        loading = true

        do {
            let page = try await InventoryAPI().listSkus(q: requestedQuery.nilIfBlank, pageSize: 50)
            guard generation == searchGeneration, requestedQuery == query, !Task.isCancelled else { return }
            results = page.items.sorted {
                let lhs = availability(for: $0)
                let rhs = availability(for: $1)
                if (lhs > 0) != (rhs > 0) { return lhs > 0 }
                return $0.sku.localizedCaseInsensitiveCompare($1.sku) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            guard generation == searchGeneration, requestedQuery == query, !isTransferSearchCancellation(error) else {
                return
            }
            errorMessage = transferErrorMessage(error, fallback: "Could not search inventory.")
        }

        guard generation == searchGeneration, requestedQuery == query else { return }
        loading = false
        loaded = true
    }
}

private func isTransferSearchCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }

    return (error as? URLError)?.code == .cancelled
}

// MARK: - Shared transfer presentation helpers

private struct TransferStatusBadge: View {
    let status: String

    var body: some View {
        TransferBadge(text: status.capitalized, color: transferStatusColor(status))
    }
}

private struct TransferBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private func transferStatusColor(_ status: String) -> Color {
    switch status {
    case "POSTED": return Theme.success
    case "VOIDED": return Theme.danger
    default: return Theme.muted
    }
}

private func transferCostColor(_ status: String) -> Color {
    switch status {
    case "PAID": return Theme.success
    case "VOID": return Theme.muted
    default: return Theme.primary
    }
}

private func transferSpreadLabel(_ spread: String) -> String {
    switch spread {
    case "VALUE": return "By value"
    case "NONE": return "Not spread"
    default: return "By quantity"
    }
}

private func transferDecimal(_ value: String?) -> String {
    guard let value, let number = Double(value) else { return "—" }
    return String(format: "$%.4f", number)
}

private func transferDayIsValid(_ value: String) -> Bool {
    guard let value = value.nilIfBlank else { return true }
    guard value.count == 10 else { return false }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value) != nil
}

private func transferErrorMessage(_ error: Error, fallback: String) -> String {
    (error as? LocalizedError)?.errorDescription ?? fallback
}
