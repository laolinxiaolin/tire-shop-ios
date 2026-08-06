import LocalAuthentication
import ProximityReader
import SwiftUI
import StripeTerminal
import UIKit

struct NewQuoteNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var quote: QuoteStore
    @Environment(\.dismiss) private var dismiss

    private enum FocusField: Hashable {
        case price(String)
        case taxRate
        case roundTarget
    }

    @State private var saving = false
    @State private var errorMessage: String?
    @State private var roundTarget = ""
    @State private var warehouses: [Warehouse] = []
    @State private var loadingWarehouses = true
    @State private var warehouseError: String?
    @State private var availabilityBySku: [String: Int] = [:]
    @State private var availabilityLocation = ""
    @State private var loadingAvailability = false
    @State private var availabilityRequestID = UUID()
    @State private var priceDrafts: [String: String] = [:]
    @FocusState private var focusedField: FocusField?

    var body: some View {
        Form {
            if !auth.has("sales.manage") {
                Section {
                    Text("You do not have permission to manage sales.")
                        .foregroundStyle(Theme.muted)
                }
            } else {
                customerSection
                warehouseSection
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
        .disabled(saving)
        .navigationTitle(quote.editingSaleId == nil ? "New Sale" : "Edit sale")
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField != nil {
                HStack {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.sm)
                .background(.bar)
            }
        }
        .task {
            await loadWarehouses()
            await quote.restoreDefaultTaxRate()
            await loadAvailability()
        }
        .onChange(of: quote.customer) { _, _ in
            Task { await quote.applyCustomerTaxRate() }
        }
        .onChange(of: quote.location) { _, _ in
            Task { await loadAvailability() }
        }
        .onChange(of: quote.lines.filter { $0.itemType == "SKU" }.map(\.itemId)) { _, _ in
            Task { await loadAvailability() }
        }
        .onChange(of: focusedField) { oldField, newField in
            if case let .price(lineID)? = oldField {
                finishPriceEditing(lineID)
            }

            if case let .price(lineID)? = newField,
               let line = quote.lines.first(where: { $0.id == lineID }) {
                priceDrafts[lineID] = editablePriceText(line.unitPrice)
            }
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

    private var warehouseSection: some View {
        Section("Warehouse") {
            if loadingWarehouses {
                HStack(spacing: Theme.Space.sm) {
                    ProgressView()
                    Text("Loading warehouses...")
                        .foregroundStyle(Theme.muted)
                }
            } else if warehouses.isEmpty {
                Text(warehouseError ?? "No active warehouses are available.")
                    .foregroundStyle(Theme.danger)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        if quote.location.nilIfBlank != nil,
                           !warehouses.contains(where: { $0.code == quote.location }) {
                            CompactFilterChip(
                                title: quote.location,
                                selected: true,
                                invalid: true,
                                accessibilityLabel: "\(quote.location) — inactive"
                            )
                        }

                        ForEach(warehouses) { warehouse in
                            CompactFilterChip(
                                title: warehouse.code,
                                selected: quote.location == warehouse.code,
                                accessibilityLabel: "\(warehouse.code) — \(warehouse.name)"
                            ) {
                                quote.setLocation(warehouse.code)
                            }
                        }
                    }
                }
                .frame(height: 32)

                Text("Tire availability and stock relief use this warehouse.")
                    .font(.footnote)
                    .foregroundStyle(
                        warehouses.contains(where: { $0.code == quote.location }) ? Theme.muted : Theme.danger
                    )

                if loadingAvailability && quote.lines.contains(where: { $0.itemType == "SKU" }) {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView()
                        Text("Checking tire availability...")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
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
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(line.description)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)

                            Text(line.itemType == "SERVICE" ? "Service" : "Tire")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }

                        Spacer(minLength: Theme.Space.sm)

                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(Theme.muted)

                            TextField("0", text: priceBinding(for: line))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .price(line.id))
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit().weight(.semibold))
                                .accessibilityLabel("Unit price for \(line.description)")
                        }
                        .padding(.horizontal, Theme.Space.sm)
                        .frame(width: 120, height: 44)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(
                                    focusedField == .price(line.id) ? Theme.primary : Theme.border,
                                    lineWidth: focusedField == .price(line.id) ? 2 : 1
                                )
                        }
                    }

                    if let available = availableQuantity(for: line) {
                        Text("\(available) available at \(quote.location)")
                            .font(.caption)
                            .foregroundStyle(line.qty > available ? Theme.danger : Theme.muted)
                    }

                    HStack(spacing: Theme.Space.md) {
                        Stepper("Qty \(line.qty)", value: Binding(
                            get: { line.qty },
                            set: { quote.updateQty(line.id, qty: $0) }
                        ), in: 1...maximumQuantity(for: line))

                        Divider()
                            .frame(height: 28)

                        Button(role: .destructive) {
                            priceDrafts.removeValue(forKey: line.id)
                            quote.removeLine(line.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.danger)
                        .accessibilityLabel("Remove \(line.description)")
                    }

                }
                .padding(.vertical, Theme.Space.xs)
            }

            NavigationLink("Add tire") {
                InventoryListNativeView(selectForQuote: true)
                    .navigationTitle("Add a tire")
            }
            .disabled(quote.location.nilIfBlank == nil)

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
                if let message = quote.taxLookupMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                HStack {
                    Text("Tax rate")
                    Spacer()
                    TextField("Tax", value: Binding(
                        get: { quote.taxRate },
                        set: { quote.setTaxRate($0) }
                    ), format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .taxRate)
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
                    .focused($focusedField, equals: .roundTarget)
                Button("Apply") {
                    if let target = Double(roundTarget) {
                        quote.roundTotal(to: target)
                        priceDrafts.removeAll()
                        roundTarget = ""
                    }
                }
                .disabled(Double(roundTarget) == nil)
            }
        }
    }

    private func priceBinding(for line: QuoteLine) -> Binding<String> {
        Binding(
            get: {
                priceDrafts[line.id] ?? formattedPriceText(line.unitPrice)
            },
            set: { input in
                let sanitized = sanitizePriceInput(input)
                priceDrafts[line.id] = sanitized

                if let value = Double(sanitized) {
                    quote.updatePrice(line.id, unitPrice: value)
                }
            }
        )
    }

    private func finishPriceEditing(_ lineID: String) {
        guard let line = quote.lines.first(where: { $0.id == lineID }) else {
            priceDrafts.removeValue(forKey: lineID)
            return
        }

        if let draft = priceDrafts[lineID], let value = Double(draft) {
            quote.updatePrice(lineID, unitPrice: value)
            priceDrafts[lineID] = formattedPriceText(value)
        } else {
            priceDrafts[lineID] = formattedPriceText(line.unitPrice)
        }
    }

    private func sanitizePriceInput(_ input: String) -> String {
        var result = ""
        var hasDecimal = false
        var fractionalDigits = 0

        for character in input {
            if character.isNumber {
                if !hasDecimal || fractionalDigits < 2 {
                    result.append(character)
                    if hasDecimal { fractionalDigits += 1 }
                }
            } else if (character == "." || character == ",") && !hasDecimal {
                result.append(".")
                hasDecimal = true
            }
        }

        return result
    }

    private func editablePriceText(_ value: Double) -> String {
        var result = formattedPriceText(value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }

    private func formattedPriceText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private var canSubmit: Bool {
        auth.has("sales.manage")
            && quote.customer != nil
            && quote.location.nilIfBlank != nil
            && warehouses.contains(where: { $0.code == quote.location })
            && !quote.lines.isEmpty
            && !(loadingAvailability && quote.lines.contains(where: { $0.itemType == "SKU" }))
            && !hasStockShortage
            && !saving
    }

    private var hasStockShortage: Bool {
        guard availabilityLocation == quote.location else { return false }
        return quote.lines.contains { line in
            line.itemType == "SKU" && line.qty > (availabilityBySku[line.itemId] ?? 0)
        }
    }

    private var buttonTitle: String {
        if saving { return quote.editingSaleId == nil ? "Confirming..." : "Saving..." }
        if quote.pendingConfirmationSaleId != nil { return "Retry confirmation" }
        if quote.pendingCreationIdempotencyKey != nil { return "Retry sale creation" }
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
                dismiss()
            } else {
                let saleID: String
                if let pendingID = quote.pendingConfirmationSaleId {
                    let pendingSale = try await SalesAPI().get(id: pendingID)
                    if pendingSale.status == "INVOICED" {
                        quote.clear()
                        applyDefaultWarehouse()
                        saving = false
                        return
                    }
                    _ = try await SalesAPI().update(id: pendingID, body: input)
                    saleID = pendingID
                } else {
                    let isCreationRetry = quote.pendingCreationInput != nil
                    if !isCreationRetry {
                        quote.pendingCreationInput = input
                        quote.pendingCreationIdempotencyKey = UUID().uuidString
                    }
                    let creationInput = quote.pendingCreationInput ?? input
                    let idempotencyKey = quote.pendingCreationIdempotencyKey ?? UUID().uuidString
                    quote.pendingCreationIdempotencyKey = idempotencyKey

                    let sale: SaleCreateResult
                    do {
                        sale = try await SalesAPI().create(creationInput, idempotencyKey: idempotencyKey)
                    } catch {
                        if let apiError = error as? APIError, apiError.status != 0 {
                            quote.pendingCreationInput = nil
                            quote.pendingCreationIdempotencyKey = nil
                        }
                        throw error
                    }
                    quote.pendingConfirmationSaleId = sale.id
                    if isCreationRetry {
                        _ = try await SalesAPI().update(id: sale.id, body: input)
                    }
                    saleID = sale.id
                }

                _ = try await SalesAPI().confirm(id: saleID)
                quote.clear()
                applyDefaultWarehouse()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }

    private func availableQuantity(for line: QuoteLine) -> Int? {
        guard line.itemType == "SKU", availabilityLocation == quote.location else { return nil }
        return availabilityBySku[line.itemId] ?? 0
    }

    private func maximumQuantity(for line: QuoteLine) -> Int {
        guard let available = availableQuantity(for: line) else { return 999 }
        return max(line.qty, max(available, 1))
    }

    @MainActor
    private func loadWarehouses() async {
        loadingWarehouses = true
        warehouseError = nil
        defer { loadingWarehouses = false }

        do {
            warehouses = try await WarehousesAPI().list(activeOnly: true)
            applyDefaultWarehouse()
        } catch {
            warehouses = []
            warehouseError = (error as? LocalizedError)?.errorDescription ?? "Could not load warehouses."
        }
    }

    private func applyDefaultWarehouse() {
        guard quote.location.nilIfBlank == nil else { return }
        let home = auth.user?.homeWarehouse?.nilIfBlank
        let selected = home.flatMap { code in warehouses.first { $0.code == code }?.code }
            ?? warehouses.first(where: \.isDefault)?.code
            ?? warehouses.first?.code
        if let selected {
            quote.setLocation(selected)
        }
    }

    @MainActor
    private func loadAvailability() async {
        let requestID = UUID()
        availabilityRequestID = requestID

        guard let location = quote.location.nilIfBlank else {
            availabilityBySku = [:]
            availabilityLocation = ""
            loadingAvailability = false
            return
        }

        let skuIds = Set(quote.lines.filter { $0.itemType == "SKU" }.map(\.itemId))
        guard !skuIds.isEmpty else {
            availabilityBySku = [:]
            availabilityLocation = location
            loadingAvailability = false
            return
        }

        loadingAvailability = true
        availabilityLocation = ""
        defer {
            if quote.location == location && availabilityRequestID == requestID {
                loadingAvailability = false
            }
        }

        do {
            var pageNumber = 1
            var matching: [String: TireSku] = [:]

            while true {
                let page = try await InventoryAPI().listSkus(
                    page: pageNumber,
                    pageSize: 1000
                )
                for sku in page.items where skuIds.contains(sku.id) {
                    matching[sku.id] = sku
                }
                guard matching.count < skuIds.count,
                      page.page * page.pageSize < page.total,
                      !page.items.isEmpty else { break }
                pageNumber = page.page + 1
            }

            guard quote.location == location, availabilityRequestID == requestID else { return }
            availabilityBySku = Dictionary(uniqueKeysWithValues: skuIds.map { id in
                let inventory = matching[id]?.inventory.first { $0.location == location }
                let quantity = max(0, (inventory?.qtyOnHand ?? 0) - (inventory?.qtyReserved ?? 0))
                return (id, quantity)
            })
            availabilityLocation = location
        } catch {
            guard quote.location == location, availabilityRequestID == requestID else { return }
            availabilityBySku = [:]
            availabilityLocation = ""
        }
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
    @EnvironmentObject private var auth: AuthStore

    let sku: TireSku
    var initialLocation: String? = nil

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
                    RowLine(
                        title: item.location,
                        subtitle: "\(item.qtyReserved) reserved · \(AppFormat.money(item.unitCost)) cost",
                        trailing: "\(item.qtyOnHand)"
                    )
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
                if auth.has("inventory.manage") {
                    NavigationLink("Edit tire") {
                        SkuFormNativeView(editing: sku)
                    }
                }
                if auth.canActOrRequest("inventory.adjust") {
                    NavigationLink("Adjust stock") {
                        AdjustStockNativeView(sku: sku, initialLocation: initialLocation)
                    }
                }
                NavigationLink("Stock history") {
                    SkuHistoryNativeView(skuId: sku.id)
                }
                if auth.has("sales.manage") {
                    NavigationLink("Add to sale") {
                        SkuAddToQuoteView(sku: sku)
                    }
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
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var quote: QuoteStore
    let sku: TireSku

    @State private var loadingWarehouse = false
    @State private var warehouseError: String?

    private var available: Int {
        guard let location = quote.location.nilIfBlank else { return 0 }
        guard let inventory = sku.inventory.first(where: { $0.location == location }) else { return 0 }
        return max(0, inventory.qtyOnHand - inventory.qtyReserved)
    }

    private var availabilityText: String {
        guard let location = quote.location.nilIfBlank else {
            return loadingWarehouse ? "Loading sale warehouse..." : "Select a sale warehouse first."
        }
        return "\(available) available at \(location)"
    }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("\(sku.brand) \(sku.model)")
                .font(.title3)
                .fontWeight(.bold)
            Text("\(sku.size) - \(sku.sku)")
                .foregroundStyle(Theme.muted)
            Text(warehouseError ?? availabilityText)
                .font(.subheadline)
                .foregroundStyle(available > 0 && warehouseError == nil ? Theme.muted : Theme.danger)
            PrimaryButton(
                title: "Add to sale",
                disabled: !auth.has("sales.manage")
                    || quote.location.nilIfBlank == nil
                    || available <= 0
                    || loadingWarehouse
            ) {
                guard auth.has("sales.manage") else { return }
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
        .task {
            await ensureSaleWarehouse()
        }
    }

    @MainActor
    private func ensureSaleWarehouse() async {
        loadingWarehouse = true
        warehouseError = nil
        defer { loadingWarehouse = false }

        do {
            let warehouses = try await WarehousesAPI().list(activeOnly: true)
            guard !warehouses.isEmpty else {
                warehouseError = "No active warehouses are available."
                return
            }
            if !warehouses.contains(where: { $0.code == quote.location }) {
                let home = auth.user?.homeWarehouse?.nilIfBlank
                let selected = home.flatMap { code in warehouses.first { $0.code == code }?.code }
                    ?? warehouses.first(where: \.isDefault)?.code
                    ?? warehouses[0].code
                quote.setLocation(selected)
            }
        } catch {
            warehouseError = (error as? LocalizedError)?.errorDescription ?? "Could not load warehouses."
        }
    }
}

struct SkuFormNativeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

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
                .disabled(!auth.has("inventory.manage") || !isValid || saving)
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
        guard auth.has("inventory.manage") else {
            errorMessage = "You do not have permission to manage inventory."
            return
        }
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
    @EnvironmentObject private var auth: AuthStore

    let sku: TireSku
    let initialLocation: String?

    @State private var sign = 1
    @State private var quantity = ""
    @State private var reason = "PURCHASE"
    @State private var note = ""
    @State private var warehouses: [Warehouse] = []
    @State private var location: String
    @State private var loadingWarehouses = true
    @State private var warehouseError: String?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var approvalRequestId: String?

    init(sku: TireSku, initialLocation: String? = nil) {
        self.sku = sku
        self.initialLocation = initialLocation
        let seedLocation = initialLocation?.nilIfBlank
            ?? sku.inventory.first(where: { $0.qtyOnHand > 0 })?.location
            ?? sku.inventory.first?.location
            ?? ""
        _location = State(initialValue: seedLocation)
    }

    private var currentInventory: TireSkuInventory? {
        sku.inventory.first { $0.location == location }
    }

    private var current: Int {
        currentInventory?.qtyOnHand ?? 0
    }

    private var reserved: Int {
        currentInventory?.qtyReserved ?? 0
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
                RowLine(title: "Reserved", trailing: "\(reserved)")
                RowLine(title: "Unit cost", trailing: currentInventory.map { AppFormat.money($0.unitCost) } ?? "—")
                RowLine(title: "Change", trailing: delta > 0 ? "+\(delta)" : "\(delta)")
                RowLine(title: "Resulting", trailing: "\(resulting)")
                if resulting < reserved {
                    Text("\(reserved) reserved units must remain at this warehouse.")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section("Warehouse") {
                if loadingWarehouses {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView()
                        Text("Loading warehouses...")
                            .foregroundStyle(Theme.muted)
                    }
                } else if warehouses.isEmpty {
                    Text(warehouseError ?? "No active warehouses are available.")
                        .foregroundStyle(Theme.danger)
                } else {
                    Picker("Location", selection: $location) {
                        ForEach(warehouses) { warehouse in
                            Text("\(warehouse.code) — \(warehouse.name)")
                                .tag(warehouse.code)
                        }
                    }
                }
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
                .disabled(
                    delta == 0
                        || resulting < reserved
                        || !warehouses.contains(where: { $0.code == location })
                        || !auth.canActOrRequest("inventory.adjust")
                        || saving
                )
            }
        }
        .navigationTitle("Adjust stock")
        .task {
            await loadWarehouses()
        }
        .alert(
            "Approval requested",
            isPresented: Binding(
                get: { approvalRequestId != nil },
                set: { if !$0 { approvalRequestId = nil } }
            )
        ) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Stock was not changed yet. Request \(approvalRequestId ?? "") is waiting for approval.")
        }
    }

    @MainActor
    private func apply() async {
        guard auth.canActOrRequest("inventory.adjust") else {
            errorMessage = "You do not have permission to adjust inventory."
            return
        }
        saving = true
        errorMessage = nil

        do {
            guard let location = location.nilIfBlank else {
                throw APIError(status: 0, message: "Select a warehouse first.")
            }
            guard warehouses.contains(where: { $0.code == location }) else {
                throw APIError(status: 0, message: "Select an active warehouse first.")
            }
            guard resulting >= reserved else {
                throw APIError(status: 0, message: "Reserved units cannot be removed.")
            }
            let result = try await InventoryAPI().adjust(
                id: sku.id,
                delta: delta,
                reason: reason,
                location: location,
                note: note.nilIfBlank
            )
            switch result {
            case .immediate:
                dismiss()
            case .approval(let request):
                approvalRequestId = request.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        saving = false
    }

    @MainActor
    private func loadWarehouses() async {
        loadingWarehouses = true
        warehouseError = nil
        defer { loadingWarehouses = false }

        do {
            warehouses = try await WarehousesAPI().list(activeOnly: true)
            if !warehouses.contains(where: { $0.code == location }) {
                location = initialLocation.flatMap { preferred in
                    warehouses.first { $0.code == preferred }?.code
                } ?? sku.inventory.first(where: { inventory in
                    inventory.qtyOnHand > 0 && warehouses.contains { $0.code == inventory.location }
                })?.location
                    ?? warehouses.first(where: \.isDefault)?.code
                    ?? warehouses.first?.code
                    ?? ""
            }
        } catch {
            warehouses = []
            warehouseError = (error as? LocalizedError)?.errorDescription ?? "Could not load warehouses."
        }
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

struct TapToPayLaunchAnnouncementView: View {
    let canManageSettings: Bool
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(Theme.primary)

                        Text("Tap to Pay on iPhone is available for checkout")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.text)

                        Text("On an eligible iPhone, Tire Force US can accept Apple Pay, contactless cards, and other contactless digital wallets directly from an invoice checkout.")
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        ProximityReaderDiscoveryButton(title: "Show Apple Tap to Pay guide")
                        Text("This opens Apple's merchant education for how customers should tap cards and devices on iPhone.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        TapToPayInfoRow(
                            title: "Use it at invoice checkout",
                            detail: "Open an unpaid invoice, choose Tap to Pay on iPhone, confirm your identity, then ask the customer to hold their card or device near the top of the iPhone.",
                            systemImage: "iphone.gen3"
                        )
                        TapToPayInfoRow(
                            title: "Keep a fallback ready",
                            detail: "If the iPhone, account, or network is not ready, use Card / manual payment from the same invoice.",
                            systemImage: "creditcard"
                        )
                        TapToPayInfoRow(
                            title: "Offer a receipt",
                            detail: "After payment, offer to email the invoice or receipt from the success screen or invoice detail.",
                            systemImage: "envelope"
                        )

                        if canManageSettings {
                            TapToPayInfoRow(
                                title: "Admin setup only",
                                detail: "If Stripe or Apple asks to enable Tap to Pay on iPhone or accept terms, an authorized admin should complete that step.",
                                systemImage: "person.badge.shield.checkmark"
                            )
                        }
                    }
                }
                .padding(Theme.Space.xl)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Space.sm) {
                    PrimaryButton(title: "I understand", action: onDone)
                    Text("This message appears once for payment-enabled users.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(Theme.Space.lg)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onDone)
                }
            }
        }
    }
}

