import Foundation
import Combine

extension Notification.Name {
    static let showCurrentChecks = Notification.Name("tireShop.showCurrentChecks")
}

@MainActor
final class ChecksListStore: ObservableObject {
    typealias CurrentLoader = () async throws -> UndepositedChecks
    typealias ReportLoader = (String) async throws -> UndepositedCheckReport
    typealias DateSaver = (String, String) async throws -> CheckPlannedDateResult

    @Published private(set) var items: [CheckRegisterItem] = []
    @Published private(set) var totalAmount = 0.0
    @Published private(set) var timezone = ShopClock.timeZone.identifier
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var ready = false
    @Published private(set) var errorMessage: String?

    private let currentLoader: CurrentLoader
    private let reportLoader: ReportLoader
    private let dateSaver: DateSaver
    private var scope: String?
    private var generation = 0
    private var rowOrder: [String]?

    init(
        currentLoader: @escaping CurrentLoader = { try await CashAccountsAPI().undepositedChecks() },
        reportLoader: @escaping ReportLoader = { try await AccountingAPI().undepositedCheckReport(asOf: $0) },
        dateSaver: @escaping DateSaver = {
            try await AccountingAPI().updatePlannedDepositDate(paymentId: $0, plannedDepositDate: $1)
        }
    ) {
        self.currentLoader = currentLoader
        self.reportLoader = reportLoader
        self.dateSaver = dateSaver
    }

    func load(asOf: String, today: String, canReport: Bool, resort: Bool = false) async {
        guard !saving else { return }
        generation += 1
        let request = generation
        let current = asOf == today
        let nextScope = "\(asOf):\(current):\(canReport)"
        if scope != nextScope {
            scope = nextScope
            items = []
            totalAmount = 0
            ready = false
            rowOrder = nil
        }
        if resort { rowOrder = nil }
        errorMessage = nil
        guard CheckDates.isValid(asOf), asOf <= today, current || canReport else {
            loading = false
            return
        }
        loading = true
        defer { if request == generation { loading = false } }
        do {
            let rows: [CheckRegisterItem]
            let total: Double
            let zone: String
            if current {
                let result = try await currentLoader()
                rows = result.items.map { CheckRegisterItem($0) }
                total = rows.reduce(0) { $0 + $1.amount }
                zone = ShopClock.timeZone.identifier
            } else {
                let report = try await reportLoader(asOf)
                guard report.asOf == asOf else { throw URLError(.badServerResponse) }
                rows = report.items
                total = report.totalAmount
                zone = report.timezone
            }
            try Task.checkCancellation()
            guard request == generation else { return }
            if current {
                items = Self.ordered(rows, today: today, preserving: rowOrder)
                rowOrder = items.map(\.id)
            } else {
                items = rows
            }
            totalAmount = total
            timezone = zone
            ready = true
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func saveDate(for row: CheckRegisterItem, date: String) async -> Bool {
        guard !saving, let paymentId = row.paymentId, CheckDates.isValid(date) else { return false }
        generation += 1
        let request = generation
        loading = false
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let result = try await dateSaver(paymentId, date)
            guard request == generation else { return false }
            if let index = items.firstIndex(where: { $0.id == row.id }) {
                items[index].plannedDepositDate = result.plannedDepositDate
            }
            return true
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            return false
        }
    }

    static func ordered(_ rows: [CheckRegisterItem], today: String, preserving order: [String]?) -> [CheckRegisterItem] {
        func priority(_ row: CheckRegisterItem) -> Int {
            guard let date = row.plannedDepositDate else { return 1 }
            return date <= today ? 0 : 2
        }
        let sorted = rows.sorted { left, right in
            if priority(left) != priority(right) { return priority(left) < priority(right) }
            if left.plannedDepositDate != right.plannedDepositDate {
                return (left.plannedDepositDate ?? "") < (right.plannedDepositDate ?? "")
            }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.id < right.id
        }
        guard let order else { return sorted }
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return sorted.enumerated().sorted {
            let left = positions[$0.element.id] ?? (positions.count + $0.offset)
            let right = positions[$1.element.id] ?? (positions.count + $1.offset)
            return left < right
        }.map(\.element)
    }
}

@MainActor
final class CheckReminderStore: ObservableObject {
    @Published private(set) var summary: CheckReminderSummary?
    @Published private(set) var failed = false
    @Published private var dismissedDay: String?
    private var loading = false
    private var pending = false
    private var generation = 0
    private var userID: String?
    private let defaults: UserDefaults
    private let currentDay: () -> String
    private let loader: () async throws -> CheckReminderSummary

    init(
        defaults: UserDefaults = .standard,
        currentDay: @escaping () -> String = { ShopClock.dayString(from: Date()) },
        loader: @escaping () async throws -> CheckReminderSummary = {
            try await AccountingAPI().checkReminders()
        }
    ) {
        self.defaults = defaults
        self.currentDay = currentDay
        self.loader = loader
    }

    var isBannerVisible: Bool {
        guard dismissedDay != currentDay() else { return false }
        if failed { return true }
        guard let summary else { return false }
        return summary.dueTodayCount + summary.overdueCount + summary.unscheduledCount > 0
    }

    private var dismissalKey: String? {
        userID.map { "checkReminderDismissedDay.v1.\($0)" }
    }

    func dismissForToday() {
        dismissedDay = currentDay()
        if let dismissalKey {
            defaults.set(dismissedDay, forKey: dismissalKey)
        }
    }

    func reset(for userID: String? = nil) {
        generation += 1
        self.userID = userID
        dismissedDay = dismissalKey.flatMap { defaults.string(forKey: $0) }
        summary = nil
        failed = false
        loading = false
        pending = false
    }

    func refresh() async {
        if let dismissalKey {
            let savedDay = defaults.string(forKey: dismissalKey)
            if dismissedDay != savedDay { dismissedDay = savedDay }
        }
        guard !loading else { pending = true; return }
        loading = true
        let request = generation
        do {
            let value = try await loader()
            guard request == generation else { return }
            if !Task.isCancelled {
                summary = value
                failed = false
            }
        } catch {
            guard request == generation else { return }
            if !Task.isCancelled { failed = true }
        }
        guard request == generation else { return }
        loading = false
        if Task.isCancelled { pending = false; return }
        if pending {
            pending = false
            await refresh()
        }
    }
}
