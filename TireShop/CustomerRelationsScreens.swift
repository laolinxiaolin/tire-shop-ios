import SwiftUI

private enum CrmTab: String, CaseIterable, Identifiable {
    case followUps
    case atRisk
    case templates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followUps: return "Follow-ups"
        case .atRisk: return "At-risk"
        case .templates: return "Templates"
        }
    }
}

private enum FollowUpFilter: String, CaseIterable, Identifiable {
    case open
    case overdue
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .overdue: return "Overdue"
        case .done: return "Done"
        }
    }
}

private enum CrmLabels {
    static let interactionTypes: [(InteractionType, String)] = [
        ("CALL", "Call"),
        ("VISIT", "Visit"),
        ("EMAIL", "Email"),
        ("NOTE", "Note"),
        ("OTHER", "Other")
    ]

    static func status(_ value: FollowUpStatus) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func interaction(_ value: InteractionType) -> String {
        interactionTypes.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private enum CrmDate {
    static let isoFormatter = ISO8601DateFormatter()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFormatter.date(from: value)
    }

    static func isOverdue(_ value: String?, status: FollowUpStatus) -> Bool {
        guard status == "OPEN", let date = date(value) else { return false }
        return date < Date()
    }
}

private struct TemplateEditorTarget: Identifiable {
    let template: OutreachTemplate?
    let id: String
}

struct CustomerRelationsNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var tab: CrmTab = .followUps

    private var canManage: Bool {
        auth.has("crm.manage")
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(CrmTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Space.lg)
            .background(Theme.background)

            Divider()

            Group {
                switch tab {
                case .followUps:
                    CrmFollowUpsView(canManage: canManage)
                case .atRisk:
                    CrmAtRiskView(canManage: canManage)
                case .templates:
                    CrmTemplatesView(canManage: canManage)
                }
            }
        }
        .background(Theme.background)
    }
}

private struct CrmFollowUpsView: View {
    @EnvironmentObject private var auth: AuthStore

    let canManage: Bool

    @State private var filter: FollowUpFilter = .open
    @State private var mine = false
    @State private var items: [CustomerFollowUp] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            controls

            Group {
                if loading && items.isEmpty {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, items.isEmpty {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if items.isEmpty {
                    EmptyStateView(text: "No follow-ups found.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Space.sm) {
                            ForEach(items) { followUp in
                                CrmFollowUpRow(followUp: followUp, canManage: canManage) { status in
                                    Task { await setStatus(followUp.id, status: status) }
                                }
                            }
                        }
                        .padding(Theme.Space.lg)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task {
            if items.isEmpty { await load() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(FollowUpFilter.allCases) { option in
                        Button {
                            guard filter != option else { return }
                            filter = option
                            Task { await load() }
                        } label: {
                            Text(option.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, Theme.Space.md)
                                .padding(.vertical, 7)
                                .background(filter == option ? Theme.primary : Theme.card)
                                .foregroundStyle(filter == option ? Theme.primaryText : Theme.text)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .stroke(filter == option ? Theme.primary : Theme.border)
                                )
                        }
                    }
                }
            }

            Toggle("Mine", isOn: Binding(
                get: { mine },
                set: { next in
                    mine = next
                    Task { await load() }
                }
            ))
            .font(.subheadline)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
        .background(Theme.background)
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let status: FollowUpStatus? = filter == .done ? "DONE" : (filter == .open ? "OPEN" : nil)
            let page = try await CrmAPI().followUps(
                status: status,
                assignedToId: mine ? auth.user?.id : nil,
                overdue: filter == .overdue ? true : nil,
                pageSize: 50
            )
            items = page.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load follow-ups."
        }
        loading = false
    }

    @MainActor
    private func setStatus(_ id: String, status: FollowUpStatus) async {
        do {
            _ = try await CrmAPI().updateFollowUp(
                id: id,
                body: FollowUpPatchInput(title: nil, note: nil, dueAt: nil, assignedToId: nil, status: status)
            )
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update follow-up."
        }
    }
}

private struct CrmFollowUpRow: View {
    let followUp: CustomerFollowUp
    let canManage: Bool
    let onStatus: (FollowUpStatus) -> Void

