import XCTest
@testable import TireShop

@MainActor
final class ChecksStoreTests: XCTestCase {
    private let today = "2026-09-12"

    private func currentCheck(
        _ id: String,
        date: String?,
        amount: Double = 100,
        createdAt: String = "2026-09-01T12:00:00Z"
    ) -> UndepositedCheck {
        UndepositedCheck(
            id: id, amount: amount, reference: "check-\(id)", note: nil,
            createdAt: createdAt, methodName: "Cheque", invoiceRef: "INV-1",
            customerName: "Acme", plannedDepositDate: date, receiptRef: "RCPT-1"
        )
    }

    private func registerCheck(_ id: String, paymentId: String?, date: String?) -> CheckRegisterItem {
        CheckRegisterItem(
            id: id, paymentId: paymentId, amount: 100, reference: "check-\(id)", note: nil,
            createdAt: "2026-09-01T12:00:00Z", plannedDepositDate: date,
            receiptRef: "RCPT-1", invoiceRef: "INV-1", customerName: "Acme", methodName: "Cheque"
        )
    }

    private func report(_ asOf: String, rows: [CheckRegisterItem]) -> UndepositedCheckReport {
        UndepositedCheckReport(
            asOf: asOf, timezone: "America/New_York", totalAmount: rows.reduce(0) { $0 + $1.amount },
            count: rows.count, items: rows
        )
    }

    private func reminder(_ id: String, due: Int = 1) -> CheckReminderSummary {
        CheckReminderSummary(
            asOf: today, timezone: "America/New_York", dueTodayCount: due,
            overdueCount: 2, unscheduledCount: 3, totalAmount: 600,
            items: [registerCheck(id, paymentId: id, date: today)]
        )
    }

    func testCurrentChecksSortDueThenMissingThenFutureWithStableTies() async {
        let rows = [
            currentCheck("future-late", date: "2026-10-01"),
            currentCheck("missing-new", date: nil, createdAt: "2026-09-02T12:00:00Z"),
            currentCheck("due", date: today),
            currentCheck("overdue-b", date: "2026-09-10"),
            currentCheck("future-early", date: "2026-09-20"),
            currentCheck("missing-old", date: nil),
            currentCheck("overdue-a", date: "2026-09-10"),
            currentCheck("oldest", date: "2026-09-09"),
        ]
        let store = ChecksListStore(
            currentLoader: { UndepositedChecks(accountCode: "1010", items: rows) },
            reportLoader: { _ in XCTFail("Today must use the current-check endpoint"); throw URLError(.badURL) }
        )

        await store.load(asOf: today, today: today, canReport: false)

        XCTAssertEqual(store.items.map(\.id), [
            "oldest", "overdue-a", "overdue-b", "due", "missing-old", "missing-new", "future-early", "future-late",
        ])
        XCTAssertEqual(store.items.map(\.paymentId), store.items.map { Optional($0.id) })
        XCTAssertEqual(store.totalAmount, 800)
        XCTAssertTrue(store.ready)
        XCTAssertFalse(store.loading)
    }

    func testDateEditAndBackgroundReloadKeepOrderUntilExplicitResort() async throws {
        var serverRows = [
            currentCheck("future", date: "2026-09-20"),
            currentCheck("due", date: today),
            currentCheck("missing", date: nil),
        ]
        var saved: [String] = []
        let store = ChecksListStore(
            currentLoader: { UndepositedChecks(accountCode: "1010", items: serverRows) },
            dateSaver: { id, date in
                saved = [id, date]
                return CheckPlannedDateResult(id: id, plannedDepositDate: date)
            }
        )
        await store.load(asOf: today, today: today, canReport: true)
        let due = try XCTUnwrap(store.items.first { $0.id == "due" })

        let savedSuccessfully = await store.saveDate(for: due, date: "2026-09-30")
        XCTAssertTrue(savedSuccessfully)
        XCTAssertEqual(saved, ["due", "2026-09-30"])
        XCTAssertEqual(store.items.map(\.id), ["due", "missing", "future"])
        XCTAssertEqual(store.items.first?.plannedDepositDate, "2026-09-30")

        serverRows = [
            currentCheck("missing", date: nil, amount: 125),
            currentCheck("future", date: "2026-09-20"),
            currentCheck("due", date: "2026-09-30"),
        ]
        await store.load(asOf: today, today: today, canReport: true)
        XCTAssertEqual(store.items.map(\.id), ["due", "missing", "future"])
        XCTAssertEqual(store.totalAmount, 325)

        await store.load(asOf: today, today: today, canReport: true, resort: true)
        XCTAssertEqual(store.items.map(\.id), ["missing", "future", "due"])
    }

