import SwiftUI

struct DashboardNativeView: View {
    @EnvironmentObject private var i18n: I18nStore

    var body: some View {
        AsyncContentView(load: DashboardAPI().summary) { summary in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    StatGrid(stats: [
                        (i18n.t("dashboard.todaySales"), AppFormat.money(summary.today.revenue)),
                        (i18n.t("dashboard.mtd"), AppFormat.money(summary.month.revenue)),
                        (i18n.t("dashboard.openAR"), AppFormat.money(summary.openAR.total)),
                        (i18n.t("dashboard.lowStock"), "\(summary.lowStockCount)")
                    ])

                    lowStockSection(summary.lowStock)
                    topSellerSection(summary.topSkus)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background)
        }
    }

    private func lowStockSection(_ items: [DashboardSummary.LowStockSku]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(i18n.t("dashboard.lowStockTitle"))

            if items.isEmpty {
                DashboardEmptyRow(text: i18n.t("dashboard.aboveReorder"))
            } else {
                dashboardCard {
                    ForEach(items) { item in
                        RowLine(
                            title: "\(item.brand) \(item.model)",
                            subtitle: "\(item.size) - \(item.sku)",
                            trailing: "\(item.onHand) \(i18n.t("inventory.onHand"))"
                        )
                    }
                }
            }
        }
    }

    private func topSellerSection(_ items: [DashboardSummary.TopSku]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(i18n.t("dashboard.topSellers"))

            if items.isEmpty {
                DashboardEmptyRow(text: i18n.t("dashboard.noSalesMonth"))
            } else {
                dashboardCard {
                    ForEach(items) { item in
                        RowLine(
                            title: "\(item.brand) \(item.model)",
                            subtitle: "\(item.size) - \(item.sku)",
                            trailing: i18n.t("dashboard.sold", ["n": item.qty])
                        )
                    }
                }
            }
        }
    }

    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.border)
        )
    }
}

