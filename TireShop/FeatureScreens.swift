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

struct InventoryListNativeView: View {
    var selectForQuote = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var quote: QuoteStore

    var body: some View {
        AsyncContentView(load: { try await InventoryAPI().listSkus(pageSize: 50) }) { page in
            List(page.items) { sku in
                if selectForQuote {
                    Button {
                        quote.addLine(
                            itemType: "SKU",
                            itemId: sku.id,
                            description: "\(sku.brand) \(sku.model) \(sku.size) (\(sku.position.replacingOccurrences(of: "_", with: "-")))",
                            unitPrice: Double(sku.priceRetail) ?? 0
                        )
                        dismiss()
                    } label: {
                        skuRow(sku)
                    }
                } else {
                    NavigationLink {
                        SkuDetailNativeView(sku: sku)
                    } label: {
                        skuRow(sku)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func skuRow(_ sku: TireSku) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(sku.brand) \(sku.model)")
                .fontWeight(.semibold)
            Text("\(sku.size) - \(sku.sku)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text("\(sku.inventory.reduce(0) { $0 + $1.qtyOnHand }) on hand")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct SkuManagementNativeView: View {
    var body: some View {
        InventoryListNativeView()
    }
}

struct SalesListNativeView: View {
    var body: some View {
        AsyncContentView(load: { try await SalesAPI().list(pageSize: 50) }) { page in
            List(page.items) { sale in
                NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                    RowLine(
                        title: "\(sale.ref ?? "Sale") - \(sale.customer.name)",
                        subtitle: "\(sale.status) - \(AppFormat.dateTime(sale.createdAt))",
                        trailing: AppFormat.money(sale.total)
                    )
                }
            }
            .listStyle(.plain)
        }
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