struct TapToPayEducationView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("ttpoiAdminSetupReviewed.v1") private var adminSetupReviewed = false

    private var canCollect: Bool { auth.has("payments.collect") }
    private var canManageSettings: Bool { auth.has("settings.manage") }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Theme.primary)

                    Text("Tap to Pay on iPhone")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Use an eligible iPhone to accept Apple Pay, contactless cards, and other contactless digital wallets from unpaid invoices.")
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, Theme.Space.sm)
            }

            Section {
                RowLine(title: "Signed-in role", trailing: auth.user?.roleName ?? "Unknown")
                TapToPayInfoRow(
                    title: canCollect ? "Payment access is enabled" : "Payment access is not enabled",
                    detail: canCollect
                        ? "This account can start Tap to Pay on iPhone checkout when the device and Stripe account are eligible."
                        : "Ask an admin to grant payment collection access before using Tap to Pay on iPhone.",
                    systemImage: canCollect ? "checkmark.seal.fill" : "lock.fill",
                    tint: canCollect ? Theme.success : Theme.danger
                )

                if canManageSettings {
                    Toggle("Admin reviewed setup guidance", isOn: $adminSetupReviewed)
                } else {
                    Text("If setup prompts or terms appear, ask an authorized admin to complete them.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            } header: {
                Text("Setup status")
            } footer: {
                Text("Stripe or Apple setup prompts should be completed by an authorized admin, not by a cashier account.")
            }

            Section("Apple Merchant Education") {
                ProximityReaderDiscoveryButton(title: "Show Apple Tap to Pay guide")
                TapToPayInfoRow(
                    title: "Customer tap guidance",
                    detail: "Use Apple's guide to show where the customer should hold a contactless card, iPhone, Apple Watch, or other NFC wallet during checkout.",
                    systemImage: "iphone.radiowaves.left.and.right"
                )
                TapToPayInfoRow(
                    title: "Record this for review",
                    detail: "Open this guide before checkout in the App Review screen recording so merchant education is visible.",
                    systemImage: "video"
                )
            }

            Section("New User Flow") {
                TapToPayInfoRow(
                    title: "Before the first payment",
                    detail: "Show the user this guide, explain compatible iPhone requirements, and keep Card / manual payment available as fallback.",
                    systemImage: "1.circle"
                )
                TapToPayInfoRow(
                    title: "First checkout",
                    detail: "The app checks device support, initializes the reader, and shows any reader setup progress before collecting payment.",
                    systemImage: "2.circle"
                )
                TapToPayInfoRow(
                    title: "After payment",
                    detail: "Confirm the captured payment and offer to send the invoice or receipt to the customer.",
                    systemImage: "3.circle"
                )
            }

            Section("Checkout Flow") {
                TapToPayInfoRow(
                    title: "Start from an unpaid invoice",
                    detail: "Choose Tap to Pay on iPhone from the invoice actions. The amount, balance, surcharge, and payment intent stay visible before charging.",
                    systemImage: "doc.text"
                )
                TapToPayInfoRow(
                    title: "Customer-present collection",
                    detail: "When prompted, ask the customer to hold their contactless card or device near the top of the iPhone until the reader confirms the result.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                TapToPayInfoRow(
                    title: "Fallback path",
                    detail: "If Tap to Pay on iPhone is not available, return to the invoice and use Card / manual payment.",
                    systemImage: "arrow.uturn.backward.circle"
                )
            }

            Section("Apple Review Evidence") {
                TapToPayInfoRow(
                    title: "Record these flows",
                    detail: "New user education, existing user returning to checkout, and the full checkout path from invoice to receipt offer.",
                    systemImage: "video"
                )
                TapToPayInfoRow(
                    title: "Show unsupported handling",
                    detail: "If a device is not eligible, the checkout screen explains the issue and keeps the fallback payment path available.",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle("Tap to Pay on iPhone")
    }
}

private struct TapToPayInfoRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint = Theme.primary

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ProximityReaderDiscoveryButton: View {
    let title: String

    @State private var presenting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button {
                Task { await presentAppleGuide() }
            } label: {
                HStack {
                    Label(presenting ? "Opening Apple guide..." : title, systemImage: "questionmark.circle")
                    if presenting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(presenting)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    @MainActor
    private func presentAppleGuide() async {
        guard #available(iOS 18.0, *) else {
            errorMessage = "Apple's in-app Tap to Pay guide requires iOS 18 or later. Use the checklist below on this device."
            return
        }

        presenting = true
        defer { presenting = false }

        do {
            let discovery = ProximityReaderDiscovery()
            let content = try await discovery.content(for: .payment(.howToTap))
            guard let viewController = topPresentedViewController() else {
                throw APIError(status: 0, message: "Could not open the Apple guide from this screen.")
            }
            try await discovery.presentContent(content, from: viewController)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not open the Apple guide."
        }
    }
}

@MainActor
private func topPresentedViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
    return topPresentedViewController(from: root)
}

@MainActor
private func topPresentedViewController(from root: UIViewController) -> UIViewController {
    if let presented = root.presentedViewController {
        return topPresentedViewController(from: presented)
    }
    if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
        return topPresentedViewController(from: visible)
    }
    if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
        return topPresentedViewController(from: selected)
    }
    return root
}