    private var overdue: Bool {
        CrmDate.isOverdue(followUp.dueAt, status: followUp.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(followUp.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)

                    if let note = followUp.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer()

                if overdue {
                    Text("Overdue")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 4)
                        .foregroundStyle(Theme.danger)
                        .background(Theme.danger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                } else if followUp.status != "OPEN" {
                    Text(CrmLabels.status(followUp.status))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, 4)
                        .foregroundStyle(Theme.muted)
                        .background(Theme.muted.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }

            HStack {
                if let customer = followUp.customer {
                    NavigationLink(value: AppRoute.customerDetail(id: customer.id, name: customer.name)) {
                        Text(customer.company ?? customer.name)
                    }
                } else {
                    Text("No customer")
                }

                Spacer()
                Text(AppFormat.dateTime(followUp.dueAt))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)

            Text("Assigned to \(followUp.assignedToName ?? "Unassigned")")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            if canManage && followUp.status == "OPEN" {
                HStack(spacing: Theme.Space.sm) {
                    Button("Complete") { onStatus("DONE") }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { onStatus("CANCELLED") }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.border)
        )
    }
}

private struct CrmAtRiskView: View {
    let canManage: Bool

    @State private var page: AtRiskCustomersPage?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var logTarget: AtRiskCustomer?
    @State private var emailTarget: AtRiskCustomer?

