import SwiftUI
import UIKit

/// Supplier profile page — parity with the web `/suppliers/[id]` page added
/// in backend PR #407. Shows the six summary figures from
/// `GET /api/suppliers/:id` plus four paginated activity tabs
/// (containers / bills / payments / warranty claims).
struct SupplierDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var supplier: SupplierDetail?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: SupplierEditTarget?
    @State private var tab: SupplierDetailTab = .containers
    @State private var paymentTarget: String?

    private var canManage: Bool {
        auth.has("purchasing.manage")
    }

    private var canViewPayments: Bool {
        auth.has("payables.view")
    }

    private var canViewReturns: Bool {
        auth.has("returns.view")
    }

    var body: some View {
        Group {
            if loading && supplier == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, supplier == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let supplier {
                detail(supplier)
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .background(Theme.background)
        .navigationTitle(supplier?.name ?? "Supplier")
        .toolbar {
            if canManage, let supplier {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = SupplierEditTarget(supplier: supplier.asSupplier, id: supplier.id)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit supplier")
                }
            }
        }
        .sheet(item: $editing) { target in
            SupplierEditorView(supplier: target.supplier) {
                editing = nil
                Task { await load() }
            }
        }
        .sheet(item: Binding(
            get: { paymentTarget.map { PaymentSheetTarget(id: $0) } },
            set: { paymentTarget = $0?.id }
        )) { target in
            SupplierPaymentDetailSheet(id: target.id, canReverse: auth.has("payables.pay")) {}
        }
        .task {
            if supplier == nil { await load() }
        }
    }

    private func detail(_ supplier: SupplierDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(supplier.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.text)
                    Text(subline(supplier))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                StatGrid(stats: [
                    ("Owed to supplier", AppFormat.money(supplier.summary.supplierOpenAP)),
                    ("Other container costs", AppFormat.money(supplier.summary.otherOpenAP)),
                    ("Paid to supplier", AppFormat.money(supplier.summary.supplierPaid)),
                    ("Landed value received", AppFormat.money(supplier.summary.landedValue)),
                    ("Containers", "\(supplier.summary.receivedContainerCount) / \(supplier.summary.containerCount)"),
                    ("Tires received", "\(supplier.summary.tiresReceived)")
                ])

                SupplierInfoSection(rows: [
                    ("Contact", supplier.contactName ?? "-"),
                    ("Phone", AppFormat.phone(supplier.phone).nilIfBlank ?? "-"),
                    ("Email", supplier.email ?? "-"),
                    ("Address", supplier.address ?? "-"),
                    ("Notes", supplier.notes ?? "-"),
                    ("Default DDP", supplier.defaultDDP == true ? "Yes" : "No"),
                    ("First order", supplier.summary.firstOrderAt.map(AppFormat.shortDate) ?? "-"),
                    ("Last order", supplier.summary.lastOrderAt.map(AppFormat.shortDate) ?? "-")
                ])

                Picker("Section", selection: $tab) {
                    Text("Containers").tag(SupplierDetailTab.containers)
                    Text("Bills").tag(SupplierDetailTab.costs)
                    if canViewPayments {
                        Text("Payments").tag(SupplierDetailTab.payments)
                    }
                    if canViewReturns {
                        Text("Warranty claims").tag(SupplierDetailTab.returns)
                    }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .containers:
                    SupplierContainersTab(supplierId: id)
                case .costs:
                    SupplierCostsTab(supplierId: id)
                case .payments:
                    SupplierPaymentsTab(supplierId: id) { paymentId in
                        paymentTarget = paymentId
                    }
                case .returns:
                    SupplierReturnsTab(supplierId: id)
                }
            }
            .padding(Theme.Space.lg)
        }
        .refreshable {
            await load()
        }
    }

    private func subline(_ supplier: SupplierDetail) -> String {
        [supplier.country, supplier.currency]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            supplier = try await SuppliersAPI().get(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load supplier."
        }
        loading = false
    }
}

private enum SupplierDetailTab: String, CaseIterable, Identifiable {
    case containers
    case costs
    case payments
    case returns

    var id: String { rawValue }
}

private struct SupplierEditTarget: Identifiable {
    let supplier: Supplier?
    let id: String
}

