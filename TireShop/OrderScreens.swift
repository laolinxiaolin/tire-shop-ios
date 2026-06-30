import SwiftUI

// Web Orders — storefront-placed orders an operator confirms into a Sale.
// Ported from apps/web/app/orders/{page.tsx,[id]/page.tsx}.

struct OrdersListNativeView: View {
    @State private var status: String = "PENDING"
    @State private var page: Paged<Order>?
    @State private var loaded = false
    @State private var errorMessage: String?

    private let statuses = ["PENDING", "CONFIRMED", "CANCELLED"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $status) {
                ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Space.md)

            Group {
                if !loaded {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, page == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let page, page.items.isEmpty {
                    EmptyStateView(text: "No \(status.lowercased()) orders.")
                } else if let page {
                    List(page.items) { order in
                        NavigationLink(value: AppRoute.orderDetail(order.id)) {
                            RowLine(
                                title: "\(order.ref ?? "Order") - \(order.customer.company ?? order.customer.name)",
                                subtitle: "\(order.fulfillment.capitalized) - \(AppFormat.dateTime(order.createdAt))",
                                trailing: AppFormat.money(order.total)
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(Theme.background)
        .task(id: status) { await load() }
    }

    @MainActor
    private func load() async {
        do {
            page = try await OrdersAPI().list(status: status, pageSize: 50)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load orders."
        }
        loaded = true
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