    func testHistoricalReportKeepsAllRowsIncludingDeletedPaymentsAndFutureSchedules() async {
        let cutoff = "2026-09-10"
        let rows = [
            registerCheck("deleted-payment", paymentId: nil, date: "2026-09-30"),
            registerCheck("unscheduled", paymentId: "payment-2", date: nil),
            registerCheck("overdue", paymentId: "payment-3", date: "2026-09-09"),
        ]
        var reportRequests: [String] = []
        var saves = 0
        let store = ChecksListStore(
            currentLoader: { XCTFail("A historical report must not use current checks"); throw URLError(.badURL) },
            reportLoader: { date in reportRequests.append(date); return self.report(date, rows: rows) },
            dateSaver: { id, date in
                saves += 1
                return CheckPlannedDateResult(id: id, plannedDepositDate: date)
            }
        )

        await store.load(asOf: cutoff, today: today, canReport: true)

        XCTAssertEqual(reportRequests, [cutoff])
        XCTAssertEqual(store.items, rows)
        XCTAssertEqual(store.totalAmount, 300)
        XCTAssertEqual(store.timezone, "America/New_York")
        let saved = await store.saveDate(for: rows[0], date: today)
        XCTAssertFalse(saved)
        XCTAssertEqual(saves, 0)
    }

