import SwiftUI

struct NewQuoteNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var quote: QuoteStore

    @State private var saving = false
    @State private var errorMessage: String?
    @State private var roundTarget = ""

    var body: some View {
        Form {
            if !auth.has("sales.manage") {
                Section {
                    Text("You do not have permission to manage sales.")
                        .foregroundStyle(Theme.muted)
                }
            } else {
                customerSection
                linesSection
                totalsSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(buttonTitle) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .navigationTitle(quote.editingSaleId == nil ? "New Sale" : "Edit sale")
        .task {
            await quote.restoreDefaultTaxRate()
        }
    }

    private var customerSection: some View {
        Section("Customer") {
            if let customer = quote.customer {
                RowLine(
                    title: customer.name,
                    subtitle: customer.company,
                    trailing: customer.taxExempt ? "Tax exempt" : nil
                )
            } else {
                Text("No customer selected")
                    .foregroundStyle(Theme.muted)
            }

            NavigationLink("Select customer") {
                CustomerPickerNativeView(selectForQuote: true)
            }
        }
    }

    private var linesSection: some View {
        Section("Items") {
            if quote.lines.isEmpty {
                Text("No items yet")
                    .foregroundStyle(Theme.muted)
            }

            ForEach(quote.lines) { line in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    RowLine(
                        title: line.description,
                        subtitle: line.itemType == "SERVICE" ? "Service" : "Tire",
                        trailing: AppFormat.money(line.lineTotal)
                    )

                    Stepper("Qty \(line.qty)", value: Binding(
                        get: { line.qty },
                        set: { quote.updateQty(line.id, qty: $0) }
                    ), in: 1...999)

                    TextField("Unit price", value: Binding(
                        get: { line.unitPrice },
                        set: { quote.updatePrice(line.id, unitPrice: $0) }
                    ), format: .number)
                    .keyboardType(.decimalPad)

                    Button(role: .destructive) {
                        quote.removeLine(line.id)
                    } label: {
                        Text("Remove")
                    }
                }
            }

            NavigationLink("Add tire") {
                SkuPickerNativeView(selectForQuote: true)
            }

            NavigationLink("Add service") {
                ServicePickerNativeView()
            }
        }
    }

    private var totalsSection: some View {
        Section("Totals") {
            RowLine(title: "Subtotal", trailing: AppFormat.money(quote.subtotal))

            if quote.customer?.taxExempt == true {
                RowLine(title: "Tax exempt", trailing: AppFormat.money(0.0))
            } else {
                HStack {
                    Text("Tax rate")
                    Spacer()
                    TextField("Tax", value: $quote.taxRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text("%")
                }
                RowLine(title: "Tax", trailing: AppFormat.money(quote.taxAmount))
            }

            RowLine(title: "Total", trailing: AppFormat.money(quote.total))

            HStack {
                TextField("Round total", text: $roundTarget)
                    .keyboardType(.decimalPad)
                Button("Apply") {
                    if let target = Double(roundTarget) {
                        quote.roundTotal(to: target)
                        roundTarget = ""
                    }
                }
                .disabled(Double(roundTarget) == nil)
            }
        }
    }

    private var canSubmit: Bool {
        auth.has("sales.manage") && quote.customer != nil && !quote.lines.isEmpty && !saving
    }

    private var buttonTitle: String {
        if saving { return quote.editingSaleId == nil ? "Confirming..." : "Saving..." }
        return quote.editingSaleId == nil ? "Confirm & invoice" : "Save changes"
    }

    @MainActor
    private func submit() async {
        saving = true
        errorMessage = nil

        do {
            let input = try quote.saleInput()
            if let editingId = quote.editingSaleId {
                _ = try await SalesAPI().update(id: editingId, body: input)
                quote.clear()
            } else {
                let sale = try await SalesAPI().create(input)
                _ = try await SalesAPI().confirm(id: sale.id)
                quote.clear()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}

struct EditSaleNativeView: View {
    @EnvironmentObject private var quote: QuoteStore
    let id: String

    var body: some View {
        AsyncContentView(load: loadSale) { _ in
            NewQuoteNativeView()
        }
        .navigationTitle("Edit sale")
    }

    @MainActor
    private func loadSale() async throws -> Sale {
        let sale = try await SalesAPI().get(id: id)
        let customer = try await CustomersAPI().get(id: sale.customerId)
        quote.seed(from: sale, customer: QuoteCustomer(customer: customer))
        return sale
    }
}

struct ServicePickerNativeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quote: QuoteStore

    var body: some View {
        AsyncContentView(load: ServicesAPI().list) { services in
            List(services) { service in
                Button {
                    quote.addLine(
                        itemType: "SERVICE",
                        itemId: service.id,
                        description: service.name,
                        unitPrice: Double(service.price) ?? 0
                    )
                    dismiss()
                } label: {
                    RowLine(title: service.name, subtitle: service.code, trailing: AppFormat.money(service.price))
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Add service")
    }
}

struct SkuDetailNativeView: View {
    let sku: TireSku

    private var onHand: Int {
        sku.inventory.reduce(0) { $0 + $1.qtyOnHand }
    }

    var body: some View {
        List {
            Section {
                RowLine(title: "\(sku.size) - \(sku.brand)", subtitle: "\(sku.model) - \(sku.sku)", trailing: sku.active ? "Active" : "Inactive")
                RowLine(title: "On hand", trailing: String(onHand))
                RowLine(title: "Retail", trailing: AppFormat.money(sku.priceRetail))
                RowLine(title: "Cost", trailing: AppFormat.money(sku.priceCost))
            }

            Section("Inventory") {
                ForEach(sku.inventory) { item in
                    RowLine(title: item.location, subtitle: "\(item.qtyReserved) reserved", trailing: "\(item.qtyOnHand)")
                }
            }

            Section("Specs") {
                RowLine(title: "Category", trailing: sku.category)
                RowLine(title: "Position", trailing: sku.position)
                RowLine(title: "Segment", trailing: sku.segment ?? "-")
                RowLine(title: "Reorder point", trailing: "\(sku.reorderPoint)")
                RowLine(title: "LI & SR", trailing: sku.loadIndex ?? "-")
                RowLine(title: "Pattern", trailing: sku.pattern ?? "-")
                RowLine(title: "Tread depth", trailing: sku.treadDepth32 ?? "-")
                RowLine(title: "Max load", trailing: sku.maxLoadSingleLb.map(String.init) ?? "-")
                RowLine(title: "Weight", trailing: sku.weightLb ?? "-")
                RowLine(title: "Ply rating", trailing: sku.plyRating ?? "-")
            }

            Section {
                NavigationLink("Edit tire") {
                    SkuFormNativeView(editing: sku)
                }
                NavigationLink("Adjust stock") {
                    AdjustStockNativeView(sku: sku)
                }
                NavigationLink("Add to sale") {
                    SkuAddToQuoteView(sku: sku)
                }
            }
        }
        .navigationTitle("Tire")
    }
}

struct SkuLookupNativeView: View {
    let idOrSku: String

    var body: some View {
        AsyncContentView(load: loadSku) { sku in
            SkuDetailNativeView(sku: sku)
        }
    }

    private func loadSku() async throws -> TireSku {
        let page = try await InventoryAPI().listSkus(q: idOrSku, pageSize: 50)
        if let exact = page.items.first(where: { $0.id == idOrSku || $0.sku == idOrSku }) {
            return exact
        }
        guard let first = page.items.first else {
            throw APIError(status: 404, message: "Tire not found.")
        }
        return first
    }
}

struct SkuLookupEditNativeView: View {
    let idOrSku: String

    var body: some View {
        AsyncContentView(load: loadSku) { sku in
            SkuFormNativeView(editing: sku)
        }
    }

    private func loadSku() async throws -> TireSku {
        let page = try await InventoryAPI().listSkus(q: idOrSku, pageSize: 50)
        if let exact = page.items.first(where: { $0.id == idOrSku || $0.sku == idOrSku }) {
            return exact
        }
        guard let first = page.items.first else {
            throw APIError(status: 404, message: "Tire not found.")
        }
        return first
    }
}

struct SkuAddToQuoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quote: QuoteStore
    let sku: TireSku

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("\(sku.brand) \(sku.model)")
                .font(.title3)
                .fontWeight(.bold)
            Text("\(sku.size) - \(sku.sku)")
                .foregroundStyle(Theme.muted)
            PrimaryButton(title: "Add to sale") {
                quote.addLine(
                    itemType: "SKU",
                    itemId: sku.id,
                    description: "\(sku.brand) \(sku.model) \(sku.size) (\(sku.position.replacingOccurrences(of: "_", with: "-")))",
                    unitPrice: Double(sku.priceRetail) ?? 0
                )
                dismiss()
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct SkuFormNativeView: View {
    @Environment(\.dismiss) private var dismiss
    let editing: TireSku?

    @State private var sku = ""
    @State private var brand = ""
    @State private var model = ""
    @State private var size = ""
    @State private var category = ""
    @State private var position = ""
    @State private var segment = ""
    @State private var loadIndex = ""
    @State private var pattern = ""
    @State private var treadDepth32 = ""
    @State private var maxLoadSingleLb = ""
    @State private var weightLb = ""
    @State private var plyRating = ""
    @State private var priceRetail = ""
    @State private var priceCost = ""
    @State private var reorderPoint = ""
    @State private var active = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Tire") {
                TextField("SKU", text: $sku)
                TextField("Brand", text: $brand)
                TextField("Model", text: $model)
                TextField("Size", text: $size)
                TextField("Category", text: $category)
                TextField("Position", text: $position)
                TextField("Segment", text: $segment)
            }

            Section("Specs") {
                TextField("LI & SR", text: $loadIndex)
                TextField("Pattern", text: $pattern)
                TextField("Tread depth", text: $treadDepth32)
                    .keyboardType(.decimalPad)
                TextField("Max load", text: $maxLoadSingleLb)
                    .keyboardType(.numberPad)
                TextField("Weight", text: $weightLb)
                    .keyboardType(.decimalPad)
                TextField("Ply rating", text: $plyRating)
            }

            Section("Pricing") {
                TextField("Retail", text: $priceRetail)
                    .keyboardType(.decimalPad)
                TextField("Cost", text: $priceCost)
                    .keyboardType(.decimalPad)
                TextField("Reorder point", text: $reorderPoint)
                    .keyboardType(.numberPad)
                if editing != nil {
                    Toggle("Active", isOn: $active)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button(saving ? "Saving..." : editing == nil ? "Create tire" : "Save changes") {
                    Task { await save() }
                }
                .disabled(!isValid || saving)
            }
        }
        .navigationTitle(editing == nil ? "New tire" : "Edit tire")
        .onAppear(perform: seed)
    }

    private var isValid: Bool {
        !sku.isEmpty && !brand.isEmpty && !model.isEmpty && !size.isEmpty && !category.isEmpty && !position.isEmpty && Double(priceRetail) != nil
    }

    private func seed() {
        guard let editing, sku.isEmpty else { return }
        sku = editing.sku
        brand = editing.brand
        model = editing.model
        size = editing.size
        category = editing.category
        position = editing.position
        segment = editing.segment ?? ""
        loadIndex = editing.loadIndex ?? ""
        pattern = editing.pattern ?? ""
        treadDepth32 = editing.treadDepth32 ?? ""
        maxLoadSingleLb = editing.maxLoadSingleLb.map(String.init) ?? ""
        weightLb = editing.weightLb ?? ""
        plyRating = editing.plyRating ?? ""
        priceRetail = editing.priceRetail
        priceCost = editing.priceCost
        reorderPoint = String(editing.reorderPoint)
        active = editing.active
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil

        do {
            if let editing {
                _ = try await InventoryAPI().updateSku(id: editing.id, body: TireSkuPatchInput(
                    sku: sku,
                    brand: brand,
                    model: model,
                    size: size,
                    category: category,
                    position: position,
                    segment: segment.nilIfBlank,
                    loadIndex: loadIndex.nilIfBlank,
                    pattern: pattern.nilIfBlank,
                    treadDepth32: Double(treadDepth32),
                    maxLoadSingleLb: Int(maxLoadSingleLb),
                    weightLb: Double(weightLb),
                    plyRating: plyRating.nilIfBlank,
                    priceRetail: Double(priceRetail),
                    priceCost: Double(priceCost),
                    reorderPoint: Int(reorderPoint),
                    active: active
                ))
            } else {
                _ = try await InventoryAPI().createSku(SkuInput(
                    sku: sku,
                    brand: brand,
                    model: model,
                    size: size,
                    category: category,
                    position: position,
                    segment: segment.nilIfBlank,
                    loadIndex: loadIndex.nilIfBlank,
                    pattern: pattern.nilIfBlank,
                    treadDepth32: Double(treadDepth32),
                    maxLoadSingleLb: Int(maxLoadSingleLb),
                    weightLb: Double(weightLb),
                    plyRating: plyRating.nilIfBlank,
                    priceRetail: Double(priceRetail) ?? 0,
                    priceCost: Double(priceCost),
                    reorderPoint: Int(reorderPoint),
                    active: active
                ))
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}

struct AdjustStockNativeView: View {
    @Environment(\.dismiss) private var dismiss
    let sku: TireSku

    @State private var sign = 1
    @State private var quantity = ""
    @State private var reason = "PURCHASE"
    @State private var note = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var current: Int {
        sku.inventory.reduce(0) { $0 + $1.qtyOnHand }
    }

    private var delta: Int {
        guard let raw = Int(quantity), raw > 0 else { return 0 }
        return sign * raw
    }

    private var resulting: Int {
        current + delta
    }

    var body: some View {
        Form {
            Section {
                RowLine(title: "\(sku.brand) \(sku.model)", subtitle: "\(sku.size) - \(sku.sku)")
                RowLine(title: "On hand", trailing: "\(current)")
                RowLine(title: "Change", trailing: delta > 0 ? "+\(delta)" : "\(delta)")
                RowLine(title: "Resulting", trailing: "\(resulting)")
            }

            Section("Adjustment") {
                Picker("Direction", selection: $sign) {
                    Text("Add").tag(1)
                    Text("Remove").tag(-1)
                }
                .pickerStyle(.segmented)

                TextField("Quantity", text: $quantity)
                    .keyboardType(.numberPad)

                Picker("Reason", selection: $reason) {
                    Text("Purchase").tag("PURCHASE")
                    Text("Adjustment").tag("ADJUSTMENT")
                    Text("Return").tag("RETURN")
                }

                TextField("Note", text: $note, axis: .vertical)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button(saving ? "Applying..." : "Apply") {
                    Task { await apply() }
                }
                .disabled(delta == 0 || resulting < 0 || saving)
            }
        }
        .navigationTitle("Adjust stock")
    }

    @MainActor
    private func apply() async {
        saving = true
        errorMessage = nil

        do {
            _ = try await InventoryAPI().adjust(id: sku.id, delta: delta, reason: reason, note: note.nilIfBlank)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}

struct AdjustStockLookupNativeView: View {
    let idOrSku: String

    var body: some View {
        AsyncContentView(load: loadSku) { sku in
            AdjustStockNativeView(sku: sku)
        }
    }

    private func loadSku() async throws -> TireSku {
        let page = try await InventoryAPI().listSkus(q: idOrSku, pageSize: 50)
        if let exact = page.items.first(where: { $0.id == idOrSku || $0.sku == idOrSku }) {
            return exact
        }
        guard let first = page.items.first else {
            throw APIError(status: 404, message: "Tire not found.")
        }
        return first
    }
}

struct TapToPayNativeView: View {
    let invoiceId: String
    let amount: Double

    var body: some View {
        AsyncContentView(load: loadIntent) { intent in
            List {
                Section("Payment") {
                    RowLine(title: "Invoice", trailing: invoiceId)
                    RowLine(title: "Amount", trailing: AppFormat.money(amount))
                    RowLine(title: "Balance", trailing: AppFormat.money(intent.balance))
                    RowLine(title: "Surcharge", trailing: AppFormat.money(intent.surcharge))
                }

                Section("Terminal") {
                    RowLine(title: "Payment intent", subtitle: intent.paymentIntentId)
                    RowLine(title: "Reader", subtitle: intent.readerId ?? "-", trailing: intent.readerStatus)
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Tap to Pay")
    }

    private func loadIntent() async throws -> TerminalIntent {
        try await PaymentsAPI().terminalIntent(invoiceId: invoiceId)
    }
}

struct StartReturnNativeView: View {
    @Environment(\.dismiss) private var dismiss
    let saleId: String
    let saleRef: String?

    @State private var reason = ""
    @State private var notes = ""
    @State private var type = "RETURN"
    @State private var refundMethod = "STORE_CREDIT"
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        AsyncContentView(load: { try await ReturnsAPI().returnable(saleId: saleId) }) { returnable in
            Form {
                Section("Sale") {
                    RowLine(title: saleRef ?? returnable.saleRef ?? "Sale", subtitle: returnable.saleStatus)
                    RowLine(title: "Returnable lines", trailing: "\(returnable.lines.count)")
                }

                Section("Return") {
                    Picker("Type", selection: $type) {
                        Text("Return").tag("RETURN")
                        Text("Exchange").tag("EXCHANGE")
                        Text("Warranty").tag("WARRANTY")
                    }
                    Picker("Refund method", selection: $refundMethod) {
                        Text("Store credit").tag("STORE_CREDIT")
                        Text("Original").tag("ORIGINAL")
                        Text("Cash").tag("CASH")
                        Text("Check").tag("CHECK")
                        Text("Card").tag("CARD")
                    }
                    TextField("Reason", text: $reason)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Lines") {
                    ForEach(returnable.lines, id: \.saleLineId) { line in
                        RowLine(title: line.description, subtitle: "\(line.qtyRemaining) remaining", trailing: AppFormat.money(line.unitPrice))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(saving ? "Creating..." : "Create draft return") {
                        Task { await create(returnable: returnable) }
                    }
                    .disabled(returnable.lines.isEmpty || saving)
                }
            }
        }
        .navigationTitle("Return / Exchange")
    }

    @MainActor
    private func create(returnable: Returnable) async {
        saving = true
        errorMessage = nil

        do {
            let lines = returnable.lines.map {
                ReturnLineInput(saleLineId: $0.saleLineId, qty: $0.qtyRemaining, inventoryDisposition: "RESTOCK")
            }
            _ = try await ReturnsAPI().create(saleId: saleId, body: CreateReturnInput(
                type: type,
                reason: reason.nilIfBlank,
                restockingFee: nil,
                refundMethod: refundMethod,
                paymentMethodId: returnable.originalPaymentMethodId,
                notes: notes.nilIfBlank,
                lines: lines,
                replacementLines: nil,
                warrantyDisposition: nil,
                supplierId: nil
            ))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }
}