enum TapToPayOutcomeStatus: Equatable {
    case approved
    case declined
    case timedOut
    case failed

    var title: String {
        switch self {
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .timedOut: return "Timed out"
        case .failed: return "Not completed"
        }
    }

    var systemImage: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .declined: return "xmark.octagon.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .approved: return Theme.success
        case .declined, .timedOut, .failed: return Theme.danger
        }
    }
}

struct TapToPayOutcome: Equatable {
    let status: TapToPayOutcomeStatus
    let detail: String
    let amount: Double
    let invoiceId: String
    let paymentIntentId: String
    let happenedAt: Date
}

private struct TapToPayReceiptShare: Identifiable {
    let text: String
    let id = UUID()
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TapToPayNativeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var terminal = TapToPayTerminalController.shared
    @State private var emailInvoice: SaleInvoice?
    @State private var receiptShare: TapToPayReceiptShare?
    @State private var splitAmountText = ""
    @State private var splitAmount: Double?
    @State private var preflight: ChargePreflight?
    @State private var acknowledgedWarnings = false
    @State private var splitMessage: String?
    @State private var charging = false

    let invoiceId: String
    let amount: Double
    let saleId: String?
    let saleRef: String?
    let customerName: String?

    private var canCollect: Bool { auth.has("payments.collect") }
    private var invoiceOutcome: TapToPayOutcome? { terminal.outcome(for: invoiceId) }
    private var invoiceSucceeded: Bool { terminal.succeeded(for: invoiceId) }
    private var invoiceIsProcessing: Bool { terminal.isProcessing(invoiceId: invoiceId) }
    private var hasWarnings: Bool { (preflight?.warnings.isEmpty ?? true) == false }

