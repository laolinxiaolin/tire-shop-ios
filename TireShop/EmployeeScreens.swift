import SwiftUI
import UIKit

private enum EmployeeLabels {
    static let statusOptions: [(EmployeeStatus, String)] = [
        ("ACTIVE", "Active"),
        ("INACTIVE", "Inactive"),
        ("TERMINATED", "Terminated")
    ]

    static let payTypeOptions: [(PayType, String)] = [
        ("HOURLY", "Hourly"),
        ("SALARY", "Salary")
    ]

    static let commissionBasisOptions: [(CommissionBasis, String)] = [
        ("REVENUE", "Revenue"),
        ("GROSS_PROFIT", "Gross profit")
    ]

    static func status(_ value: EmployeeStatus) -> String {
        statusOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func payType(_ value: PayType) -> String {
        payTypeOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func commissionBasis(_ value: CommissionBasis) -> String {
        commissionBasisOptions.first { $0.0 == value }?.1 ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private enum EmployeeDate {
    static let inputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoFormatter = ISO8601DateFormatter()

    static func input(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return String(value.prefix(10))
    }

    static func serverValue(_ value: String, label: String) throws -> String? {
        guard let trimmed = value.nilIfBlank else { return nil }
        if trimmed.contains("T") {
            return trimmed
        }
        guard let date = inputFormatter.date(from: trimmed) else {
            throw APIError(status: 0, message: "\(label) must use YYYY-MM-DD.")
        }
        return isoFormatter.string(from: date)
    }
}

private struct EmployeeEditorTarget: Identifiable {
    let employee: Employee?
    let id: String
}

struct EmployeesListNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    private let pageSize = 25

    @State private var q = ""
    @State private var status = ""
    @State private var page = 1
    @State private var data: Paged<Employee>?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: EmployeeEditorTarget?

    private var canManage: Bool {
        auth.has("employees.manage")
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
                    EmptyStateView(text: "No employees found.")
                } else if let data {
                    List(data.items) { employee in
                        NavigationLink(value: AppRoute.employeeDetail(employee.id)) {
                            EmployeeListRow(employee: employee)
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
                        editing = EmployeeEditorTarget(employee: nil, id: UUID().uuidString)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New employee")
                }
            }
        }
        .sheet(item: $editing) { target in
            EmployeeEditorView(employee: target.employee) { _ in
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
            AppTextField(label: "Search", text: $q, placeholder: "Name, position, department, number")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    statusButton(value: "", label: "All")
                    ForEach(EmployeeLabels.statusOptions, id: \.0) { option in
                        statusButton(value: option.0, label: option.1)
                    }
                }
            }

            HStack(spacing: Theme.Space.sm) {
                SecondaryButton(title: "Reset") {
                    q = ""
                    status = ""
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

    private func statusButton(value: String, label: String) -> some View {
        Button {
            guard status != value else { return }
            status = value
            page = 1
            Task { await load() }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 7)
                .background(status == value ? Theme.primary : Theme.card)
                .foregroundStyle(status == value ? Theme.primaryText : Theme.text)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(status == value ? Theme.primary : Theme.border)
                )
        }
    }

    private func pagination(_ data: Paged<Employee>) -> some View {
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
                Text("\(data.total) employees")
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
            data = try await EmployeesAPI().list(
                q: q.nilIfBlank,
                status: status.nilIfBlank,
                page: page,
                pageSize: pageSize
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load employees."
        }
        loading = false
    }
}

private struct EmployeeListRow: View {
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(employee.fullName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                EmployeeStatusBadge(status: employee.status)
            }

            Text([employee.position, employee.department].compactMap { $0?.nilIfBlank }.joined(separator: " - "))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            HStack {
                Text(EmployeeLabels.payType(employee.payType))
                Spacer()
                Text("\(AppFormat.money(employee.payRate)) - \(String(format: "%.2f", employee.commissionRate * 100))% commission")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            if let employeeNo = employee.employeeNo, !employeeNo.isEmpty {
                Text(employeeNo)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct EmployeeStatusBadge: View {
    let status: EmployeeStatus

    private var color: Color {
        switch status {
        case "ACTIVE": return Theme.success
        case "TERMINATED": return Theme.danger
        default: return Theme.muted
        }
    }

    var body: some View {
        Text(EmployeeLabels.status(status))
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

struct EmployeeDetailNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    let id: String

    @State private var employee: Employee?
    @State private var commissions: [CommissionEntry] = []
    @State private var payouts: [CommissionPayout] = []
    @State private var openPayout: CommissionPayout?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var editing: EmployeeEditorTarget?
    @State private var showPayoutSheet = false

    private var canManage: Bool {
        auth.has("employees.manage")
    }

    private var canPay: Bool {
        auth.has("employees.commissions.pay")
    }

    private var summary: EmployeeCommissionSummary {
        employee?.commissions ?? EmployeeCommissionSummary(accrued: 0, paid: 0, total: 0)
    }

    var body: some View {
        Group {
            if loading && employee == nil {
                LoadingView(label: "Loading...")
            } else if let errorMessage, employee == nil {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if let employee {
                detail(employee)
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .background(Theme.background)
        .navigationTitle(employee?.fullName ?? "Employee")
        .toolbar {
            if canManage, let employee {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EmployeeEditorTarget(employee: employee, id: employee.id)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit employee")
                }
            }
        }
        .sheet(item: $editing) { target in
            EmployeeEditorView(employee: target.employee) { _ in
                editing = nil
                Task { await load() }
            }
        }
        .sheet(isPresented: $showPayoutSheet) {
            CommissionPayoutSheet(employeeId: id) {
                showPayoutSheet = false
                Task { await load() }
            }
        }
        .task {
            if employee == nil { await load() }
        }
    }

    private func detail(_ employee: Employee) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                StatGrid(stats: [
                    ("Accrued", AppFormat.money(summary.accrued)),
                    ("Paid", AppFormat.money(summary.paid)),
                    ("Total", AppFormat.money(summary.total))
                ])

                if canPay {
                    PrimaryButton(title: "Pay out by period") {
                        showPayoutSheet = true
                    }
                }

                if let actionError {
                    Text(actionError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                EmployeeDetailSection(title: "Profile", rows: [
                    ("Status", EmployeeLabels.status(employee.status)),
                    ("Employee no.", employee.employeeNo ?? "-"),
                    ("Position", employee.position ?? "-"),
                    ("Department", employee.department ?? "-"),
                    ("Phone", AppFormat.phone(employee.phone).nilIfBlank ?? "-"),
                    ("Email", employee.email ?? "-"),
                    ("Address", employee.address ?? "-"),
                    ("Hire date", AppFormat.calendarDate(employee.hireDate)),
                    ("End date", employee.endDate == nil ? "-" : AppFormat.calendarDate(employee.endDate)),
                    ("Linked user", employee.user?.email ?? "No login")
                ])

                EmployeeDetailSection(title: "Compensation", rows: [
                    ("Pay type", EmployeeLabels.payType(employee.payType)),
                    (employee.payType == "SALARY" ? "Annual pay" : "Hourly pay", AppFormat.money(employee.payRate)),
                    ("Commission rate", String(format: "%.2f%%", employee.commissionRate * 100)),
                    ("Commission basis", EmployeeLabels.commissionBasis(employee.commissionBasis)),
                    ("Notes", employee.notes ?? "-")
                ])

                SectionHeader("Recent commissions")
                if commissions.isEmpty {
                    EmptyInlineView(text: "No commissions yet.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(commissions) { entry in
                            EmployeeCommissionRow(entry: entry)
                            Divider()
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                SectionHeader("Payout history")
                if payouts.isEmpty {
                    EmptyInlineView(text: "No payouts yet.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(payouts) { payout in
                            Button {
                                openPayout = payout
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: Theme.Space.sm) {
                                        Text(payout.ref)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.text)
                                        CommissionPayoutStatusBadge(status: payout.status)
                                        Spacer()
                                        Text(AppFormat.money(payout.amount))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.text)
                                    }
                                    Text("\(payout.entryCount) entries · \(payout.paymentMethod?.name ?? "-") · \(AppFormat.shortDate(payout.createdAt))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                    if let reason = payout.voidReason?.nilIfBlank {
                                        Text(reason).font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, Theme.Space.sm)
                            Divider()
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            .padding(Theme.Space.lg)
        }
        .refreshable {
            await load()
        }
        .sheet(item: $openPayout) { payout in
            CommissionPayoutDetailSheet(employeeId: id, payoutId: payout.id) {
                Task { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        actionError = nil
        do {
            async let employeeTask = EmployeesAPI().get(id: id)
            async let commissionTask = CommissionsAPI().list(employeeId: id, pageSize: 50)
            async let payoutTask = EmployeesAPI().payouts(id: id)
            let (loadedEmployee, commissionPage, loadedPayouts) = try await (employeeTask, commissionTask, payoutTask)
            employee = loadedEmployee
            commissions = commissionPage.items
            payouts = loadedPayouts
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load employee."
        }
        loading = false
    }
}

private struct EmployeeDetailSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title)
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

private struct EmptyInlineView: View {
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

private struct EmployeeCommissionRow: View {
    let entry: CommissionEntry

    var body: some View {
        Group {
            if let sale = entry.sale {
                NavigationLink(value: AppRoute.saleDetail(sale.id)) {
                    content(saleLabel: sale.ref ?? "Sale")
                }
            } else {
                content(saleLabel: entry.note?.nilIfBlank == nil ? "-" : "Rollover")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private func content(saleLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormat.shortDate(entry.createdAt))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(AppFormat.money(entry.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(entry.amount < 0 ? Theme.danger : Theme.text)
            }

            HStack {
                Text(saleLabel)
                Spacer()
                Text(entry.status.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)

            Text("\(EmployeeLabels.commissionBasis(entry.basis)) - \(AppFormat.money(entry.basisAmount)) x \(String(format: "%.2f", entry.rate * 100))%")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct EmployeeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let employee: Employee?
    let onSaved: (Employee) -> Void

    @State private var fullName: String
    @State private var employeeNo: String
    @State private var userId: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var position: String
    @State private var department: String
    @State private var status: EmployeeStatus
    @State private var hireDate: String
    @State private var endDate: String
    @State private var payType: PayType
    @State private var payRate: String
    @State private var commissionPct: String
    @State private var commissionBasis: CommissionBasis
    @State private var notes: String
    @State private var users: [UserAccount] = []
    @State private var saving = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        employee != nil
    }

    private var canSeeUsers: Bool {
        auth.has("users.manage")
    }

    init(employee: Employee?, onSaved: @escaping (Employee) -> Void) {
        self.employee = employee
        self.onSaved = onSaved
        _fullName = State(initialValue: employee?.fullName ?? "")
        _employeeNo = State(initialValue: employee?.employeeNo ?? "")
        _userId = State(initialValue: employee?.userId ?? "")
        _phone = State(initialValue: employee?.phone ?? "")
        _email = State(initialValue: employee?.email ?? "")
        _address = State(initialValue: employee?.address ?? "")
        _position = State(initialValue: employee?.position ?? "")
        _department = State(initialValue: employee?.department ?? "")
        _status = State(initialValue: employee?.status ?? "ACTIVE")
        _hireDate = State(initialValue: EmployeeDate.input(employee?.hireDate))
        _endDate = State(initialValue: EmployeeDate.input(employee?.endDate))
        _payType = State(initialValue: employee?.payType ?? "HOURLY")
        _payRate = State(initialValue: employee.map { String($0.payRate) } ?? "")
        _commissionPct = State(initialValue: employee.map { String(format: "%.4f", $0.commissionRate * 100) } ?? "")
        _commissionBasis = State(initialValue: employee?.commissionBasis ?? "REVENUE")
        _notes = State(initialValue: employee?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    AppTextField(label: "Name", text: $fullName, placeholder: "Full name", textContentType: .name)
                    AppTextField(label: "Employee no.", text: $employeeNo)

                    Picker("Status", selection: $status) {
                        ForEach(EmployeeLabels.statusOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }

                    AppTextField(label: "Position", text: $position)
                    AppTextField(label: "Department", text: $department)
                    AppTextField(label: "Phone", text: $phone, keyboardType: .phonePad, textContentType: .telephoneNumber)
                    AppTextField(label: "Email", text: $email, keyboardType: .emailAddress, textContentType: .emailAddress)
                    AppTextField(label: "Address", text: $address, textContentType: .fullStreetAddress)
                }

                Section("Dates") {
                    AppTextField(label: "Hire date", text: $hireDate, placeholder: "YYYY-MM-DD")
                    AppTextField(label: "End date", text: $endDate, placeholder: "YYYY-MM-DD")
                }

                Section("Compensation") {
                    Picker("Pay type", selection: $payType) {
                        ForEach(EmployeeLabels.payTypeOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }

                    AppTextField(
                        label: payType == "SALARY" ? "Annual pay" : "Hourly pay",
                        text: $payRate,
                        keyboardType: .decimalPad
                    )

                    AppTextField(label: "Commission percent", text: $commissionPct, keyboardType: .decimalPad)

                    Picker("Commission basis", selection: $commissionBasis) {
                        ForEach(EmployeeLabels.commissionBasisOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                }

                if canSeeUsers {
                    Section("Linked login") {
                        Picker("User", selection: $userId) {
                            Text("No login").tag("")
                            ForEach(users) { user in
                                Text("\(user.fullName) (\(user.email))").tag(user.id)
                            }
                        }
                        Text("The selected user can sign in as this employee.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
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
            .navigationTitle(isEditing ? "Edit Employee" : "New Employee")
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
                    .disabled(saving || fullName.nilIfBlank == nil)
                }
            }
            .task {
                if canSeeUsers && users.isEmpty {
                    await loadUsers()
                }
            }
        }
    }

    @MainActor
    private func loadUsers() async {
        do {
            users = try await UsersAPI().list()
        } catch {
            users = []
        }
    }

    @MainActor
    private func save() async {
        guard let cleanName = fullName.nilIfBlank else { return }
        saving = true
        errorMessage = nil

        do {
            let parsedPayRate = try parseAmount(payRate, label: payType == "SALARY" ? "Annual pay" : "Hourly pay")
            let parsedCommissionPct = try parsePercent(commissionPct)
            let cleanUserId = userId.nilIfBlank

            let input = EmployeeSaveInput(
                fullName: cleanName,
                employeeNo: employeeNo.nilIfBlank,
                userId: cleanUserId,
                includeUserId: isEditing || cleanUserId != nil,
                phone: phone.nilIfBlank,
                email: email.nilIfBlank,
                address: address.nilIfBlank,
                position: position.nilIfBlank,
                department: department.nilIfBlank,
                status: status,
                hireDate: try EmployeeDate.serverValue(hireDate, label: "Hire date"),
                endDate: try EmployeeDate.serverValue(endDate, label: "End date"),
                payType: payType,
                payRate: parsedPayRate,
                commissionRate: parsedCommissionPct / 100,
                commissionBasis: commissionBasis,
                notes: notes.nilIfBlank
            )

            let saved: Employee
            if let employee {
                saved = try await EmployeesAPI().update(id: employee.id, body: input)
            } else {
                saved = try await EmployeesAPI().create(input)
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save employee."
        }

        saving = false
    }

    private func parseAmount(_ value: String, label: String) throws -> Double {
        guard let trimmed = value.nilIfBlank else { return 0 }
        guard let amount = AppFormat.parseAmount(trimmed), amount >= 0 else {
            throw APIError(status: 0, message: "\(label) must be a positive number.")
        }
        return amount
    }

    private func parsePercent(_ value: String) throws -> Double {
        guard let trimmed = value.nilIfBlank else { return 0 }
        guard let percent = AppFormat.parseAmount(trimmed), percent >= 0, percent <= 100 else {
            throw APIError(status: 0, message: "Commission percent must be between 0 and 100.")
        }
        return percent
    }
}

// MARK: - Numbered commission payouts

private func commissionPayoutTone(_ status: CommissionPayoutStatus) -> Color {
    switch status {
    case "PAID": return Theme.success
    case "DRAFT": return .orange
    default: return Theme.muted
    }
}

struct CommissionPayoutStatusBadge: View {
    let status: CommissionPayoutStatus

    var body: some View {
        Text(status.capitalized)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(commissionPayoutTone(status))
            .background(commissionPayoutTone(status).opacity(0.12))
            .clipShape(Capsule())
    }
}

/// Composes a numbered payout draft for one pay period.
///
/// The draft reserves the lines it selects; nothing posts to accounting until
/// it is marked paid from the payout document.
private struct CommissionPayoutSheet: View {
    let employeeId: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from = ShopClock.monthStart()
    @State private var to = Date()
    @State private var sales: [CommissionEntry] = []
    @State private var rollovers: [CommissionEntry] = []
    @State private var selected = Set<String>()
    @State private var methods: [PaymentMethod] = []
    @State private var methodId = ""
    @State private var loading = false
    @State private var creating = false
    @State private var errorMessage: String?
    @State private var requestID = 0
    @State private var createPresented = false
    // Stable across retries of the same composition, and reset whenever the
    // selection changes so a materially different payout gets a fresh key.
    @State private var idempotencyKey: String?

    /// What a payout may actually settle: accrued sale commissions that no other
    /// draft has already reserved.
    private var eligible: [CommissionEntry] {
        sales.filter {
            $0.status == "ACCRUED" && $0.payoutId == nil && $0.amount > 0 && $0.saleId != nil
        }
    }

    private var selectedEntries: [CommissionEntry] {
        eligible.filter { selected.contains($0.id) }
    }

    private var selectedTotal: Double {
        selectedEntries.reduce(0) { $0 + $1.amount }
    }

    private var rolloverTotal: Double {
        rollovers.reduce(0) { $0 + $1.amount }
    }

    /// Outstanding negative rollovers ride along with any payout, so they come
    /// off the total rather than being opted into.
    private var payoutTotal: Double {
        selectedTotal + rolloverTotal
    }

    private var selectedMethod: PaymentMethod? {
        methods.first { $0.id == methodId }
    }

    private var canCreate: Bool {
        !creating && !loading && !selectedEntries.isEmpty && !methodId.isEmpty && payoutTotal >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }
                }

                if loading {
                    Section { ProgressView() }
                } else if eligible.isEmpty {
                    Section {
                        Text("No commissions are eligible in this period.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Section("Sales in period") {
                        ForEach(eligible) { entry in
                            Button {
                                toggle(entry.id)
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(entry.id) ? Theme.primary : Theme.muted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.sale?.ref ?? entry.note?.nilIfBlank ?? "Commission")
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.text)
                                        Text(AppFormat.shortDate(entry.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(AppFormat.money(entry.amount))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .tint(Theme.text)
                        }

                        Button(selected.count == eligible.count ? "Select none" : "Select all") {
                            setSelection(
                                selected.count == eligible.count ? [] : Set(eligible.map(\.id))
                            )
                        }
                        .font(.caption)
                    }
                }

                if !rollovers.isEmpty {
                    Section {
                        ForEach(rollovers) { rollover in
                            Label(
                                (rollover.note?.nilIfBlank ?? "Rollover") + " · " + AppFormat.money(rollover.amount),
                                systemImage: "arrow.uturn.forward"
                            )
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        }
                    } header: {
                        Text("Automatic rollovers")
                    } footer: {
                        Text("Outstanding negative balances are always carried into the next payout.")
                    }
                }

                Section("Summary") {
                    RowLine(
                        title: "Selected entries",
                        trailing: "\(selectedEntries.count) · \(AppFormat.money(selectedTotal))"
                    )
                    if !rollovers.isEmpty {
                        RowLine(
                            title: "Rollovers",
                            trailing: "\(rollovers.count) · \(AppFormat.money(rolloverTotal))"
                        )
                    }
                    RowLine(title: "Payout total", trailing: AppFormat.money(payoutTotal))

                    if methods.isEmpty {
                        Text("No payment method has an employee-payout account configured.")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    } else {
                        Picker("Pay out via", selection: $methodId) {
                            Text("Choose a method").tag("")
                            ForEach(methods) { method in
                                Text("\(method.name) · \(method.payoutAccount?.name ?? "—")")
                                    .tag(method.id)
                            }
                        }
                    }

                    if payoutTotal < 0 && !selectedEntries.isEmpty {
                        Text("The rollovers owed exceed this selection. Add more sales to cover them.")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(creating ? "Creating..." : "Create draft payout \(AppFormat.money(payoutTotal))") {
                        createPresented = true
                    }
                    .disabled(!canCreate)
                } footer: {
                    Text("When paid, accounting will credit \(selectedMethod?.payoutAccount?.name ?? "—").")
                }
            }
            .navigationTitle("Pay out by period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await loadMethods() }
            .task(id: PayoutRange(from: from, to: to)) { await loadPreview() }
            .onChange(of: methodId) { _, _ in
                // A different funding method is a different request identity.
                idempotencyKey = nil
            }
            .alert("Create draft payout?", isPresented: $createPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Create draft") { Task { await create() } }
            } message: {
                Text("Reserve \(selectedEntries.count) commission line\(selectedEntries.count == 1 ? "" : "s") for \(AppFormat.money(payoutTotal)) via \(selectedMethod?.name ?? "the selected method")?")
            }
        }
    }

    /// Identifies one from/to pair so the preview reloads when either moves.
    private struct PayoutRange: Equatable {
        let from: Date
        let to: Date
    }

    private func toggle(_ id: String) {
        var next = selected
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        setSelection(next)
    }

    /// Any change to the selection invalidates the idempotency key, so a
    /// materially different payout can never reuse the previous one's.
    private func setSelection(_ newSelection: Set<String>) {
        selected = newSelection
        idempotencyKey = nil
    }

    @MainActor
    private func loadMethods() async {
        guard methods.isEmpty else { return }
        do {
            // Only explicitly disbursement-capable manual methods can fund a
            // payout: a processor-backed method has no outgoing account, and one
            // without a payout account would silently reuse its incoming
            // clearing account for outgoing cash.
            let all = try await CashAccountsAPI().methods()
            methods = all.filter { $0.isActive && $0.processor == nil && $0.payoutAccount != nil }
            if methodId.isEmpty, let first = methods.first {
                methodId = first.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load payment methods."
        }
    }

    @MainActor
    private func loadPreview() async {
        requestID += 1
        let current = requestID
        guard from <= to else {
            sales = []
            rollovers = []
            setSelection([])
            loading = false
            errorMessage = "The From date must not be after the To date."
            return
        }

        loading = true
        errorMessage = nil
        do {
            let preview = try await EmployeesAPI().payoutPreview(
                id: employeeId,
                from: ShopClock.dayString(from: from),
                to: ShopClock.dayString(from: to)
            )
            guard current == requestID else { return }
            sales = preview.sales
            rollovers = preview.rollovers
            setSelection(Set(eligible.map(\.id)))
        } catch {
            guard current == requestID else { return }
            sales = []
            rollovers = []
            setSelection([])
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load commissions for this period."
        }
        if current == requestID { loading = false }
    }

    @MainActor
    private func create() async {
        guard canCreate else { return }
        creating = true
        errorMessage = nil
        do {
            let key = idempotencyKey ?? UUID().uuidString
            idempotencyKey = key
            _ = try await EmployeesAPI().createPayout(
                id: employeeId,
                body: CommissionPayoutCreateInput(
                    entryIds: selectedEntries.map(\.id),
                    paymentMethodId: methodId,
                    // Rounded the way the server rounds it, so a float tail
                    // cannot fail the expected-amount check.
                    expectedAmount: (payoutTotal * 100).rounded() / 100,
                    from: ShopClock.dayString(from: from),
                    to: ShopClock.dayString(from: to)
                ),
                idempotencyKey: key
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not create the payout."
        }
        creating = false
    }
}

/// One payout document: the lines it reserved, and the pay/void actions that
/// move it out of DRAFT.
struct CommissionPayoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    let employeeId: String
    let payoutId: String
    let onChanged: () -> Void

    @State private var payout: CommissionPayout?
    @State private var loading = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var payPresented = false
    @State private var voidPresented = false
    @State private var voidReason = ""

    private var canPay: Bool { auth.has("employees.commissions.pay") }
    private var canVoid: Bool { auth.canActOrRequest("employees.commissions.pay") }

    var body: some View {
        NavigationStack {
            Group {
                if loading && payout == nil {
                    LoadingView(label: "Loading payout...")
                } else if let errorMessage, payout == nil {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if let payout {
                    content(payout)
                } else {
                    LoadingView(label: "Loading payout...")
                }
            }
            .navigationTitle(payout?.ref ?? "Payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { if payout == nil { await load() } }
            .alert("Mark payout paid?", isPresented: $payPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Mark paid") { Task { await pay() } }
            } message: {
                if let payout {
                    Text("This posts the journal for \(payout.ref) in the amount of \(AppFormat.money(payout.amount)).")
                }
            }
            .alert("Void payout", isPresented: $voidPresented) {
                TextField("Reason (optional)", text: $voidReason)
                Button("Cancel", role: .cancel) {}
                Button(payout?.status == "PAID" ? "Reverse and void" : "Void", role: .destructive) {
                    Task { await voidPayout() }
                }
            } message: {
                if payout?.status == "PAID" {
                    Text("This reverses the posted accounting and re-accrues every eligible commission line.")
                } else {
                    Text("This releases the draft's reserved commission lines.")
                }
            }
        }
    }

    private func content(_ payout: CommissionPayout) -> some View {
        Form {
            Section {
                HStack {
                    Text(payout.ref).font(.headline)
                    Spacer()
                    CommissionPayoutStatusBadge(status: payout.status)
                }
                RowLine(title: "Amount", trailing: AppFormat.money(payout.amount))
                RowLine(title: "Entries", trailing: "\(payout.entryCount)")
                if let periodFrom = payout.periodFrom, let periodTo = payout.periodTo {
                    RowLine(
                        title: "Period",
                        trailing: "\(AppFormat.calendarDate(periodFrom)) – \(AppFormat.calendarDate(periodTo))"
                    )
                }
                RowLine(title: "Payment method", trailing: payout.paymentMethod?.name ?? "—")
                if let account = payout.fundingAccount {
                    RowLine(title: "Funding account", trailing: "\(account.code) · \(account.name)")
                }
                RowLine(title: "Created", trailing: AppFormat.dateTime(payout.createdAt))
                if let paidAt = payout.paidAt {
                    RowLine(title: "Paid", trailing: AppFormat.dateTime(paidAt))
                }
                if let voidedAt = payout.voidedAt {
                    RowLine(title: "Voided", trailing: AppFormat.dateTime(voidedAt))
                }
                if let reason = payout.voidReason?.nilIfBlank {
                    RowLine(title: "Void reason", trailing: reason)
                }
            }

            if let notice {
                Section { Text(notice).font(.subheadline).foregroundStyle(Theme.success) }
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.subheadline).foregroundStyle(Theme.danger) }
            }

            if let entries = payout.entries, !entries.isEmpty {
                Section("Commission lines") {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.sale?.ref ?? entry.note?.nilIfBlank ?? "Commission")
                                    .font(.subheadline)
                                Text(AppFormat.shortDate(entry.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(AppFormat.money(entry.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if canPay || canVoid {
                Section {
                    if canPay && payout.status == "DRAFT" {
                        Button(working ? "Posting..." : "Mark paid") {
                            payPresented = true
                        }
                        .disabled(working)
                    }
                    if canVoid && payout.status != "VOID" {
                        Button("Void payout", role: .destructive) {
                            voidReason = ""
                            voidPresented = true
                        }
                        .disabled(working)
                    }
                } footer: {
                    if payout.status == "DRAFT" {
                        Text("Marking it paid posts the payout journal in one transaction.")
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        do {
            payout = try await EmployeesAPI().payout(id: employeeId, payoutId: payoutId)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load the payout."
        }
        loading = false
    }

    @MainActor
    private func pay() async {
        working = true
        errorMessage = nil
        notice = nil
        do {
            payout = try await EmployeesAPI().payPayout(id: employeeId, payoutId: payoutId)
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not mark the payout paid."
        }
        working = false
    }

    @MainActor
    private func voidPayout() async {
        working = true
        errorMessage = nil
        notice = nil
        do {
            // Voiding a PAID payout reverses a posted cash journal, so it takes
            // the same second-signature route as the other cash reversals and
            // can come back as an approval request instead of a document.
            let result = try await EmployeesAPI().voidPayout(
                id: employeeId,
                payoutId: payoutId,
                reason: voidReason.nilIfBlank
            )
            switch result {
            case .immediate(let updated):
                payout = updated
            case .approval:
                notice = "Sent for approval. The payout stays as it is until it is decided."
                await load()
            }
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not void the payout."
        }
        working = false
    }
}
