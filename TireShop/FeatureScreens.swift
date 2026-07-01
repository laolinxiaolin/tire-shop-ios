import SwiftUI

struct DashboardNativeView: View {
    var body: some View {
        AsyncContentView(load: DashboardAPI().summary) { summary in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    StatGrid(stats: [
                        ("Today's sales", AppFormat.money(summary.today.revenue)),
                        ("Month to date", AppFormat.money(summary.month.revenue)),
                        ("Open A/R", AppFormat.money(summary.openAR.total)),
                        ("Low stock", "\(summary.lowStockCount)")
                    ])

                    SectionHeader("Low stock")
                    VStack(spacing: 0) {
                        ForEach(summary.lowStock) { item in
                            RowLine(
                                title: "\(item.brand) \(item.model)",
                                subtitle: "\(item.size) - \(item.sku)",
                                trailing: "\(item.onHand) on hand"
                            )
                        }
                    }

                    SectionHeader("Top sellers this month")
                    VStack(spacing: 0) {
                        ForEach(summary.topSkus) { item in
                            RowLine(
                                title: "\(item.brand) \(item.model)",
                                subtitle: "\(item.size) - \(item.sku)",
                                trailing: "\(item.qty) sold"
                            )
                        }
                    }
                }
                .padding(Theme.Space.lg)
            }
            .background(Theme.background)
        }
    }
}

private struct InventorySortOption: Identifiable {
    let id: String
    let label: String
}

private enum InventoryLabels {
    static let categoryOptions: [(String, String)] = [
        ("", "All categories"),
        ("SEMI", "Semi"),
        ("LT", "Light truck")
    ]

    static let positionOptions: [(String, String)] = [
        ("", "All positions"),
        ("STEER", "Steer"),
        ("DRIVE", "Drive"),
        ("TRAILER", "Trailer"),
        ("ALL_POSITION", "All position")
    ]

    static let sortOptions: [InventorySortOption] = [
        InventorySortOption(id: "", label: "Default"),
        InventorySortOption(id: "sku", label: "SKU"),
        InventorySortOption(id: "brand", label: "Brand"),
        InventorySortOption(id: "model", label: "Model"),
        InventorySortOption(id: "size", label: "Size"),
        InventorySortOption(id: "category", label: "Category"),
        InventorySortOption(id: "position", label: "Position"),
        InventorySortOption(id: "priceRetail", label: "Retail price"),
        InventorySortOption(id: "priceCost", label: "Cost"),
        InventorySortOption(id: "reorderPoint", label: "Reorder point"),
        InventorySortOption(id: "createdAt", label: "Created")
    ]

