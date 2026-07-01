import SwiftUI

struct SaleDetailNativeView: View {
    let id: String
    @State private var paymentContext: PaymentContext?

    var body: some View {
        AsyncContentView(load: { try await SalesAPI().get(id: id) }) { sale in
            List {
                Section {
                    RowLine(title: sale.customer.name, subtitle: sale.ref ?? sale.id, trailing: AppFormat.money(sale.total))
                    RowLine(title: "Status", subtitle: sale.status)
                    RowLine(title: "Tax", subtitle: AppFormat.money(sale.taxAmount), trailing: sale.taxRate)
                }

                Section("Lines") {
                    ForEach(sale.lines) { line in
                        RowLine(title: line.description, subtitle: "Qty \(line.qty)", trailing: AppFormat.money(line.lineTotal))
                    }
                }

                if let invoice = sale.invoice {
                    Section("Invoice") {
                        RowLine(title: invoice.ref ?? invoice.id, subtitle: "Paid \(AppFormat.money(invoice.paidTotal))", trailing: AppFormat.money(invoice.amountDue))

                        if (Double(invoice.amountDue) ?? 0) > 0 {
                            NavigationLink(value: AppRoute.tapToPay(invoiceId: invoice.id, amount: Double(invoice.amountDue) ?? 0)) {
                                Text("Tap to Pay")
                            }

                            Button("Record manual payment") {
                                paymentContext = PaymentContext(invoice: invoice, customerId: sale.customerId)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: AppRoute.editSale(sale.id)) {
                        Text("Edit sale")
                    }
                    NavigationLink(value: AppRoute.startReturn(saleId: sale.id, saleRef: sale.ref)) {
                        Text("Return / Exchange")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Sale")
        .sheet(item: $paymentContext) { context in
            PaymentSheetNativeView(
                invoiceId: context.invoice.id,
                balance: Double(context.invoice.amountDue) ?? 0,
                customerId: context.customerId,
                onPaid: { paymentContext = nil }
            )
        }
    }

    private struct PaymentContext: Identifiable {
        let invoice: SaleInvoice
        let customerId: String

        var id: String { invoice.id }
    }
}

struct WorkOrderDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var order: WorkOrder?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var taskDescription = ""
    @State private var savingTask = false
    @State private var busyTaskId: String?
    @State private var deletingTask: WorkOrderTask?
    @State private var editing = false

    private var canManage: Bool {
        auth.has("workorders.manage")
    }

    var body: some View {
        Group {
            if loading && order == nil {
                LoadingView(label: "Loading...")
            } else if let order {
                content(order)
            } else if let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .navigationTitle("Work Order")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canManage, order != nil {
                    Button {
                        editing = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let order {
                WorkOrderEditorView(order: order) {
                    editing = false
                    Task { await load() }
                }
            }
        }
        .alert("Delete task?", isPresented: Binding(
            get: { deletingTask != nil },
            set: { if !$0 { deletingTask = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingTask = nil }
            Button("Delete", role: .destructive) {
                Task { await deleteTask() }
            }
        } message: {
            Text("This removes the task from the work order.")
        }
        .task {
            if order == nil { await load() }
        }
        .refreshable {
            await load()
        }
    }

    private func content(_ order: WorkOrder) -> some View {
        List {
            Section {
                NavigationLink(value: AppRoute.saleDetail(order.sale.id)) {
                    RowLine(
                        title: order.sale.customer.name,
                        subtitle: order.sale.ref ?? order.sale.id,
                        trailing: AppFormat.money(order.sale.total)
                    )
                }
                RowLine(title: "Status", subtitle: WorkOrderLabels.title(order.status))
                RowLine(title: "Bay", subtitle: order.bay ?? "-")
                RowLine(title: "Notes", subtitle: order.notes ?? "-")
            }

            if !order.sale.lines.isEmpty {
                Section("Sale Lines") {
                    ForEach(order.sale.lines) { line in
                        RowLine(
                            title: line.description,
                            subtitle: "Qty \(line.qty) - \(line.itemType.replacingOccurrences(of: "_", with: " ").capitalized)"
                        )
                    }
                }
            }

            Section("Tasks") {
                if order.tasks.isEmpty {
                    Text("No tasks yet.")
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(order.tasks) { task in
                        WorkOrderTaskRow(
                            task: task,
                            canManage: canManage,
                            busy: busyTaskId == task.id,
                            onToggle: { Task { await toggleTask(task) } },
                            onDelete: { deletingTask = task }
                        )
                    }
                }

                if canManage {
                    HStack(spacing: Theme.Space.sm) {
                        TextField("New task", text: $taskDescription)
                            .textInputAutocapitalization(.sentences)
                            .onSubmit {
                                Task { await addTask() }
                            }

                        Button {
                            Task { await addTask() }
                        } label: {
                            if savingTask {
                                ProgressView()
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        .disabled(savingTask || taskDescription.nilIfBlank == nil)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            order = try await WorkOrdersAPI().get(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load work order."
        }
        loading = false
    }

    @MainActor
    private func addTask() async {
        guard let description = taskDescription.nilIfBlank else { return }
        savingTask = true
        errorMessage = nil
        do {
            _ = try await WorkOrdersAPI().addTask(id: id, description: description)
            taskDescription = ""
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not add task."
        }
        savingTask = false
    }

    @MainActor
    private func toggleTask(_ task: WorkOrderTask) async {
        busyTaskId = task.id
        errorMessage = nil
        do {
            _ = try await WorkOrdersAPI().toggleTask(workOrderId: id, taskId: task.id, done: !task.done)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update task."
        }
        busyTaskId = nil
    }

    @MainActor
    private func deleteTask() async {
        guard let task = deletingTask else { return }
        deletingTask = nil
        busyTaskId = task.id
        errorMessage = nil
        do {
            _ = try await WorkOrdersAPI().deleteTask(workOrderId: id, taskId: task.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete task."
        }
        busyTaskId = nil
    }
}

private struct WorkOrderTaskRow: View {
    let task: WorkOrderTask
    let canManage: Bool
    let busy: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Button {
                onToggle()
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Theme.success : Theme.muted)
            }
            .buttonStyle(.plain)
            .disabled(!canManage || busy)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(task.description)
                    .foregroundStyle(task.done ? Theme.muted : Theme.text)
                    .strikethrough(task.done)

                if let doneAt = task.doneAt {
                    Text(AppFormat.dateTime(doneAt))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            if busy {
                ProgressView()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canManage {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }
        }
    }
}

private struct WorkOrderEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let order: WorkOrder
    let onSaved: () -> Void

    @State private var status: WorkOrderStatus
    @State private var bay: String
    @State private var notes: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(order: WorkOrder, onSaved: @escaping () -> Void) {
        self.order = order
        self.onSaved = onSaved
        _status = State(initialValue: order.status)
        _bay = State(initialValue: order.bay ?? "")
        _notes = State(initialValue: order.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Work Order") {
                    Picker("Status", selection: $status) {
                        ForEach(WorkOrderLabels.statuses, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }

                    TextField("Bay", text: $bay)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Edit Work Order")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        do {
            _ = try await WorkOrdersAPI().update(
                id: order.id,
                body: WorkOrderPatchInput(status: status, bay: bay.nilIfBlank, notes: notes.nilIfBlank)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save work order."
        }
        saving = false
    }
}
struct InventoryCountDetailNativeView: View {
    let id: String

    var body: some View {
        AsyncContentView(load: { try await InventoryCountsAPI().get(id: id) }) { count in
            List {
                Section {
                    RowLine(title: count.ref ?? "Inventory count", subtitle: count.location, trailing: count.status)
                    RowLine(title: "Variance", subtitle: AppFormat.money(count.costVariance))
                    RowLine(title: "Notes", subtitle: count.notes ?? "-")
                }

                Section("Lines") {
                    ForEach(count.lines) { line in
                        RowLine(
                            title: "\(line.sku.brand) \(line.sku.model)",
                            subtitle: "\(line.sku.size) - expected \(line.expectedQty)",
                            trailing: line.countedQty.map(String.init) ?? "-"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Inventory Count")
    }
}

struct ContainerDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var container: Container?
    @State private var loading = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?

    @State private var reference = ""
    @State private var bolNumber = ""
    @State private var isDDP = false
    @State private var costSpread: CostSpreadMethod = "VALUE"
    @State private var etaAt = ""
    @State private var arrivedAt = ""
    @State private var notes = ""
    @State private var lines: [ContainerDraftLineEditor] = []

    @State private var editingCost: ContainerCostEditorTarget?
    @State private var deleteCostTarget: ContainerCost?
    @State private var skuSearchLineId: String?
    @State private var showingCancelConfirm = false
    @State private var showingUnreceiveConfirm = false
    @State private var unreceiveReason = ""

    private var canManage: Bool {
        auth.has("purchasing.manage")
    }

    private var canReceive: Bool {
        auth.has("purchasing.receive")
    }

    private var editable: Bool {
        guard let container else { return false }
        return ContainerDetailLabels.isEditable(container.status)
    }

    private var canEditDraft: Bool {
        canManage && editable
    }

    private var preview: ContainerLocalPreview {
        ContainerLocalPreview.compute(isDDP: isDDP, costSpread: costSpread, costs: container?.costs ?? [], lines: lines)
    }

    var body: some View {
        Group {
            if loading && container == nil {
                LoadingView(label: "Loading...")
            } else if let container {
                content(container)
            } else if let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .navigationTitle(container?.ref ?? "Container")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if container == nil { await load() }
        }
        .refreshable {
            await load()
        }
        .sheet(item: $editingCost) { target in
            ContainerCostEditorView(containerId: id, cost: target.cost) {
                editingCost = nil
                Task { await load() }
            }
        }
        .sheet(isPresented: Binding(
            get: { skuSearchLineId != nil },
            set: { if !$0 { skuSearchLineId = nil } }
        )) {
            SkuSearchSheet { sku in
                if let lineId = skuSearchLineId {
                    setLineSku(lineId: lineId, sku: sku)
                }
                skuSearchLineId = nil
            }
        }
        .alert("Delete cost?", isPresented: Binding(
            get: { deleteCostTarget != nil },
            set: { if !$0 { deleteCostTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteCostTarget = nil }
            Button("Delete", role: .destructive) {
                Task { await deleteCost() }
            }
        } message: {
            Text("This removes the cost from the container.")
        }
        .alert("Cancel container?", isPresented: $showingCancelConfirm) {
            Button("Keep", role: .cancel) {}
            Button("Cancel container", role: .destructive) {
                Task { await cancelContainer() }
            }
        } message: {
            Text("This marks the container as cancelled.")
        }
        .alert("Unreceive container?", isPresented: $showingUnreceiveConfirm) {
            TextField("Reason", text: $unreceiveReason)
            Button("Keep received", role: .cancel) { unreceiveReason = "" }
            Button("Unreceive", role: .destructive) {
                Task { await unreceiveContainer() }
            }
        } message: {
            Text("This pulls the received tires back out of inventory and returns the container to Arrived.")
        }
    }

    private func content(_ container: Container) -> some View {
        List {
            Section {
                RowLine(
                    title: container.ref ?? container.reference ?? "Container",
                    subtitle: container.supplier.name,
                    trailing: ContainerDetailLabels.status(container.status)
                )
                if let country = container.supplier.country?.nilIfBlank {
                    RowLine(title: "Supplier country", subtitle: country)
                }
                StatusTimelineView(status: container.status)
            }

            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.subheadline)
                        .foregroundStyle(actionMessage == "Saved" ? Theme.success : Theme.danger)
                }
            }

            Section("Actions") {
                if canEditDraft {
                    Button {
                        Task { await saveDraft() }
                    } label: {
                        Label(busy ? "Saving..." : "Save draft", systemImage: "square.and.arrow.down")
                    }
                    .disabled(busy || !linesAreValid)

                    if let next = ContainerDetailLabels.nextStatus(after: container.status), next != "RECEIVED" {
                        Button {
                            Task { await advance(to: next) }
                        } label: {
                            Label("Mark \(ContainerDetailLabels.status(next))", systemImage: "arrow.right.circle")
                        }
                        .disabled(busy)
                    }

                    if let next = ContainerDetailLabels.nextStatus(after: container.status), next == "RECEIVED", canReceive {
                        Button {
                            Task { await advance(to: next) }
                        } label: {
                            Label("Receive into inventory", systemImage: "shippingbox.and.arrow.backward")
                        }
                        .disabled(busy || lines.isEmpty || !linesAreValid)
                    }

                    Button(role: .destructive) {
                        showingCancelConfirm = true
                    } label: {
                        Label("Cancel container", systemImage: "xmark.circle")
                    }
                    .disabled(busy)
                } else if container.status == "RECEIVED", canReceive {
                    Button(role: .destructive) {
                        showingUnreceiveConfirm = true
                    } label: {
                        Label("Unreceive", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(busy)
                } else {
                    Text("No actions available for this status.")
                        .foregroundStyle(Theme.muted)
                }
            }

            Section("Order and Shipping") {
                TextField("PO reference", text: $reference)
                    .disabled(!canEditDraft)
                TextField("BOL / container #", text: $bolNumber)
                    .disabled(!canEditDraft)
                TextField("ETA (YYYY-MM-DD)", text: $etaAt)
                    .keyboardType(.numbersAndPunctuation)
                    .disabled(!canEditDraft)
                TextField("Arrived (YYYY-MM-DD)", text: $arrivedAt)
                    .keyboardType(.numbersAndPunctuation)
                    .disabled(!canEditDraft)
                Picker("Cost spread", selection: $costSpread) {
                    ForEach(ContainerDetailLabels.spreadOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .disabled(!canEditDraft || isDDP)
                Toggle("DDP pricing", isOn: $isDDP)
                    .disabled(!canEditDraft)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .disabled(!canEditDraft)
            }

            costsSection(title: "Supplier Payments", costs: supplierPaymentCosts, totalLabel: "Recorded")
            costsSection(title: "Container Costs", costs: containerExtraCosts, totalLabel: isDDP ? "Extra costs" : "To spread")

            Section {
                if lines.isEmpty {
                    Text(canEditDraft ? "No lines yet. Add tires before receiving." : "No lines.")
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(lines) { line in
                        ContainerLineEditRow(
                            line: binding(for: line.id),
                            editable: canEditDraft,
                            previewLine: preview.lines.first { $0.id == line.id },
                            onPickSku: { skuSearchLineId = line.id },
                            onRemove: { removeLine(line.id) }
                        )
                    }
                }

                if canEditDraft {
                    Button {
                        addLine()
                    } label: {
                        Label("Add line", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Lines")
            } footer: {
                if !linesAreValid {
                    Text("Each line needs a SKU, quantity, unit cost, and FET at 0 or above.")
                        .foregroundStyle(Theme.danger)
                }
            }

            if let attachments = container.attachments, !attachments.isEmpty {
                Section("Documents") {
                    ForEach(attachments) { attachment in
                        RowLine(
                            title: attachment.filename,
                            subtitle: ContainerDetailLabels.attachmentKind(attachment.kind),
                            trailing: "\(attachment.sizeBytes / 1024) KB"
                        )
                    }
                }
            }

            Section("Summary") {
                RowLine(title: "Total tires", trailing: "\(preview.totalQty)")
                RowLine(title: "Supplier total", trailing: AppFormat.money(preview.supplierTotal))
                RowLine(title: "Supplier balance", trailing: AppFormat.money(preview.supplierBalance))
                RowLine(title: "Container extras", trailing: AppFormat.money(preview.extrasTotal))
                RowLine(title: "FET total", trailing: AppFormat.money(preview.fetTotal))
                RowLine(title: "Grand landed", trailing: AppFormat.money(preview.grandLanded))
            }
        }
        .listStyle(.insetGrouped)
    }

    private var supplierPaymentCosts: [ContainerCost] {
        (container?.costs ?? []).filter { ContainerDetailLabels.supplierPaymentCategories.contains($0.category) }
    }

    private var containerExtraCosts: [ContainerCost] {
        (container?.costs ?? []).filter { !ContainerDetailLabels.supplierPaymentCategories.contains($0.category) }
    }

    private var linesAreValid: Bool {
        lines.allSatisfy { line in
            line.skuId.nilIfBlank != nil
                && (Int(line.qty) ?? 0) > 0
                && (Double(line.unitCost) ?? -1) >= 0
                && (Double(line.fetPerUnit) ?? -1) >= 0
        }
    }

    private func costsSection(title: String, costs: [ContainerCost], totalLabel: String) -> some View {
        Section {
            if costs.isEmpty {
                Text("None recorded yet.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(costs) { cost in
                    ContainerCostRow(cost: cost)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEditDraft {
                                Button("Delete", role: .destructive) {
                                    deleteCostTarget = cost
                                }
                                Button("Edit") {
                                    editingCost = ContainerCostEditorTarget(cost: cost)
                                }
                                .tint(Theme.primary)
                            }
                        }
                }
            }

            if canEditDraft {
                Button {
                    editingCost = ContainerCostEditorTarget(cost: nil)
                } label: {
                    Label("Add cost", systemImage: "plus.circle")
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("\(totalLabel): \(AppFormat.money(costs.reduce(0) { $0 + (Double($1.amount) ?? 0) }))")
        }
    }

    private func binding(for lineId: String) -> Binding<ContainerDraftLineEditor> {
        Binding(
            get: {
                lines.first { $0.id == lineId } ?? ContainerDraftLineEditor.empty(id: lineId)
            },
            set: { updated in
                if let index = lines.firstIndex(where: { $0.id == lineId }) {
                    lines[index] = updated
                }
            }
        )
    }

    private func addLine() {
        lines.append(ContainerDraftLineEditor.empty(id: UUID().uuidString))
    }

    private func removeLine(_ lineId: String) {
        lines.removeAll { $0.id == lineId }
    }

    private func setLineSku(lineId: String, sku: TireSku) {
        if lines.contains(where: { $0.id != lineId && $0.skuId == sku.id }) {
            actionMessage = "\(sku.sku) is already on this container."
            return
        }
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[index].skuId = sku.id
        lines[index].skuLabel = "\(sku.sku) - \(sku.brand) \(sku.model) \(sku.size)"
        if (Double(lines[index].unitCost) ?? 0) <= 0 {
            lines[index].unitCost = sku.priceCost
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let loaded = try await ContainersAPI().get(id: id)
            seed(loaded)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load container."
        }
        loading = false
    }

    @MainActor
    private func saveDraft() async {
        guard let body = draftBody() else { return }
        busy = true
        actionMessage = nil
        do {
            let updated = try await ContainersAPI().update(id: id, body: body)
            seed(updated)
            actionMessage = "Saved"
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save container."
        }
        busy = false
    }

    @MainActor
    private func advance(to status: ContainerStatus) async {
        busy = true
        actionMessage = nil
        do {
            if status == "RECEIVED", let body = draftBody() {
                _ = try await ContainersAPI().update(id: id, body: body)
            }
            let updated = try await ContainersAPI().setStatus(id: id, status: status)
            seed(updated)
            actionMessage = "Moved to \(ContainerDetailLabels.status(status))"
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update status."
        }
        busy = false
    }

    @MainActor
    private func cancelContainer() async {
        busy = true
        actionMessage = nil
        do {
            let updated = try await ContainersAPI().cancel(id: id)
            seed(updated)
            actionMessage = "Container cancelled"
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? "Could not cancel container."
        }
        busy = false
    }

    @MainActor
    private func unreceiveContainer() async {
        busy = true
        actionMessage = nil
        do {
            let updated = try await ContainersAPI().unreceive(id: id, reason: unreceiveReason.nilIfBlank)
            seed(updated)
            unreceiveReason = ""
            actionMessage = "Container unreceived"
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? "Could not unreceive container."
        }
        busy = false
    }

    @MainActor
    private func deleteCost() async {
        guard let cost = deleteCostTarget else { return }
        deleteCostTarget = nil
        busy = true
        actionMessage = nil
        do {
            _ = try await ContainersAPI().deleteCost(id: id, costId: cost.id)
            await load()
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete cost."
        }
        busy = false
    }

    private func draftBody() -> ContainerPatchInput? {
        guard linesAreValid else {
            actionMessage = "Fix the container lines before saving."
            return nil
        }

        let inputLines = lines.compactMap { line -> ContainerDraftLineInput? in
            guard
                let skuId = line.skuId.nilIfBlank,
                let qty = Int(line.qty),
                let unitCost = Double(line.unitCost),
                let fet = Double(line.fetPerUnit)
            else {
                return nil
            }
            return ContainerDraftLineInput(skuId: skuId, qty: qty, unitCost: unitCost, fetPerUnit: fet)
        }

        return ContainerPatchInput(
            reference: reference.nilIfBlank,
            bolNumber: bolNumber.nilIfBlank,
            isDDP: isDDP,
            costSpread: costSpread,
            etaAt: etaAt.nilIfBlank,
            arrivedAt: arrivedAt.nilIfBlank,
            notes: notes.nilIfBlank,
            lines: inputLines
        )
    }

    @MainActor
    private func seed(_ value: Container) {
        container = value
        reference = value.reference ?? ""
        bolNumber = value.bolNumber ?? ""
        isDDP = value.isDDP
        costSpread = value.costSpread
        etaAt = ContainerDetailLabels.dateField(value.etaAt)
        arrivedAt = ContainerDetailLabels.dateField(value.arrivedAt)
        notes = value.notes ?? ""
        lines = value.lines.map(ContainerDraftLineEditor.init)
    }
}

private enum ContainerDetailLabels {
    static let supplierPaymentCategories: [ContainerCostCategory] = ["DOWN_PAYMENT", "BALANCE_PAYMENT", "SUPPLIER_OTHER"]
    static let statusFlow: [ContainerStatus] = ["DRAFT", "ORDERED", "IN_TRANSIT", "ARRIVED", "RECEIVED"]
    static let spreadOptions: [(CostSpreadMethod, String)] = [
        ("VALUE", "By value"),
        ("QUANTITY", "By quantity"),
        ("NONE", "No allocation")
    ]
    static let costCategories: [(ContainerCostCategory, String)] = [
        ("DOWN_PAYMENT", "Down payment"),
        ("BALANCE_PAYMENT", "Balance payment"),
        ("SUPPLIER_OTHER", "Supplier - other"),
        ("FREIGHT", "Sea freight"),
        ("DUTY", "Customs duty"),
        ("TRUCKING", "Trucking"),
        ("LABOR", "Unloading labor"),
        ("OTHER", "Other")
    ]

    static func status(_ value: ContainerStatus) -> String {
        switch value {
        case "DRAFT": return "Draft"
        case "ORDERED": return "Ordered"
        case "IN_TRANSIT": return "In transit"
        case "ARRIVED": return "Arrived"
        case "RECEIVED": return "Received"
        case "CANCELLED": return "Cancelled"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func costCategory(_ value: ContainerCostCategory) -> String {
        costCategories.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func attachmentKind(_ value: ContainerAttachmentKind) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func isEditable(_ status: ContainerStatus) -> Bool {
        status != "RECEIVED" && status != "CANCELLED"
    }

    static func nextStatus(after status: ContainerStatus) -> ContainerStatus? {
        guard let index = statusFlow.firstIndex(of: status), index + 1 < statusFlow.count else { return nil }
        return statusFlow[index + 1]
    }

    static func dateField(_ value: String?) -> String {
        guard let value, value.count >= 10 else { return "" }
        return String(value.prefix(10))
    }
}

private struct StatusTimelineView: View {
    let status: ContainerStatus

    var body: some View {
        if status == "CANCELLED" {
            Text("Cancelled")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.danger)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(ContainerDetailLabels.statusFlow, id: \.self) { step in
                        let active = step == status
                        let completed = isCompleted(step)
                        Text(ContainerDetailLabels.status(step))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, 6)
                            .foregroundStyle(active ? Theme.primaryText : completed ? Theme.success : Theme.muted)
                            .background(active ? Theme.primary : completed ? Theme.success.opacity(0.12) : Theme.border.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func isCompleted(_ step: ContainerStatus) -> Bool {
        guard
            let currentIndex = ContainerDetailLabels.statusFlow.firstIndex(of: status),
            let stepIndex = ContainerDetailLabels.statusFlow.firstIndex(of: step)
        else {
            return false
        }
        return stepIndex < currentIndex
    }
}

private struct ContainerDraftLineEditor: Identifiable, Equatable {
    let id: String
    var skuId: String
    var skuLabel: String
    var qty: String
    var unitCost: String
    var fetPerUnit: String

    init(line: ContainerLine) {
        id = line.id
        skuId = line.skuId
        skuLabel = "\(line.sku.sku) - \(line.sku.brand) \(line.sku.model) \(line.sku.size)"
        qty = String(line.qty)
        unitCost = line.unitCost
        fetPerUnit = line.fetPerUnit
    }

    static func empty(id: String) -> ContainerDraftLineEditor {
        ContainerDraftLineEditor(id: id, skuId: "", skuLabel: "", qty: "1", unitCost: "0", fetPerUnit: "0")
    }

    private init(id: String, skuId: String, skuLabel: String, qty: String, unitCost: String, fetPerUnit: String) {
        self.id = id
        self.skuId = skuId
        self.skuLabel = skuLabel
        self.qty = qty
        self.unitCost = unitCost
        self.fetPerUnit = fetPerUnit
    }
}

private struct ContainerPreviewLine: Identifiable {
    let id: String
    let allocPerUnit: Double
    let landedUnitCost: Double
    let landedTotal: Double
}

private struct ContainerLocalPreview {
    let totalQty: Int
    let supplierTotal: Double
    let extrasTotal: Double
    let fetTotal: Double
    let grandLanded: Double
    let supplierPaid: Double
    let supplierBalance: Double
    let lines: [ContainerPreviewLine]

    static func compute(
        isDDP: Bool,
        costSpread: CostSpreadMethod,
        costs: [ContainerCost],
        lines draftLines: [ContainerDraftLineEditor]
    ) -> ContainerLocalPreview {
        let extras = costs
            .filter { !ContainerDetailLabels.supplierPaymentCategories.contains($0.category) }
            .reduce(0) { $0 + (Double($1.amount) ?? 0) }
        let supplierPaid = costs
            .filter { ContainerDetailLabels.supplierPaymentCategories.contains($0.category) }
            .reduce(0) { $0 + (Double($1.amount) ?? 0) }
        let totalQty = draftLines.reduce(0) { $0 + (Int($1.qty) ?? 0) }
        let supplierTotal = draftLines.reduce(0) { total, line in
            total + Double(Int(line.qty) ?? 0) * (Double(line.unitCost) ?? 0)
        }
        let requestedSpread = isDDP ? "NONE" : costSpread
        let effectiveSpread = requestedSpread == "NONE" && extras > 0.005 ? "VALUE" : requestedSpread

        let previewLines = draftLines.map { line -> ContainerPreviewLine in
            let qty = Int(line.qty) ?? 0
            let unitCost = Double(line.unitCost) ?? 0
            var allocPerUnit = 0.0
            if effectiveSpread == "QUANTITY" {
                allocPerUnit = totalQty > 0 ? extras / Double(totalQty) : 0
            } else if effectiveSpread == "VALUE" {
                let lineValue = Double(qty) * unitCost
                let share = supplierTotal > 0 ? (lineValue / supplierTotal) * extras : 0
                allocPerUnit = qty > 0 ? share / Double(qty) : 0
            }
            let landedUnit = round(unitCost + allocPerUnit, places: 4)
            return ContainerPreviewLine(
                id: line.id,
                allocPerUnit: round(allocPerUnit, places: 4),
                landedUnitCost: landedUnit,
                landedTotal: round(landedUnit * Double(qty), places: 2)
            )
        }

        let fetTotal = draftLines.reduce(0) { total, line in
            total + Double(Int(line.qty) ?? 0) * (Double(line.fetPerUnit) ?? 0)
        }
        let grand = previewLines.reduce(0) { $0 + $1.landedTotal }
        let supplierBalance = supplierTotal - supplierPaid
        return ContainerLocalPreview(
            totalQty: totalQty,
            supplierTotal: round(supplierTotal, places: 2),
            extrasTotal: round(extras, places: 2),
            fetTotal: round(fetTotal, places: 2),
            grandLanded: round(grand, places: 2),
            supplierPaid: round(supplierPaid, places: 2),
            supplierBalance: round(supplierBalance, places: 2),
            lines: previewLines
        )
    }

    private static func round(_ value: Double, places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}

private struct ContainerCostRow: View {
    let cost: ContainerCost

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(ContainerDetailLabels.costCategory(cost.category))
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Text(AppFormat.money(cost.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack {
                Text(cost.status == "PAID" ? "Paid" : "Due")
                    .foregroundStyle(cost.status == "PAID" ? Theme.success : Theme.muted)
                if let vendor = cost.vendor?.nilIfBlank {
                    Text(vendor)
                }
                if let dueAt = cost.dueAt {
                    Text("Due \(AppFormat.shortDate(dueAt))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            if let detail = [cost.reference, cost.description].compactMap({ $0?.nilIfBlank }).joined(separator: " - ").nilIfBlank {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ContainerLineEditRow: View {
    @Binding var line: ContainerDraftLineEditor

    let editable: Bool
    let previewLine: ContainerPreviewLine?
    let onPickSku: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(line.skuLabel.nilIfBlank ?? "No SKU selected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(line.skuId.isEmpty ? Theme.danger : Theme.text)
                        .lineLimit(2)

                    if editable {
                        Button(line.skuId.isEmpty ? "Pick SKU" : "Change SKU") {
                            onPickSku()
                        }
                        .font(.caption)
                    }
                }

                Spacer()

                if editable {
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Qty").font(.caption).foregroundStyle(Theme.muted)
                    TextField("Qty", text: $line.qty)
                        .keyboardType(.numberPad)
                        .disabled(!editable)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Unit").font(.caption).foregroundStyle(Theme.muted)
                    TextField("Cost", text: $line.unitCost)
                        .keyboardType(.decimalPad)
                        .disabled(!editable)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("FET").font(.caption).foregroundStyle(Theme.muted)
                    TextField("FET", text: $line.fetPerUnit)
                        .keyboardType(.decimalPad)
                        .disabled(!editable)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let previewLine {
                HStack {
                    Text("Alloc \(AppFormat.money(previewLine.allocPerUnit))")
                    Spacer()
                    Text("Landed \(AppFormat.money(previewLine.landedUnitCost))")
                    Spacer()
                    Text(AppFormat.money(previewLine.landedTotal))
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ContainerCostEditorTarget: Identifiable {
    let cost: ContainerCost?
    let id: String

    init(cost: ContainerCost?) {
        self.cost = cost
        id = cost?.id ?? UUID().uuidString
    }
}

private struct ContainerCostEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let containerId: String
    let cost: ContainerCost?
    let onSaved: () -> Void

    @State private var category: ContainerCostCategory
    @State private var amount: String
    @State private var dueAt: String
    @State private var vendor: String
    @State private var reference: String
    @State private var description: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(containerId: String, cost: ContainerCost?, onSaved: @escaping () -> Void) {
        self.containerId = containerId
        self.cost = cost
        self.onSaved = onSaved
        _category = State(initialValue: cost?.category ?? "FREIGHT")
        _amount = State(initialValue: cost?.amount ?? "")
        _dueAt = State(initialValue: ContainerDetailLabels.dateField(cost?.dueAt))
        _vendor = State(initialValue: cost?.vendor ?? "")
        _reference = State(initialValue: cost?.reference ?? "")
        _description = State(initialValue: cost?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cost") {
                    Picker("Category", selection: $category) {
                        ForEach(ContainerDetailLabels.costCategories, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    AppTextField(label: "Amount", text: $amount, placeholder: "0.00", keyboardType: .decimalPad)
                    AppTextField(label: "Due date", text: $dueAt, placeholder: "YYYY-MM-DD", keyboardType: .numbersAndPunctuation)
                    AppTextField(label: "Vendor", text: $vendor, placeholder: "Vendor or payee")
                    AppTextField(label: "Reference", text: $reference)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(cost == nil ? "Add Cost" : "Edit Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(saving || Double(amount) == nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let amountValue = Double(amount) else { return }
        saving = true
        errorMessage = nil
        let body = ContainerCostSaveInput(
            category: category,
            amount: amountValue,
            description: description.nilIfBlank,
            vendor: vendor.nilIfBlank,
            vendorId: nil,
            dueAt: dueAt.nilIfBlank,
            reference: reference.nilIfBlank,
            encodeNulls: cost != nil
        )
        do {
            if let cost {
                _ = try await ContainersAPI().updateCost(id: containerId, costId: cost.id, body: body)
            } else {
                _ = try await ContainersAPI().addCost(id: containerId, body: body)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save cost."
        }
        saving = false
    }
}

private struct SkuSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onPick: (TireSku) -> Void

    @State private var q = ""
    @State private var results: [TireSku] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.muted)
                    TextField("Search SKU, brand, model...", text: $q)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                        .onChange(of: q) { _, _ in scheduleSearch() }
                }
                .padding(.horizontal, Theme.Space.md)
                .frame(height: 44)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.border)
                )
                .padding(Theme.Space.lg)

                if loading {
                    LoadingView(label: "Searching...")
                } else if let errorMessage {
                    RetryView(message: errorMessage) { Task { await search() } }
                } else if results.isEmpty {
                    EmptyStateView(text: q.nilIfBlank == nil ? "Search for a SKU." : "No SKUs found.")
                } else {
                    List(results) { sku in
                        Button {
                            onPick(sku)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("\(sku.sku) - \(sku.brand) \(sku.model)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.text)
                                Text("\(sku.size) - \(sku.category)/\(sku.position.replacingOccurrences(of: "_", with: "-"))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pick SKU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    @MainActor
    private func search() async {
        guard q.nilIfBlank != nil else {
            results = []
            return
        }
        loading = true
        errorMessage = nil
        do {
            let page = try await InventoryAPI().listSkus(q: q.nilIfBlank, pageSize: 30)
            results = page.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not search SKUs."
        }
        loading = false
    }
}

struct NewCustomerNativeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var company = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var taxExempt = false
    @State private var taxExemptNumber = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name", text: $name)
                TextField("Company", text: $company)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Address", text: $address, axis: .vertical)
                TextField("Notes", text: $notes, axis: .vertical)
            }

            Section("Tax") {
                Toggle("Tax exempt", isOn: $taxExempt)
                TextField("Tax exemption number", text: $taxExemptNumber)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button(saving ? "Saving..." : "Create customer") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .navigationTitle("New customer")
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil

        do {
            let normalizedPhone = try AppFormat.normalizeUSPhone(phone)
            _ = try await CustomersAPI().create(NewCustomerInput(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                company: company.nilIfBlank,
                phone: normalizedPhone,
                email: email.nilIfBlank,
                address: address.nilIfBlank,
                notes: notes.nilIfBlank,
                taxExempt: taxExempt,
                taxExemptNumber: taxExemptNumber.nilIfBlank
            ))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}

struct NewInventoryCountNativeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category = ""
    @State private var position = ""
    @State private var location = "MAIN"
    @State private var notes = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Scope") {
                TextField("Category", text: $category)
                TextField("Position", text: $position)
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button(saving ? "Creating..." : "Create count") {
                    Task { await save() }
                }
                .disabled(saving)
            }
        }
        .navigationTitle("New count")
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil

        do {
            _ = try await InventoryCountsAPI().create(InventoryCountCreateInput(
                scopeCategory: category.nilIfBlank,
                scopePosition: position.nilIfBlank,
                location: location.nilIfBlank,
                notes: notes.nilIfBlank
            ))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}

struct CustomerPickerNativeView: View {
    var selectForQuote = false

    var body: some View {
        if selectForQuote {
            QuoteCustomerPickerList()
        } else {
            CustomersListNativeView()
                .navigationTitle("Select customer")
        }
    }
}

struct SkuPickerNativeView: View {
    var selectForQuote = false

    var body: some View {
        InventoryListNativeView(selectForQuote: selectForQuote)
            .navigationTitle("Add a tire")
    }
}

private struct QuoteCustomerPickerList: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quote: QuoteStore

    var body: some View {
        AsyncContentView(load: { try await CustomersAPI().list(pageSize: 50) }) { page in
            List(page.items) { customer in
                Button {
                    quote.setCustomer(QuoteCustomer(customer: customer))
                    dismiss()
                } label: {
                    RowLine(
                        title: customer.company ?? customer.name,
                        subtitle: customer.company == nil ? nil : customer.name,
                        trailing: customer.taxExempt ? "Tax exempt" : nil
                    )
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Select customer")
    }
}
