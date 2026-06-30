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

struct CustomerDetailNativeView: View {
    let id: String
    let fallbackName: String

    var body: some View {
        AsyncContentView(load: { try await CustomersAPI().get(id: id) }) { customer in
            List {
                Section("Profile") {
                    RowLine(title: customer.name, subtitle: customer.company, trailing: customer.taxExempt ? "Tax exempt" : nil)
                    RowLine(title: "Phone", subtitle: AppFormat.phone(customer.phone))
                    RowLine(title: "Email", subtitle: customer.email ?? "-")
                    RowLine(title: "Address", subtitle: customer.address ?? "-")
                }

                if let sales = customer.sales, !sales.isEmpty {
                    Section("Sales") {
                        ForEach(sales) { sale in
                            NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                                RowLine(title: sale.ref ?? "Sale", subtitle: sale.status, trailing: AppFormat.money(sale.total))
                            }
                        }
                    }
                }

                if let documents = customer.documents, !documents.isEmpty {
                    Section("Documents") {
                        ForEach(documents) { document in
                            RowLine(title: document.filename, subtitle: document.kind, trailing: AppFormat.shortDate(document.createdAt))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(fallbackName)
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
    let id: String

    var body: some View {
        AsyncContentView(load: { try await ContainersAPI().get(id: id) }) { container in
            List {
                Section {
                    RowLine(title: container.ref ?? container.reference ?? "Container", subtitle: container.supplier.name, trailing: container.status)
                    RowLine(title: "BOL", subtitle: container.bolNumber ?? "-")
                    RowLine(title: "ETA", subtitle: AppFormat.shortDate(container.etaAt))
                    RowLine(title: "Received", subtitle: AppFormat.shortDate(container.receivedAt))
                }

                Section("Lines") {
                    ForEach(container.lines) { line in
                        RowLine(
                            title: "\(line.sku.brand) \(line.sku.model)",
                            subtitle: "\(line.sku.size) - qty \(line.qty)",
                            trailing: AppFormat.money(line.landedTotal ?? line.unitCost)
                        )
                    }
                }

                if !container.costs.isEmpty {
                    Section("Costs") {
                        ForEach(container.costs) { cost in
                            RowLine(title: cost.category, subtitle: cost.vendor ?? cost.description, trailing: AppFormat.money(cost.amount))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Container")
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