private struct PaymentSheetTarget: Identifiable {
    let id: String
}

private extension SupplierDetail {
    var asSupplier: Supplier {
        Supplier(
            id: id,
            name: name,
            contactName: contactName,
            phone: phone,
            email: email,
            country: country,
            address: address,
            currency: currency,
            defaultDDP: defaultDDP,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            count: nil
        )
    }
}

private enum SupplierDetailLabels {
    static func costCategory(_ value: String) -> String {
        switch value {
        case "DOWN_PAYMENT": return "Down payment"
        case "BALANCE_PAYMENT": return "Balance payment"
        case "SUPPLIER_OTHER": return "Supplier other"
        case "FREIGHT": return "Freight"
        case "DUTY": return "Duty"
        case "TRUCKING": return "Trucking"
        case "LABOR": return "Labor"
        case "OTHER": return "Other"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func costStatus(_ value: String) -> String {
        switch value {
        case "DUE": return "Due"
        case "PAID": return "Paid"
        case "VOID": return "Void"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func containerStatus(_ value: String) -> String {
        switch value {
        case "DRAFT": return "Draft"
        case "ORDERED": return "Ordered"
        case "IN_TRANSIT": return "In transit"
        case "ARRIVED": return "Arrived"
        case "RECEIVED": return "Received"
        case "CANCELLED": return "Cancelled"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func returnType(_ value: String) -> String {
        switch value {
        case "RETURN": return "Return"
        case "EXCHANGE": return "Exchange"
        case "WARRANTY": return "Warranty"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func returnStatus(_ value: String) -> String {
        switch value {
        case "DRAFT": return "Draft"
        case "POSTED": return "Posted"
        case "VOIDED": return "Voided"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func warrantyDisposition(_ value: String?) -> String {
        switch value {
        case "SUPPLIER_CLAIM": return "Supplier claim"
        case "WRITE_OFF": return "Write off"
        default: return "-"
        }
    }
}

private struct SupplierInfoSection: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Supplier info")
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                        Text(row.0)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(row.1)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, Theme.Space.sm)
                    Divider()
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }
}

private struct SupplierEmptyInlineView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(Theme.Space.lg)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

struct PagedFooter: View {
    let page: Int
    let totalPages: Int
    let total: Int
    let label: String
    let loading: Bool
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Button {
                onPrev()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .disabled(page <= 1 || loading)

            VStack(spacing: 2) {
                Text("Page \(page) of \(totalPages)")
                    .font(.footnote)
                    .fontWeight(.semibold)
                Text("\(total) \(label)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)

            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(page >= totalPages || loading)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.card)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
    }
}

// MARK: - Containers tab

private struct SupplierContainersTab: View {
    let supplierId: String

    private let pageSize = 25

    @State private var data: Paged<SupplierContainerRow>?
    @State private var page = 1
    @State private var loading = false
    @State private var errorMessage: String?

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading && data == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, data == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let data, data.items.isEmpty {
                SupplierEmptyInlineView(text: "No activity yet.")
            } else if let data {
                VStack(spacing: 0) {
                    ForEach(data.items) { row in
                        NavigationLink(value: AppRoute.containerDetail(row.id)) {
                            SupplierContainerRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                LoadingView(label: "Loading...")
            }

            if let data, data.total > 0 {
                PagedFooter(
                    page: data.page,
                    totalPages: totalPages,
                    total: data.total,
                    label: "containers",
                    loading: loading
                ) {
                    page = max(1, page - 1)
                    Task { await load() }
                } onNext: {
                    page = min(totalPages, page + 1)
                    Task { await load() }
                }
            }
        }
        .task {
            if data == nil { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await SuppliersAPI().containers(id: supplierId, page: page, pageSize: pageSize)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load containers."
        }
        loading = false
    }
}

private struct SupplierContainerRowView: View {
    let row: SupplierContainerRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.ref ?? String(row.id.prefix(8)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(SupplierDetailLabels.containerStatus(row.status))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 4)
                    .foregroundStyle(Theme.primary)
                    .background(Theme.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            HStack {
                Text([
                    row.reference,
                    row.bolNumber,
                    row.location
                ].compactMap { $0?.nilIfBlank }.joined(separator: " - "))
                Spacer()
                Text("\(row.tireQty) tires")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            HStack {
                Text([
                    row.orderedAt.map { "Ordered \(AppFormat.shortDate($0))" },
                    row.etaAt.map { "ETA \(AppFormat.shortDate($0))" },
                    row.receivedAt.map { "Received \(AppFormat.shortDate($0))" }
                ].compactMap { $0 }.joined(separator: " - "))
                Spacer()
                if row.isDDP {
                    Text("DDP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.primary)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }
}

// MARK: - Bills (costs) tab

private struct SupplierCostsTab: View {
    let supplierId: String

    private let pageSize = 25
    private let scopes: [(String, String)] = [
        ("", "All costs"),
        ("supplier", "Owed to supplier"),
        ("other", "Other costs")
    ]
    private let statuses: [(String, String)] = [
        ("", "All statuses"),
        ("DUE", "Due"),
        ("PAID", "Paid"),
        ("VOID", "Void")
    ]

    @State private var data: Paged<SupplierCostRow>?
    @State private var page = 1
    @State private var scope = ""
    @State private var status = ""
    @State private var loading = false
    @State private var errorMessage: String?

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(scopes, id: \.0) { option in
                        chip(value: option.0, selected: $scope, label: option.1)
                    }
                }
            }
            .padding(.bottom, Theme.Space.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(statuses, id: \.0) { option in
                        chip(value: option.0, selected: $status, label: option.1)
                    }
                }
            }
            .padding(.bottom, Theme.Space.sm)

            if loading && data == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, data == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let data, data.items.isEmpty {
                SupplierEmptyInlineView(text: "No activity yet.")
            } else if let data {
                VStack(spacing: 0) {
                    ForEach(data.items) { cost in
                        SupplierCostRowView(cost: cost)
                        Divider()
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                LoadingView(label: "Loading...")
            }

            if let data, data.total > 0 {
                PagedFooter(
                    page: data.page,
                    totalPages: totalPages,
                    total: data.total,
                    label: "bills",
                    loading: loading
                ) {
                    page = max(1, page - 1)
                    Task { await load() }
                } onNext: {
                    page = min(totalPages, page + 1)
                    Task { await load() }
                }
            }
        }
        .task {
            if data == nil { await load() }
        }
    }

    private func chip(value: String, selected: Binding<String>, label: String) -> some View {
        Button {
            guard selected.wrappedValue != value else { return }
            selected.wrappedValue = value
            page = 1
            Task { await load() }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 7)
                .background(selected.wrappedValue == value ? Theme.primary : Theme.card)
                .foregroundStyle(selected.wrappedValue == value ? Theme.primaryText : Theme.text)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(selected.wrappedValue == value ? Theme.primary : Theme.border)
                )
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await SuppliersAPI().costs(
                id: supplierId,
                page: page,
                pageSize: pageSize,
                scope: scope.nilIfBlank,
                status: status.nilIfBlank
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load bills."
        }
        loading = false
    }
}

private struct SupplierCostRowView: View {
    let cost: SupplierCostRow

    var body: some View {
        Group {
            if let container = cost.container {
                NavigationLink(value: AppRoute.containerDetail(container.id)) {
                    content(containerLabel: container.ref ?? String(container.id.prefix(8)))
                }
                .buttonStyle(.plain)
            } else {
                content(containerLabel: "-")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .opacity(cost.status == "VOID" ? 0.45 : 1)
    }

    private func content(containerLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(SupplierDetailLabels.costCategory(cost.category))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(AppFormat.money(cost.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
            }

            HStack {
                Text("\(SupplierDetailLabels.costStatus(cost.status)) - \(cost.vendor ?? "No vendor")")
                Spacer()
                Text("Paid \(AppFormat.money(cost.amountPaid))")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            HStack {
                Text([
                    cost.description,
                    cost.reference,
                    cost.dueAt.map { "Due \(AppFormat.shortDate($0))" },
                    cost.paidAt.map { "Paid \(AppFormat.shortDate($0))" }
                ].compactMap { $0?.nilIfBlank }.joined(separator: " - "))
                Spacer()
                Text("Container \(containerLabel)")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Payments tab

private struct SupplierPaymentsTab: View {
    let supplierId: String
    let onOpenPayment: (String) -> Void

    private let pageSize = 25

    @State private var data: Paged<SupplierPaymentRow>?
    @State private var page = 1
    @State private var loading = false
    @State private var errorMessage: String?

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading && data == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, data == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let data, data.items.isEmpty {
                SupplierEmptyInlineView(text: "No activity yet.")
            } else if let data {
                VStack(spacing: 0) {
                    ForEach(data.items) { payment in
                        Button {
                            onOpenPayment(payment.id)
                        } label: {
                            SupplierPaymentRowView(payment: payment)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                LoadingView(label: "Loading...")
            }

            if let data, data.total > 0 {
                PagedFooter(
                    page: data.page,
                    totalPages: totalPages,
                    total: data.total,
                    label: "payments",
                    loading: loading
                ) {
                    page = max(1, page - 1)
                    Task { await load() }
                } onNext: {
                    page = min(totalPages, page + 1)
                    Task { await load() }
                }
            }
        }
        .task {
            if data == nil { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await SuppliersAPI().payments(id: supplierId, page: page, pageSize: pageSize)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load payments."
        }
        loading = false
    }
}

private struct SupplierPaymentRowView: View {
    let payment: SupplierPaymentRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(payment.ref)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(payment.status)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 4)
                    .foregroundStyle(payment.status == "POSTED" ? Theme.success : Theme.danger)
                    .background((payment.status == "POSTED" ? Theme.success : Theme.danger).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            HStack {
                Text(payment.vendor ?? "No vendor")
                Spacer()
                Text("Total \(AppFormat.money(payment.total))")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            HStack {
                Text([
                    payment.fundingAccount.map { "\($0.name) (\($0.code))" },
                    payment.reference,
                    AppFormat.shortDate(payment.paidAt)
                ].compactMap { $0?.nilIfBlank }.joined(separator: " - "))
                Spacer()
                Text("Applied here \(AppFormat.money(payment.appliedToSupplier))")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            if !payment.lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(payment.lines) { line in
                        Text([
                            SupplierDetailLabels.costCategory(line.containerCost.category),
                            line.containerCost.container.map { $0.ref ?? String($0.id.prefix(8)) },
                            AppFormat.money(line.amount)
                        ].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .opacity(payment.status == "REVERSED" ? 0.45 : 1)
    }
}

// MARK: - Warranty claims (returns) tab

private struct SupplierReturnsTab: View {
    let supplierId: String

    private let pageSize = 25

    @State private var data: Paged<SupplierReturnRow>?
    @State private var page = 1
    @State private var loading = false
    @State private var errorMessage: String?

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading && data == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, data == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let data, data.items.isEmpty {
                SupplierEmptyInlineView(text: "No activity yet.")
            } else if let data {
                VStack(spacing: 0) {
                    ForEach(data.items) { record in
                        NavigationLink(value: AppRoute.returnDetail(record.id)) {
                            SupplierReturnRowView(record: record)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                LoadingView(label: "Loading...")
            }

            if let data, data.total > 0 {
                PagedFooter(
                    page: data.page,
                    totalPages: totalPages,
                    total: data.total,
                    label: "claims",
                    loading: loading
                ) {
                    page = max(1, page - 1)
                    Task { await load() }
                } onNext: {
                    page = min(totalPages, page + 1)
                    Task { await load() }
                }
            }
        }
        .task {
            if data == nil { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await SuppliersAPI().returns(id: supplierId, page: page, pageSize: pageSize)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load warranty claims."
        }
        loading = false
    }
}

private struct SupplierReturnRowView: View {
    let record: SupplierReturnRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.ref ?? String(record.id.prefix(8)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(AppFormat.money(record.refundTotal))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
            }

            HStack {
                Text("\(SupplierDetailLabels.returnType(record.type)) - \(SupplierDetailLabels.returnStatus(record.status))")
                Spacer()
                Text("\(record.count?.lines ?? 0) lines")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            HStack {
                Text([
                    SupplierDetailLabels.warrantyDisposition(record.warrantyDisposition),
                    record.sale.ref.map { "Sale \($0)" },
                    AppFormat.shortDate(record.createdAt)
                ].compactMap { $0?.nilIfBlank }.joined(separator: " - "))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .opacity(record.status == "VOIDED" ? 0.45 : 1)
    }
}
