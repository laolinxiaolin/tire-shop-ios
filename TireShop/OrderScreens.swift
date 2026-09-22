import SwiftUI

// Web Orders — storefront-placed orders an operator confirms into a Sale.
// Ported from apps/web/app/orders/{page.tsx,[id]/page.tsx}.

@MainActor
final class OrdersListStore: ObservableObject {
    typealias Loader = (String, Int, Int) async throws -> Paged<Order>
    @Published private(set) var items: [Order] = []
    @Published private(set) var total = 0
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    private let loader: Loader
    private let pageSize: Int
    private var status = ""
    private var page = 0
    private var generation = 0
    private var failedReload = false

    var hasMore: Bool { page > 0 && page * pageSize < total }

    init(pageSize: Int = 50, loader: @escaping Loader = { status, page, size in
        try await OrdersAPI().list(status: status, page: page, pageSize: size)
    }) {
        self.pageSize = pageSize
        self.loader = loader
    }

    func reload(status: String) async {
        generation += 1
        if self.status != status {
            items = []
            total = 0
            page = 0
            loaded = false
        }
        self.status = status
        await request(page: 1, replacing: true)
    }

    func loadMore() async {
        guard !loading, hasMore, !failedReload else { return }
        await request(page: page + 1, replacing: false)
    }

    func retry() async {
        guard !loading else { return }
        if failedReload || page == 0 {
            await reload(status: status)
        } else {
            await loadMore()
        }
    }

    private func request(page requestedPage: Int, replacing: Bool) async {
        let generation = generation
        let status = status
        loading = true
        errorMessage = nil
        defer { if generation == self.generation { loading = false; loaded = true } }
        do {
            let result = try await loader(status, requestedPage, pageSize)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            var merged = replacing ? [] : items
            for order in result.items {
                if let index = merged.firstIndex(where: { $0.id == order.id }) {
                    merged[index] = order
                } else {
                    merged.append(order)
                }
            }
            items = merged
            total = result.total
            page = requestedPage
            failedReload = false
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            failedReload = replacing
        }
    }
}

struct OrdersListNativeView: View {
    @State private var status = "PENDING"
    @StateObject private var store = OrdersListStore()
    private let statuses = ["PENDING", "CONFIRMED", "CANCELLED"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $status) {
                ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Space.md)

            if !store.loaded {
                LoadingView(label: "Loading...")
            } else {
                List {
                    ForEach(store.items) { order in
                        NavigationLink(value: AppRoute.orderDetail(order.id)) {
                            RowLine(
                                title: "\(order.ref ?? "Order") - \(order.customer.company ?? order.customer.name)",
                                subtitle: "\(order.fulfillment.capitalized) - \(AppFormat.dateTime(order.createdAt))",
                                trailing: AppFormat.money(order.total)
                            )
                        }
                    }
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(Theme.danger)
                        Button("Retry") { Task { await store.retry() } }
                            .disabled(store.loading)
                    } else if store.items.isEmpty && !store.loading {
                        Text("No \(status.lowercased()) orders.").foregroundStyle(Theme.muted)
                    }
                    if store.loading {
                        ProgressView("Loading...")
                    } else if store.hasMore && store.errorMessage == nil {
                        Button("Load more") { Task { await store.loadMore() } }
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.reload(status: status) }
            }
        }
        .background(Theme.background)
        .task(id: status) { await store.reload(status: status) }
    }
}

struct OrderDetailNativeView: View {
    let id: String

    @State private var order: Order?
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let order {
                content(order)
            } else {
                RetryView(message: errorMessage ?? "Order not found.") { Task { await load() } }
            }
        }
        .navigationTitle(order?.ref ?? "Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
    }

    private func content(_ order: Order) -> some View {
        List {
            Section {
                RowLine(title: "Status", subtitle: nil, trailing: order.status.capitalized)
                RowLine(title: "Customer", subtitle: order.customer.company, trailing: order.customer.name)
                RowLine(title: "Warehouse", subtitle: nil, trailing: order.location)
                if let email = order.customerUser?.email {
                    RowLine(title: "Placed by", subtitle: nil, trailing: email)
                }
                RowLine(title: "Fulfillment", subtitle: order.deliveryAddress, trailing: order.fulfillment.capitalized)
                if let notes = order.notes, !notes.isEmpty {
                    RowLine(title: "Notes", subtitle: notes, trailing: nil)
                }
            }

            Section("Lines") {
                ForEach(order.lines) { line in
                    RowLine(
                        title: line.description,
                        subtitle: "Qty \(line.qty) @ \(AppFormat.money(line.unitPrice))",
                        trailing: AppFormat.money(line.lineTotal)
                    )
                }
                RowLine(title: "Subtotal", subtitle: nil, trailing: AppFormat.money(order.subtotal))
                RowLine(title: "Total", subtitle: nil, trailing: AppFormat.money(order.total))
            }

            if order.status == "PENDING" {
                Section {
                    PrimaryButton(title: "Confirm into Sale", loading: working) {
                        Task { await act(confirm: true) }
                    }
                    SecondaryButton(title: "Cancel order") {
                        Task { await act(confirm: false) }
                    }
                }
            } else if let sale = order.sale ?? order.saleId.map({ OrderSaleRef(id: $0, ref: nil) }) {
                Section {
                    NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                        RowLine(title: "View Sale", subtitle: nil, trailing: sale.ref)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @MainActor
    private func load() async {
        do {
            order = try await OrdersAPI().get(id: id)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load order."
        }
        loaded = true
    }

    @MainActor
    private func act(confirm: Bool) async {
        working = true
        errorMessage = nil
        do {
            order = confirm ? try await OrdersAPI().confirm(id: id) : try await OrdersAPI().cancel(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Action failed."
        }
        working = false
    }
}
