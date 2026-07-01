import QuickLook
import SwiftUI
import UniformTypeIdentifiers

private enum CustomerDetailTab: String, CaseIterable, Identifiable {
    case profile
    case account
    case sales
    case relationship

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile"
        case .account: return "Account"
        case .sales: return "Sales"
        case .relationship: return "Relationship"
        }
    }
}

private enum CustomerDocumentKinds {
    static let all: [(CustomerDocumentKind, String)] = [
        ("ST5_EXEMPTION", "ST5 exemption"),
        ("RESALE_CERT", "Resale certificate"),
        ("OTHER", "Document")
    ]

    static func label(_ value: CustomerDocumentKind) -> String {
        all.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private enum CustomerCrmLabels {
    static let interactionTypes: [(InteractionType, String)] = [
        ("CALL", "Call"),
        ("VISIT", "Visit"),
        ("EMAIL", "Email"),
        ("NOTE", "Note"),
        ("OTHER", "Other")
    ]

    static func interaction(_ value: InteractionType) -> String {
        interactionTypes.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func status(_ value: FollowUpStatus) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct CustomerPaymentContext: Identifiable {
    let invoice: CustomerAccount.OpenInvoice
    let customerId: String

    var id: String { invoice.id }
}

private struct CustomerDocumentPreview: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct CustomerDocumentDeleteTarget: Identifiable {
    let document: CustomerDocument
    var id: String { document.id }
}

private struct CustomerPasswordResetTarget: Identifiable {
    let user: CustomerUser
    var id: String { user.id }
}

struct CustomerDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    let id: String
    let fallbackName: String

    @State private var tab: CustomerDetailTab = .profile
    @State private var customer: Customer?
    @State private var account: CustomerAccount?
    @State private var storefrontUsers: [CustomerUser] = []
    @State private var priceTiers: [PriceTier] = []
    @State private var salespersonOptions: [CustomerSalesperson] = []
    @State private var relationship: RelationshipSummary?
    @State private var interactions: [CustomerInteraction] = []
    @State private var followUps: [CustomerFollowUp] = []
    @State private var assignableUsers: [AssignableUser] = []

    @State private var loading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    @State private var editingProfile = false
    @State private var documentPreview: CustomerDocumentPreview?
    @State private var deleteDocumentTarget: CustomerDocumentDeleteTarget?
    @State private var importingDocument = false
    @State private var uploadKind: CustomerDocumentKind = "ST5_EXEMPTION"
    @State private var uploadingDocument = false
    @State private var deletingCustomer = false
    @State private var deleteCustomerPending = false

    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var savingTags = false

    @State private var taxExempt = false
    @State private var taxNumber = ""
    @State private var taxExpires = ""
    @State private var savingTax = false

    @State private var accountEnabled = false
    @State private var creditLimit = ""
    @State private var savingAccount = false
    @State private var selectedTier = ""
    @State private var savingTier = false
    @State private var selectedSalesperson = ""
    @State private var savingSalesperson = false
    @State private var paymentContext: CustomerPaymentContext?

    @State private var newUserEmail = ""
    @State private var newUserPassword = ""
    @State private var creatingUser = false
    @State private var passwordResetTarget: CustomerPasswordResetTarget?

    @State private var interactionType: InteractionType = "CALL"
    @State private var interactionSummary = ""
    @State private var interactionBody = ""
    @State private var savingInteraction = false
    @State private var deletingInteractionId: String?
    @State private var emailing = false

    @State private var followUpTitle = ""
    @State private var followUpDueAt = Date().addingTimeInterval(86_400)
    @State private var followUpNote = ""
    @State private var followUpAssignee = ""
    @State private var savingFollowUp = false
    @State private var busyFollowUpId: String?

    private var canManageCustomers: Bool { auth.has("customers.manage") }
    private var canDeleteCustomers: Bool { auth.has("customers.delete") }
    private var canCollectPayments: Bool { auth.has("payments.collect") }
    private var canViewEmployees: Bool { auth.has("employees.view") }
    private var canViewCrm: Bool { auth.has("crm.view") }
    private var canManageCrm: Bool { auth.has("crm.manage") }

    private var visibleTabs: [CustomerDetailTab] {
        CustomerDetailTab.allCases.filter { $0 != .relationship || canViewCrm }
    }

    var body: some View {
        Group {
            if loading && customer == nil {
                LoadingView(label: "Loading...")
            } else if let customer {
                VStack(spacing: 0) {
                    Picker("View", selection: $tab) {
                        ForEach(visibleTabs) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.Space.lg)
                    .background(Theme.background)

                    Divider()

                    tabContent(customer)
                }
            } else if let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .navigationTitle(customer?.name ?? fallbackName)
        .task {
            if customer == nil { await load() }
        }
        .refreshable { await load() }
        .sheet(isPresented: $editingProfile) {
            if let customer {
                CustomerProfileEditorView(customer: customer) { updated in
                    applyCustomer(updated)
                    Task { await loadSupportingData(for: updated) }
                }
            }
        }
        .sheet(item: $documentPreview) { preview in
            QuickLookSheet(url: preview.url)
        }
        .sheet(item: $paymentContext) { context in
            PaymentSheetNativeView(invoiceId: context.invoice.id, balance: context.invoice.balance, customerId: context.customerId) {
                Task { await loadAccount() }
            }
        }
        .sheet(item: $passwordResetTarget) { target in
            CustomerPasswordResetView(user: target.user) { password in
                _ = try await CustomersAPI().resetUserPassword(id: id, userId: target.user.id, password: password)
                await loadStorefrontUsers()
            }
        }
        .sheet(isPresented: $emailing) {
            if let customer {
                EmailComposeNativeView(customerId: customer.id, customerName: customer.name, customerCompany: customer.company) {
                    Task { await loadRelationshipData() }
                }
            }
        }
        .fileImporter(
            isPresented: $importingDocument,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleDocumentImport(result) }
        }
        .alert("Delete document?", isPresented: Binding(
            get: { deleteDocumentTarget != nil },
            set: { if !$0 { deleteDocumentTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteDocumentTarget = nil }
            Button("Delete", role: .destructive) {
                Task { await deleteDocument() }
            }
        } message: {
            Text("This removes the file from the customer profile.")
        }
        .alert("Delete customer?", isPresented: $deleteCustomerPending) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteCustomer() }
            }
        } message: {
            Text("This permanently removes the customer and their documents. The server will refuse if the account has sales, orders or store-credit history.")
        }
    }

    @ViewBuilder
    private func tabContent(_ customer: Customer) -> some View {
        switch tab {
        case .profile:
            profileForm(customer)
        case .account:
            accountForm(customer)
        case .sales:
            salesForm(customer)
        case .relationship:
            relationshipForm(customer)
        }
    }

    private func profileForm(_ customer: Customer) -> some View {
        Form {
            messageSections

            Section {
                RowLine(title: customer.name, subtitle: customer.company, trailing: customer.taxExempt ? "Tax exempt" : nil)
                RowLine(title: "Phone", subtitle: AppFormat.phone(customer.phone).nilIfBlank ?? "-")
                RowLine(title: "Email", subtitle: customer.email ?? "-")
                RowLine(title: "Address", subtitle: customer.address ?? "-")
                if let notes = customer.notes?.nilIfBlank {
                    RowLine(title: "Notes", subtitle: notes)
                }
                if canManageCustomers {
                    Button {
                        editingProfile = true
                    } label: {
                        Label("Edit profile", systemImage: "square.and.pencil")
                    }
                }
            } header: {
                Text("Profile")
            } footer: {
                if let ref = customer.ref {
                    Text(ref)
                }
            }

            tagsSection
            taxSection
            documentsSection(customer)

            if canManageCustomers {
                storefrontSection(customer)
            }

            if canDeleteCustomers {
                Section("Danger Zone") {
                    Button(role: .destructive) {
                        deleteCustomerPending = true
                    } label: {
                        Label(deletingCustomer ? "Deleting..." : "Delete customer", systemImage: "trash")
                    }
                    .disabled(deletingCustomer)
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            if tags.isEmpty {
                Text("No tags yet.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(tags, id: \.self) { tag in
                    HStack {
                        Text(tag)
                        Spacer()
                        if canManageCustomers {
                            Button(role: .destructive) {
                                Task { await saveTags(tags.filter { $0 != tag }) }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .disabled(savingTags)
                        }
                    }
                }
            }

            if canManageCustomers {
                HStack {
                    TextField("Add tag", text: $newTag)
                        .textInputAutocapitalization(.never)
                    Button {
                        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !tag.isEmpty else { return }
                        Task { await saveTags(Array(Set(tags + [tag])).sorted()) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(savingTags || newTag.nilIfBlank == nil)
                }
            }
        }
    }

    private var taxSection: some View {
        Section {
            Toggle("Tax exempt", isOn: $taxExempt)
                .disabled(!canManageCustomers || savingTax)

            if taxExempt {
                TextField("Certificate number", text: $taxNumber)
                    .disabled(!canManageCustomers || savingTax)
                TextField("Expires YYYY-MM-DD", text: $taxExpires)
                    .keyboardType(.numbersAndPunctuation)
                    .disabled(!canManageCustomers || savingTax)
            }

            if canManageCustomers {
                Button {
                    Task { await saveTaxStatus() }
                } label: {
                    Label(savingTax ? "Saving..." : "Save tax status", systemImage: "checkmark.seal")
                }
                .disabled(savingTax)
            }
        } header: {
            Text("Tax Status")
        } footer: {
            Text("Leave expiration blank when the exemption has no known end date.")
        }
    }

    private func documentsSection(_ customer: Customer) -> some View {
        Section {
            Picker("Upload as", selection: $uploadKind) {
                ForEach(CustomerDocumentKinds.all, id: \.0) { kind, label in
                    Text(label).tag(kind)
                }
            }
            .disabled(!canManageCustomers || uploadingDocument)

            if canManageCustomers {
                Button {
                    importingDocument = true
                } label: {
                    Label(uploadingDocument ? "Uploading..." : "Upload document", systemImage: "doc.badge.plus")
                }
                .disabled(uploadingDocument)
            }

            let docs = customer.documents ?? []
            if docs.isEmpty {
                Text("No documents on file.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(docs) { document in
                    HStack(alignment: .top) {
                        Button {
                            Task { await openDocument(document) }
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(document.filename)
                                Text("\(CustomerDocumentKinds.label(document.kind)) · \(ByteCountFormatter.string(fromByteCount: Int64(document.sizeBytes), countStyle: .file)) · \(AppFormat.dateTime(document.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if canDeleteCustomers {
                            Button(role: .destructive) {
                                deleteDocumentTarget = CustomerDocumentDeleteTarget(document: document)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Documents")
        } footer: {
            Text("PDF, JPEG or PNG.")
        }
    }

    private func storefrontSection(_ customer: Customer) -> some View {
        Section {
            if !customer.accountEnabled {
                Text("Account billing is disabled. Enable it on the Account tab before creating storefront logins.")
                    .foregroundStyle(.orange)
            }

            if customer.accountEnabled {
                TextField("Email", text: $newUserEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Temporary password", text: $newUserPassword)
                    .textContentType(.newPassword)
                Button {
                    Task { await createStorefrontUser() }
                } label: {
                    Label(creatingUser ? "Creating..." : "Create login", systemImage: "person.badge.plus")
                }
                .disabled(creatingUser || newUserEmail.nilIfBlank == nil || newUserPassword.count < 8)
            }

            if storefrontUsers.isEmpty {
                Text("No storefront users.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(storefrontUsers) { user in
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(user.email)
                                    .fontWeight(.semibold)
                                Text(user.lastLoginAt.map { "Last login \((AppFormat.dateTime($0)))" } ?? "Never logged in")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(user.active ? "Active" : "Inactive")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(user.active ? Theme.success : Theme.danger)
                        }

                        HStack {
                            if isLocked(user) {
                                Button("Unlock") {
                                    Task { await unlockStorefrontUser(user) }
                                }
                                .buttonStyle(.bordered)
                            }
                            Button("Reset password") {
                                passwordResetTarget = CustomerPasswordResetTarget(user: user)
                            }
                            .buttonStyle(.bordered)
                            Button(user.active ? "Deactivate" : "Activate") {
                                Task { await setStorefrontUser(user, active: !user.active) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
        } header: {
            Text("Storefront Access")
        } footer: {
            Text("Passwords must be at least 8 characters.")
        }
    }

    private func accountForm(_ customer: Customer) -> some View {
        Form {
            messageSections

            Section("Account Billing") {
                Toggle("Allow paying on account", isOn: $accountEnabled)
                    .disabled(!canManageCustomers || savingAccount)
                if accountEnabled {
                    TextField("Credit limit", text: $creditLimit)
                        .keyboardType(.decimalPad)
                        .disabled(!canManageCustomers || savingAccount)
                }
                if let account {
                    RowLine(title: "Open balance", trailing: AppFormat.money(account.totalBalance))
                    if let limit = account.customer.creditLimit {
                        RowLine(title: "Credit limit", trailing: AppFormat.money(limit))
                    }
                }
                if canManageCustomers {
                    Button {
                        Task { await saveAccountSettings() }
                    } label: {
                        Label(savingAccount ? "Saving..." : "Save account", systemImage: "creditcard")
                    }
                    .disabled(savingAccount)
                }
            }

            if let account, !account.openInvoices.isEmpty {
                Section("Open Invoices") {
                    ForEach(account.openInvoices) { invoice in
                        HStack {
                            NavigationLink(value: AppRoute.saleDetail(invoice.sale.id)) {
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text(invoice.ref ?? invoice.sale.ref ?? "Invoice")
                                    Text(AppFormat.shortDate(invoice.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                                Text(AppFormat.money(invoice.balance))
                                    .fontWeight(.semibold)
                                if canCollectPayments && invoice.balance > 0 {
                                    Button("Record payment") {
                                        paymentContext = CustomerPaymentContext(invoice: invoice, customerId: customer.id)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            priceTierSection(customer)

            if canViewEmployees {
                salespersonSection(customer)
            }
        }
    }

    private func priceTierSection(_ customer: Customer) -> some View {
        Section {
            Picker("Price tier", selection: $selectedTier) {
                Text("No tier").tag("")
                ForEach(priceTierOptions(for: customer)) { tier in
                    Text(priceTierLabel(tier)).tag(tier.id)
                }
            }
            .disabled(!canManageCustomers || savingTier || priceTiers.isEmpty)

            if let tier = customer.priceTier {
                RowLine(title: "Current", subtitle: priceTierLabel(tier))
            }

            if canManageCustomers {
                Button {
                    Task { await savePriceTier() }
                } label: {
                    Label(savingTier ? "Saving..." : "Save price tier", systemImage: "tag")
                }
                .disabled(savingTier)
            }
        } header: {
            Text("Price Tier")
        } footer: {
            Text("Customer-specific storefront pricing uses this tier when no per-SKU override exists.")
        }
    }

    private func salespersonSection(_ customer: Customer) -> some View {
        Section {
            Picker("Salesperson", selection: $selectedSalesperson) {
                Text("Unassigned").tag("")
                ForEach(salespersonOptionsForCustomer(customer)) { person in
                    Text(salespersonLabel(person)).tag(person.id)
                }
            }
            .disabled(!canManageCustomers || savingSalesperson || salespersonOptions.isEmpty)

            if let salesperson = customer.salesperson {
                RowLine(title: "Current", subtitle: salespersonLabel(salesperson))
            }

            if canManageCustomers {
                Button {
                    Task { await saveSalesperson() }
                } label: {
                    Label(savingSalesperson ? "Saving..." : "Save salesperson", systemImage: "person.crop.circle")
                }
                .disabled(savingSalesperson)
            }
        } header: {
            Text("Salesperson")
        } footer: {
            Text("Commissions are attributed to the assigned salesperson.")
        }
    }

    private func salesForm(_ customer: Customer) -> some View {
        Form {
            let sales = customer.sales ?? []
            if sales.isEmpty {
                Section {
                    Text("No past sales for this customer.")
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Section("Past Sales") {
                    ForEach(sales) { sale in
                        NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack {
                                    Text(sale.ref ?? "Sale")
                                        .fontWeight(.semibold)
                                    if sale.channel == "ONLINE" {
                                        Text("online")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, Theme.Space.xs)
                                            .padding(.vertical, 2)
                                            .background(Theme.primary.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                    }
                                    Spacer()
                                    Text(AppFormat.money(sale.total))
                                }
                                HStack {
                                    Text(sale.status.capitalized)
                                    Spacer()
                                    Text(AppFormat.shortDate(sale.createdAt))
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relationshipForm(_ customer: Customer) -> some View {
        Form {
            messageSections

            if let relationship {
                Section {
                    RowLine(title: "Last purchase", subtitle: relationship.lastPurchaseAt.map(AppFormat.shortDate) ?? "Never")
                    RowLine(title: "Lifetime spend", trailing: AppFormat.money(relationship.lifetimeSpend))
                    RowLine(title: "Sales", trailing: "\(relationship.saleCount)")
                    RowLine(title: "Open follow-ups", trailing: "\(relationship.openFollowUpCount)")
                    if relationship.atRisk {
                        Label("At risk after \(relationship.lapsedDays) days without a purchase.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Relationship")
                }
            }

            interactionsSection(customer)
            followUpsSection(customer)
        }
    }

    private func interactionsSection(_ customer: Customer) -> some View {
        Section {
            if canManageCrm {
                Picker("Type", selection: $interactionType) {
                    ForEach(CustomerCrmLabels.interactionTypes, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                TextField("Summary", text: $interactionSummary)
                TextField("Details", text: $interactionBody, axis: .vertical)
                    .lineLimit(1...3)
                Button {
                    Task { await addInteraction() }
                } label: {
                    Label(savingInteraction ? "Saving..." : "Log interaction", systemImage: "bubble.left.and.bubble.right")
                }
                .disabled(savingInteraction || interactionSummary.nilIfBlank == nil)

                if customer.email?.nilIfBlank != nil {
                    Button {
                        emailing = true
                    } label: {
                        Label("Send email", systemImage: "envelope")
                    }
                }
            }

            if interactions.isEmpty {
                Text("No interactions yet.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(interactions) { interaction in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text(CustomerCrmLabels.interaction(interaction.type))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.primary)
                            Spacer()
                            Text(AppFormat.dateTime(interaction.occurredAt))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Text(interaction.summary)
                            .fontWeight(.semibold)
                        if let body = interaction.body?.nilIfBlank {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        if let createdBy = interaction.createdByName?.nilIfBlank {
                            Text(createdBy)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        if canManageCrm {
                            Button(role: .destructive) {
                                Task { await deleteInteraction(interaction) }
                            } label: {
                                Label(deletingInteractionId == interaction.id ? "Deleting..." : "Delete", systemImage: "trash")
                            }
                            .font(.caption)
                            .disabled(deletingInteractionId == interaction.id)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
        } header: {
            Text("Interactions")
        }
    }

    private func followUpsSection(_ customer: Customer) -> some View {
        Section {
            if canManageCrm {
                TextField("Title", text: $followUpTitle)
                DatePicker("Due", selection: $followUpDueAt, displayedComponents: [.date, .hourAndMinute])
                TextField("Note", text: $followUpNote, axis: .vertical)
                    .lineLimit(1...3)

                if !assignableUsers.isEmpty {
                    Picker("Assignee", selection: $followUpAssignee) {
                        Text("Unassigned").tag("")
                        ForEach(assignableUsers) { user in
                            Text(user.fullName).tag(user.id)
                        }
                    }
                }

                Button {
                    Task { await addFollowUp() }
                } label: {
                    Label(savingFollowUp ? "Saving..." : "Add follow-up", systemImage: "calendar.badge.plus")
                }
                .disabled(savingFollowUp || followUpTitle.nilIfBlank == nil)
            }

            if followUps.isEmpty {
                Text("No follow-ups.")
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(followUps) { followUp in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text(followUp.title)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(CustomerCrmLabels.status(followUp.status))
                                .font(.caption)
                                .foregroundStyle(followUp.status == "OPEN" ? Color.orange : Theme.muted)
                        }
                        Text(AppFormat.dateTime(followUp.dueAt))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        if let note = followUp.note?.nilIfBlank {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        if let assigned = followUp.assignedToName?.nilIfBlank {
                            Text("Assigned to \(assigned)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        if canManageCrm {
                            HStack {
                                if followUp.status == "OPEN" {
                                    Button("Complete") {
                                        Task { await setFollowUp(followUp, status: "DONE") }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Cancel") {
                                        Task { await setFollowUp(followUp, status: "CANCELLED") }
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button("Reopen") {
                                        Task { await setFollowUp(followUp, status: "OPEN") }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .font(.caption)
                            .disabled(busyFollowUpId == followUp.id)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            }
        } header: {
            Text("Follow-Ups")
        }
    }

    @ViewBuilder
    private var messageSections: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(Theme.danger)
                    .font(.subheadline)
            }
        }
        if let statusMessage {
            Section {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .font(.subheadline)
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        statusMessage = nil

        do {
            let loaded = try await CustomersAPI().get(id: id)
            applyCustomer(loaded)
            await loadSupportingData(for: loaded)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load customer."
        }

        loading = false
    }

    @MainActor
    private func loadSupportingData(for customer: Customer) async {
        await loadAccount()

        if canManageCustomers {
            await loadStorefrontUsers()
        }

        do {
            let tiers = try await PriceTiersAPI().list()
            priceTiers = tiers.filter { $0.active || $0.id == customer.priceTierId }
        } catch {
            priceTiers = []
        }

        if canViewEmployees {
            await loadSalespeople(current: customer.salesperson)
        }

        if canViewCrm {
            await loadRelationshipData()
        }
    }

    @MainActor
    private func applyCustomer(_ customer: Customer) {
        self.customer = customer
        tags = customer.tags ?? []
        taxExempt = customer.taxExempt
        taxNumber = customer.taxExemptNumber ?? ""
        taxExpires = customer.taxExemptExpiresAt.map { String($0.prefix(10)) } ?? ""
        accountEnabled = customer.accountEnabled
        creditLimit = customer.creditLimit ?? ""
        selectedTier = customer.priceTierId ?? ""
        selectedSalesperson = customer.salespersonId ?? ""
    }

    @MainActor
    private func reloadCustomer() async {
        do {
            let updated = try await CustomersAPI().get(id: id)
            applyCustomer(updated)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not refresh customer."
        }
    }

    @MainActor
    private func loadAccount() async {
        do {
            account = try await CustomersAPI().account(id: id)
        } catch {
            account = nil
        }
    }

    @MainActor
    private func loadStorefrontUsers() async {
        do {
            storefrontUsers = try await CustomersAPI().users(id: id)
        } catch {
            storefrontUsers = []
        }
    }

    @MainActor
    private func loadSalespeople(current: CustomerSalesperson?) async {
        do {
            let page = try await EmployeesAPI().list(status: "ACTIVE", pageSize: 1000)
            var options = page.items.map { CustomerSalesperson(id: $0.id, fullName: $0.fullName, status: $0.status) }
            if let current, !options.contains(where: { $0.id == current.id }) {
                options.append(current)
            }
            salespersonOptions = options.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        } catch {
            salespersonOptions = current.map { [$0] } ?? []
        }
    }

    @MainActor
    private func loadRelationshipData() async {
        do {
            async let summaryTask = CrmAPI().relationshipSummary(customerId: id)
            async let interactionsTask = CrmAPI().interactions(customerId: id)
            async let followUpsTask = CrmAPI().followUps(customerId: id, pageSize: 200)
            relationship = try await summaryTask
            interactions = try await interactionsTask
            followUps = try await followUpsTask.items
            if canManageCrm {
                assignableUsers = (try? await CrmAPI().assignableUsers()) ?? []
            }
        } catch {
            relationship = nil
            interactions = []
            followUps = []
        }
    }

    @MainActor
    private func saveTags(_ next: [String]) async {
        savingTags = true
        clearMessages()
        do {
            let unique = Array(NSOrderedSet(array: next.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? next
            let updated = try await CustomersAPI().updateTags(id: id, body: CustomerTagsPatch(tags: unique))
            newTag = ""
            applyCustomer(updated)
            statusMessage = "Tags saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save tags."
        }
        savingTags = false
    }

    @MainActor
    private func saveTaxStatus() async {
        savingTax = true
        clearMessages()
        do {
            let expires = try taxExpiresIso()
            let updated = try await CustomersAPI().setTaxStatus(
                id: id,
                body: CustomerTaxStatusInput(
                    taxExempt: taxExempt,
                    taxExemptNumber: taxExempt ? taxNumber.nilIfBlank : nil,
                    taxExemptExpiresAt: taxExempt ? expires : nil
                )
            )
            applyCustomer(updated)
            statusMessage = "Tax status saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save tax status."
        }
        savingTax = false
    }

    @MainActor
    private func openDocument(_ document: CustomerDocument) async {
        clearMessages()
        do {
            let url = try await CustomersAPI().downloadDocument(id: id, document: document)
            documentPreview = CustomerDocumentPreview(url: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not open document."
        }
    }

    @MainActor
    private func handleDocumentImport(_ result: Result<[URL], Error>) async {
        guard canManageCustomers else { return }
        uploadingDocument = true
        clearMessages()
        var tempURL: URL?
        do {
            let source = try result.get().first
            guard let source else { return }
            let copied = try copyImportedDocument(source)
            tempURL = copied
            _ = try await CustomersAPI().uploadDocument(
                id: id,
                fileURL: copied,
                fileName: source.lastPathComponent,
                mimeType: mimeType(for: source),
                kind: uploadKind
            )
            await reloadCustomer()
            statusMessage = "Document uploaded."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not upload document."
        }
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        uploadingDocument = false
    }

    @MainActor
    private func deleteDocument() async {
        guard let target = deleteDocumentTarget else { return }
        clearMessages()
        do {
            _ = try await CustomersAPI().deleteDocument(id: id, documentId: target.document.id)
            deleteDocumentTarget = nil
            await reloadCustomer()
            statusMessage = "Document deleted."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete document."
        }
    }

    @MainActor
    private func createStorefrontUser() async {
        guard let email = newUserEmail.nilIfBlank, !newUserPassword.isEmpty else { return }
        creatingUser = true
        clearMessages()
        do {
            _ = try await CustomersAPI().createUser(id: id, body: CustomerUserCreateInput(email: email, password: newUserPassword))
            newUserEmail = ""
            newUserPassword = ""
            await loadStorefrontUsers()
            statusMessage = "Storefront login created."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not create storefront login."
        }
        creatingUser = false
    }

    @MainActor
    private func setStorefrontUser(_ user: CustomerUser, active: Bool) async {
        clearMessages()
        do {
            _ = try await CustomersAPI().setUserActive(id: id, userId: user.id, body: CustomerUserActiveInput(active: active))
            await loadStorefrontUsers()
            statusMessage = active ? "Storefront login activated." : "Storefront login deactivated."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update storefront login."
        }
    }

    @MainActor
    private func unlockStorefrontUser(_ user: CustomerUser) async {
        clearMessages()
        do {
            _ = try await CustomersAPI().unlockUser(id: id, userId: user.id)
            await loadStorefrontUsers()
            statusMessage = "Storefront login unlocked."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not unlock storefront login."
        }
    }

    @MainActor
    private func saveAccountSettings() async {
        savingAccount = true
        clearMessages()
        do {
            let limit: Double?
            if accountEnabled, let raw = creditLimit.nilIfBlank {
                guard let parsed = Double(raw), parsed >= 0 else {
                    throw APIError(status: 0, message: "Credit limit must be zero or greater.")
                }
                limit = parsed
            } else {
                limit = nil
            }

            let updated = try await CustomersAPI().updateAccount(id: id, body: CustomerAccountPatch(accountEnabled: accountEnabled, creditLimit: limit))
            applyCustomer(updated)
            await loadAccount()
            statusMessage = "Account settings saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save account settings."
        }
        savingAccount = false
    }

    @MainActor
    private func savePriceTier() async {
        savingTier = true
        clearMessages()
        do {
            let updated = try await CustomersAPI().updatePriceTier(id: id, body: CustomerPriceTierPatch(priceTierId: selectedTier.nilIfBlank))
            applyCustomer(updated)
            statusMessage = "Price tier saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save price tier."
        }
        savingTier = false
    }

    @MainActor
    private func saveSalesperson() async {
        savingSalesperson = true
        clearMessages()
        do {
            let updated = try await CustomersAPI().updateSalesperson(id: id, body: CustomerSalespersonPatch(salespersonId: selectedSalesperson.nilIfBlank))
            applyCustomer(updated)
            await loadSalespeople(current: updated.salesperson)
            statusMessage = "Salesperson saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save salesperson."
        }
        savingSalesperson = false
    }

    @MainActor
    private func addInteraction() async {
        guard let summary = interactionSummary.nilIfBlank else { return }
        savingInteraction = true
        clearMessages()
        do {
            _ = try await CrmAPI().addInteraction(
                customerId: id,
                body: CustomerInteractionInput(type: interactionType, summary: summary, body: interactionBody.nilIfBlank, occurredAt: nil)
            )
            interactionSummary = ""
            interactionBody = ""
            interactionType = "CALL"
            await loadRelationshipData()
            statusMessage = "Interaction logged."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not log interaction."
        }
        savingInteraction = false
    }

    @MainActor
    private func deleteInteraction(_ interaction: CustomerInteraction) async {
        deletingInteractionId = interaction.id
        clearMessages()
        do {
            _ = try await CrmAPI().deleteInteraction(id: interaction.id)
            await loadRelationshipData()
            statusMessage = "Interaction deleted."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete interaction."
        }
        deletingInteractionId = nil
    }

    @MainActor
    private func addFollowUp() async {
        guard let title = followUpTitle.nilIfBlank else { return }
        savingFollowUp = true
        clearMessages()
        do {
            _ = try await CrmAPI().addFollowUp(
                customerId: id,
                body: FollowUpCreateInput(
                    title: title,
                    note: followUpNote.nilIfBlank,
                    dueAt: Self.isoFormatter.string(from: followUpDueAt),
                    assignedToId: followUpAssignee.nilIfBlank
                )
            )
            followUpTitle = ""
            followUpNote = ""
            followUpDueAt = Date().addingTimeInterval(86_400)
            await loadRelationshipData()
            statusMessage = "Follow-up added."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not add follow-up."
        }
        savingFollowUp = false
    }

    @MainActor
    private func setFollowUp(_ followUp: CustomerFollowUp, status: FollowUpStatus) async {
        busyFollowUpId = followUp.id
        clearMessages()
        do {
            _ = try await CrmAPI().updateFollowUp(
                id: followUp.id,
                body: FollowUpPatchInput(title: nil, note: nil, dueAt: nil, assignedToId: nil, status: status)
            )
            await loadRelationshipData()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not update follow-up."
        }
        busyFollowUpId = nil
    }

    @MainActor
    private func deleteCustomer() async {
        deletingCustomer = true
        clearMessages()
        do {
            _ = try await CustomersAPI().remove(id: id)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not delete customer."
        }
        deletingCustomer = false
    }

    private func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func taxExpiresIso() throws -> String? {
        guard let raw = taxExpires.nilIfBlank else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: raw) != nil else {
            throw APIError(status: 0, message: "Expiration must use YYYY-MM-DD.")
        }
        return "\(raw)T00:00:00.000Z"
    }

    private func priceTierOptions(for customer: Customer) -> [PriceTier] {
        var options = priceTiers
        if let tier = customer.priceTier, !options.contains(where: { $0.id == tier.id }) {
            options.append(tier)
        }
        return options.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func priceTierLabel(_ tier: PriceTier) -> String {
        guard let raw = tier.percentOffRetail, let fraction = Double(raw) else { return tier.name }
        let percent = String(format: "%.1f", fraction * 100)
        return "\(tier.name) - \(percent)% off retail"
    }

    private func salespersonOptionsForCustomer(_ customer: Customer) -> [CustomerSalesperson] {
        var options = salespersonOptions
        if let salesperson = customer.salesperson, !options.contains(where: { $0.id == salesperson.id }) {
            options.append(salesperson)
        }
        return options.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private func salespersonLabel(_ person: CustomerSalesperson) -> String {
        guard let status = person.status, status != "ACTIVE" else { return person.fullName }
        return "\(person.fullName) (\(status.capitalized))"
    }

    private func isLocked(_ user: CustomerUser) -> Bool {
        guard let lockedUntil = user.lockedUntil, let date = Self.isoFormatter.date(from: lockedUntil) else { return false }
        return date > Date()
    }

    private func copyImportedDocument(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("customer-doc-\(UUID().uuidString)-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()
}

private struct CustomerProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let customer: Customer
    let onSaved: (Customer) -> Void

    @State private var name: String
    @State private var company: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var notes: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(customer: Customer, onSaved: @escaping (Customer) -> Void) {
        self.customer = customer
        self.onSaved = onSaved
        _name = State(initialValue: customer.name)
        _company = State(initialValue: customer.company ?? "")
        _phone = State(initialValue: AppFormat.phone(customer.phone))
        _email = State(initialValue: customer.email ?? "")
        _address = State(initialValue: customer.address ?? "")
        _notes = State(initialValue: customer.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    AppTextField(label: "Name", text: $name)
                    AppTextField(label: "Company", text: $company)
                    AppTextField(label: "Phone", text: $phone)
                    AppTextField(label: "Email", text: $email)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Edit Profile")
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

        do {
            let normalizedPhone = try AppFormat.normalizeUSPhone(phone)
            let updated = try await CustomersAPI().update(
                id: customer.id,
                body: CustomerProfilePatch(
                    name: cleanName,
                    company: company.nilIfBlank,
                    phone: normalizedPhone,
                    email: email.nilIfBlank,
                    address: address.nilIfBlank,
                    notes: notes.nilIfBlank
                )
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save profile."
        }

        saving = false
    }
}

private struct CustomerPasswordResetView: View {
    @Environment(\.dismiss) private var dismiss

    let user: CustomerUser
    let onSave: (String) async throws -> Void

    @State private var password = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(user.email) {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                    Text("Minimum 8 characters.")
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
            .navigationTitle("Reset Password")
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
                    .disabled(saving || password.count < 8)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        do {
            try await onSave(password)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reset password."
        }
        saving = false
    }
}

