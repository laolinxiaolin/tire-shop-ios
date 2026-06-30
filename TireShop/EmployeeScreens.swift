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
    @State private var loading = false
    @State private var paying = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var editing: EmployeeEditorTarget?
    @State private var confirmPayout = false

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
        .alert("Pay out commissions?", isPresented: $confirmPayout) {
            Button("Cancel", role: .cancel) {}
            Button("Pay out") {
                Task { await payout() }
            }
        } message: {
            Text("This will pay out \(AppFormat.money(summary.accrued)) in accrued commission.")
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
                    PrimaryButton(
                        title: "Pay out \(AppFormat.money(summary.accrued))",
                        loading: paying,
                        disabled: paying || summary.accrued <= 0
                    ) {
                        confirmPayout = true
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
                    ("Hire date", AppFormat.shortDate(employee.hireDate)),
                    ("End date", employee.endDate == nil ? "-" : AppFormat.shortDate(employee.endDate)),
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
                            RowLine(
                                title: AppFormat.shortDate(payout.createdAt),
                                subtitle: "\(payout.entryCount) lines",
                                trailing: AppFormat.money(payout.amount)
                            )
                            .padding(.horizontal, Theme.Space.md)
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

    @MainActor
    private func payout() async {
        paying = true
        actionError = nil
        do {
            _ = try await EmployeesAPI().payout(id: id)
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not pay out commissions."
        }
        paying = false
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
        guard let amount = Double(trimmed), amount >= 0 else {
            throw APIError(status: 0, message: "\(label) must be a positive number.")
        }
        return amount
    }

    private func parsePercent(_ value: String) throws -> Double {
        guard let trimmed = value.nilIfBlank else { return 0 }
        guard let percent = Double(trimmed), percent >= 0, percent <= 100 else {
            throw APIError(status: 0, message: "Commission percent must be between 0 and 100.")
        }
        return percent
    }
}
