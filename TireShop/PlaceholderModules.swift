import SwiftUI

// Screens that fill in formerly placeholder-only destinations, ported from the
// web UI (apps/web/app/{notifications,accounting/monthly-sales,settings/brand-info,
// settings/tire-attributes}).

private enum DayFormat {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }

    static var today: Date { Date() }

    static var monthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }
}

// MARK: - Notifications

struct NotificationsNativeView: View {
    var body: some View {
        AsyncContentView(load: loadAndMark) { page in
            if page.items.isEmpty {
                EmptyStateView(text: "No notifications yet.")
            } else {
                List(page.items) { note in
                    NotificationRow(note: note)
                }
                .listStyle(.plain)
            }
        }
    }

    private func loadAndMark() async throws -> NotificationsPage {
        let api = NotificationsAPI()
        let page = try await api.list(pageSize: 50)
        if page.unread > 0 {
            _ = try? await api.markAllRead()
        }
        return page
    }
}

private struct NotificationRow: View {
    let note: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Circle()
                .fill(note.readAt == nil ? Theme.primary : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(note.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)

                if let body = note.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                Text(AppFormat.dateTime(note.createdAt))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

// MARK: - Monthly Sales

struct MonthlySalesNativeView: View {
    @State private var from = DayFormat.monthStart
    @State private var to = DayFormat.today
    @State private var report: MonthlySalesReport?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, displayedComponents: .date)

                PrimaryButton(title: "Run report", loading: loading) {
                    Task { await load() }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                if let report {
                    StatGrid(stats: [
                        ("Tires sold", trimmed(report.summary.qty)),
                        ("Amount", AppFormat.money(report.summary.amount)),
                        ("Sales tax", AppFormat.money(report.summary.salesTax)),
                        ("Total FET", AppFormat.money(report.summary.totalFet)),
                        ("Gross profit", AppFormat.money(report.summary.amount - report.summary.totalCost))
                    ])

                    SectionHeader("\(report.summary.lineCount) lines")

                    VStack(spacing: 0) {
                        ForEach(Array(report.rows.enumerated()), id: \.offset) { _, row in
                            MonthlySalesRowView(row: row)
                            Divider()
                        }
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.background)
        .task {
            if report == nil { await load() }
        }
    }

    private func trimmed(_ value: Double) -> String {
        String(format: value == value.rounded() ? "%.0f" : "%.2f", value)
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            report = try await MonthlySalesAPI().report(from: DayFormat.string(from), to: DayFormat.string(to))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load report."
        }
        loading = false
    }
}

private struct MonthlySalesRowView: View {
    let row: MonthlySalesRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(row.invoiceNo)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(AppFormat.money(row.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
            }
            Text("\(row.brand) \(row.size) \(row.pattern)".trimmingCharacters(in: .whitespaces))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            HStack {
                Text(AppFormat.shortDate(row.date))
                Spacer()
                Text("Qty \(String(format: "%.0f", row.qty)) @ \(AppFormat.money(row.salesPrice))")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.sm)
    }
}

// MARK: - Commissions

struct CommissionsNativeView: View {
    private let pageSize = 25
    private let statuses: [(String, String)] = [
        ("", "All"),
        ("ACCRUED", "Accrued"),
        ("PAID", "Paid"),
        ("VOID", "Void")
    ]

    @State private var status = ""
    @State private var page = 1
    @State private var data: Paged<CommissionEntry>?
    @State private var loading = false
    @State private var errorMessage: String?