    var body: some View {
        AsyncContentView(load: loadIntent) { intent in
            List {
                Section("Payment") {
                    RowLine(title: "Invoice", trailing: invoiceId)
                    if let saleRef = saleRef?.nilIfBlank {
                        RowLine(title: "Sale", trailing: saleRef)
                    } else if let saleId = saleId?.nilIfBlank {
                        RowLine(title: "Sale", trailing: saleId)
                    }
                    if let customerName = customerName?.nilIfBlank {
                        RowLine(title: "Customer", trailing: customerName)
                    }
                    RowLine(title: "Invoice balance", trailing: AppFormat.money(intent.balance))
                    RowLine(title: "Card fee", trailing: AppFormat.money(preflight?.fee ?? intent.surcharge))
                    RowLine(title: "Customer pays", trailing: AppFormat.money(chargeAmount(intent)))
                }

                splitSection(intent: intent)

                Section("Before charging") {
                    ProximityReaderDiscoveryButton(title: "Show Apple Tap to Pay guide")

                    if canCollect {
                        TapToPayInfoRow(
                            title: "Confirm identity",
                            detail: "The app asks for Face ID, Touch ID, or the device passcode when available before starting a Tap to Pay on iPhone payment.",
                            systemImage: "faceid"
                        )
                    } else {
                        TapToPayInfoRow(
                            title: "Payment permission required",
                            detail: "This account cannot take payments. Ask an admin to grant payment collection access.",
                            systemImage: "lock.fill",
                            tint: Theme.danger
                        )
                    }

                    TapToPayInfoRow(
                        title: "Fallback available",
                        detail: "If this iPhone, account, or network cannot use Tap to Pay on iPhone, return to the invoice and choose Card / manual payment.",
                        systemImage: "creditcard"
                    )
                }

                Section("Transaction outcome") {
                    if let outcome = invoiceOutcome {
                        TapToPayOutcomeView(outcome: outcome)
                    } else if invoiceIsProcessing {
                        TapToPayInfoRow(
                            title: "Processing",
                            detail: "Keep this screen open until the transaction is approved, declined, or timed out.",
                            systemImage: "hourglass",
                            tint: Theme.primary
                        )
                    } else {
                        TapToPayInfoRow(
                            title: "Ready",
                            detail: "No transaction has been processed yet.",
                            systemImage: "circle",
                            tint: Theme.muted
                        )
                    }
                }

                Section("Terminal") {
                    RowLine(title: "Payment intent", subtitle: intent.paymentIntentId)
                    RowLine(title: "Reader", subtitle: intent.readerId ?? "-", trailing: intent.readerStatus)
                }

                Section("Status") {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        if invoiceIsProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: invoiceSucceeded ? "checkmark.circle.fill" : "iphone.gen3")
                                .foregroundStyle(invoiceSucceeded ? Theme.success : Theme.primary)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(terminal.statusMessage(for: invoiceId))
                                .foregroundStyle(Theme.text)
                            if let readerMessage = terminal.readerMessage(for: invoiceId) {
                                Text(readerMessage)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    RowLine(title: "Connection", trailing: terminal.connectionStatusText)
                    RowLine(title: "Payment", trailing: terminal.paymentStatusText)

                    if let readerName = terminal.readerName {
                        RowLine(title: "Connected reader", subtitle: readerName)
                    }

                    if let intentStatus = terminal.paymentIntentStatusText {
                        RowLine(title: "Intent status", trailing: intentStatus)
                    }
                }

                if terminal.isCurrent(invoiceId: invoiceId), let updateProgress = terminal.updateProgress {
                    Section("Reader setup") {
                        ProgressView(value: updateProgress)
                        Text("\(Int(updateProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                if let errorMessage = terminal.errorMessage(for: invoiceId) {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }

                if let outcome = invoiceOutcome {
                    Section(outcome.status == .approved ? "Receipt" : "Transaction Result") {
                        TapToPayInfoRow(
                            title: outcome.status == .approved ? "Send a digital receipt" : "Share the result privately",
                            detail: outcome.status == .approved
                                ? "Send the receipt by email, or use the private share sheet for Messages, Mail, AirDrop, or other approved destinations."
                                : "If the customer wants confirmation, use the private share sheet to send the declined or timed-out result by Messages, Mail, AirDrop, or another approved destination.",
                            systemImage: "square.and.arrow.up",
                            tint: outcome.status == .approved ? Theme.success : Theme.primary
                        )

                        if outcome.status == .approved {
                            Button {
                                emailInvoice = SaleInvoice(
                                    id: invoiceId,
                                    ref: nil,
                                    amountDue: "0.00",
                                    paidTotal: String(format: "%.2f", outcome.amount)
                                )
                            } label: {
                                Label("Email invoice / receipt", systemImage: "envelope")
                            }
                        }

                        Button {
                            receiptShare = TapToPayReceiptShare(text: shareText(for: outcome))
                        } label: {
                            Label("Share digital receipt / result", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                chargeBar(intent: intent)
            }
        }
        .navigationTitle("Tap to Pay on iPhone")
        .navigationBarBackButtonHidden(invoiceIsProcessing)
        .onAppear {
            terminal.prepare(invoiceId: invoiceId)
        }
        .onDisappear {
            if invoiceIsProcessing {
                terminal.cancelActiveCharge(invoiceId: invoiceId)
            }
        }
        .sheet(item: $emailInvoice) { invoice in
            InvoiceEmailView(invoice: invoice)
        }
        .sheet(item: $receiptShare) { share in
            ActivityShareSheet(items: [share.text])
        }
    }

    private func loadIntent() async throws -> TerminalIntent {
        try await PaymentsAPI().terminalIntent(invoiceId: invoiceId, amount: splitAmount)
    }

    private func splitSection(intent: TerminalIntent) -> some View {
        Section("Split amount") {
            TextField("Amount (blank = full balance)", text: $splitAmountText)
                .keyboardType(.decimalPad)
                .onChange(of: splitAmountText) { _, _ in
                    // Editing the field invalidates the applied preflight until
                    // it's re-applied, so the breakdown/button can't disagree
                    // with the typed amount.
                    preflight = nil
                    acknowledgedWarnings = false
                }
            Button("Use full balance") {
                splitAmountText = ""
                splitAmount = nil
                preflight = nil
                acknowledgedWarnings = false
            }
            Button("Apply this amount") {
                let value = AppFormat.parseAmount(splitAmountText)
                guard let value, value > 0, value <= intent.balance + 0.005 else {
                    splitMessage = "Enter an amount between 0.01 and \(AppFormat.money(intent.balance))."
                    return
                }
                splitMessage = nil
                splitAmount = value
                Task { await checkPreflight(amount: value) }
            }
            if let splitMessage {
                Text(splitMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            if let preflight {
                RowLine(title: "You'll be charged", trailing: AppFormat.money(preflight.requestAmount))
                RowLine(title: "Applied to invoice", trailing: AppFormat.money(preflight.applied))
                if preflight.fee > 0 {
                    RowLine(title: "Card fee", trailing: AppFormat.money(preflight.fee))
                }
                RowLine(title: "Remaining balance", trailing: AppFormat.money(preflight.remaining))
            }

            if hasWarnings {
                ForEach(preflight?.warnings ?? [], id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                }
                Button(acknowledgedWarnings ? "Warnings acknowledged" : "Acknowledge warnings") {
                    acknowledgedWarnings = true
                }
                .disabled(acknowledgedWarnings)
            }
        }
    }

    @MainActor
    private func checkPreflight(amount: Double) async {
        acknowledgedWarnings = false
        preflight = try? await PaymentsAPI().chargePreflight(
            invoiceId: invoiceId,
            body: ChargePreflightInput(amount: amount, paymentMethodId: nil)
        )
    }

    private func chargeBar(intent: TerminalIntent) -> some View {
        VStack(spacing: Theme.Space.sm) {
            if invoiceSucceeded {
                PrimaryButton(title: "Done") {
                    dismiss()
                }
            } else {
                Button {
                    Task { await chargeWithIntent(intent: intent) }
                } label: {
                    HStack {
                        if invoiceIsProcessing || charging {
                            ProgressView()
                                .tint(Theme.primaryText)
                        }
                        Text(invoiceIsProcessing ? "Processing..." : "Charge \(AppFormat.money(chargeAmount(intent)))")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(canCharge(intent) ? Theme.primary : Theme.border)
                    .foregroundStyle(canCharge(intent) ? Theme.primaryText : Theme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .disabled(!canCharge(intent) || charging)

                if invoiceIsProcessing {
                    Button("Cancel payment", role: .destructive) {
                        terminal.cancelActiveCharge(invoiceId: invoiceId)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(.ultraThinMaterial)
    }

    private func canCharge(_ intent: TerminalIntent) -> Bool {
        guard canCollect && terminal.canCharge(invoiceId: invoiceId, intent: intent) else { return false }
        // A split charge requires a completed preflight and acknowledged warnings.
        if splitAmount != nil {
            guard let preflight else { return false }
            if hasWarnings && !acknowledgedWarnings {
                return false
            }
        }
        return true
    }

    /// The amount the charge button should show: the split amount once a
    /// preflight has confirmed it, otherwise the loaded intent's amount.
    private func chargeAmount(_ intent: TerminalIntent) -> Double {
        preflight?.requestAmount ?? splitAmount ?? intent.amount
    }

    /// Starts the terminal charge. For a plain full-balance charge the already-
    /// loaded intent is reused; a split amount creates a fresh intent at charge
    /// time (so adjusting a split doesn't orphan a PaymentIntent per apply).
    @MainActor
    private func chargeWithIntent(intent: TerminalIntent) async {
        guard !charging else { return }
        charging = true
        defer { charging = false }
        do {
            let chargeIntent: TerminalIntent
            if splitAmount == nil {
                chargeIntent = intent
            } else {
                chargeIntent = try await PaymentsAPI().terminalIntent(invoiceId: invoiceId, amount: splitAmount)
            }
            guard chargeIntent.clientSecret?.nilIfBlank != nil, chargeIntent.amount > 0 else {
                splitMessage = "The server did not return a chargeable payment intent."
                return
            }
            terminal.startCharge(invoiceId: invoiceId, intent: chargeIntent)
        } catch {
            splitMessage = (error as? LocalizedError)?.errorDescription ?? "Could not start the charge."
        }
    }

    private func shareText(for outcome: TapToPayOutcome) -> String {
        let saleText = saleRef?.nilIfBlank.map { "\nSale: \($0)" } ?? ""
        let customerText = customerName?.nilIfBlank.map { "\nCustomer: \($0)" } ?? ""
        return """
        Tire Force US Tap to Pay on iPhone
        Result: \(outcome.status.title)
        Amount: \(AppFormat.money(outcome.amount))
        Invoice: \(outcome.invoiceId)\(saleText)\(customerText)
        Payment intent: \(outcome.paymentIntentId)
        Time: \(AppFormat.dateTime(outcome.happenedAt))
        Note: \(outcome.detail)
        """
    }
}

private struct TapToPayOutcomeView: View {
    let outcome: TapToPayOutcome

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: outcome.status.systemImage)
                .font(.title2)
                .foregroundStyle(outcome.status.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(outcome.status.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(outcome.status.tint)
                Text(outcome.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                Text("Amount \(AppFormat.money(outcome.amount))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.sm)
    }
}

final class TapToPayTerminalController: NSObject, ObservableObject {
    static let shared = TapToPayTerminalController()

    @Published private(set) var isBusy = false
    @Published private(set) var succeeded = false
    @Published private(set) var statusMessage = "Reader ready. Tap Charge, then have the customer hold their card to the phone."
    @Published private(set) var readerMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var outcome: TapToPayOutcome?
    @Published private(set) var readerName: String?
    @Published private(set) var connectionStatusText = "Not connected"
    @Published private(set) var paymentStatusText = "Not ready"
    @Published private(set) var paymentIntentStatusText: String?
    @Published private(set) var updateProgress: Double?
    @Published private var invoiceOutcomes: [String: TapToPayOutcome] = [:]

    private var currentInvoiceId: String?
    private var pendingInvoiceId: String?
    private var resetWhenIdle = false
    private var lastLocationId: String?
    private var paymentsAPI = PaymentsAPI()
    private var chargeTask: Task<Void, Never>?
    private var activePaymentCancelable: Cancelable?

    private override init() {
        super.init()
    }

    @MainActor
    func prepare(invoiceId: String) {
        guard currentInvoiceId != invoiceId else { return }
        if isBusy {
            pendingInvoiceId = invoiceId
            return
        }
        activate(invoiceId: invoiceId)
    }

    @MainActor
    func resetForSessionChange() {
        invoiceOutcomes.removeAll()
        pendingInvoiceId = nil
        lastLocationId = nil
        if isBusy {
            resetWhenIdle = true
            chargeTask?.cancel()
            cancelTerminalOperation()
        } else {
            clearActiveInvoice()
        }
    }

    @MainActor
    func outcome(for invoiceId: String) -> TapToPayOutcome? {
        invoiceOutcomes[invoiceId]
    }

    @MainActor
    func succeeded(for invoiceId: String) -> Bool {
        invoiceOutcomes[invoiceId]?.status == .approved
    }

    @MainActor
    func isCurrent(invoiceId: String) -> Bool {
        currentInvoiceId == invoiceId
    }

    @MainActor
    func isProcessing(invoiceId: String) -> Bool {
        currentInvoiceId == invoiceId && isBusy
    }

    @MainActor
    func statusMessage(for invoiceId: String) -> String {
        guard currentInvoiceId == invoiceId else {
            return isBusy
                ? "Another invoice is currently using Tap to Pay on this iPhone."
                : "Open this invoice again to prepare Tap to Pay."
        }
        return statusMessage
    }

    @MainActor
    func readerMessage(for invoiceId: String) -> String? {
        currentInvoiceId == invoiceId ? readerMessage : nil
    }

    @MainActor
    func errorMessage(for invoiceId: String) -> String? {
        currentInvoiceId == invoiceId ? errorMessage : nil
    }

    @MainActor
    private func activate(invoiceId: String) {
        currentInvoiceId = invoiceId
        invoiceOutcomes.removeValue(forKey: invoiceId)
        succeeded = false
        errorMessage = nil
        outcome = nil
        readerMessage = nil
        paymentIntentStatusText = nil
        updateProgress = nil
        statusMessage = "Checking this iPhone for Tap to Pay on iPhone..."
        Task { await warmUpForForeground() }
    }

    @MainActor
    private func clearActiveInvoice() {
        currentInvoiceId = nil
        succeeded = false
        errorMessage = nil
        outcome = nil
        readerMessage = nil
        paymentIntentStatusText = nil
        updateProgress = nil
        paymentStatusText = "Not ready"
        statusMessage = "Reader ready. Tap Charge, then have the customer hold their card to the phone."
    }

    @MainActor
    func warmUpForForeground() async {
        guard !isBusy else { return }

        ensureTerminalInitialized()

        if #unavailable(iOS 17.0) {
            errorMessage = tapToPayUnsupportedMessage("Tap to Pay on iPhone requires iOS 17 or later.")
            statusMessage = "Tap to Pay on iPhone is not available on this iPhone."
            paymentStatusText = "Unsupported"
            return
        }

        let support = Terminal.shared.supportsReaders(
            of: .tapToPay,
            discoveryMethod: .tapToPay,
            simulated: false
        )

        switch support {
        case .success:
            if errorMessage?.contains("Tap to Pay on iPhone is not available") == true {
                errorMessage = nil
            }
            paymentStatusText = currentInvoiceId == nil ? "Ready when checkout starts" : "Ready to charge"
            statusMessage = currentInvoiceId == nil
                ? "Tap to Pay on iPhone is available from unpaid invoice checkout."
                : "Reader ready. Tap Charge, then have the customer hold their card or device near the top of the iPhone."
        case .failure(let error):
            errorMessage = paymentErrorMessage(error)
            paymentStatusText = "Unsupported"
            statusMessage = "Tap to Pay on iPhone is not available on this iPhone."
        }
    }

    @MainActor
    func canCharge(invoiceId: String, intent: TerminalIntent) -> Bool {
        currentInvoiceId == invoiceId
            && !isBusy
            && !succeeded(for: invoiceId)
            && intent.clientSecret?.nilIfBlank != nil
            && intent.amount > 0
    }

    @MainActor
    func startCharge(invoiceId: String, intent: TerminalIntent) {
        guard chargeTask == nil, canCharge(invoiceId: invoiceId, intent: intent) else { return }
        chargeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.charge(invoiceId: invoiceId, intent: intent)
            self.chargeTask = nil
        }
    }

    @MainActor
    func cancelActiveCharge(invoiceId: String) {
        guard currentInvoiceId == invoiceId, isBusy else { return }
        statusMessage = "Canceling payment and checking its final status..."
        chargeTask?.cancel()
        cancelTerminalOperation()
    }

    @MainActor
    private func charge(invoiceId: String, intent serverIntent: TerminalIntent) async {
        guard canCharge(invoiceId: invoiceId, intent: serverIntent) else { return }

        isBusy = true
        succeeded = false
        errorMessage = nil
        outcome = nil
        invoiceOutcomes.removeValue(forKey: invoiceId)
        readerMessage = nil
        updateProgress = nil
        paymentIntentStatusText = nil
        currentInvoiceId = invoiceId
        var clientSecretForReconciliation: String?

        do {
            guard let clientSecret = serverIntent.clientSecret?.nilIfBlank else {
                throw APIError(status: 0, message: "Server did not return a payment to collect.")
            }
            clientSecretForReconciliation = clientSecret

            statusMessage = "Confirming cashier identity..."
            try await authorizeCashierIfAvailable()
            try Task.checkCancellation()

            statusMessage = "Creating the charge..."
            let locationId = try await terminalLocationId()
            try Task.checkCancellation()
            ensureTerminalInitialized()
            try validateTapToPaySupport()

            let reader = try await connectTapToPayReader(locationId: locationId)
            try Task.checkCancellation()
            readerName = readerDisplayName(reader)

            statusMessage = "Loading the payment..."
            var paymentIntent = try await retrievePaymentIntent(clientSecret: clientSecret)
            try Task.checkCancellation()
            paymentIntentStatusText = paymentIntentStatusLabel(paymentIntent.status)

            statusMessage = "Hold the customer's card or device near the top of the iPhone..."
            paymentIntent = try await collectPaymentMethod(paymentIntent)
            try Task.checkCancellation()
            paymentIntentStatusText = paymentIntentStatusLabel(paymentIntent.status)

            statusMessage = "Confirming payment..."
            let confirmedIntent = try await confirmPaymentIntent(paymentIntent)
            paymentIntentStatusText = paymentIntentStatusLabel(confirmedIntent.status)

            succeeded = confirmedIntent.status == .succeeded || confirmedIntent.status == .requiresCapture
            if succeeded {
                let detail = confirmedIntent.status == .requiresCapture
                    ? "Approved. The server is capturing this payment."
                    : "Approved. Payment captured."
                outcome = TapToPayOutcome(
                    status: .approved,
                    detail: detail,
                    amount: serverIntent.amount,
                    invoiceId: invoiceId,
                    paymentIntentId: serverIntent.paymentIntentId,
                    happenedAt: Date()
                )
                statusMessage = detail
            } else {
                let status = confirmedIntent.status == .canceled ? TapToPayOutcomeStatus.timedOut : .declined
                let detail = status == .timedOut
                    ? "Timed out before approval. Try again or use Card / manual payment."
                    : "Declined. Ask the customer for another card or use Card / manual payment."
                outcome = TapToPayOutcome(
                    status: status,
                    detail: detail,
                    amount: serverIntent.amount,
                    invoiceId: invoiceId,
                    paymentIntentId: serverIntent.paymentIntentId,
                    happenedAt: Date()
                )
                statusMessage = detail
            }
        } catch {
            activePaymentCancelable = nil

            if
                let clientSecretForReconciliation,
                let reconciledIntent = try? await retrievePaymentIntent(clientSecret: clientSecretForReconciliation),
                reconciledIntent.status == .succeeded || reconciledIntent.status == .requiresCapture
            {
                succeeded = true
                paymentIntentStatusText = paymentIntentStatusLabel(reconciledIntent.status)
                let detail = reconciledIntent.status == .requiresCapture
                    ? "Approved. The server is capturing this payment."
                    : "Approved. Payment captured."
                outcome = TapToPayOutcome(
                    status: .approved,
                    detail: detail,
                    amount: serverIntent.amount,
                    invoiceId: invoiceId,
                    paymentIntentId: serverIntent.paymentIntentId,
                    happenedAt: Date()
                )
                errorMessage = nil
                statusMessage = detail
            } else if Task.isCancelled {
                succeeded = false
                errorMessage = nil
                outcome = TapToPayOutcome(
                    status: .timedOut,
                    detail: "Canceled before approval. Reopen the invoice and verify its balance before using another payment method.",
                    amount: serverIntent.amount,
                    invoiceId: invoiceId,
                    paymentIntentId: serverIntent.paymentIntentId,
                    happenedAt: Date()
                )
                statusMessage = outcome?.detail ?? "Payment canceled."
            } else {
                let message = paymentErrorMessage(error)
                let status = outcomeStatus(for: message)
                errorMessage = message
                outcome = TapToPayOutcome(
                    status: status,
                    detail: outcomeDetail(for: status, message: message),
                    amount: serverIntent.amount,
                    invoiceId: invoiceId,
                    paymentIntentId: serverIntent.paymentIntentId,
                    happenedAt: Date()
                )
                statusMessage = outcome?.detail ?? "Payment could not be completed."
            }
        }

        activePaymentCancelable = nil
        isBusy = false
        if let outcome, outcome.invoiceId == invoiceId {
            invoiceOutcomes[invoiceId] = outcome
        }

        if resetWhenIdle {
            resetWhenIdle = false
            invoiceOutcomes.removeAll()
            lastLocationId = nil
            let nextInvoiceId = pendingInvoiceId
            pendingInvoiceId = nil
            clearActiveInvoice()
            if let nextInvoiceId {
                activate(invoiceId: nextInvoiceId)
            }
        } else if let pendingInvoiceId {
            self.pendingInvoiceId = nil
            activate(invoiceId: pendingInvoiceId)
        }
    }

    @MainActor
    private func collectPaymentMethod(_ paymentIntent: PaymentIntent) async throws -> PaymentIntent {
        defer { activePaymentCancelable = nil }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activePaymentCancelable = Terminal.shared.collectPaymentMethod(paymentIntent) { intent, error in
                    if let intent {
                        continuation.resume(returning: intent)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: APIError(status: 0, message: "Card collection ended without a result."))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelTerminalOperation()
            }
        }
    }

    @MainActor
    private func confirmPaymentIntent(_ paymentIntent: PaymentIntent) async throws -> PaymentIntent {
        defer { activePaymentCancelable = nil }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activePaymentCancelable = Terminal.shared.confirmPaymentIntent(paymentIntent) { intent, error in
                    if let intent {
                        continuation.resume(returning: intent)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: APIError(status: 0, message: "Payment confirmation ended without a result."))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelTerminalOperation()
            }
        }
    }

    @MainActor
    private func cancelTerminalOperation() {
        guard let activePaymentCancelable, !activePaymentCancelable.completed else { return }
        activePaymentCancelable.cancel { _ in }
    }

    private func ensureTerminalInitialized() {
        if Terminal.isInitialized() {
            Terminal.shared.delegate = self
        } else {
            Terminal.initWithTokenProvider(self, delegate: self)
        }
    }

    private func terminalLocationId() async throws -> String {
        if let locationId = lastLocationId?.nilIfBlank {
            return locationId
        }

        let token = try await paymentsAPI.connectionToken()
        await MainActor.run {
            lastLocationId = token.locationId
        }

        guard let locationId = token.locationId?.nilIfBlank else {
            throw APIError(status: 0, message: "No Stripe Terminal location is configured on the server.")
        }

        return locationId
    }

    private func validateTapToPaySupport() throws {
        let support = Terminal.shared.supportsReaders(
            of: .tapToPay,
            discoveryMethod: .tapToPay,
            simulated: false
        )

        if case .failure(let error) = support {
            throw error
        }
    }

    private func authorizeCashierIfAvailable() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Confirm it is you before taking a Tap to Pay on iPhone payment."
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? APIError(status: 0, message: "Cashier identity was not confirmed."))
                }
            }
        }
    }

    private func connectTapToPayReader(locationId: String) async throws -> Reader {
        if let connectedReader = Terminal.shared.connectedReader {
            if connectedReader.deviceType == .tapToPay, connectedReader.locationId == locationId {
                return connectedReader
            }

            try await disconnectReader()
        }

        await MainActor.run {
            statusMessage = "Looking for the Tap to Pay on iPhone reader..."
        }

        let discoveryConfig = try TapToPayDiscoveryConfigurationBuilder()
            .setSimulated(false)
            .build()

        let reader = try await discoverReader(configuration: discoveryConfig)

        await MainActor.run {
            statusMessage = "Connecting to the reader..."
        }

        let connectionConfig = try TapToPayConnectionConfigurationBuilder(
            delegate: self,
            locationId: locationId
        )
        .setMerchantDisplayName("Tire Force US")
        .setAutoReconnectOnUnexpectedDisconnect(true)
        .build()

        return try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.connectReader(reader, connectionConfig: connectionConfig) { connectedReader, error in
                if let connectedReader {
                    continuation.resume(returning: connectedReader)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: APIError(status: 0, message: "Tap to Pay on iPhone reader did not connect."))
                }
            }
        }
    }

    private func discoverReader(configuration: TapToPayDiscoveryConfiguration) async throws -> Reader {
        let stream = Terminal.shared.discoverReaders(configuration)
        for try await readers in stream {
            if let reader = readers.first {
                return reader
            }
        }

        throw APIError(status: 0, message: "Tap to Pay on iPhone reader was not found on this device.")
    }

    private func retrievePaymentIntent(clientSecret: String) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PaymentIntent, Error>) in
            Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { paymentIntent, error in
                if let paymentIntent {
                    continuation.resume(returning: paymentIntent)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: APIError(status: 0, message: "Server did not return a payment to collect."))
                }
            }
        }
    }

    private func disconnectReader() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Terminal.shared.disconnectReader { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func readerDisplayName(_ reader: Reader) -> String {
        if let label = reader.label?.nilIfBlank {
            return label
        }
        if let stripeId = reader.stripeId?.nilIfBlank {
            return stripeId
        }
        return reader.serialNumber
    }

    private func paymentIntentStatusLabel(_ status: PaymentIntentStatus) -> String {
        switch status {
        case .requiresPaymentMethod:
            return "Needs payment method"
        case .requiresConfirmation:
            return "Needs confirmation"
        case .requiresAction:
            return "Needs action"
        case .requiresCapture:
            return "Needs capture"
        case .processing:
            return "Processing"
        case .canceled:
            return "Canceled"
        case .succeeded:
            return "Succeeded"
        case .requiresReauthorization:
            return "Needs reauthorization"
        @unknown default:
            return "Unknown"
        }
    }

    private func paymentErrorMessage(_ error: Error) -> String {
        let fallback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowercased = fallback.lowercased()

        if error is LAError || fallback.contains("Cashier identity") {
            return "Cashier identity was not confirmed. Try again, or use Card / manual payment if the customer needs another checkout option."
        }

        if lowercased.contains("not support")
            || lowercased.contains("unsupported")
            || lowercased.contains("not available")
            || lowercased.contains("eligible")
            || lowercased.contains("entitlement")
            || lowercased.contains("proximity reader") {
            return tapToPayUnsupportedMessage(fallback)
        }

        guard fallback != "The operation couldn't be completed." else {
            return "Something went wrong while taking the payment."
        }
        return fallback
    }

    private func outcomeStatus(for message: String) -> TapToPayOutcomeStatus {
        let lowercased = message.lowercased()
        if lowercased.contains("declined") || lowercased.contains("decline") {
            return .declined
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") || lowercased.contains("time out") {
            return .timedOut
        }
        return .failed
    }

    private func outcomeDetail(for status: TapToPayOutcomeStatus, message: String) -> String {
        switch status {
        case .approved:
            return "Approved. Payment captured."
        case .declined:
            return "Declined. Ask the customer for another card or use Card / manual payment. Details: \(message)"
        case .timedOut:
            return "Timed out before approval. Try again or use Card / manual payment. Details: \(message)"
        case .failed:
            return "Not completed. Try again or use Card / manual payment. Details: \(message)"
        }
    }

    private func tapToPayUnsupportedMessage(_ detail: String) -> String {
        if #unavailable(iOS 17.0) {
            return "Tap to Pay on iPhone requires iOS 17 or later. Update iOS or use Card / manual payment for this invoice."
        }

        return "Tap to Pay on iPhone is not available on this device or account. Use an eligible iPhone with Tap to Pay on iPhone enabled for this app and Stripe account, or use Card / manual payment for this invoice. Details: \(detail)"
    }

    private func updateOnMain(_ apply: @escaping () -> Void) {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

extension TapToPayTerminalController: ConnectionTokenProvider {
    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        Task {
            do {
                let token = try await paymentsAPI.connectionToken()
                updateOnMain {
                    self.lastLocationId = token.locationId
                }
                completion(token.secret, nil)
            } catch {
                completion(nil, error as NSError)
            }
        }
    }
}

extension TapToPayTerminalController: TerminalDelegate {
    func terminal(_ terminal: Terminal, didChangeConnectionStatus status: ConnectionStatus) {
        updateOnMain {
            self.connectionStatusText = Terminal.stringFromConnectionStatus(status)
        }
    }

    func terminal(_ terminal: Terminal, didChangePaymentStatus status: PaymentStatus) {
        updateOnMain {
            self.paymentStatusText = Terminal.stringFromPaymentStatus(status)
        }
    }
}

extension TapToPayTerminalController: TapToPayReaderDelegate {
    func tapToPayReader(
        _ reader: Reader,
        didStartInstallingUpdate update: ReaderSoftwareUpdate,
        cancelable: Cancelable?
    ) {
        updateOnMain {
            self.statusMessage = "Initializing reader..."
            self.updateProgress = 0
        }
    }

    func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        updateOnMain {
            self.updateProgress = Double(progress)
        }
    }

    func tapToPayReader(
        _ reader: Reader,
        didFinishInstallingUpdate update: ReaderSoftwareUpdate?,
        error: Error?
    ) {
        updateOnMain {
            self.updateProgress = nil
            if let error {
                self.errorMessage = self.paymentErrorMessage(error)
            } else {
                self.statusMessage = "Reader ready."
            }
        }
    }

    func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        updateOnMain {
            self.readerMessage = Terminal.stringFromReaderInputOptions(inputOptions)
        }
    }

    func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
        updateOnMain {
            self.readerMessage = Terminal.stringFromReaderDisplayMessage(displayMessage)
        }
    }

    func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {
        updateOnMain {
            self.readerName = nil
            self.connectionStatusText = "Not connected"
            self.readerMessage = nil
            if !self.succeeded {
                self.statusMessage = "Reader disconnected."
            }
        }
    }

    func reader(_ reader: Reader, didStartReconnect cancelable: Cancelable, disconnectReason: DisconnectReason) {
        updateOnMain {
            self.statusMessage = "Reader disconnected. Reconnecting..."
        }
    }

    func readerDidSucceedReconnect(_ reader: Reader) {
        updateOnMain {
            self.readerName = self.readerDisplayName(reader)
            self.statusMessage = "Reader reconnected."
        }
    }

    func readerDidFailReconnect(_ reader: Reader) {
        updateOnMain {
            self.readerName = nil
            self.statusMessage = "Reader could not reconnect."
        }
    }
}

struct StartReturnNativeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let saleId: String
    let saleRef: String?