private struct DashboardEmptyRow: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border)
            )
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

    private let pageSize = 1000

    @State private var q = ""
    @State private var category = ""
    @State private var position = ""
    @State private var brand = ""
    @State private var brands: [String] = []
    @State private var sortBy = ""
    @State private var sortOrder = "asc"
    // Out-of-stock rows are hidden by default; this opts back into them.
    @State private var showZeroStock = false
    @State private var warehouses: [Warehouse] = []
    @State private var location = ""
    @State private var didChooseInitialLocation = false
    @State private var loadingWarehouses = false
    @State private var warehouseError: String?
    @State private var items: [TireSku] = []
    @State private var total = 0
    @State private var loadedPage = 0
    @State private var hasLoaded = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var loadMoreError: String?
    @State private var searchTask: Task<Void, Never>?

    private var selectedLocation: String {
        selectForQuote ? quote.location : location
    }

    private var hasMorePages: Bool {
        hasLoaded && items.count < total
    }

    private var hasActiveFilters: Bool {
        !category.isEmpty || !position.isEmpty || !brand.isEmpty || !sortBy.isEmpty
    }

    private var activeFilterCount: Int {
        [category, position, brand, sortBy].filter { !$0.isEmpty }.count
    }

    private var activeSummary: String? {
        var parts: [String] = []
        if !category.isEmpty { parts.append(InventoryLabels.category(category)) }
        if !position.isEmpty { parts.append(InventoryLabels.position(position)) }
        if !brand.isEmpty { parts.append(brand) }
        if !sortBy.isEmpty { parts.append("\(InventoryLabels.sort(sortBy)) \(sortOrder.uppercased())") }
        if showZeroStock { parts.append("Including 0 stock") }
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
                } else if hasLoaded && items.isEmpty && !hasMorePages {
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
            if warehouses.isEmpty { await loadWarehouses() }
            if brands.isEmpty { await loadBrands() }
            if !hasLoaded { await reload() }
        }
        .onChange(of: quote.location) { _, _ in
            if selectForQuote {
                Task { await reload() }
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var inventoryList: some View {
        List {
            ForEach(items) { sku in
                skuRow(sku)
                    .onAppear {
                        if sku.id == items.last?.id {
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
                InventorySkuRow(
                    sku: sku,
                    location: selectedLocation.nilIfBlank,
                    showsUnitCost: false,
                    showsAvailableQuantity: true
                )
            }
            .tint(Theme.text)
            .disabled(Self.available(sku, location: selectedLocation.nilIfBlank) <= 0)
        } else {
            NavigationLink {
                SkuDetailNativeView(sku: sku, initialLocation: selectedLocation.nilIfBlank)
            } label: {
                InventorySkuRow(sku: sku, location: selectedLocation.nilIfBlank)
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
            Text("\(items.count) shown")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            warehouseFilter

            HStack(spacing: Theme.Space.sm) {
                compactSearchField
                showZeroButton
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

    @ViewBuilder
    private var warehouseFilter: some View {
        if loadingWarehouses {
            HStack(spacing: Theme.Space.sm) {
                ProgressView()
                    .tint(Theme.primary)
                Text("Loading warehouses...")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(height: 32)
        } else if warehouses.isEmpty {
            Label(
                warehouseError ?? "No active warehouses are available.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(warehouseError == nil ? Theme.muted : Theme.danger)
            .frame(height: 32)
        } else if selectForQuote {
            HStack {
                CompactFilterChip(
                    title: selectedLocation.isEmpty ? "All warehouses" : selectedLocation,
                    selected: true,
                    accessibilityLabel: warehouseLabel(selectedLocation)
                )
                Spacer(minLength: 0)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    CompactFilterChip(
                        title: "All warehouses",
                        selected: location.isEmpty,
                        accessibilityLabel: "All warehouses"
                    ) {
                        selectWarehouse("")
                    }

                    ForEach(warehouses) { warehouse in
                        CompactFilterChip(
                            title: warehouse.code,
                            selected: location == warehouse.code,
                            accessibilityLabel: "\(warehouse.code) — \(warehouse.name)"
                        ) {
                            selectWarehouse(warehouse.code)
                        }
                    }
                }
            }
            .frame(height: 32)
        }
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

    private var showZeroButton: some View {
        Button {
            showZeroStock.toggle()
            Task { await reload() }
        } label: {
            Label("Show 0", systemImage: showZeroStock ? "eye.fill" : "eye")
                .font(.caption)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
                .frame(width: 78, height: 42)
                .background(showZeroStock ? Theme.primary : Theme.card)
                .foregroundStyle(showZeroStock ? Theme.primaryText : Theme.text)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(showZeroStock ? Theme.primary : Theme.border)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show zero stock items")
        .accessibilityValue(showZeroStock ? "On" : "Off")
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

            if !brands.isEmpty {
                Section("Brand") {
                    Button {
                        updateFilter($brand, "")
                    } label: {
                        menuLabel("All brands", selected: brand.isEmpty)
                    }

                    ForEach(brands, id: \.self) { option in
                        Button {
                            updateFilter($brand, option)
                        } label: {
                            menuLabel(option, selected: brand == option)
                        }
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
            .disabled(!hasActiveFilters && !showZeroStock)
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
        if !showZeroStock {
            return "No in-stock items found. Turn on Show 0 to include them."
        }
        return "No inventory found."
    }

    private func updateFilter(_ selected: Binding<String>, _ value: String) {
        guard selected.wrappedValue != value else { return }
        selected.wrappedValue = value
        Task { await reload() }
    }

    private func selectWarehouse(_ code: String) {
        guard location != code else { return }
        location = code
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
        brand = ""
        sortBy = ""
        sortOrder = "asc"
        showZeroStock = false
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
        guard Self.available(sku, location: selectedLocation.nilIfBlank) > 0 else { return }
        quote.addLine(
            itemType: "SKU",
            itemId: sku.id,
            description: "\(sku.brand) \(sku.model) \(sku.size) (\(sku.position.replacingOccurrences(of: "_", with: "-")))",
            unitPrice: Double(sku.priceRetail) ?? 0
        )
        dismiss()
    }

    private static func available(_ sku: TireSku, location: String?) -> Int {
        guard let location else {
            return sku.inventory.reduce(0) { total, inventory in
                total + max(0, inventory.qtyOnHand - inventory.qtyReserved)
            }
        }
        guard let inventory = sku.inventory.first(where: { $0.location == location }) else { return 0 }
        return max(0, inventory.qtyOnHand - inventory.qtyReserved)
    }

    @MainActor
    private func reload() async {
        loading = true
        errorMessage = nil
        loadMoreError = nil
        defer { loading = false }

        do {
            var page = 1
            var allItems: [TireSku] = []
            var expectedTotal = 0
            var lastLoadedPage = 0

            while true {
                let pageData = try await requestInventoryPage(page)
                expectedTotal = pageData.total
                lastLoadedPage = pageData.page

                let existingIds = Set(allItems.map(\.id))
                allItems.append(contentsOf: pageData.items.filter { !existingIds.contains($0.id) })

                guard allItems.count < pageData.total, !pageData.items.isEmpty else { break }
                page = pageData.page + 1
            }

            items = allItems
            total = expectedTotal
            loadedPage = lastLoadedPage
            hasLoaded = true
        } catch {
            guard !isCancellation(error) else { return }

            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load inventory."
            hasLoaded = !items.isEmpty
        }
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
            errorMessage = nil
            loadMoreError = nil
        } else {
            loadingMore = true
            loadMoreError = nil
        }
        defer {
            if reset {
                loading = false
            } else {
                loadingMore = false
            }
        }

        do {
            let pageData = try await requestInventoryPage(page)

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
            guard !isCancellation(error) else { return }

            let message = (error as? LocalizedError)?.errorDescription ?? "Could not load inventory."
            if reset {
                errorMessage = message
                hasLoaded = !items.isEmpty
            } else {
                loadMoreError = message
            }
        }
    }

    private func requestInventoryPage(_ page: Int) async throws -> Paged<TireSku> {
        try await InventoryAPI().listSkus(
            q: q.nilIfBlank,
            category: category.nilIfBlank,
            position: position.nilIfBlank,
            brand: brand.nilIfBlank,
            sortBy: sortBy.nilIfBlank,
            sortOrder: sortBy.isEmpty ? nil : sortOrder,
            inStock: showZeroStock ? nil : true,
            location: selectedLocation.nilIfBlank,
            page: page,
            pageSize: pageSize
        )
    }

    @MainActor
    private func loadBrands() async {
        do {
            brands = try await InventoryAPI().listBrands()
        } catch {
            brands = []
        }
    }

    @MainActor
    private func loadWarehouses() async {
        loadingWarehouses = true
        warehouseError = nil
        defer { loadingWarehouses = false }

        do {
            warehouses = try await WarehousesAPI().list(activeOnly: true)

            if selectForQuote {
                if quote.location.nilIfBlank == nil {
                    quote.setLocation(defaultInventoryLocation())
                }
            } else if !didChooseInitialLocation {
                location = defaultInventoryLocation()
                didChooseInitialLocation = true
            }
        } catch {
            warehouses = []
            warehouseError = (error as? LocalizedError)?.errorDescription ?? "Could not load warehouses."
        }
    }

    private func defaultInventoryLocation() -> String {
        warehouses.first(where: { $0.code == "MAIN" })?.code
            ?? warehouses.first(where: \.isDefault)?.code
            ?? warehouses.first?.code
            ?? ""
    }

    private func warehouseLabel(_ code: String) -> String {
        guard let warehouse = warehouses.first(where: { $0.code == code }) else {
            return code.isEmpty ? "All warehouses" : code
        }
        return "\(warehouse.code) — \(warehouse.name)"
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        return false
    }
}

private struct InventorySkuRow: View {
    let sku: TireSku
    var location: String? = nil
    var showsUnitCost = true
    var showsAvailableQuantity = false

    private var selectedInventory: TireSkuInventory? {
        guard let location else { return nil }
        return sku.inventory.first { $0.location == location }
    }

    private var onHand: Int {
        if location != nil {
            return selectedInventory?.qtyOnHand ?? 0
        }
        return sku.inventory.reduce(0) { $0 + $1.qtyOnHand }
    }

    private var available: Int {
        if location != nil {
            guard let selectedInventory else { return 0 }
            return max(0, selectedInventory.qtyOnHand - selectedInventory.qtyReserved)
        }
        return sku.inventory.reduce(0) { total, inventory in
            total + max(0, inventory.qtyOnHand - inventory.qtyReserved)
        }
    }

    private var displayedQuantity: Int {
        showsAvailableQuantity ? available : onHand
    }

    private var inventoryDetail: String {
        if showsAvailableQuantity {
            if let location {
                let reserved = selectedInventory?.qtyReserved ?? 0
                return "\(available) available at \(location) · \(reserved) reserved"
            }
            return "\(available) available across all warehouses"
        }

        if let location {
            let cost = selectedInventory.map { AppFormat.money($0.unitCost) } ?? "—"
            return showsUnitCost
                ? "\(location) · \(onHand) on hand · \(cost) cost"
                : "\(onHand) on hand at \(location)"
        }

        let rows = sku.inventory
            .sorted { $0.location < $1.location }
            .map { row in
                showsUnitCost
                    ? "\(row.location) \(row.qtyOnHand) @ \(AppFormat.money(row.unitCost))"
                    : "\(row.location) \(row.qtyOnHand)"
            }
        return rows.isEmpty ? "No warehouse stock" : rows.joined(separator: " · ")
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
                if location == nil {
                    Text(showsAvailableQuantity ? "\(available) available" : "\(onHand) total")
                }
            }
            .font(.caption)
            .foregroundStyle(displayedQuantity <= sku.reorderPoint ? Theme.danger : Theme.muted)

            Text(inventoryDetail)
                .font(.caption2)
                .foregroundStyle(displayedQuantity <= sku.reorderPoint ? Theme.danger : Theme.muted)
                .lineLimit(2)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

struct SkuManagementNativeView: View {
    var body: some View {
        InventoryListNativeView()
    }
}

private struct SalesSortOption: Identifiable {
    let id: String
    let label: String
}

private enum SalesDateRange: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case threeDays = "3days"
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All dates"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .threeDays: return "Last 3 days"
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    func params() -> (from: String?, to: String?) {
        guard self != .all else { return (nil, nil) }

        let calendar = Calendar.current
        let now = Date()
        let startToday = calendar.startOfDay(for: now)
        let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday

        func iso(_ date: Date) -> String {
            Self.isoFormatter.string(from: date)
        }

        switch self {
        case .all:
            return (nil, nil)
        case .today:
            return (iso(startToday), iso(startTomorrow))
        case .yesterday:
            let startYesterday = calendar.date(byAdding: .day, value: -1, to: startToday) ?? startToday
            return (iso(startYesterday), iso(startToday))
        case .threeDays:
            let start = calendar.date(byAdding: .day, value: -2, to: startToday) ?? startToday
            return (iso(start), iso(startTomorrow))
        case .week:
            let weekday = calendar.component(.weekday, from: now)
            let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: startToday) ?? startToday
            return (iso(start), iso(startTomorrow))
        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? startToday
            return (iso(start), iso(startTomorrow))
        case .year:
            let components = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: components) ?? startToday
            return (iso(start), iso(startTomorrow))
        }
    }
}

private enum SalesLabels {
    static let statusOptions: [(String, String)] = [
        ("", "All statuses"),
        ("DRAFT", "Draft"),
        ("QUOTE", "Quote"),
        ("CONFIRMED", "Confirmed"),
        ("INVOICED", "Invoiced"),
        ("PAID", "Paid"),
        ("CANCELLED", "Cancelled")
    ]

    static let sortOptions: [SalesSortOption] = [
        SalesSortOption(id: "", label: "Newest first"),
        SalesSortOption(id: "ref", label: "Sale #"),
        SalesSortOption(id: "status", label: "Status"),
        SalesSortOption(id: "subtotal", label: "Subtotal"),
        SalesSortOption(id: "taxAmount", label: "Tax"),
        SalesSortOption(id: "total", label: "Total"),
        SalesSortOption(id: "createdAt", label: "Date")
    ]

    static func status(_ value: SaleStatus) -> String {
        statusOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func sort(_ value: String) -> String {
        sortOptions.first { $0.id == value }?.label ?? "Newest first"
    }
}

private struct SalesStatusBadge: View {
    let status: SaleStatus

    private var label: String {
        SalesLabels.status(status)
    }

    private var systemImage: String {
        switch status {
        case "PAID": return "checkmark.circle.fill"
        case "INVOICED": return "doc.text.fill"
        default: return "circle.fill"
        }
    }

    private var foreground: Color {
        switch status {
        case "PAID": return Color(lightHex: 0x0757b7, darkHex: 0x8fc5ff)
        case "INVOICED": return Color(lightHex: 0x8a4b00, darkHex: 0xffc266)
        default: return Theme.muted
        }
    }

    private var background: Color {
        switch status {
        case "PAID": return Color(lightHex: 0xdcecff, darkHex: 0x12345a)
        case "INVOICED": return Color(lightHex: 0xffedcc, darkHex: 0x4b310d)
        default: return Theme.background
        }
    }

    private var border: Color {
        switch status {
        case "PAID": return Color(lightHex: 0x78afea, darkHex: 0x4389d0)
        case "INVOICED": return Color(lightHex: 0xd69a3d, darkHex: 0xc9821e)
        default: return Theme.border
        }
    }

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: status == "INVOICED" ? 2 : 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(label)")
    }
}

struct SalesListNativeView: View {
    private let pageSize = 50

    @State private var q = ""
    @State private var status = ""
    @State private var range: SalesDateRange = .all
    @State private var sortBy = ""
    @State private var sortOrder = "asc"
    @State private var data: SalesListResponse?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var hasActiveFilters: Bool {
        !status.isEmpty || range != .all || !sortBy.isEmpty
    }

    private var activeFilterCount: Int {
        [
            status.isEmpty ? nil : status,
            range == .all ? nil : range.rawValue,
            sortBy.isEmpty ? nil : sortBy
        ].compactMap { $0 }.count
    }

    private var activeSummary: String? {
        var parts: [String] = []
        if !status.isEmpty { parts.append(SalesLabels.status(status)) }
        if range != .all { parts.append(range.label) }
        if !sortBy.isEmpty { parts.append("\(SalesLabels.sort(sortBy)) \(sortOrder.uppercased())") }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    var body: some View {
        VStack(spacing: 0) {
            salesHeader

            Group {
                if loading && data == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: emptyMessage)
                } else if let data {
                    salesContent(data)
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

    private func salesContent(_ data: SalesListResponse) -> some View {
        VStack(spacing: 0) {
            List(data.items) { sale in
                NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                    saleRow(sale)
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }

            if !data.items.isEmpty {
                summaryFooter(data.summary)
            }
        }
    }

    private func saleRow(_ sale: SaleListItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                Text("\(sale.ref ?? "Sale") - \(sale.customer.company ?? sale.customer.name)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer(minLength: Theme.Space.sm)

                Text(AppFormat.money(sale.total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            HStack(spacing: Theme.Space.sm) {
                SalesStatusBadge(status: sale.status)

                Text(saleSubtitle(sale))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var salesHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                searchBar
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
        .frame(maxWidth: .infinity)
    }

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                ForEach(SalesLabels.statusOptions, id: \.0) { option in
                    Button {
                        updateStatus(option.0)
                    } label: {
                        menuLabel(option.1, selected: status == option.0)
                    }
                }
            }

            Section("Date range") {
                ForEach(SalesDateRange.allCases) { option in
                    Button {
                        updateRange(option)
                    } label: {
                        menuLabel(option.label, selected: range == option)
                    }
                }
            }

            Section("Sort") {
                ForEach(SalesLabels.sortOptions) { option in
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
            .disabled(!hasActiveFilters)
        } label: {
            ZStack(alignment: .topTrailing) {
                Label("Filters", systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .labelStyle(.titleAndIcon)
                    .frame(width: 94, height: 42)
                    .background(activeFilterCount > 0 ? Theme.primary : Theme.card)
                    .foregroundStyle(activeFilterCount > 0 ? Theme.primaryText : Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(activeFilterCount > 0 ? Theme.primary : Theme.border)
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
        .accessibilityLabel("Sales filters")
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

    private func summaryFooter(_ summary: SalesSummary) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                summaryPill(title: "Sales", value: "\(summary.count)")
                summaryPill(title: "Tires", value: "\(summary.tireQty)")
                summaryPill(title: "Tax", value: AppFormat.money(summary.taxAmount))
                summaryPill(
                    title: "Gross profit",
                    value: AppFormat.money(summary.grossProfit),
                    valueColor: (Double(summary.grossProfit) ?? 0) < 0 ? Theme.danger : Theme.success
                )
                summaryPill(title: "Total", value: AppFormat.money(summary.total))
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
        }
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
    }

    private func summaryPill(title: String, value: String, valueColor: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 86, alignment: .leading)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var emptyMessage: String {
        if q.nilIfBlank != nil || hasActiveFilters {
            return "No sales match the current filters."
        }
        return "No sales found."
    }

    private func saleSubtitle(_ sale: SaleListItem) -> String {
        var parts = [
            sale.location,
            AppFormat.dateTime(sale.createdAt)
        ]

        if sale.tireQty > 0 {
            let more = sale.extraLineCount > 0 ? " +\(sale.extraLineCount) more" : ""
            parts.append("\(sale.tireQty) tires - \(sale.sampleDescription ?? "SKU lines")\(more)")
        }

        return parts.joined(separator: " - ")
    }

    private func updateStatus(_ value: String) {
        guard status != value else { return }
        status = value
        Task { await load() }
    }

    private func updateRange(_ value: SalesDateRange) {
        guard range != value else { return }
        range = value
        Task { await load() }
    }

    private func updateSort(_ value: String) {
        guard sortBy != value else { return }
        sortBy = value
        if value.isEmpty {
            sortOrder = "asc"
        }
        Task { await load() }
    }

    private func updateSortOrder(_ value: String) {
        guard sortOrder != value else { return }
        sortOrder = value
        Task { await load() }
    }

    private func resetFilters(includeSearch: Bool) {
        if includeSearch {
            q = ""
        }
        status = ""
        range = .all
        sortBy = ""
        sortOrder = "asc"
        Task { await load() }
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
            let dateParams = range.params()
            data = try await SalesAPI().list(
                q: q.nilIfBlank,
                status: status.nilIfBlank,
                from: dateParams.from,
                to: dateParams.to,
                sortBy: sortBy.nilIfBlank,
                sortOrder: sortBy.isEmpty ? nil : sortOrder,
                pageSize: pageSize
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load sales."
        }
        loading = false
    }
}

struct CustomersListNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var q = ""
    @State private var customers: [Customer] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private var canManageCustomers: Bool {
        auth.has("customers.manage")
    }

    var body: some View {
        Group {
            if loading && customers.isEmpty {
                LoadingView(label: "Loading...")
            } else if let errorMessage, customers.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if customers.isEmpty {
                customerEmptyState
            } else {
                List(customers) { customer in
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
                .refreshable { await load() }
            }
        }
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name, company, phone…")
        .toolbar {
            if canManageCustomers {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.newCustomer) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New customer")
                }
            }
        }
        .onAppear {
            Task { await load() }
        }
        .task(id: q) {
            if !q.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
            }
            await load()
        }
    }

    @ViewBuilder
    private var customerEmptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(q.nilIfBlank == nil ? "No customers found." : "No customers match that search.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, Theme.Space.xl)
            if canManageCustomers {
                NavigationLink(value: AppRoute.newCustomer) {
                    Label("New customer", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            customers = try await CustomersAPI().list(q: q.nilIfBlank, pageSize: 50).items
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load customers."
            }
        }
        loading = false
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
                    EmptyStateView(text: "No work orders have been started yet.")
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
                .filter(\.hasVisibleWorkContent)
        } catch {
            items = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load work orders."
        }
        loading = false
    }
}

private enum ReturnLabels {
    static let statuses: [(String, String)] = [
        ("", "All"),
        ("DRAFT", "Draft"),
        ("POSTED", "Posted"),
        ("VOIDED", "Voided")
    ]

    static func status(_ value: ReturnStatus) -> String {
        statuses.first { $0.0 == value }?.1 ?? title(value)
    }

    static func type(_ value: ReturnType) -> String {
        switch value {
        case "RETURN": return "Return"
        case "EXCHANGE": return "Exchange"
        case "WARRANTY": return "Warranty"
        default: return title(value)
        }
    }

    static func refundMethod(_ value: RefundMethod, paymentMethod: InvoicePayment.Method?) -> String {
        switch value {
        case "ORIGINAL": return paymentMethod?.name ?? "Original tender"
        case "STORE_CREDIT": return "Store credit"
        default: return paymentMethod?.name ?? title(value)
        }
    }

    static func disposition(_ value: InventoryDisposition) -> String {
        switch value {
        case "RESTOCK": return "Restock"
        case "SCRAP": return "Scrap"
        default: return title(value)
        }
    }

    private static func title(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct ReturnsListNativeView: View {
    private let pageSize = 50

    @State private var status = ""
    @State private var page: Paged<ReturnRecord>?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            statusFilter

            Group {
                if loading && page == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, page == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let page, page.items.isEmpty {
                    EmptyStateView(text: status.isEmpty ? "No returns found." : "No returns match this status.")
                } else if let page {
                    List(page.items) { record in
                        NavigationLink(value: AppRoute.returnDetail(record.id)) {
                            RowLine(
                                title: "\(record.ref ?? "Return") - \(ReturnLabels.type(record.type))",
                                subtitle: returnSubtitle(record),
                                trailing: AppFormat.money(record.refundTotal)
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
        .task(id: status) {
            await load()
        }
    }

    private var statusFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(ReturnLabels.statuses, id: \.0) { option in
                    Button {
                        status = option.0
                    } label: {
                        Text(option.1)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 6)
                            .background(status == option.0 ? Theme.primary : Theme.card)
                            .foregroundStyle(status == option.0 ? Theme.primaryText : Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .stroke(status == option.0 ? Theme.primary : Theme.border)
                            )
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.xs)
        }
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private func returnSubtitle(_ record: ReturnRecord) -> String {
        let customer = record.sale?.customer?.company ?? record.sale?.customer?.name ?? "Unknown customer"
        return [
            ReturnLabels.status(record.status),
            customer,
            AppFormat.dateTime(record.createdAt)
        ].joined(separator: " - ")
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            page = try await ReturnsAPI().list(status: status.nilIfBlank, pageSize: pageSize)
        } catch {
            page = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load returns."
        }
        loading = false
    }
}

struct ReturnDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var record: ReturnRecord?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showVoidPrompt = false
    @State private var voidReason = ""
    @State private var voiding = false

    private var canVoid: Bool {
        auth.has("returns.void") && record?.status == "POSTED"
    }

    var body: some View {
        Group {
            if loading && record == nil {
                LoadingView(label: "Loading...")
            } else if let record {
                content(record)
            } else if let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .navigationTitle("Return")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canVoid {
                    Button(role: .destructive) {
                        showVoidPrompt = true
                    } label: {
                        if voiding {
                            ProgressView()
                        } else {
                            Label("Void", systemImage: "xmark.circle")
                        }
                    }
                    .disabled(voiding)
                }
            }
        }
        .alert("Void return?", isPresented: $showVoidPrompt) {
            TextField("Reason", text: $voidReason)
            Button("Cancel", role: .cancel) {
                voidReason = ""
            }
            Button("Void", role: .destructive) {
                Task { await voidReturn() }
            }
        } message: {
            Text("This reverses a posted return and its accounting entries.")
        }
        .task {
            if record == nil { await load() }
        }
    }

    private func content(_ record: ReturnRecord) -> some View {
        List {
            Section {
                RowLine(title: record.ref ?? "Return", subtitle: ReturnLabels.type(record.type), trailing: ReturnLabels.status(record.status))
                RowLine(title: "Warehouse", subtitle: record.location)

                if let sale = record.sale {
                    NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                        RowLine(
                            title: sale.ref ?? "Sale",
                            subtitle: sale.customer?.company ?? sale.customer?.name ?? "Unknown customer"
                        )
                    }
                }

                if let replacement = record.replacementSale {
                    NavigationLink(value: AppRoute.saleDetail(replacement.id)) {
                        RowLine(
                            title: replacement.ref ?? "Replacement sale",
                            subtitle: replacement.status,
                            trailing: AppFormat.money(replacement.total)
                        )
                    }
                }

                RowLine(title: "Created", subtitle: AppFormat.dateTime(record.createdAt))
                if let postedAt = record.postedAt {
                    RowLine(title: "Posted", subtitle: AppFormat.dateTime(postedAt))
                }
                if let voidedAt = record.voidedAt {
                    RowLine(title: "Voided", subtitle: AppFormat.dateTime(voidedAt))
                }
                if let reason = record.reason?.nilIfBlank {
                    RowLine(title: "Reason", subtitle: reason)
                }
                if let notes = record.notes?.nilIfBlank {
                    RowLine(title: "Notes", subtitle: notes)
                }
            }

            Section("Refund") {
                RowLine(title: "Subtotal", trailing: AppFormat.money(record.refundSubtotal))
                RowLine(title: "Tax", trailing: AppFormat.money(record.refundTax))
                RowLine(title: "Restocking fee", trailing: AppFormat.money(record.restockingFee))
                RowLine(title: "Total", trailing: AppFormat.money(record.refundTotal))
                RowLine(title: "Method", subtitle: ReturnLabels.refundMethod(record.refundMethod, paymentMethod: record.paymentMethod))
            }

            Section("Lines") {
                if record.lines.isEmpty {
                    Text("No return lines.")
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(record.lines) { line in
                        RowLine(
                            title: lineTitle(line),
                            subtitle: "Qty \(line.qty) - \(ReturnLabels.disposition(line.inventoryDisposition))",
                            trailing: AppFormat.money(line.unitRefund)
                        )
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
        .refreshable {
            await load()
        }
    }

    private func lineTitle(_ line: ReturnLine) -> String {
        if let saleLine = line.saleLine {
            return saleLine.description
        }
        if let sku = line.sku {
            return "\(sku.brand) \(sku.model) \(sku.size)"
        }
        return line.skuId
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            record = try await ReturnsAPI().get(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load return."
        }
        loading = false
    }

    @MainActor
    private func voidReturn() async {
        guard record?.status == "POSTED" else { return }
        voiding = true
        errorMessage = nil
        do {
            record = try await ReturnsAPI().void(id: id, reason: voidReason.nilIfBlank)
            voidReason = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not void return."
        }
        voiding = false
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

private enum PurchasingTab: String, CaseIterable, Identifiable {
    case containers
    case suppliers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .containers: return "Containers"
        case .suppliers: return "Suppliers"
        }
    }
}

private enum ContainerLabels {
    static let statusFlow: [ContainerStatus] = ["DRAFT", "ORDERED", "IN_TRANSIT", "ARRIVED", "RECEIVED"]

    static let statusOptions: [(String, String)] = [
        ("", "All statuses"),
        ("DRAFT", "Draft"),
        ("ORDERED", "Ordered"),
        ("IN_TRANSIT", "In transit"),
        ("ARRIVED", "Arrived"),
        ("RECEIVED", "Received"),
        ("CANCELLED", "Cancelled")
    ]

    static func status(_ value: ContainerStatus) -> String {
        statusOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct SupplierEditorTarget: Identifiable {
    let supplier: Supplier?
    let id: String
}

struct PurchasingNativeView: View {
    @State private var tab: PurchasingTab = .containers

    var body: some View {
        VStack(spacing: 0) {
            Picker("Purchasing", selection: $tab) {
                ForEach(PurchasingTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .background(Theme.background)

            switch tab {
            case .containers:
                PurchasingContainersListView()
            case .suppliers:
                PurchasingSuppliersListView()
            }
        }
        .background(Theme.background)
    }
}

private struct PurchasingContainersListView: View {
    @EnvironmentObject private var auth: AuthStore

    private let pageSize = 50

    @State private var q = ""
    @State private var status = ""
    @State private var page: Paged<ContainerListItem>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showingNewContainer = false
    @State private var cancelTarget: ContainerListItem?
    @State private var searchTask: Task<Void, Never>?

    private var canManage: Bool {
        auth.has("purchasing.manage")
    }

    private var hasFilters: Bool {
        q.nilIfBlank != nil || !status.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.sm)
                    .background(Theme.background)
            }

            Group {
                if loading && page == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, page == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let page, page.items.isEmpty {
                    EmptyStateView(text: hasFilters ? "No containers match the current filters." : "No containers found.")
                } else if let page {
                    List(page.items) { container in
                        NavigationLink(value: AppRoute.containerDetail(container.id)) {
                            RowLine(
                                title: container.ref ?? container.reference ?? "Container",
                                subtitle: subtitle(container),
                                trailing: "\(container.totalTires ?? 0) tires"
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canManage && container.status != "RECEIVED" && container.status != "CANCELLED" {
                                Button("Cancel", role: .destructive) {
                                    cancelTarget = container
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
        }
        .task {
            if page == nil { await load() }
        }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewContainer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New container")
                }
            }
        }
        .sheet(isPresented: $showingNewContainer) {
            NewContainerNativeView {
                showingNewContainer = false
                Task { await load() }
            }
        }
        .alert("Cancel container?", isPresented: Binding(
            get: { cancelTarget != nil },
            set: { if !$0 { cancelTarget = nil } }
        )) {
            Button("Keep", role: .cancel) { cancelTarget = nil }
            Button("Cancel container", role: .destructive) {
                Task { await cancelContainer() }
            }
        } message: {
            Text("This marks the container as cancelled. Received containers cannot be cancelled.")
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                searchBar
                statusMenu
            }

            if !status.isEmpty {
                HStack(spacing: Theme.Space.sm) {
                    Text(ContainerLabels.status(status))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)

                    Spacer()

                    Button("Reset") {
                        status = ""
                        Task { await load() }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
                }
                .frame(height: 22)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField("Search ref, BOL, supplier...", text: $q)
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
        .frame(maxWidth: .infinity)
    }

    private var statusMenu: some View {
        Menu {
            Section("Status") {
                ForEach(ContainerLabels.statusOptions, id: \.0) { option in
                    Button {
                        status = option.0
                        Task { await load() }
                    } label: {
                        if status == option.0 {
                            Label(option.1, systemImage: "checkmark")
                        } else {
                            Text(option.1)
                        }
                    }
                }
            }
        } label: {
            Label("Status", systemImage: status.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .labelStyle(.titleAndIcon)
                .frame(width: 94, height: 42)
                .background(status.isEmpty ? Theme.card : Theme.primary)
                .foregroundStyle(status.isEmpty ? Theme.text : Theme.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(status.isEmpty ? Theme.border : Theme.primary)
                )
        }
        .accessibilityLabel("Container status filter")
    }

    private func subtitle(_ container: ContainerListItem) -> String {
        var parts = [ContainerLabels.status(container.status), container.location, container.supplier.name]
        if let country = container.supplier.country?.nilIfBlank {
            parts.append(country)
        }
        parts.append(paymentLabel(container))
        return parts.joined(separator: " - ")
    }

    private func paymentLabel(_ container: ContainerListItem) -> String {
        let supplierCosts = container.costs.filter { ["DOWN_PAYMENT", "BALANCE_PAYMENT", "SUPPLIER_OTHER"].contains($0.category) }
        guard !supplierCosts.isEmpty else { return "Unpaid" }
        let total = supplierCosts.reduce(0) { $0 + (Double($1.amount) ?? 0) }
        let paid = supplierCosts.reduce(0) { $0 + (Double($1.amountPaid) ?? 0) }
        if paid >= total - 0.01 { return "Paid" }
        if paid > 0 { return "Partially paid" }
        return "Unpaid"
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
            page = try await ContainersAPI().list(status: status.nilIfBlank, q: q.nilIfBlank, pageSize: pageSize)
        } catch {
            page = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load containers."
        }
        loading = false
    }

    @MainActor
    private func cancelContainer() async {
        guard let target = cancelTarget else { return }
        cancelTarget = nil
        actionError = nil
        do {
            _ = try await ContainersAPI().cancel(id: target.id)
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not cancel container."
        }
    }
}

private struct PurchasingSuppliersListView: View {
    @EnvironmentObject private var auth: AuthStore

    private let pageSize = 50

    @State private var q = ""
    @State private var page: Paged<Supplier>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var editing: SupplierEditorTarget?
    @State private var deleteTarget: Supplier?
    @State private var searchTask: Task<Void, Never>?

    private var canManage: Bool {
        auth.has("purchasing.manage")
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.sm)
                    .background(Theme.background)
            }

            Group {
                if loading && page == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, page == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let page, page.items.isEmpty {
                    EmptyStateView(text: q.nilIfBlank == nil ? "No suppliers found." : "No suppliers match this search.")
                } else if let page {
                    List(page.items) { supplier in
                        SupplierListRow(supplier: supplier, subtitle: supplierSubtitle(supplier))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canManage {
                                    Button("Delete", role: .destructive) {
                                        deleteTarget = supplier
                                    }
                                    Button("Edit") {
                                        editing = SupplierEditorTarget(supplier: supplier, id: supplier.id)
                                    }
                                    .tint(Theme.primary)
                                }
                            }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    LoadingView(label: "Loading...")
                }
            }
        }
        .task {
            if page == nil { await load() }
        }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = SupplierEditorTarget(supplier: nil, id: UUID().uuidString)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New supplier")
                }
            }
        }
        .sheet(item: $editing) { target in
            SupplierEditorView(supplier: target.supplier) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Delete supplier?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                Task { await deleteSupplier() }
            }
        } message: {
            Text("Suppliers with containers cannot be deleted.")
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField("Search supplier, country, contact...", text: $q)
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
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private func supplierSubtitle(_ supplier: Supplier) -> String {
        [
            supplier.contactName,
            supplier.country,
            supplier.email,
            supplier.currency
        ].compactMap { $0?.nilIfBlank }.joined(separator: " - ")
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
            page = try await SuppliersAPI().list(q: q.nilIfBlank, pageSize: pageSize)
        } catch {
            page = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load suppliers."
        }
        loading = false
    }

    @MainActor
    private func deleteSupplier() async {
        guard let supplier = deleteTarget else { return }
        deleteTarget = nil
        actionError = nil
        do {
            _ = try await SuppliersAPI().remove(id: supplier.id)
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not delete supplier."
        }
    }
}

private struct SupplierListRow: View {
    let supplier: Supplier
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(supplier.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                if supplier.defaultDDP == true {
                    Text("DDP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 4)
                        .foregroundStyle(Theme.primary)
                        .background(Theme.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Text("\(supplier.count?.containers ?? 0) containers")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct SupplierEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let supplier: Supplier?
    let onSaved: () -> Void

    @State private var name: String
    @State private var country: String
    @State private var contactName: String
    @State private var phone: String
    @State private var email: String
    @State private var currency: String
    @State private var defaultDDP: Bool
    @State private var address: String
    @State private var notes: String
    @State private var saving = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        supplier != nil
    }

    init(supplier: Supplier?, onSaved: @escaping () -> Void) {
        self.supplier = supplier
        self.onSaved = onSaved
        _name = State(initialValue: supplier?.name ?? "")
        _country = State(initialValue: supplier?.country ?? "")
        _contactName = State(initialValue: supplier?.contactName ?? "")
        _phone = State(initialValue: supplier?.phone ?? "")
        _email = State(initialValue: supplier?.email ?? "")
        _currency = State(initialValue: supplier?.currency ?? "USD")
        _defaultDDP = State(initialValue: supplier?.defaultDDP ?? false)
        _address = State(initialValue: supplier?.address ?? "")
        _notes = State(initialValue: supplier?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplier") {
                    AppTextField(label: "Name", text: $name, placeholder: "Supplier name")
                    AppTextField(label: "Country", text: $country, placeholder: "China")
                    AppTextField(label: "Contact", text: $contactName, textContentType: .name)
                    AppTextField(label: "Phone", text: $phone, keyboardType: .phonePad, textContentType: .telephoneNumber)
                    AppTextField(label: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
                    AppTextField(label: "Currency", text: $currency, placeholder: "USD")
                        .onChange(of: currency) { _, value in
                            currency = String(value.uppercased().prefix(8))
                        }
                    Toggle("Default DDP pricing", isOn: $defaultDDP)
                }

                Section("Address") {
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Supplier" : "New Supplier")
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
                    .disabled(saving || name.nilIfBlank == nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let cleanName = name.nilIfBlank else { return }
        saving = true
        errorMessage = nil
        let body = SupplierSaveInput(
            name: cleanName,
            contactName: contactName.nilIfBlank,
            phone: phone.nilIfBlank,
            email: email.nilIfBlank,
            country: country.nilIfBlank,
            address: address.nilIfBlank,
            currency: currency.nilIfBlank ?? "USD",
            defaultDDP: defaultDDP,
            notes: notes.nilIfBlank,
            encodeNulls: isEditing
        )

        do {
            if let supplier {
                _ = try await SuppliersAPI().update(id: supplier.id, body: body)
            } else {
                _ = try await SuppliersAPI().create(body)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save supplier."
        }
        saving = false
    }
}

private struct NewContainerNativeView: View {
    @Environment(\.dismiss) private var dismiss

    let onCreated: () -> Void

    @State private var suppliers: [Supplier] = []
    @State private var supplierId = ""
    @State private var reference = ""
    @State private var loading = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Container") {
                    Picker("Supplier", selection: $supplierId) {
                        Text("Pick supplier").tag("")
                        ForEach(suppliers) { supplier in
                            Text(supplierLabel(supplier)).tag(supplier.id)
                        }
                    }
                    AppTextField(label: "Reference / BOL", text: $reference, placeholder: "BOL-2026-04-001")
                }

                if suppliers.isEmpty && !loading {
                    Section {
                        Text("Add a supplier first, then create a container.")
                            .foregroundStyle(Theme.muted)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("New Container")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await create() }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(saving || supplierId.isEmpty)
                }
            }
            .task {
                if suppliers.isEmpty { await loadSuppliers() }
            }
        }
    }

    private func supplierLabel(_ supplier: Supplier) -> String {
        var label = supplier.name
        if let country = supplier.country?.nilIfBlank {
            label += " (\(country))"
        }
        if supplier.defaultDDP == true {
            label += " - DDP"
        }
        return label
    }

    @MainActor
    private func loadSuppliers() async {
        loading = true
        errorMessage = nil
        do {
            let page = try await SuppliersAPI().list(pageSize: 1000)
            suppliers = page.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load suppliers."
        }
        loading = false
    }

    @MainActor
    private func create() async {
        guard !supplierId.isEmpty else { return }
        saving = true
        errorMessage = nil
        do {
            _ = try await ContainersAPI().create(ContainerCreateInput(supplierId: supplierId, reference: reference.nilIfBlank))
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not create container."
        }
        saving = false
    }
}

// Money, Accounting, Cash Accounts, FET, and End of Day now live in
// FinanceScreens.swift with full action flows.

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
