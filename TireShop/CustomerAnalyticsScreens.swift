import SwiftUI
import UIKit

private struct AnalyticsSession: Hashable {
    let userId: String?
    let permissions: [String]
    let isAdmin: Bool
    let demo: Bool
    let server: String
    let token: String?

    @MainActor init(_ auth: AuthStore) {
        userId = auth.user?.id
        permissions = (auth.user?.permissions ?? []).sorted()
        isAdmin = auth.user?.isAdmin == true
        demo = auth.user?.demo == true
        server = Server.baseURLString
        token = APIClient.shared.token
    }
}

private struct AnalyticsRequest: Hashable {
    let session: AnalyticsSession
    let customerId: String?
    let query: CustomerAnalyticsQuery
}

struct CustomerAnalyticsNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @StateObject private var resource = CustomerAnalyticsResource<CustomerAnalyticsRankings, AnalyticsRequest>()
    @State private var query = CustomerAnalyticsQuery()
    @State private var exporting = false
    @State private var exportError: String?
    @State private var exportFile: PreviewFile?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportGeneration = UUID()

    private let loader: (CustomerAnalyticsQuery) async throws -> CustomerAnalyticsRankings

    init(
        initialQuery: CustomerAnalyticsQuery = .init(),
        loader: @escaping (CustomerAnalyticsQuery) async throws -> CustomerAnalyticsRankings = {
            try await CustomerAnalyticsAPI().rankings($0)
        }
    ) {
        _query = State(initialValue: initialQuery)
        self.loader = loader
    }

    private var canView: Bool { auth.has("customers.analytics.view") }
    private var effectiveQuery: CustomerAnalyticsQuery {
        var value = query
        value.sort = value.sort.allowed(canViewProfit: auth.has("customers.profit.view"))
        return value
    }
    private var scope: AnalyticsRequest? {
        guard canView, query.filters.isValid else { return nil }
        return AnalyticsRequest(session: AnalyticsSession(auth), customerId: nil, query: effectiveQuery)
    }
    private var data: CustomerAnalyticsRankings? { resource.value(for: scope) }
    private var profit: Bool { auth.has("customers.profit.view") && data?.canViewProfit == true }
    private var availableSorts: [CustomerAnalyticsSort] {
        CustomerAnalyticsSort.allCases.filter {
            !$0.requiresProfitPermission || (auth.has("customers.profit.view") && data?.canViewProfit != false)
        }
    }

    var body: some View {
        Group {
            if canView {
                report
            } else {
                EmptyStateView(text: i18n.t("analytics.noAccess"))
            }
        }
        .navigationTitle(i18n.t("analytics.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canView {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportTask = Task { await export() }
                    } label: {
                        Label(i18n.t(exporting ? "analytics.exporting" : "analytics.export"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(exporting || resource.loading || data == nil || auth.user?.demo == true)
                }
            }
        }
        .task(id: scope) { await reload(debounce: true) }
        .onChange(of: scope) { _, _ in
            exportTask?.cancel()
            exportGeneration = UUID()
            exporting = false
            exportError = nil
            exportFile = nil
        }
        .onChange(of: data?.canViewProfit) { _, allowed in
            if allowed == false, query.sort.requiresProfitPermission {
                query.sort = .sales
                query.page = 1
            }
        }
        .onDisappear { exportTask?.cancel() }
        .sheet(item: $exportFile) { file in AnalyticsShareSheet(url: file.url) }
    }

    private var report: some View {
        List {
            Section(i18n.t("analytics.filters")) {
                AnalyticsFiltersView(filters: filtersBinding)
                TextField(i18n.t("analytics.search"), text: searchBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker(i18n.t("analytics.sort"), selection: sortBinding) {
                    ForEach(availableSorts, id: \.self) { sort in
                        Text(i18n.t("analytics.\(sort == .priceLevel ? "currentLevel" : sort.rawValue)")).tag(sort)
                    }
                }
                Picker(i18n.t("analytics.direction"), selection: directionBinding) {
                    Text(i18n.t("analytics.descending")).tag(CustomerAnalyticsDirection.desc)
                    Text(i18n.t("analytics.ascending")).tag(CustomerAnalyticsDirection.asc)
                }
            }
            Section {
                AnalyticsBasisView(profit: profit)
                if auth.user?.demo == true {
                    Text(i18n.t("analytics.demoExportUnavailable")).font(.footnote).foregroundStyle(Theme.muted)
                }
                if let exportError { Text(exportError).foregroundStyle(Theme.danger) }
            }
            AnalyticsLoadState(loading: resource.loading, error: resource.error(for: scope)) {
                await reload()
            }
            if let data {
                Section {
                    AnalyticsPeriodView(period: data.period)
                    AnalyticsCoverageView(coverage: data.historyCoverage)
                }
                Section(i18n.t("analytics.allCustomersTotal")) {
                    AnalyticsMetricsView(metrics: data.totals, profit: profit, timezone: data.period.timezone)
                }
                Section(i18n.t("analytics.rankings")) {
                    if data.items.isEmpty { Text(i18n.t("analytics.empty")).foregroundStyle(Theme.muted) }
                    ForEach(data.items) { row in
                        VStack(alignment: .leading, spacing: Theme.Space.md) {
                            NavigationLink(value: AppRoute.customerAnalyticsDetail(customerId: row.customerId, query: effectiveQuery)) {
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text(row.customerName).font(.headline)
                                    if let company = row.company?.nilIfBlank {
                                        Text(company).font(.subheadline).foregroundStyle(Theme.muted)
                                    }
                                    Text("\(i18n.t("analytics.currentLevel")): \(i18n.t("analytics.level.\(row.currentPriceLevel?.rawValue ?? "UNKNOWN")"))")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            AnalyticsMetricsView(metrics: row.metrics, profit: profit, timezone: data.period.timezone, compact: true)
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                    AnalyticsPaginationView(page: data.page, pageSize: data.pageSize, total: data.total, selection: $query.page, size: pageSizeBinding)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await reload() }
    }

    private var filtersBinding: Binding<CustomerAnalyticsFilters> {
        Binding(get: { query.filters }, set: { query.filters = $0; query.page = 1 })
    }
    private var searchBinding: Binding<String> {
        Binding(get: { query.q }, set: { query.q = $0; query.page = 1 })
    }
    private var sortBinding: Binding<CustomerAnalyticsSort> {
        Binding(get: { effectiveQuery.sort }, set: { query.sort = $0; query.page = 1 })
    }
    private var directionBinding: Binding<CustomerAnalyticsDirection> {
        Binding(get: { query.direction }, set: { query.direction = $0; query.page = 1 })
    }
    private var pageSizeBinding: Binding<Int> {
        Binding(get: { query.pageSize }, set: { query.pageSize = $0; query.page = 1 })
    }

    private func reload(debounce: Bool = false) async {
        let request = effectiveQuery
        await resource.load(scope: scope, debounce: debounce) { try await loader(request) }
    }

    private func export() async {
        guard let requestScope = scope, data != nil, !resource.loading, !exporting,
              auth.user?.demo != true else { return }
        exporting = true
        let generation = UUID()
        exportGeneration = generation
        exportError = nil
        defer { if exportGeneration == generation { exporting = false } }
        do {
            let url = try await CustomerAnalyticsAPI().export(requestScope.query)
            guard !Task.isCancelled, exportGeneration == generation, scope == requestScope, auth.user?.demo != true else {
                TemporaryDownloadStore.remove(url)
                return
            }
            exportFile = PreviewFile(url: url)
        } catch {
            guard !Task.isCancelled, exportGeneration == generation, scope == requestScope else { return }
            exportError = error.localizedDescription
        }
    }
}

struct CustomerAnalyticsDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @StateObject private var summaryResource = CustomerAnalyticsResource<CustomerAnalyticsSummary, AnalyticsRequest>()
    @StateObject private var productsResource = CustomerAnalyticsResource<CustomerAnalyticsPage<CustomerAnalyticsProduct>, AnalyticsRequest>()
    @StateObject private var historyResource = CustomerAnalyticsResource<CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent>, AnalyticsRequest>()
    @State private var filters: CustomerAnalyticsFilters
    @State private var productPage = 1
    @State private var productPageSize = 10
    @State private var historyPage = 1
    @State private var historyPageSize = 25

    let customerId: String
    private let summaryLoader: (String, CustomerAnalyticsFilters) async throws -> CustomerAnalyticsSummary
    private let productsLoader: (String, CustomerAnalyticsFilters, Int, Int) async throws -> CustomerAnalyticsPage<CustomerAnalyticsProduct>
    private let historyLoader: (String, CustomerAnalyticsFilters, Int, Int) async throws -> CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent>

    init(
        customerId: String,
        initialQuery: CustomerAnalyticsQuery = .init(),
        summaryLoader: @escaping (String, CustomerAnalyticsFilters) async throws -> CustomerAnalyticsSummary = {
            try await CustomerAnalyticsAPI().summary(customerId: $0, filters: $1)
        },
        productsLoader: @escaping (String, CustomerAnalyticsFilters, Int, Int) async throws -> CustomerAnalyticsPage<CustomerAnalyticsProduct> = {
            try await CustomerAnalyticsAPI().products(customerId: $0, filters: $1, page: $2, pageSize: $3)
        },
        historyLoader: @escaping (String, CustomerAnalyticsFilters, Int, Int) async throws -> CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent> = {
            try await CustomerAnalyticsAPI().history(customerId: $0, filters: $1, page: $2, pageSize: $3)
        }
    ) {
        self.customerId = customerId
        _filters = State(initialValue: initialQuery.filters)
        self.summaryLoader = summaryLoader
        self.productsLoader = productsLoader
        self.historyLoader = historyLoader
    }

    private var canView: Bool { auth.has("customers.analytics.view") }
    private var summaryScope: AnalyticsRequest? { scope() }
    private var productsScope: AnalyticsRequest? { scope(page: productPage, pageSize: productPageSize) }
    private var historyScope: AnalyticsRequest? { scope(page: historyPage, pageSize: historyPageSize) }
    private var summary: CustomerAnalyticsSummary? { summaryResource.value(for: summaryScope) }
    private var products: CustomerAnalyticsPage<CustomerAnalyticsProduct>? { productsResource.value(for: productsScope) }
    private var history: CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent>? { historyResource.value(for: historyScope) }
    private var profit: Bool { auth.has("customers.profit.view") && summary?.canViewProfit == true }

    var body: some View {
        Group {
            if canView {
                List {
                    if let customer = summary?.customer {
                        Section {
                            Text(customer.name).font(.title2.weight(.semibold))
                            if let company = customer.company?.nilIfBlank { Text(company).foregroundStyle(Theme.muted) }
                            LabeledContent(i18n.t("analytics.currentLevel"), value: i18n.t("analytics.level.\(customer.currentPriceLevel?.rawValue ?? "UNKNOWN")"))
                        }
                    }
                    Section(i18n.t("analytics.filters")) { AnalyticsFiltersView(filters: filtersBinding) }
                    Section { AnalyticsBasisView(profit: profit) }
                    AnalyticsLoadState(loading: summaryResource.loading, error: summaryResource.error(for: summaryScope)) {
                        await loadSummary()
                    }
                    if let summary {
                        Section {
                            AnalyticsPeriodView(period: summary.period)
                            AnalyticsCoverageView(coverage: summary.historyCoverage)
                        }
                        Section(i18n.t("analytics.periodSummary")) {
                            AnalyticsMetricsView(metrics: summary.summary, profit: profit, timezone: summary.period.timezone)
                        }
                        Section(i18n.t("analytics.lifetimeSummary")) {
                            AnalyticsMetricsView(metrics: summary.lifetime, profit: profit, timezone: summary.period.timezone)
                            if filters.priceLevel != nil {
                                Text(i18n.t("analytics.lifetimeLevelNote")).font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    productsSection
                    historySection
                }
                .listStyle(.insetGrouped)
                .refreshable { await reload() }
            } else {
                EmptyStateView(text: i18n.t("analytics.noAccess"))
            }
        }
        .navigationTitle(i18n.t("analytics.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: summaryScope) { await loadSummary() }
        .task(id: productsScope) { await loadProducts() }
        .task(id: historyScope) { await loadHistory() }
    }

    private var productsSection: some View {
        Section(i18n.t("analytics.topProducts")) {
            Text(i18n.t("analytics.productNote")).font(.footnote).foregroundStyle(Theme.muted)
            AnalyticsLoadState(loading: productsResource.loading, error: productsResource.error(for: productsScope)) { await loadProducts() }
            if let products {
                AnalyticsCoverageView(coverage: products.historyCoverage)
                if products.items.isEmpty { Text(i18n.t("analytics.noProducts")).foregroundStyle(Theme.muted) }
                ForEach(products.items) { product in
                    AnalyticsProductView(product: product)
                }
                AnalyticsPaginationView(page: products.page, pageSize: products.pageSize, total: products.total, selection: $productPage, size: Binding(
                    get: { productPageSize }, set: { productPageSize = $0; productPage = 1 }
                ))
            }
        }
    }

    private var historySection: some View {
        Section(i18n.t("analytics.history")) {
            Text(i18n.t("analytics.historyNote")).font(.footnote).foregroundStyle(Theme.muted)
            AnalyticsLoadState(loading: historyResource.loading, error: historyResource.error(for: historyScope)) { await loadHistory() }
            if let history {
                AnalyticsCoverageView(coverage: history.historyCoverage)
                if history.items.isEmpty { Text(i18n.t("analytics.noHistory")).foregroundStyle(Theme.muted) }
                ForEach(history.items) { event in
                    AnalyticsHistoryView(event: event, profit: profit, canViewSales: auth.has("sales.view"), timezone: history.period.timezone)
                }
                AnalyticsPaginationView(page: history.page, pageSize: history.pageSize, total: history.total, selection: $historyPage, size: Binding(
                    get: { historyPageSize }, set: { historyPageSize = $0; historyPage = 1 }
                ))
            }
        }
    }

    private var filtersBinding: Binding<CustomerAnalyticsFilters> {
        Binding(get: { filters }, set: { filters = $0; productPage = 1; historyPage = 1 })
    }

    private func scope(page: Int = 1, pageSize: Int = 25) -> AnalyticsRequest? {
        guard canView, filters.isValid else { return nil }
        var query = CustomerAnalyticsQuery()
        query.filters = filters
        query.page = page
        query.pageSize = pageSize
        return AnalyticsRequest(session: AnalyticsSession(auth), customerId: customerId, query: query)
    }

    private func loadSummary() async {
        let request = filters
        await summaryResource.load(scope: summaryScope) { try await summaryLoader(customerId, request) }
    }
    private func loadProducts() async {
        let request = filters, page = productPage, size = productPageSize
        await productsResource.load(scope: productsScope) { try await productsLoader(customerId, request, page, size) }
    }
    private func loadHistory() async {
        let request = filters, page = historyPage, size = historyPageSize
        await historyResource.load(scope: historyScope) { try await historyLoader(customerId, request, page, size) }
    }
    private func reload() async {
        async let summary: Void = loadSummary()
        async let products: Void = loadProducts()
        async let history: Void = loadHistory()
        _ = await (summary, products, history)
    }
}

struct AnalyticsFiltersView: View {
    @EnvironmentObject private var i18n: I18nStore
    @Binding var filters: CustomerAnalyticsFilters

    var body: some View {
        Picker(i18n.t("analytics.period"), selection: Binding(get: { filters.period }, set: { preset in
            var next = filters
            next.period = preset
            if preset == .custom {
                if next.start.isEmpty { next.start = ShopClock.dayString(from: ShopClock.monthStart()) }
                if next.end.isEmpty { next.end = ShopClock.dayString(from: Date()) }
            }
            filters = next
        })) {
            ForEach(CustomerAnalyticsPreset.allCases, id: \.self) { preset in
                Text(i18n.t("analytics.period.\(preset.rawValue)")).tag(preset)
            }
        }
        if filters.period == .custom {
            DatePicker(i18n.t("analytics.start"), selection: dateBinding(\.start), displayedComponents: .date)
                .environment(\.timeZone, ShopClock.timeZone)
                .environment(\.calendar, ShopClock.calendar)
            DatePicker(i18n.t("analytics.end"), selection: dateBinding(\.end), displayedComponents: .date)
                .environment(\.timeZone, ShopClock.timeZone)
                .environment(\.calendar, ShopClock.calendar)
            if !filters.isValid { Text(i18n.t("analytics.invalidDates")).foregroundStyle(Theme.danger) }
        }
        Picker(i18n.t("analytics.historicalLevel"), selection: $filters.priceLevel) {
            Text(i18n.t("analytics.allLevels")).tag(nil as CustomerAnalyticsPriceLevel?)
            ForEach(CustomerAnalyticsPriceLevel.allCases, id: \.self) { level in
                Text(i18n.t("analytics.level.\(level.rawValue)")).tag(Optional(level))
            }
        }
        Text(i18n.t("analytics.levelNote")).font(.footnote).foregroundStyle(Theme.muted)
    }

    private func dateBinding(_ keyPath: WritableKeyPath<CustomerAnalyticsFilters, String>) -> Binding<Date> {
        Binding(
            get: { ShopClock.date(fromDayString: filters[keyPath: keyPath]) ?? ShopClock.startOfDay() },
            set: { filters[keyPath: keyPath] = ShopClock.dayString(from: $0) }
        )
    }
}

struct AnalyticsBasisView: View {
    @EnvironmentObject private var i18n: I18nStore
    let profit: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(i18n.t("analytics.basis"))
            Text(i18n.t("analytics.returnsNote"))
            if profit { Text(i18n.t("analytics.costNote")) }
            DisclosureGroup(i18n.t("analytics.reconciliation")) {
                Text(i18n.t("analytics.crmBridge")).padding(.top, Theme.Space.xs)
            }
        }
        .font(.footnote).foregroundStyle(Theme.muted)
    }
}

struct AnalyticsPeriodView: View {
    @EnvironmentObject private var i18n: I18nStore
    let period: CustomerAnalyticsPeriod
    var body: some View {
        Text([i18n.t("analytics.period.\(period.preset.rawValue)"), dates, period.timezone].compactMap { $0 }.joined(separator: " · "))
            .font(.footnote).foregroundStyle(Theme.muted)
    }
    private var dates: String? {
        guard let start = period.start, let end = period.end else { return nil }
        return "\(start.prefix(10)) – \(end.prefix(10))"
    }
}

struct AnalyticsCoverageView: View {
    @EnvironmentObject private var i18n: I18nStore
    let coverage: CustomerAnalyticsHistoryCoverage
    var body: some View {
        if coverage.status != .complete {
            Label(i18n.t("analytics.historyCoverage.\(coverage.status.rawValue)"), systemImage: "info.circle")
                .font(.footnote).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AnalyticsMetricsView: View {
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metrics: CustomerAnalyticsMetrics
    let profit: Bool
    let timezone: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            grid(primary)
            if compact {
                DisclosureGroup(i18n.t("analytics.breakdown")) { grid(revenue).padding(.top, Theme.Space.sm) }
            } else {
                grid(revenue)
            }
            if profit { grid(costs) }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var primary: [(String, String)] {
        [
            ("sales", AppFormat.money(metrics.sales)),
            ("tiresSold", metrics.tiresSold.formatted()),
            ("orders", metrics.orders.formatted()),
            ("averageOrder", AnalyticsDisplay.money(metrics.averageOrder)),
            ("lastOrder", AnalyticsDisplay.date(metrics.lastOrder, timezone: timezone, locale: i18n.language.locale))
        ]
    }
    private var revenue: [(String, String)] {
        [("tireRevenue", metrics.tireRevenue), ("serviceRevenue", metrics.serviceRevenue),
         ("deliveryRevenue", metrics.deliveryRevenue), ("restockingFees", metrics.restockingFees)]
            .map { ($0.0, AppFormat.money($0.1)) }
    }
    private var costs: [(String, String)] {
        [
            ("actualCogs", metrics.actualCogs.map { AppFormat.money($0) } ?? i18n.t("analytics.unavailable")),
            ("bookedCogs", AnalyticsDisplay.money(metrics.bookedCogs)),
            ("grossProfit", metrics.grossProfit.map { AppFormat.money($0) } ?? i18n.t("analytics.unavailable")),
            ("gpPercent", metrics.gpPercent.map { String(format: "%.2f%%", $0) } ?? i18n.t("analytics.unavailable")),
            ("costCoverage", metrics.costCoverage.map { String(format: "%.1f%%", $0 * 100) } ?? i18n.t("analytics.unavailable")),
            ("unverifiedCostUnits", metrics.unverifiedCostUnits?.formatted() ?? "—")
        ]
    }
    private func grid(_ entries: [(String, String)]) -> some View {
        // Keep monetary values together when Dynamic Type needs wider columns.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.adaptive(minimum: 140), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.md) {
            ForEach(entries, id: \.0) { entry in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(i18n.t("analytics.\(entry.0)")).font(.caption).foregroundStyle(Theme.muted)
                    Text(entry.1).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct AnalyticsProductView: View {
    @EnvironmentObject private var i18n: I18nStore
    let product: CustomerAnalyticsProduct
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(product.sku?.nilIfBlank ?? i18n.t("analytics.unknown")).font(.headline)
            LabeledContent(i18n.t("analytics.brand"), value: product.brand?.nilIfBlank ?? i18n.t("analytics.unknown"))
            LabeledContent(i18n.t("analytics.model"), value: product.model?.nilIfBlank ?? i18n.t("analytics.unknown"))
            LabeledContent(i18n.t("analytics.size"), value: product.size?.nilIfBlank ?? i18n.t("analytics.unknown"))
            LabeledContent(i18n.t("analytics.quantity"), value: product.quantity.formatted())
            LabeledContent(i18n.t("analytics.netRevenue"), value: AppFormat.money(product.netRevenue))
            LabeledContent(i18n.t("analytics.averageUnitPrice"), value: AnalyticsDisplay.money(product.averageUnitPrice))
        }
        .font(.subheadline).padding(.vertical, Theme.Space.xs)
    }
}

struct AnalyticsHistoryView: View {
    @EnvironmentObject private var i18n: I18nStore
    let event: CustomerAnalyticsHistoryEvent
    let profit: Bool
    let canViewSales: Bool
    let timezone: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if canViewSales && event.sourceAvailable {
                NavigationLink(value: AppRoute.saleDetail(event.saleId)) { Text(event.ref?.nilIfBlank ?? event.saleId).font(.headline) }
            } else {
                Text(event.ref?.nilIfBlank ?? event.saleId).font(.headline)
            }
            LabeledContent(i18n.t("analytics.date"), value: AnalyticsDisplay.date(event.date, timezone: timezone, locale: i18n.language.locale))
            LabeledContent(i18n.t("analytics.event"), value: i18n.t("analytics.event.\(event.kind.rawValue)"))
            LabeledContent(i18n.t("analytics.historicalLevel"), value: i18n.t("analytics.level.\(event.priceLevel?.rawValue ?? "UNKNOWN")"))
            LabeledContent(i18n.t("analytics.fulfillment"), value: event.fulfillment.map { i18n.t("analytics.fulfillment.\($0)") } ?? i18n.t("analytics.unknown"))
            LabeledContent(i18n.t("analytics.sales"), value: AppFormat.money(event.sales))
            LabeledContent(i18n.t("analytics.tiresSold"), value: event.tiresSold.formatted())
            LabeledContent(i18n.t("analytics.deliveryRevenue"), value: AppFormat.money(event.deliveryRevenue))
            LabeledContent(i18n.t("analytics.restockingFees"), value: AppFormat.money(event.restockingFees))
            if profit { LabeledContent(i18n.t("analytics.bookedCogs"), value: AnalyticsDisplay.money(event.bookedCogs)) }
        }
        .font(.subheadline).padding(.vertical, Theme.Space.xs)
    }
}

struct AnalyticsPaginationView: View {
    @EnvironmentObject private var i18n: I18nStore
    let page: Int
    let pageSize: Int
    let total: Int
    @Binding var selection: Int
    @Binding var size: Int

    private var pages: Int { max(1, Int(ceil(Double(total) / Double(max(1, pageSize))))) }
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Picker(i18n.t("analytics.pageSize"), selection: $size) {
                ForEach([10, 25, 50, 100], id: \.self) { Text(String($0)).tag($0) }
            }
            Text(i18n.t("analytics.page", ["page": page, "pages": pages, "total": total])).font(.caption).foregroundStyle(Theme.muted)
            HStack {
                Button { selection = max(1, page - 1) } label: { Label(i18n.t("analytics.previous"), systemImage: "chevron.left") }
                    .disabled(page <= 1)
                Spacer()
                Button { selection = page + 1 } label: { Label(i18n.t("analytics.next"), systemImage: "chevron.right") }
                    .disabled(page >= pages)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct AnalyticsLoadState: View {
    @EnvironmentObject private var i18n: I18nStore
    let loading: Bool
    let error: String?
    let retry: () async -> Void

    var body: some View {
        if loading { ProgressView(i18n.t("common.loading")) }
        if let error {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(error.isEmpty ? i18n.t("analytics.loadFailed") : error).foregroundStyle(Theme.danger)
                Button(i18n.t("common.retry")) { Task { await retry() } }
            }
        }
    }
}

enum AnalyticsDisplay {
    static func money(_ value: Double?) -> String {
        value.map { AppFormat.money($0) } ?? "—"
    }

    static func date(_ value: String?, timezone: String, locale: Locale) -> String {
        guard let date = AppFormat.date(value) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezone) ?? ShopClock.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct AnalyticsShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