    @State private var reason = ""
    @State private var notes = ""
    @State private var type = "RETURN"
    @State private var refundMethod = "STORE_CREDIT"
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var selectedQuantities: [String: Int] = [:]

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
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Toggle(isOn: includedBinding(lineId: line.saleLineId, maximum: line.qtyRemaining)) {
                                RowLine(
                                    title: line.description,
                                    subtitle: "\(line.qtyRemaining) remaining",
                                    trailing: AppFormat.money(line.unitPrice)
                                )
                            }

                            if selectedQuantity(for: line.saleLineId) > 0 {
                                Stepper(
                                    "Quantity: \(selectedQuantity(for: line.saleLineId))",
                                    value: quantityBinding(lineId: line.saleLineId, maximum: line.qtyRemaining),
                                    in: 1...max(1, line.qtyRemaining)
                                )
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
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
                    .disabled(
                        !auth.has("sales.manage")
                            || returnable.lines.isEmpty
                            || selectedQuantities.values.allSatisfy { $0 <= 0 }
                            || saving
                    )
                }
            }
        }
        .navigationTitle("Return / Exchange")
    }

    @MainActor
    private func create(returnable: Returnable) async {
        guard auth.has("sales.manage") else {
            errorMessage = "You do not have permission to create returns."
            return
        }
        saving = true
        errorMessage = nil

        do {
            let lines = returnable.lines.compactMap { line -> ReturnLineInput? in
                let quantity = min(line.qtyRemaining, max(0, selectedQuantities[line.saleLineId] ?? 0))
                guard quantity > 0 else { return nil }
                return ReturnLineInput(
                    saleLineId: line.saleLineId,
                    qty: quantity,
                    inventoryDisposition: "RESTOCK"
                )
            }
            guard !lines.isEmpty else {
                throw APIError(status: 0, message: "Select at least one item to return.")
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

    private func selectedQuantity(for lineId: String) -> Int {
        selectedQuantities[lineId] ?? 0
    }

    private func includedBinding(lineId: String, maximum: Int) -> Binding<Bool> {
        Binding(
            get: { selectedQuantity(for: lineId) > 0 },
            set: { included in
                selectedQuantities[lineId] = included ? min(maximum, max(1, selectedQuantity(for: lineId))) : 0
            }
        )
    }

    private func quantityBinding(lineId: String, maximum: Int) -> Binding<Int> {
        Binding(
            get: { min(maximum, max(1, selectedQuantity(for: lineId))) },
            set: { selectedQuantities[lineId] = min(maximum, max(1, $0)) }
        )
    }
}
