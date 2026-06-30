import SwiftUI
import UIKit

private enum VendorLabels {
    static let categories: [(VendorCategory, String)] = [
        ("TRUCKING", "Trucking"),
        ("FREIGHT", "Freight"),
        ("CUSTOMS", "Customs"),
        ("LANDLORD", "Landlord"),
        ("UTILITIES", "Utilities"),
        ("SUPPLIES", "Supplies"),
        ("LABOR", "Labor"),
        ("SERVICES", "Services"),
        ("OTHER", "Other")
    ]

    static func category(_ value: VendorCategory?) -> String {
        guard let value else { return "Uncategorized" }
        return categories.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func plain(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct VendorEditorTarget: Identifiable {
    let vendor: VendorDetail?
    let id: String
}

struct VendorsListNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    private let pageSize = 25

    @State private var q = ""
    @State private var category = ""
    @State private var activeFilter = ""
    @State private var page = 1
    @State private var data: Paged<Vendor>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: VendorEditorTarget?

    private var canManage: Bool {
        auth.has("vendors.manage")
    }

    private var activeQuery: Bool? {
        switch activeFilter {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            Group {
                if loading && data == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: "No vendors found.")
                } else if let data {
                    List(data.items) { vendor in
                        NavigationLink(value: AppRoute.vendorDetail(vendor.id)) {
                            VendorListRow(vendor: vendor)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    LoadingView(label: "Loading...")
                }
            }

            if let data, data.total > 0 {
                pagination(data)
            }
        }
        .background(Theme.background)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = VendorEditorTarget(vendor: nil, id: UUID().uuidString)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New vendor")
                }
            }
        }
        .sheet(item: $editing) { target in
            VendorEditorView(vendor: target.vendor) {
                editing = nil
                page = 1
                Task { await load() }
            }
        }
        .task {
            if data == nil { await load() }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            AppTextField(label: "Search", text: $q, placeholder: "Name, contact, email, phone")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    chip(value: "", selected: $category, label: "All")
                    ForEach(VendorLabels.categories, id: \.0) { option in
                        chip(value: option.0, selected: $category, label: option.1)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    chip(value: "", selected: $activeFilter, label: "Any status")
                    chip(value: "true", selected: $activeFilter, label: "Active")
                    chip(value: "false", selected: $activeFilter, label: "Inactive")
                }
            }

