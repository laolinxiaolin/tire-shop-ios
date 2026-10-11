import XCTest
@testable import TireShop

@MainActor
final class PaymentApplicationStoreTests: XCTestCase {
    private let filter = PaymentApplicationListFilter(view: "mine", query: nil, status: nil)

    func testFailedNextPageKeepsDisplayedPageAndRetriesIt() async {
        var pages: [Int] = []
        var fail = true
        let store = PaymentApplicationsListStore(pageSize: 1) { _, page, size in
            pages.append(page)
            if page == 2 && fail { throw URLError(.notConnectedToInternet) }
            return Paged(items: [self.row("page-\(page)")], total: 3, page: page, pageSize: size)
        }
        await store.load(filter: filter, page: 1)
        await store.load(filter: filter, page: store.page + 1)
        XCTAssertEqual(store.page, 1)
        XCTAssertEqual(store.data?.items.map(\.id), ["page-1"])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.loading)
        fail = false
        await store.retry()
        XCTAssertEqual(pages, [1, 2, 2])
        XCTAssertEqual(store.page, 2)
        XCTAssertNil(store.errorMessage)
        await store.load(filter: filter, page: store.page + 1)
        XCTAssertEqual(pages, [1, 2, 2, 3])
    }

    func testFailedLastPageCanStillBeRequestedWithNext() async {
        var pages: [Int] = []
        let store = PaymentApplicationsListStore(pageSize: 1) { _, page, size in
            pages.append(page)
            if pages.count == 2 { throw URLError(.timedOut) }
            return Paged(items: [self.row("page-\(page)")], total: 2, page: page, pageSize: size)
        }
        await store.load(filter: filter, page: 1)
        await store.load(filter: filter, page: store.page + 1)
        XCTAssertEqual(store.page, 1)
        await store.load(filter: filter, page: store.page + 1)
        XCTAssertEqual(pages, [1, 2, 2])
        XCTAssertEqual(store.page, 2)
    }

    func testOlderPageCannotReplaceNewFilterResults() async {
        let started = expectation(description: "Old page started")
        var finish: CheckedContinuation<Paged<PaymentApplicationRow>, Error>?
        let store = PaymentApplicationsListStore(pageSize: 1) { filter, page, size in
            if page == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
            return Paged(items: [self.row(filter.query ?? "all")], total: 3, page: page, pageSize: size)
        }
        await store.load(filter: filter, page: 1)
        let old = Task { await store.load(filter: filter, page: 2) }
        await fulfillment(of: [started], timeout: 1)
        let newFilter = PaymentApplicationListFilter(view: "all", query: "Acme", status: "DRAFT")
        await store.load(filter: newFilter, page: 1)
        finish?.resume(returning: Paged(items: [row("old")], total: 3, page: 2, pageSize: 1))
        await old.value
        XCTAssertEqual(store.page, 1)
        XCTAssertEqual(store.data?.items.map(\.id), ["Acme"])
        XCTAssertFalse(store.loading)
    }

    func testChangingPayeeClearsSelectionsBeforeLoadingAndRejectsOldRows() async {
        let store = PaymentApplicationResourcesStore(
            billsLoader: { [self] vendor in [bill(vendor)] },
            banksLoader: { [self] vendor, currency in [bank(vendor, currency: currency)] })
        seed(store, vendor: "a")
        XCTAssertTrue(store.ownsSelections(vendorId: "a", currency: "USD"))

        let request = store.prepare(vendorId: "b", currency: "USD")
        XCTAssertTrue(store.bills.isEmpty)
        XCTAssertTrue(store.bankOptions.isEmpty)
        XCTAssertTrue(store.bankAccountId.isEmpty)
        XCTAssertTrue(store.selectedBillIDs.isEmpty)
        XCTAssertTrue(store.amounts.isEmpty)
        XCTAssertTrue(store.lineNotes.isEmpty)
        XCTAssertFalse(store.canSelectBills(vendorId: "b"))
        XCTAssertFalse(store.ownsSelections(vendorId: "b", currency: "USD"))
        store.toggle(bill("a"), selected: true)
        XCTAssertTrue(store.selectedBillIDs.isEmpty)

        await store.load(request)
        store.toggle(bill("a"), selected: true)
        XCTAssertTrue(store.selectedBillIDs.isEmpty)
        store.toggle(bill("b"), selected: true)
        XCTAssertTrue(store.ownsSelections(vendorId: "b", currency: "USD"))
        XCTAssertFalse(store.ownsSelections(vendorId: "a", currency: "USD"))
        store.bankAccountId = "bank-a-USD"
        XCTAssertFalse(store.ownsSelections(vendorId: "b", currency: "USD"))
    }

    func testLatePayeeResponsesCannotRestorePreviousResources() async {
        let billsStarted = expectation(description: "Old bills started")
        let banksStarted = expectation(description: "Old banks started")
        var finishBills: CheckedContinuation<[PaymentApplicationOpenBill], Error>?
        var finishBanks: CheckedContinuation<[PaymentApplicationBankOption], Error>?
        let store = PaymentApplicationResourcesStore(billsLoader: { vendor in
            if vendor == "a" {
                return try await withCheckedThrowingContinuation { continuation in
                    finishBills = continuation
                    billsStarted.fulfill()
                }
            }
            return [self.bill(vendor)]
        }, banksLoader: { vendor, currency in
            if vendor == "a" {
                return try await withCheckedThrowingContinuation { continuation in
                    finishBanks = continuation
                    banksStarted.fulfill()
                }
            }
            return [self.bank(vendor, currency: currency)]
        })
        let oldRequest = store.prepare(vendorId: "a", currency: "USD")
        let old = Task { await store.load(oldRequest) }
        await fulfillment(of: [billsStarted, banksStarted], timeout: 1)
        await store.load(store.prepare(vendorId: "b", currency: "USD"))
        finishBills?.resume(returning: [bill("a")])
        finishBanks?.resume(returning: [bank("a")])
        await old.value
        XCTAssertEqual(store.bills.map(\.id), ["bill-b"])
        XCTAssertEqual(store.bankOptions.map(\.id), ["bank-b-USD"])
        XCTAssertEqual(store.bankAccountId, "bank-b-USD")
        store.toggle(bill("b"), selected: true)
        XCTAssertTrue(store.ownsSelections(vendorId: "b", currency: "USD"))
    }

    func testClearingPayeeInvalidatesInFlightRequests() async {
        let started = expectation(description: "Old bank started")
        var finish: CheckedContinuation<[PaymentApplicationBankOption], Error>?
        let store = PaymentApplicationResourcesStore(billsLoader: { [self] in [bill($0)] },
            banksLoader: { _, _ in
                try await withCheckedThrowingContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            })
        let request = store.prepare(vendorId: "a", currency: "USD")
        let old = Task { await store.load(request) }
        await fulfillment(of: [started], timeout: 1)
        _ = store.prepare(vendorId: "", currency: "USD")
        finish?.resume(returning: [bank("a")])
        await old.value
        XCTAssertTrue(store.bills.isEmpty)
        XCTAssertTrue(store.bankOptions.isEmpty)
        XCTAssertTrue(store.bankAccountId.isEmpty)
        XCTAssertTrue(store.selectedBillIDs.isEmpty)
        XCTAssertFalse(store.ownsSelections(vendorId: "a", currency: "USD"))
        XCTAssertFalse(store.billsLoading)
        XCTAssertFalse(store.banksLoading)
    }

    func testRapidCurrencyChangesClearBankSelectionAndRejectLateCurrencyResponse() async {
        let started = expectation(description: "CAD bank started")
        var finish: CheckedContinuation<[PaymentApplicationBankOption], Error>?
        var billLoads = 0
        let store = PaymentApplicationResourcesStore(billsLoader: { _ in
            billLoads += 1
            return []
        }, banksLoader: { vendor, currency in
            if currency == "CAD" {
                return try await withCheckedThrowingContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
            return [self.bank(vendor, currency: currency)]
        })
        seed(store, vendor: "a")
        let request = store.prepare(vendorId: "a", currency: "CAD")
        XCTAssertTrue(store.bankOptions.isEmpty)
        XCTAssertTrue(store.bankAccountId.isEmpty)
        XCTAssertEqual(store.selectedBillIDs, ["bill-a"])
        XCTAssertFalse(store.ownsSelections(vendorId: "a", currency: "CAD"))
        let old = Task { await store.load(request) }
        await fulfillment(of: [started], timeout: 1)
        await store.load(store.prepare(vendorId: "a", currency: "EUR"))
        finish?.resume(returning: [bank("a", currency: "CAD")])
        await old.value
        XCTAssertEqual(billLoads, 0)
        XCTAssertEqual(store.bankOptions.map(\.id), ["bank-a-EUR"])
        XCTAssertTrue(store.ownsSelections(vendorId: "a", currency: "EUR"))
        XCTAssertFalse(store.ownsSelections(vendorId: "a", currency: "USD"))
    }

    func testFailedBankLoadKeepsSavingBlockedAndRetriesOnlyBanks() async {
        var billLoads = 0
        var bankLoads = 0
        let store = PaymentApplicationResourcesStore(billsLoader: { vendor in
            billLoads += 1
            return [self.bill(vendor)]
        }, banksLoader: { vendor, currency in
            bankLoads += 1
            if bankLoads == 1 { throw URLError(.timedOut) }
            return [self.bank(vendor, currency: currency)]
        })
        await store.load(store.prepare(vendorId: "a", currency: "USD"))
        store.toggle(bill("a"), selected: true)
        XCTAssertNotNil(store.banksError)
        XCTAssertFalse(store.ownsSelections(vendorId: "a", currency: "USD"))
        await store.load(store.prepare(vendorId: "a", currency: "USD"))
        XCTAssertEqual(billLoads, 1)
        XCTAssertEqual(bankLoads, 2)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.ownsSelections(vendorId: "a", currency: "USD"))
    }

    private func seed(_ store: PaymentApplicationResourcesStore, vendor: String) {
        store.seed(vendorId: vendor, currency: "USD", bills: [bill(vendor)], bankOptions: [bank(vendor)],
            preferredBankId: "bank-\(vendor)-USD", selectedBillIDs: ["bill-\(vendor)"],
            amounts: ["bill-\(vendor)": "100.00"], lineNotes: ["bill-\(vendor)": "Reviewed"])
    }

    private func row(_ id: String) -> PaymentApplicationRow {
        .init(id: id, ref: id, status: "DRAFT", vendor: "Payee", vendorId: "vendor", currency: "USD",
            purpose: "GOODS", requestedAt: "2026-10-11", plannedPayAt: nil, totalAmount: 100,
            paidAmount: 0, requestedBy: "Operator", approvedBy: nil, decidedAt: nil, lineCount: 1, attachmentCount: 0)
    }

    private func bill(_ vendor: String) -> PaymentApplicationOpenBill {
        .init(id: "bill-\(vendor)", vendor: vendor, vendorId: vendor, category: "GOODS", description: "Tires",
            reference: nil, poReference: nil, amount: 100, amountPaid: 0, committed: 0, applicable: 100,
            occurredAt: "2026-10-11", dueAt: nil, createdAt: "2026-10-11")
    }

    private func bank(_ vendor: String, currency: String = "USD") -> PaymentApplicationBankOption {
        .init(id: "bank-\(vendor)-\(currency)", label: nil, beneficiaryName: vendor, bankName: "Bank",
            accountLast4: "1234", accountMasked: "****1234", currency: currency, isDefault: true)
    }
}