    func testLateReportCannotReplaceTheNewCutoff() async throws {
        var completeOld: CheckedContinuation<UndepositedCheckReport, Error>?
        let started = expectation(description: "Old cutoff request started")
        let oldRows = [registerCheck("old", paymentId: nil, date: nil)]
        let newRows = [registerCheck("new", paymentId: "new", date: today)]
        let store = ChecksListStore(reportLoader: { date in
            if date == "2026-09-10" {
                return try await withCheckedThrowingContinuation { continuation in
                    completeOld = continuation
                    started.fulfill()
                }
            }
            return self.report(date, rows: newRows)
        })
        let oldRequest = Task { await store.load(asOf: "2026-09-10", today: today, canReport: true) }
        await fulfillment(of: [started], timeout: 2)

        await store.load(asOf: "2026-09-11", today: today, canReport: true)
        try XCTUnwrap(completeOld).resume(returning: report("2026-09-10", rows: oldRows))
        await oldRequest.value

        XCTAssertEqual(store.items, newRows)
        XCTAssertEqual(store.totalAmount, 100)
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.errorMessage)
    }

    func testReportForWrongCutoffIsRejectedAndCanBeRetried() async {
        var requests = 0
        let rows = [registerCheck("correct", paymentId: nil, date: nil)]
        let store = ChecksListStore(reportLoader: { date in
            requests += 1
            return self.report(requests == 1 ? "2026-09-09" : date, rows: rows)
        })

        await store.load(asOf: "2026-09-10", today: today, canReport: true)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.ready)
        XCTAssertNotNil(store.errorMessage)

        await store.load(asOf: "2026-09-10", today: today, canReport: true)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.items, rows)
        XCTAssertTrue(store.ready)
        XCTAssertNil(store.errorMessage)
    }

    func testRefreshFailurePreservesRowsAndRetryClearsTheError() async {
        var requests = 0
        let store = ChecksListStore(currentLoader: {
            requests += 1
            if requests == 2 { throw URLError(.timedOut) }
            return UndepositedChecks(accountCode: "1010", items: [
                self.currentCheck("check", date: self.today, amount: requests == 1 ? 100 : 150),
            ])
        })
        await store.load(asOf: today, today: today, canReport: false)

        await store.load(asOf: today, today: today, canReport: false)
        XCTAssertEqual(store.items.map(\.id), ["check"])
        XCTAssertEqual(store.totalAmount, 100)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.loading)

        await store.load(asOf: today, today: today, canReport: false)
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(store.totalAmount, 150)
        XCTAssertNil(store.errorMessage)
    }

    func testFailedDateSaveKeepsOriginalDateAndAllowsRetry() async throws {
        var saves = 0
        let store = ChecksListStore(
            currentLoader: { UndepositedChecks(accountCode: "1010", items: [self.currentCheck("check", date: nil)]) },
            dateSaver: { id, date in
                saves += 1
                if saves == 1 { throw URLError(.networkConnectionLost) }
                return CheckPlannedDateResult(id: id, plannedDepositDate: date)
            }
        )
        await store.load(asOf: today, today: today, canReport: false)
        let row = try XCTUnwrap(store.items.first)

        let invalid = await store.saveDate(for: row, date: "2026-02-30")
        XCTAssertFalse(invalid)
        XCTAssertEqual(saves, 0)
        let first = await store.saveDate(for: row, date: today)
        XCTAssertFalse(first)
        XCTAssertNil(store.items.first?.plannedDepositDate)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.saving)

        let retry = await store.saveDate(for: row, date: today)
        XCTAssertTrue(retry)
        XCTAssertEqual(saves, 2)
        XCTAssertEqual(store.items.first?.plannedDepositDate, today)
        XCTAssertNil(store.errorMessage)
    }

    func testReminderResetRejectsPreviousUsersLateResponse() async throws {
        var completeOld: CheckedContinuation<CheckReminderSummary, Error>?
        let started = expectation(description: "Previous user's reminders started")
        var requests = 0
        let current = reminder("current-user", due: 4)
        let store = CheckReminderStore(loader: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    completeOld = continuation
                    started.fulfill()
                }
            }
            return current
        })
        let oldRequest = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)

        store.reset()
        XCTAssertNil(store.summary)
        XCTAssertFalse(store.failed)
        await store.refresh()
        try XCTUnwrap(completeOld).resume(returning: reminder("previous-user"))
        await oldRequest.value

        XCTAssertEqual(store.summary, current)
        XCTAssertFalse(store.failed)
    }

    func testReminderFailureCanRetryWithoutDroppingTheLastSummary() async {
        var requests = 0
        let initial = reminder("initial")
        let refreshed = reminder("refreshed", due: 2)
        let store = CheckReminderStore(loader: {
            requests += 1
            if requests == 2 { throw URLError(.timedOut) }
            return requests == 1 ? initial : refreshed
        })
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.summary, initial)
        XCTAssertTrue(store.failed)

        await store.refresh()
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(store.summary, refreshed)
        XCTAssertFalse(store.failed)
    }

    func testReminderRefreshesDuringARequestCoalesceIntoOneFollowUp() async throws {
        var completeFirst: CheckedContinuation<CheckReminderSummary, Error>?
        let started = expectation(description: "Initial reminder request started")
        var requests = 0
        let fresh = reminder("fresh")
        let store = CheckReminderStore(loader: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    completeFirst = continuation
                    started.fulfill()
                }
            }
            return fresh
        })
        let firstRequest = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await store.refresh()
        await store.refresh()
        try XCTUnwrap(completeFirst).resume(returning: reminder("stale"))
        await firstRequest.value

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.summary, fresh)
    }

    func testCanceledReminderRequestDoesNotBlockTheNextRefresh() async throws {
        var completeCanceled: CheckedContinuation<CheckReminderSummary, Error>?
        let started = expectation(description: "Cancelable reminder request started")
        var requests = 0
        let fresh = reminder("fresh")
        let store = CheckReminderStore(loader: {
            requests += 1
            if requests == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    completeCanceled = continuation
                    started.fulfill()
                }
            }
            return fresh
        })
        let canceledRequest = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        canceledRequest.cancel()
        try XCTUnwrap(completeCanceled).resume(returning: reminder("canceled"))
        await canceledRequest.value
        XCTAssertNil(store.summary)
        XCTAssertFalse(store.failed)

        await store.refresh()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.summary, fresh)
    }

    func testCheckWorkflowsHaveBothTranslationsAndMatchingPlaceholders() throws {
        let keys = [
            "accounting.cash.amountDollars", "accounting.cash.cancel", "accounting.cash.checksLoadFailed",
            "accounting.cash.checksSelected", "accounting.cash.checksToDeposit", "accounting.cash.confirmDeposit",
            "accounting.cash.confirmTransfer", "accounting.cash.depositAnyway", "accounting.cash.depositChecksTitle",
            "accounting.cash.depositWarningBody", "accounting.cash.depositWarningFuture", "accounting.cash.depositWarningTitle",
            "accounting.cash.depositWarningUnscheduled", "accounting.cash.deselectAll", "accounting.cash.differentAccounts",
            "accounting.cash.enterPositiveAmount", "accounting.cash.enterValidFee", "accounting.cash.feeDollars",
            "accounting.cash.feeNote", "accounting.cash.fromAccount", "accounting.cash.noteOptional",
            "accounting.cash.referenceOptional", "accounting.cash.referencePlaceholderTransfer", "accounting.cash.reversed",
            "accounting.cash.reviewChecks", "accounting.cash.selectAccount", "accounting.cash.selectAll",
            "accounting.cash.selectChecks", "accounting.cash.toAccount", "accounting.cash.transferFailed",
            "accounting.cash.transferTitle", "accounting.cash.transferring", "checks.amount",
            "checks.asOf", "checks.changeDate", "checks.checkNumber", "checks.count", "checks.currentHint",
            "checks.cutoffSummary", "checks.depositAction", "checks.depositBank", "checks.depositDate",
            "checks.depositHistoryEmpty", "checks.depositHistoryHint", "checks.depositInvoices", "checks.depositReference",
            "checks.deposited", "checks.depositsTab", "checks.dueAmount", "checks.dueToday", "checks.dueTodayCount",
            "checks.empty", "checks.exportExcel", "checks.fee", "checks.historicalHint", "checks.invoice",
            "checks.listHint", "checks.method", "checks.netAmount", "checks.noAccess", "checks.notDueYet",
            "checks.note", "checks.orderHint", "checks.overdue", "checks.overdueCount", "checks.page",
            "checks.plannedDate", "checks.receipt", "checks.received", "checks.recordedBy", "checks.refresh",
            "checks.reminderFailed", "checks.reminderTitle", "checks.setDate", "checks.title", "checks.undepositedTab",
            "checks.unscheduled", "checks.unscheduledCount", "checks.viewChecks", "common.cancel", "common.close",
            "common.exporting", "common.loading", "common.next", "common.ok", "common.prev", "common.retry",
            "common.save", "nav.checks", "payment.depositDateRequired", "payment.plannedDepositDate",
        ]
        let pattern = try NSRegularExpression(pattern: "\\{[^}]+\\}")
        func placeholders(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]) }
            }.sorted()
        }
        for key in keys {
            let english = try XCTUnwrap(I18nStore.messages[.en]?[key], "Missing English: \(key)")
            for language in AppLanguage.allCases {
                let value = try XCTUnwrap(I18nStore.messages[language]?[key], "Missing \(language.rawValue): \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                XCTAssertEqual(placeholders(value), placeholders(english), "Placeholder mismatch: \(language.rawValue): \(key)")
            }
        }
    }
}