    static func category(_ value: String) -> String {
        categoryOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func position(_ value: String) -> String {
        positionOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func sort(_ value: String) -> String {
        sortOptions.first { $0.id == value }?.label ?? "Default"
    }
}

struct InventoryListNativeView: View {
    var selectForQuote = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quote: QuoteStore

    private let pageSize = 25

    @State private var q = ""
    @State private var category = ""
    @State private var position = ""
    @State private var sortBy = ""
    @State private var sortOrder = "asc"
    @State private var hideZeroStock = false
    @State private var items: [TireSku] = []
    @State private var total = 0
    @State private var loadedPage = 0
    @State private var hasLoaded = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var loadMoreError: String?
    @State private var searchTask: Task<Void, Never>?

    private var visibleItems: [TireSku] {
        return hideZeroStock ? items.filter { Self.onHand($0) > 0 } : items
    }

    private var hasMorePages: Bool {
        hasLoaded && items.count < total
    }

    private var hasActiveFilters: Bool {
        !category.isEmpty || !position.isEmpty || !sortBy.isEmpty
    }

    private var activeFilterCount: Int {
        [category, position, sortBy].filter { !$0.isEmpty }.count
    }

    private var activeSummary: String? {
        var parts: [String] = []
        if !category.isEmpty { parts.append(InventoryLabels.category(category)) }
        if !position.isEmpty { parts.append(InventoryLabels.position(position)) }
        if !sortBy.isEmpty { parts.append("\(InventoryLabels.sort(sortBy)) \(sortOrder.uppercased())") }
        if hideZeroStock { parts.append("In stock only") }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            Group {
                if loading && !hasLoaded {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, !hasLoaded {
                    RetryView(message: errorMessage) { Task { await reload() } }
                } else if hasLoaded && visibleItems.isEmpty && !hasMorePages {
                    EmptyStateView(text: emptyMessage)
                } else if hasLoaded {
                    inventoryList
                } else {
                    LoadingView(label: "Loading...")
                }
            }
        }
        .background(Theme.background)
        .task {
            if !hasLoaded { await reload() }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var inventoryList: some View {
        List {
            ForEach(visibleItems) { sku in
                skuRow(sku)
                    .onAppear {
                        if sku.id == visibleItems.last?.id {
                            Task { await loadMoreIfNeeded() }
                        }
                    }
            }

            loadMoreRow
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func skuRow(_ sku: TireSku) -> some View {
        if selectForQuote {
            Button {
                addToQuote(sku)
            } label: {
                InventorySkuRow(sku: sku)
            }
            .tint(Theme.text)
        } else {
            NavigationLink {
                SkuDetailNativeView(sku: sku)
            } label: {
                InventorySkuRow(sku: sku)
            }
        }
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        if loadingMore {
            HStack(spacing: Theme.Space.sm) {
                Spacer()
                ProgressView()
                Text("Loading more...")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.vertical, Theme.Space.md)
        } else if let loadMoreError {
            Button {
                Task { await loadMoreIfNeeded() }
            } label: {
                VStack(spacing: 2) {
                    Text("Retry loading more")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(loadMoreError)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.sm)
            }
        } else if hasMorePages {
            HStack(spacing: Theme.Space.sm) {
                Spacer()
                ProgressView()
                Text("Loading more...")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.vertical, Theme.Space.md)
            .onAppear {
                Task { await loadMoreIfNeeded() }
            }
        } else if hasLoaded && !items.isEmpty {
            Text("\(visibleItems.count) shown")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                compactSearchField
                hideZeroButton
                filterMenu
            }

            if let activeSummary {
                HStack(spacing: Theme.Space.sm) {
                    Text(activeSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: Theme.Space.sm)

                    Button("Reset") {
                        resetFilters(includeSearch: false)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
                }
                .frame(height: 22)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private var compactSearchField: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField("Search size, brand, SKU...", text: $q)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    searchTask?.cancel()
                    Task { await reload() }
                }
                .onChange(of: q) { _, _ in
                    scheduleSearch()
                }

            if !q.isEmpty {
                Button {
                    q = ""
                    searchTask?.cancel()
                    Task { await reload() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(height: 42)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.border)
        )
    }

    private var hideZeroButton: some View {
        Button {
            hideZeroStock.toggle()
        } label: {
            Label("Hide 0", systemImage: hideZeroStock ? "eye.slash.fill" : "eye.slash")
                .font(.caption)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
                .frame(width: 78, height: 42)
                .background(hideZeroStock ? Theme.primary : Theme.card)
                .foregroundStyle(hideZeroStock ? Theme.primaryText : Theme.text)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(hideZeroStock ? Theme.primary : Theme.border)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide zero stock items")
        .accessibilityValue(hideZeroStock ? "On" : "Off")
    }

    private var filterMenu: some View {
        Menu {
            Section("Category") {
                ForEach(InventoryLabels.categoryOptions, id: \.0) { option in
                    Button {
                        updateFilter($category, option.0)
                    } label: {
                        menuLabel(option.1, selected: category == option.0)
                    }
                }
            }

            Section("Position") {
                ForEach(InventoryLabels.positionOptions, id: \.0) { option in
                    Button {
                        updateFilter($position, option.0)
                    } label: {
                        menuLabel(option.1, selected: position == option.0)
                    }
                }
            }

            Section("Sort") {
                ForEach(InventoryLabels.sortOptions) { option in
                    Button {
                        updateSort(option.id)
                    } label: {
                        menuLabel(option.label, selected: sortBy == option.id)
                    }
                }
            }

            Section("Direction") {
                Button {
                    updateSortOrder("asc")
                } label: {
                    menuLabel("Ascending", selected: sortOrder == "asc")
                }
                .disabled(sortBy.isEmpty)

                Button {
                    updateSortOrder("desc")
                } label: {
                    menuLabel("Descending", selected: sortOrder == "desc")
                }
                .disabled(sortBy.isEmpty)
            }

            Button("Reset filters") {
                resetFilters(includeSearch: false)
            }
            .disabled(!hasActiveFilters && !hideZeroStock)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(Theme.card)
                    .foregroundStyle(activeFilterCount > 0 ? Theme.primary : Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.border)
                    )

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(Theme.primary)
                        .foregroundStyle(Theme.primaryText)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel("Inventory filters")
    }

    private func menuLabel(_ title: String, selected: Bool) -> some View {
        Group {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var emptyMessage: String {
        if hideZeroStock, !items.isEmpty {
            return "No in-stock items found."
        }
        return "No inventory found."
    }

    private func updateFilter(_ selected: Binding<String>, _ value: String) {
        guard selected.wrappedValue != value else { return }
        selected.wrappedValue = value
        Task { await reload() }
    }

    private func updateSort(_ value: String) {
        guard sortBy != value else { return }
        sortBy = value
        if value.isEmpty {
            sortOrder = "asc"
        }
        Task { await reload() }
    }

    private func updateSortOrder(_ value: String) {
        guard sortOrder != value else { return }
        sortOrder = value
        Task { await reload() }
    }

    private func resetFilters(includeSearch: Bool) {
        if includeSearch {
            q = ""
        }
        category = ""
        position = ""
        sortBy = ""
        sortOrder = "asc"
        hideZeroStock = false
        Task { await reload() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func addToQuote(_ sku: TireSku) {
        quote.addLine(
            itemType: "SKU",
            itemId: sku.id,
            description: "\(sku.brand) \(sku.model) \(sku.size) (\(sku.position.replacingOccurrences(of: "_", with: "-")))",
            unitPrice: Double(sku.priceRetail) ?? 0
        )
        dismiss()
    }

    private static func onHand(_ sku: TireSku) -> Int {
        sku.inventory.reduce(0) { $0 + $1.qtyOnHand }
    }

    @MainActor
    private func reload() async {
        await loadPage(1, reset: true)
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard hasMorePages, !loading, !loadingMore else { return }
        await loadPage(loadedPage + 1, reset: false)
    }

    @MainActor
    private func loadPage(_ page: Int, reset: Bool) async {
        if reset {
            loading = true
            items = []
            total = 0
            loadedPage = 0
            hasLoaded = false
            errorMessage = nil
            loadMoreError = nil
        } else {
            loadingMore = true
            loadMoreError = nil
        }

        do {
            let pageData = try await InventoryAPI().listSkus(
                q: q.nilIfBlank,
                category: category.nilIfBlank,
                position: position.nilIfBlank,
                sortBy: sortBy.nilIfBlank,
                sortOrder: sortBy.isEmpty ? nil : sortOrder,
                page: page,
                pageSize: pageSize
            )

            total = pageData.total
            loadedPage = pageData.page
            hasLoaded = true

            if reset {
                items = pageData.items
            } else {
                let existingIds = Set(items.map(\.id))
                items.append(contentsOf: pageData.items.filter { !existingIds.contains($0.id) })
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not load inventory."
            if reset {
                errorMessage = message
                hasLoaded = false
            } else {
                loadMoreError = message
            }
        }

        if reset {
            loading = false
        } else {
            loadingMore = false
        }
    }

}

private struct InventorySkuRow: View {
    let sku: TireSku

    private var onHand: Int {
        sku.inventory.reduce(0) { $0 + $1.qtyOnHand }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sku.brand) \(sku.model)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                Text(AppFormat.money(sku.priceRetail))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
            }

            Text("\(sku.size) - \(sku.sku)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            HStack {
                Text("\(InventoryLabels.category(sku.category)) / \(InventoryLabels.position(sku.position))")
                Spacer()
                Text("\(onHand) on hand")
            }
            .font(.caption)
            .foregroundStyle(onHand <= sku.reorderPoint ? Theme.danger : Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

struct SkuManagementNativeView: View {
    var body: some View {
        InventoryListNativeView()
    }
}

struct SalesListNativeView: View {
    private let pageSize = 50

    @State private var q = ""
    @State private var data: Paged<SaleListItem>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            salesHeader

            Group {
                if loading && data == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: "No sales found.")
                } else if let data {
                    List(data.items) { sale in
                        NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                            RowLine(
                                title: "\(sale.ref ?? "Sale") - \(sale.customer.name)",
                                subtitle: "\(sale.status) - \(AppFormat.dateTime(sale.createdAt))",
                                trailing: AppFormat.money(sale.total)
                            )
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
        }
        .background(Theme.background)
        .task {
            if data == nil { await load() }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var salesHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Sales")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Theme.text)

            searchBar
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField("Search customer or sale #...", text: $q)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    searchTask?.cancel()
                    Task { await load() }
                }
                .onChange(of: q) { _, _ in
                    scheduleSearch()
                }

            if !q.isEmpty {
                Button {
                    q = ""
                    searchTask?.cancel()
                    Task { await load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(height: 42)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.border)
        )
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await SalesAPI().list(q: q.nilIfBlank, pageSize: pageSize)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load sales."
        }
        loading = false
    }
}

struct CustomersListNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await CustomersAPI().list(pageSize: 50) }) { page in
            List(page.items) { customer in
                NavigationLink(value: AppRoute.customerDetail(id: customer.id, name: customer.name)) {
                    RowLine(
                        title: customer.company ?? customer.name,
                        subtitle: [customer.company == nil ? nil : customer.name, AppFormat.phone(customer.phone), customer.email]
                            .compactMap { text in
                                guard let text, !text.isEmpty else { return nil }
                                return text
                            }
                            .joined(separator: " - "),
                        trailing: customer.taxExempt ? "Tax exempt" : nil
                    )
                }
            }
            .listStyle(.plain)
        }
    }
}

enum WorkOrderLabels {
    static let statuses: [(WorkOrderStatus, String)] = [
        ("OPEN", "Open"),
        ("IN_PROGRESS", "In Progress"),
        ("DONE", "Done"),
        ("CANCELLED", "Cancelled")
    ]

    static let filterOptions: [TireFilterOption] = [
        TireFilterOption(value: "", labelKey: "status.ALL"),
        TireFilterOption(value: "OPEN", labelKey: "workOrder.status.OPEN"),
        TireFilterOption(value: "IN_PROGRESS", labelKey: "workOrder.status.IN_PROGRESS"),
        TireFilterOption(value: "DONE", labelKey: "workOrder.status.DONE"),
        TireFilterOption(value: "CANCELLED", labelKey: "workOrder.status.CANCELLED")
    ]

    static func title(_ status: WorkOrderStatus) -> String {
        statuses.first { $0.0 == status }?.1 ?? status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct WorkOrdersListNativeView: View {
    @State private var status = ""
    @State private var items: [WorkOrder] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            FilterChips(value: $status, options: WorkOrderLabels.filterOptions)

            Group {
                if loading && items.isEmpty {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, items.isEmpty {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if items.isEmpty {
                    EmptyStateView(text: "No work orders found.")
                } else {
                    List(items) { order in
                        NavigationLink(value: AppRoute.workOrderDetail(order.id)) {
                            RowLine(
                                title: "\(order.sale.customer.name) - \(order.sale.ref ?? "Sale")",
                                subtitle: "\(WorkOrderLabels.title(order.status)) - \(order.tasks.filter(\.done).count)/\(order.tasks.count) tasks",
                                trailing: order.bay
                            )
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .task(id: status) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            items = try await WorkOrdersAPI().list(status: status.nilIfBlank)
        } catch {
            items = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load work orders."
        }
        loading = false
    }
}

struct ReturnsListNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await ReturnsAPI().list(pageSize: 50) }) { page in
            List(page.items) { record in
                RowLine(
                    title: "\(record.ref ?? "Return") - \(record.type)",
                    subtitle: "\(record.status) - \(record.sale?.customer?.name ?? "Unknown customer")",
                    trailing: AppFormat.money(record.refundTotal)
                )
            }
            .listStyle(.plain)
        }
    }
}

struct InventoryCountsListNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await InventoryCountsAPI().list(pageSize: 50) }) { page in
            List(page.items) { count in
                NavigationLink(value: AppRoute.inventoryCountDetail(count.id)) {
                    RowLine(
                        title: count.ref ?? "Inventory count",
                        subtitle: "\(count.status) - \(count.location)",
                        trailing: "\(count.count.lines) lines"
                    )
                }
            }
            .listStyle(.plain)
        }
    }
}

struct PurchasingNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await ContainersAPI().list(pageSize: 50) }) { page in
            List(page.items) { container in
                NavigationLink(value: AppRoute.containerDetail(container.id)) {
                    RowLine(
                        title: container.ref ?? container.reference ?? "Container",
                        subtitle: "\(container.supplier.name) - \(container.status)",
                        trailing: "\(container.lines.count) lines"
                    )
                }
            }
            .listStyle(.plain)
        }
    }
}

struct MoneyNativeView: View {
    var body: some View {
        AsyncContentView(load: loadMoney) { receivables, payables in
            List {
                Section("Receivables") {
                    ForEach(receivables.items, id: \.customer.id) { item in
                        RowLine(
                            title: item.customer.name,
                            subtitle: "\(item.openCount) open - \(item.ageDays) days",
                            trailing: AppFormat.money(item.openBalance)
                        )
                    }
                }

                Section("Payables") {
                    ForEach(payables.items, id: \.vendorKey) { item in
                        RowLine(
                            title: item.vendor ?? item.vendorKey,
                            subtitle: "\(item.count) due - \(item.ageDays) days",
                            trailing: AppFormat.money(item.totalDue)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadMoney() async throws -> (Paged<ReceivableCustomer>, Paged<PayableVendor>) {
        async let receivables = MoneyAPI().receivables(pageSize: 25)
        async let payables = MoneyAPI().payables(pageSize: 25)
        return try await (receivables, payables)
    }
}

struct AccountingNativeView: View {
    var body: some View {
        AsyncContentView(load: AccountingAPI().accounts) { accounts in
            List(accounts) { account in
                RowLine(
                    title: "\(account.code) - \(account.name)",
                    subtitle: account.type,
                    trailing: AppFormat.money(account.balance)
                )
            }
            .listStyle(.plain)
        }
    }
}

struct CashAccountsNativeView: View {
    var body: some View {
        AsyncContentView(load: loadCash) { accounts, methods in
            List {
                Section("Cash accounts") {
                    ForEach(accounts) { account in
                        RowLine(title: account.name, subtitle: account.code, trailing: AppFormat.money(account.balance))
                    }
                }

                Section("Payment methods") {
                    ForEach(methods) { method in
                        RowLine(title: method.name, subtitle: method.processor ?? method.account.name, trailing: method.isActive ? "Active" : "Inactive")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadCash() async throws -> ([CashAccount], [PaymentMethod]) {
        async let accounts = CashAccountsAPI().list()
        async let methods = CashAccountsAPI().methods()
        return try await (accounts, methods)
    }
}

struct FetNativeView: View {
    var body: some View {
        AsyncContentView(load: FetAPI().status) { status in
            List {
                Section {
                    RowLine(title: "Payable", subtitle: "Federal Excise Tax", trailing: AppFormat.money(status.payable))
                }

                Section("Quarters") {
                    ForEach(status.quarters, id: \.key) { quarter in
                        RowLine(
                            title: quarter.label,
                            subtitle: "\(quarter.periodStart) to \(quarter.periodEnd)",
                            trailing: AppFormat.money(quarter.fetDue)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

struct EodNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await EodAPI().report(date: Self.today) }) { report in
            List {
                Section(report.date) {
                    RowLine(title: "Sales", subtitle: "\(report.sales.summary.count) sales", trailing: AppFormat.money(report.sales.summary.total))
                    RowLine(title: "Payments", subtitle: "\(report.payments.summary.count) payments", trailing: AppFormat.money(report.payments.summary.total))
                    RowLine(title: "Expenses", subtitle: "Recorded expenses", trailing: AppFormat.money(report.expenses.total))
                    RowLine(title: "Net income", subtitle: "P&L", trailing: AppFormat.money(report.pnl.netIncome))
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct ActivityNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await ActivityAPI().list(pageSize: 50) }) { page in
            List(page.items) { log in
                RowLine(
                    title: "\(log.action) \(log.entity)",
                    subtitle: "\(log.user?.fullName ?? "System") - \(AppFormat.dateTime(log.createdAt))",
                    trailing: log.entityId
                )
            }
            .listStyle(.plain)
        }
    }
}

// Approvals, Users, Roles, and API Keys now have full action flows in AdminScreens.swift.
