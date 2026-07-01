import SwiftUI

struct DashboardNativeView: View {
    var body: some View {
        AsyncContentView(load: DashboardAPI().summary) { summary in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    StatGrid(stats: [
                        ("Today's sales", AppFormat.money(summary.today.revenue)),
                        ("Month to date", AppFormat.money(summary.month.revenue)),
                        ("Open A/R", AppFormat.money(summary.openAR.total)),
                        ("Low stock", "\(summary.lowStockCount)")
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
            SectionHeader("Low stock")

            if items.isEmpty {
                DashboardEmptyRow(text: "Everything is stocked.")
            } else {
                dashboardCard {
                    ForEach(items) { item in
                        RowLine(
                            title: "\(item.brand) \(item.model)",
                            subtitle: "\(item.size) - \(item.sku)",
                            trailing: "\(item.onHand) on hand"
                        )
                    }
                }
            }
        }
    }

    private func topSellerSection(_ items: [DashboardSummary.TopSku]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Top sellers this month")

            if items.isEmpty {
                DashboardEmptyRow(text: "No sales yet this month.")
            } else {
                dashboardCard {
                    ForEach(items) { item in
                        RowLine(
                            title: "\(item.brand) \(item.model)",
                            subtitle: "\(item.size) - \(item.sku)",
                            trailing: "\(item.qty) sold"
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
        Text(text)
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

    func params() -> (from: String?, to: String?) {
        guard self != .all else { return (nil, nil) }

        let calendar = Calendar.current
        let now = Date()
        let startToday = calendar.startOfDay(for: now)
        let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday

        func iso(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
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
                    RowLine(
                        title: "\(sale.ref ?? "Sale") - \(sale.customer.company ?? sale.customer.name)",
                        subtitle: saleSubtitle(sale),
                        trailing: AppFormat.money(sale.total)
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }

            if !data.items.isEmpty {
                summaryFooter(data.summary)
            }
        }
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
            SalesLabels.status(sale.status),
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
        var parts = [ContainerLabels.status(container.status), container.supplier.name]
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