            HStack(spacing: Theme.Space.sm) {
                SecondaryButton(title: "Reset") {
                    q = ""
                    category = ""
                    activeFilter = ""
                    page = 1
                    Task { await load() }
                }
                PrimaryButton(title: "Search", loading: loading, disabled: loading) {
                    page = 1
                    Task { await load() }
                }
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
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

    private func pagination(_ data: Paged<Vendor>) -> some View {
        HStack(spacing: Theme.Space.md) {
            Button {
                page = max(1, page - 1)
                Task { await load() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .disabled(page <= 1 || loading)

            VStack(spacing: 2) {
                Text("Page \(data.page) of \(totalPages)")
                    .font(.footnote)
                    .fontWeight(.semibold)
                Text("\(data.total) vendors")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)

            Button {
                page = min(totalPages, page + 1)
                Task { await load() }
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

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            data = try await VendorsAPI().list(
                q: q.nilIfBlank,
                category: category.nilIfBlank,
                active: activeQuery,
                page: page,
                pageSize: pageSize
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load vendors."
        }
        loading = false
    }
}

private struct VendorListRow: View {
    let vendor: Vendor

    private var contactLine: String {
        let values = [
            vendor.contactName,
            vendor.phone.map(AppFormat.phone),
            vendor.email
        ].compactMap { $0?.nilIfBlank }
        return values.joined(separator: " - ")
    }

    private var countsLine: String? {
        guard let counts = vendor.counts else { return nil }
        return "Costs \(counts.costs) - Expenses \(counts.expenses) - Refunds \(counts.refunds)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(vendor.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                VendorStatusBadge(active: vendor.active)
            }

            Text(VendorLabels.category(vendor.category))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            if !contactLine.isEmpty {
                Text(contactLine)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            if let countsLine {
                Text(countsLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct VendorStatusBadge: View {
    let active: Bool

    var body: some View {
        Text(active ? "Active" : "Inactive")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 4)
            .foregroundStyle(active ? Theme.success : Theme.muted)
            .background((active ? Theme.success : Theme.muted).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

struct VendorDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var vendor: VendorDetail?
    @State private var loading = false
    @State private var actionLoading = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var editing: VendorEditorTarget?
    @State private var showingRefund = false
    @State private var confirmDeactivate = false
    @State private var reverseTarget: VendorRefundRecord?

    private var canManage: Bool {
        auth.has("vendors.manage")
    }

    private var canPay: Bool {
        auth.has("payables.pay")
    }

    var body: some View {
        Group {
            if loading && vendor == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, vendor == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let vendor {
                detail(vendor)
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .background(Theme.background)
        .navigationTitle(vendor?.name ?? "Vendor")
        .toolbar {
            if canManage, let vendor {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = VendorEditorTarget(vendor: vendor, id: vendor.id)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit vendor")
                }
            }
        }
        .sheet(item: $editing) { target in
            VendorEditorView(vendor: target.vendor) {
                editing = nil
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingRefund) {
            VendorRefundEditorView(vendorId: id) {
                showingRefund = false
                Task { await load() }
            }
        }
        .alert("Deactivate vendor?", isPresented: $confirmDeactivate) {
            Button("Cancel", role: .cancel) {}
            Button("Deactivate", role: .destructive) {
                Task { await deactivate() }
            }
        } message: {
            Text("This keeps the vendor history and hides it from active use.")
        }
        .alert("Reverse refund?", isPresented: Binding(
            get: { reverseTarget != nil },
            set: { if !$0 { reverseTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { reverseTarget = nil }
            Button("Reverse", role: .destructive) {
                Task { await reverseRefund() }
            }
        } message: {
            Text("This will reverse the selected vendor refund.")
        }
        .task {
            if vendor == nil { await load() }
        }
    }

    private func detail(_ vendor: VendorDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text(vendor.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.text)
                        VendorStatusBadge(active: vendor.active)
                    }
                    Text(VendorLabels.category(vendor.category))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                StatGrid(stats: [
                    ("Open A/P", AppFormat.money(vendor.summary.openAP)),
                    ("Paid out", AppFormat.money(vendor.summary.paidOut)),
                    ("Refunds", AppFormat.money(vendor.summary.refunds)),
                    ("Net spend", AppFormat.money(vendor.summary.netSpend))
                ])

                if canPay || (canManage && vendor.active) {
                    VStack(spacing: Theme.Space.sm) {
                        if canPay {
                            PrimaryButton(title: "Record refund", loading: actionLoading, disabled: actionLoading) {
                                showingRefund = true
                            }
                        }

                        if canManage && vendor.active {
                            SecondaryButton(title: "Deactivate vendor", disabled: actionLoading) {
                                confirmDeactivate = true
                            }
                        }
                    }
                }

                if let actionError {
                    Text(actionError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                VendorInfoSection(rows: [
                    ("Contact", vendor.contactName ?? "-"),
                    ("Phone", AppFormat.phone(vendor.phone).nilIfBlank ?? "-"),
                    ("Email", vendor.email ?? "-"),
                    ("Address", vendor.address ?? "-"),
                    ("Notes", vendor.notes ?? "-")
                ])

                SectionHeader("Recent costs")
                if vendor.recentCosts.isEmpty {
                    VendorEmptyInlineView(text: "No recent costs.")
                } else {
                    VendorCostList(costs: vendor.recentCosts)
                }

                SectionHeader("Recent expenses")
                if vendor.recentExpenses.isEmpty {
                    VendorEmptyInlineView(text: "No recent expenses.")
                } else {
                    VendorExpenseList(expenses: vendor.recentExpenses)
                }

                SectionHeader("Refund history")
                if vendor.recentRefunds.isEmpty {
                    VendorEmptyInlineView(text: "No refunds yet.")
                } else {
                    VendorRefundList(refunds: vendor.recentRefunds, canReverse: canPay) { refund in
                        reverseTarget = refund
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
        .refreshable {
            await load()
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        actionError = nil
        do {
            vendor = try await VendorsAPI().get(id: id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load vendor."
        }
        loading = false
    }

    @MainActor
    private func deactivate() async {
        guard let vendor else { return }
        actionLoading = true
        actionError = nil
        do {
            _ = try await VendorsAPI().update(
                id: vendor.id,
                body: VendorSaveInput(
                    name: vendor.name,
                    category: vendor.category,
                    contactName: vendor.contactName,
                    phone: vendor.phone,
                    email: vendor.email,
                    address: vendor.address,
                    notes: vendor.notes,
                    active: false,
                    encodeNulls: true
                )
            )
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not deactivate vendor."
        }
        actionLoading = false
    }

    @MainActor
    private func reverseRefund() async {
        guard let target = reverseTarget else { return }
        actionLoading = true
        actionError = nil
        do {
            _ = try await VendorsAPI().reverseRefund(id: target.id)
            reverseTarget = nil
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not reverse refund."
        }
        actionLoading = false
    }
}

private struct VendorInfoSection: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader("Vendor info")
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

private struct VendorEmptyInlineView: View {
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

private struct VendorCostList: View {
    let costs: [VendorRecentCost]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(costs) { cost in
                VendorCostRow(cost: cost)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct VendorCostRow: View {
    let cost: VendorRecentCost

    var body: some View {
        Group {
            if let container = cost.container {
                NavigationLink(value: AppRoute.containerDetail(container.id)) {
                    content(containerLabel: container.ref ?? String(container.id.prefix(8)))
                }
            } else {
                content(containerLabel: "-")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private func content(containerLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(containerLabel)
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
                Text("\(VendorLabels.plain(cost.category)) - \(VendorLabels.plain(cost.status))")
                Spacer()
                Text("Paid \(AppFormat.money(cost.amountPaid))")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            HStack {
                Text(cost.description ?? "No description")
                Spacer()
                Text(AppFormat.shortDate(cost.createdAt))
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }
}

private struct VendorExpenseList: View {
    let expenses: [VendorRecentExpense]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(expenses) { expense in
                RowLine(
                    title: expense.expenseCode,
                    subtitle: [expense.reference, AppFormat.shortDate(expense.date)].compactMap { $0?.nilIfBlank }.joined(separator: " - "),
                    trailing: AppFormat.money(expense.amount)
                )
                .opacity(expense.reversedAt == nil ? 1 : 0.45)
                .strikethrough(expense.reversedAt != nil)
                .padding(.horizontal, Theme.Space.md)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct VendorRefundList: View {
    let refunds: [VendorRefundRecord]
    let canReverse: Bool
    let onReverse: (VendorRefundRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(refunds) { refund in
                HStack(alignment: .center, spacing: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(refund.ref)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.text)

                        Text([
                            AppFormat.shortDate(refund.date),
                            "Deposit \(refund.depositToCode)",
                            "Credit \(refund.creditCode)"
                        ].joined(separator: " - "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)

                        if let reference = refund.reference, !reference.isEmpty {
                            Text(reference)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        Text(AppFormat.money(refund.amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if refund.reversedAt != nil {
                            Text("Reversed")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        } else if canReverse {
                            Button("Reverse") {
                                onReverse(refund)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .opacity(refund.reversedAt == nil ? 1 : 0.45)
                .strikethrough(refund.reversedAt != nil)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                Divider()
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

struct VendorEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let vendor: VendorDetail?
    let onSaved: () -> Void

    @State private var name: String
    @State private var category: VendorCategory
    @State private var contactName: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var notes: String
    @State private var active: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        vendor != nil
    }

    init(vendor: VendorDetail?, onSaved: @escaping () -> Void) {
        self.vendor = vendor
        self.onSaved = onSaved
        _name = State(initialValue: vendor?.name ?? "")
        _category = State(initialValue: vendor?.category ?? "")
        _contactName = State(initialValue: vendor?.contactName ?? "")
        _phone = State(initialValue: vendor?.phone ?? "")
        _email = State(initialValue: vendor?.email ?? "")
        _address = State(initialValue: vendor?.address ?? "")
        _notes = State(initialValue: vendor?.notes ?? "")
        _active = State(initialValue: vendor?.active ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vendor") {
                    AppTextField(label: "Name", text: $name, placeholder: "Vendor name")

                    Picker("Category", selection: $category) {
                        Text("Uncategorized").tag("")
                        ForEach(VendorLabels.categories, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }

                    AppTextField(label: "Contact", text: $contactName, textContentType: .name)
                    AppTextField(label: "Phone", text: $phone, keyboardType: .phonePad, textContentType: .telephoneNumber)
                    AppTextField(label: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
                    AppTextField(label: "Address", text: $address, textContentType: .fullStreetAddress)
                    Toggle("Active", isOn: $active)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Vendor" : "New Vendor")
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

        let input = VendorSaveInput(
            name: cleanName,
            category: category.nilIfBlank,
            contactName: contactName.nilIfBlank,
            phone: phone.nilIfBlank,
            email: email.nilIfBlank,
            address: address.nilIfBlank,
            notes: notes.nilIfBlank,
            active: active,
            encodeNulls: isEditing
        )

        do {
            if let vendor {
                _ = try await VendorsAPI().update(id: vendor.id, body: input)
            } else {
                _ = try await VendorsAPI().create(input)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save vendor."
        }

        saving = false
    }
}

struct VendorRefundEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let vendorId: String
    let onSaved: () -> Void

    @State private var cashAccounts: [CashAccount] = []
    @State private var expenseAccounts: [ExpenseAccount] = []
    @State private var amount = ""
    @State private var depositToCode = ""
    @State private var creditCode = ""
    @State private var reference = ""
    @State private var note = ""
    @State private var loadingAccounts = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Refund") {
                    Text("Record money received back from a vendor and offset it against an expense account.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)

                    AppTextField(label: "Amount", text: $amount, keyboardType: .decimalPad)

                    Picker("Deposit to", selection: $depositToCode) {
                        ForEach(cashAccounts) { account in
                            Text("\(account.code) - \(account.name)").tag(account.code)
                        }
                    }

                    Picker("Offset account", selection: $creditCode) {
                        Text("Select account").tag("")
                        ForEach(expenseAccounts) { account in
                            Text("\(account.code) - \(account.name)").tag(account.code)
                        }
                    }
                }

                Section("Reference") {
                    AppTextField(label: "Reference", text: $reference)
                    AppTextField(label: "Note", text: $note)
                }

                if loadingAccounts {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading accounts...")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Record Refund")
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
                    .disabled(saving || loadingAccounts)
                }
            }
            .task {
                if cashAccounts.isEmpty && expenseAccounts.isEmpty {
                    await loadAccounts()
                }
            }
        }
    }

    @MainActor
    private func loadAccounts() async {
        loadingAccounts = true
        errorMessage = nil
        do {
            async let cashTask = CashAccountsAPI().list()
            async let expenseTask = AccountingAPI().expenseAccounts()
            let (cash, expenses) = try await (cashTask, expenseTask)
            cashAccounts = cash
            expenseAccounts = expenses
            depositToCode = cash.first?.code ?? ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load accounts."
        }
        loadingAccounts = false
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil

        do {
            guard let parsedAmount = Double(amount), parsedAmount > 0 else {
                throw APIError(status: 0, message: "Amount must be positive.")
            }
            guard depositToCode.nilIfBlank != nil, creditCode.nilIfBlank != nil else {
                throw APIError(status: 0, message: "Deposit and offset accounts are required.")
            }

            _ = try await VendorsAPI().recordRefund(
                id: vendorId,
                body: VendorRefundInput(
                    amount: parsedAmount,
                    depositToCode: depositToCode,
                    creditCode: creditCode,
                    date: nil,
                    reference: reference.nilIfBlank,
                    note: note.nilIfBlank
                )
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not record refund."
        }

        saving = false
    }
}