    var body: some View {
        Group {
            if loading && page == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, page == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let page, page.items.isEmpty {
                EmptyStateView(text: "No at-risk customers.")
            } else if let page {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        Text("Customers without a purchase in \(page.lapsedDays) days.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)

                        LazyVStack(spacing: Theme.Space.sm) {
                            ForEach(page.items) { customer in
                                AtRiskCustomerRow(
                                    customer: customer,
                                    canManage: canManage,
                                    onLogCall: { logTarget = customer },
                                    onEmail: customer.email == nil ? nil : { emailTarget = customer }
                                )
                            }
                        }
                    }
                    .padding(Theme.Space.lg)
                }
                .refreshable { await load() }
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .sheet(item: $logTarget) { customer in
            LogCallView(customer: customer) {
                logTarget = nil
                Task { await load() }
            }
        }
        .sheet(item: $emailTarget) { customer in
            EmailComposeNativeView(customerId: customer.id, customerName: customer.name, customerCompany: customer.company) {
                emailTarget = nil
                Task { await load() }
            }
        }
        .task {
            if page == nil { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            page = try await CrmAPI().atRisk(pageSize: 200)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load at-risk customers."
        }
        loading = false
    }
}

private struct AtRiskCustomerRow: View {
    let customer: AtRiskCustomer
    let canManage: Bool
    let onLogCall: () -> Void
    let onEmail: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink(value: AppRoute.customerDetail(id: customer.id, name: customer.name)) {
                    Text(customer.company ?? customer.name)
                        .font(.body)
                        .fontWeight(.semibold)
                }
                Spacer()
                Text(AppFormat.money(customer.lifetimeSpend))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack {
                Text(customer.company == nil ? "Customer" : customer.name)
                Spacer()
                Text(customer.lastPurchaseAt == nil ? "Never purchased" : AppFormat.shortDate(customer.lastPurchaseAt))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)

            Text("\(customer.saleCount) sale\(customer.saleCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            if canManage {
                HStack(spacing: Theme.Space.sm) {
                    Button("Log call") { onLogCall() }
                        .buttonStyle(.bordered)
                    if let onEmail {
                        Button("Send email") { onEmail() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.caption)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.border)
        )
    }
}

private struct LogCallView: View {
    @Environment(\.dismiss) private var dismiss

    let customer: AtRiskCustomer
    let onSaved: () -> Void

    @State private var summary = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    AppTextField(label: "Summary", text: $summary, placeholder: "Call result")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Log Call")
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
                    .disabled(saving || summary.nilIfBlank == nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let cleanSummary = summary.nilIfBlank else { return }
        saving = true
        errorMessage = nil
        do {
            _ = try await CrmAPI().addInteraction(
                customerId: customer.id,
                body: CustomerInteractionInput(type: "CALL", summary: cleanSummary, body: nil, occurredAt: nil)
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not log call."
        }
        saving = false
    }
}

private struct CrmTemplatesView: View {
    let canManage: Bool

    @State private var templates: [OutreachTemplate] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: TemplateEditorTarget?
    @State private var deleting: OutreachTemplate?

    var body: some View {
        VStack(spacing: 0) {
            if canManage {
                HStack {
                    Spacer()
                    Button {
                        editing = TemplateEditorTarget(template: nil, id: UUID().uuidString)
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(Theme.Space.lg)
            }

            Group {
                if loading && templates.isEmpty {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, templates.isEmpty {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if templates.isEmpty {
                    EmptyStateView(text: "No templates yet.")
                } else {
                    List {
                        ForEach(templates) { template in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack {
                                    Text(template.name)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    if !template.active {
                                        Text("Inactive")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                Text(template.subject)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)

                                if canManage {
                                    HStack(spacing: Theme.Space.sm) {
                                        Button("Edit") {
                                            editing = TemplateEditorTarget(template: template, id: template.id)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Delete", role: .destructive) {
                                            deleting = template
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .font(.caption)
                                    .padding(.top, Theme.Space.xs)
                                }
                            }
                            .padding(.vertical, Theme.Space.xs)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .sheet(item: $editing) { target in
            TemplateEditorView(template: target.template) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Delete template?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                Task { await deleteTemplate() }
            }
        } message: {
            Text("This removes the outreach template.")
        }
        .task {
            if templates.isEmpty { await load() }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            templates = try await CrmAPI().templates()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load templates."
        }
        loading = false
    }

    @MainActor
    private func deleteTemplate() async {
        guard let deleting else { return }
        do {
            _ = try await CrmAPI().deleteTemplate(id: deleting.id)
            self.deleting = nil
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete template."
        }
    }
}

private struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let template: OutreachTemplate?
    let onSaved: () -> Void

    @State private var name: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var active: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(template: OutreachTemplate?, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        _name = State(initialValue: template?.name ?? "")
        _subject = State(initialValue: template?.subject ?? "")
        _bodyText = State(initialValue: template?.body ?? "")
        _active = State(initialValue: template?.active ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    AppTextField(label: "Name", text: $name)
                    AppTextField(label: "Subject", text: $subject)
                    Toggle("Active", isOn: $active)
                }

                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                    Text("Use {{name}} and {{company}} placeholders.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
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
                    .disabled(saving || name.nilIfBlank == nil || subject.nilIfBlank == nil || bodyText.nilIfBlank == nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard
            let cleanName = name.nilIfBlank,
            let cleanSubject = subject.nilIfBlank,
            let cleanBody = bodyText.nilIfBlank
        else { return }

        saving = true
        errorMessage = nil
        let input = OutreachTemplateInput(name: cleanName, subject: cleanSubject, body: cleanBody, active: active)
        do {
            if let template {
                _ = try await CrmAPI().updateTemplate(id: template.id, body: input)
            } else {
                _ = try await CrmAPI().createTemplate(input)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save template."
        }
        saving = false
    }
}

struct EmailComposeNativeView: View {
    @Environment(\.dismiss) private var dismiss

    let customerId: String
    let customerName: String
    let customerCompany: String?
    let onSent: () -> Void

    @State private var templates: [OutreachTemplate] = []
    @State private var templateId = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(customerName) {
                    if !templates.isEmpty {
                        Picker("Template", selection: Binding(
                            get: { templateId },
                            set: { applyTemplate($0) }
                        )) {
                            Text("No template").tag("")
                            ForEach(templates) { template in
                                Text(template.name).tag(template.id)
                            }
                        }
                    }

                    AppTextField(label: "Subject", text: $subject)
                }

                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                    Text("Use {{name}} and {{company}} placeholders.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Send Email")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(sending || subject.nilIfBlank == nil || bodyText.nilIfBlank == nil)
                }
            }
            .task {
                if templates.isEmpty { await loadTemplates() }
            }
        }
    }

    @MainActor
    private func loadTemplates() async {
        do {
            let all = try await CrmAPI().templates()
            templates = all.filter { $0.active }
        } catch {
            templates = []
        }
    }

    private func applyTemplate(_ id: String) {
        templateId = id
        guard let template = templates.first(where: { $0.id == id }) else { return }
        subject = render(template.subject)
        bodyText = render(template.body)
    }

    private func render(_ text: String) -> String {
        text
            .replacingOccurrences(of: "{{name}}", with: customerName)
            .replacingOccurrences(of: "{{company}}", with: customerCompany ?? "")
    }

    @MainActor
    private func send() async {
        guard let cleanSubject = subject.nilIfBlank, let cleanBody = bodyText.nilIfBlank else { return }
        sending = true
        errorMessage = nil
        do {
            _ = try await CrmAPI().sendEmail(
                customerId: customerId,
                body: CrmEmailInput(subject: cleanSubject, body: cleanBody, templateId: templateId.nilIfBlank)
            )
            onSent()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not send email."
        }
        sending = false
    }
}