    private var totalPages: Int {
        guard let data, data.pageSize > 0 else { return 1 }
        return max(1, (data.total + data.pageSize - 1) / data.pageSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusFilter

            Group {
                if loading && data == nil {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, data == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let data, data.items.isEmpty {
                    EmptyStateView(text: "No commissions found.")
                } else if let data {
                    List(data.items) { entry in
                        CommissionRow(entry: entry)
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
        .task {
            if data == nil { await load() }
        }
    }

    private var statusFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(statuses, id: \.0) { option in
                    Button {
                        guard status != option.0 else { return }
                        status = option.0
                        page = 1
                        Task { await load() }
                    } label: {
                        Text(option.1)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 7)
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
            .padding(.vertical, Theme.Space.sm)
        }
        .background(Theme.background)
    }

    private func pagination(_ data: Paged<CommissionEntry>) -> some View {
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
                Text("\(data.total) entries")
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
            data = try await CommissionsAPI().list(
                status: status.nilIfBlank,
                page: page,
                pageSize: pageSize
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load commissions."
        }
        loading = false
    }
}

private struct CommissionRow: View {
    let entry: CommissionEntry

    var body: some View {
        Group {
            if let sale = entry.sale {
                NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                    content(saleLabel: sale.ref ?? "Sale")
                }
            } else {
                content(saleLabel: entry.note?.isEmpty == false ? "Rollover" : "-")
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func content(saleLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.employee?.fullName ?? "Unknown employee")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(AppFormat.money(entry.amount))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(entry.amount < 0 ? .red : Theme.text)
            }

            HStack {
                Text("\(AppFormat.shortDate(entry.createdAt)) · \(saleLabel)")
                Spacer()
                Text(statusLabel(entry.status))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)

            HStack {
                Text(basisLabel(entry.basis))
                Spacer()
                Text("\(AppFormat.money(entry.basisAmount)) x \(String(format: "%.2f", entry.rate * 100))%")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }

    private func basisLabel(_ basis: String) -> String {
        switch basis {
        case "GROSS_PROFIT": return "Gross profit"
        case "REVENUE": return "Revenue"
        default: return basis.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func statusLabel(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Brand Info

private struct BrandEditTarget: Identifiable {
    let brand: BrandInfo?
    let id: String
}

struct BrandInfoNativeView: View {
    @State private var brands: [BrandInfo] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var editing: BrandEditTarget?

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, brands.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if brands.isEmpty {
                EmptyStateView(text: "No brands yet. Add one with +.")
            } else {
                List {
                    ForEach(brands) { brand in
                        Button { editing = BrandEditTarget(brand: brand, id: brand.id) } label: {
                            RowLine(
                                title: brand.name,
                                subtitle: [brand.country, brand.foundedYear.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                                trailing: brand.active ? "\(brand.usageCount) SKUs" : "Inactive"
                            )
                        }
                        .tint(Theme.text)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = BrandEditTarget(brand: nil, id: "new") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { target in
            BrandEditorView(brand: target.brand) {
                editing = nil
                Task { await load() }
            }
        }
        .task { if !loaded { await load() } }
    }

    @MainActor
    private func load() async {
        do {
            brands = try await BrandsAPI().list()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load brands."
        }
        loaded = true
    }

    private func delete(_ offsets: IndexSet) {
        let targets = offsets.map { brands[$0] }
        Task {
            for brand in targets {
                _ = try? await BrandsAPI().remove(id: brand.id)
            }
            await load()
        }
    }
}

private struct BrandEditorView: View {
    let brand: BrandInfo?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var introEn = ""
    @State private var introZh = ""
    @State private var country = ""
    @State private var foundedYear = ""
    @State private var website = ""
    @State private var active = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Brand") {
                    TextField("Name", text: $name)
                    TextField("Country", text: $country)
                    TextField("Founded year", text: $foundedYear).keyboardType(.numberPad)
                    TextField("Website", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
                    Toggle("Active", isOn: $active)
                }
                Section("Intro (English)") {
                    TextField("English intro", text: $introEn, axis: .vertical).lineLimit(3...8)
                }
                Section("Intro (中文)") {
                    TextField("Chinese intro", text: $introZh, axis: .vertical).lineLimit(3...8)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle(brand == nil ? "New Brand" : "Edit Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func seed() {
        guard let brand else { return }
        name = brand.name
        introEn = brand.introEn
        introZh = brand.introZh
        country = brand.country ?? ""
        foundedYear = brand.foundedYear.map(String.init) ?? ""
        website = brand.website ?? ""
        active = brand.active
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        let body = BrandCreateInput(
            name: name.trimmingCharacters(in: .whitespaces),
            introEn: introEn.trimmingCharacters(in: .whitespaces),
            introZh: introZh.trimmingCharacters(in: .whitespaces),
            country: country.nilIfBlank,
            foundedYear: Int(foundedYear.trimmingCharacters(in: .whitespaces)),
            website: website.nilIfBlank,
            active: active
        )
        do {
            if let brand {
                _ = try await BrandsAPI().update(id: brand.id, body: body)
            } else {
                _ = try await BrandsAPI().create(body)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save."
        }
        saving = false
    }
}

// MARK: - Tire Attributes

struct TireAttributesNativeView: View {
    @State private var attributes: [TireAttribute] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var addingKind: String?
    @State private var renameTarget: TireAttribute?
    @State private var renameText = ""

    private let kinds: [(String, String)] = [
        ("CATEGORY", "Category"),
        ("POSITION", "Position"),
        ("SEGMENT", "Segment")
    ]

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, attributes.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                List {
                    ForEach(kinds, id: \.0) { kind, title in
                        Section {
                            ForEach(attributes.filter { $0.kind == kind }) { attr in
                                attributeRow(attr)
                            }
                            Button {
                                addingKind = kind
                            } label: {
                                Label("Add \(title.lowercased())", systemImage: "plus.circle")
                            }
                        } header: {
                            Text(title)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { if !loaded { await load() } }
        .sheet(item: Binding(get: { addingKind.map { KindBox(kind: $0) } }, set: { addingKind = $0?.kind })) { box in
            TireAttributeEditorView(kind: box.kind) {
                addingKind = nil
                Task { await load() }
            }
        }
        .alert("Rename label", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Label", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { Task { await commitRename() } }
        }
    }

    private func attributeRow(_ attr: TireAttribute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(attr.label).foregroundStyle(Theme.text)
                Text(attr.value).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(attr.usageCount)").font(.caption).foregroundStyle(Theme.muted)
            Button {
                Task { await toggle(attr) }
            } label: {
                Text(attr.active ? "Active" : "Off")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(attr.active ? Theme.primary : Theme.muted)
            }
            .buttonStyle(.borderless)
        }
        .swipeActions {
            Button("Delete", role: .destructive) { Task { await remove(attr) } }
            Button("Rename") {
                renameText = attr.label
                renameTarget = attr
            }
            .tint(Theme.primary)
        }
    }

    @MainActor
    private func load() async {
        do {
            attributes = try await TireAttributesAPI().list()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load attributes."
        }
        loaded = true
    }

    @MainActor
    private func toggle(_ attr: TireAttribute) async {
        _ = try? await TireAttributesAPI().update(id: attr.id, body: TireAttributePatchInput(label: nil, active: !attr.active))
        await load()
    }

    @MainActor
    private func remove(_ attr: TireAttribute) async {
        _ = try? await TireAttributesAPI().remove(id: attr.id)
        await load()
    }

    @MainActor
    private func commitRename() async {
        guard let target = renameTarget else { return }
        let label = renameText.trimmingCharacters(in: .whitespaces)
        renameTarget = nil
        _ = try? await TireAttributesAPI().update(id: target.id, body: TireAttributePatchInput(label: label.isEmpty ? target.value : label, active: nil))
        await load()
    }
}

private struct KindBox: Identifiable {
    let kind: String
    var id: String { kind }
}

private struct TireAttributeEditorView: View {
    let kind: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var label = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Value (e.g. LONG_HAUL)", text: $value).textInputAutocapitalization(.characters)
                    TextField("Label (e.g. Long Haul)", text: $label)
                } header: {
                    Text(kind.capitalized)
                } footer: {
                    Text("Value is the stored code; label is shown in the app.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle("New \(kind.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await TireAttributesAPI().create(
                TireAttributeCreateInput(kind: kind, value: trimmedValue, label: trimmedLabel.isEmpty ? trimmedValue : trimmedLabel)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save."
        }
        saving = false
    }
}

// MARK: - Shared small views

struct EmptyStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct RetryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Text(message)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Retry", action: retry)
                .frame(maxWidth: 220)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
