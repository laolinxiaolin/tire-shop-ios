import XCTest
@testable import TireShop

@MainActor
final class EmployeeDetailStoreTests: XCTestCase {
    func testHRProfileLoadsWithoutRequestingIdentifiedSalesEvidence() async {
        let profile = makeEmployee()
        let store = EmployeeDetailStore(
            profileLoader: { _ in profile },
            commissionsLoader: { _ in XCTFail("HR-only access must not request commissions"); return [] },
            payoutsLoader: { _ in XCTFail("HR-only access must not request payouts"); return [] }
        )

        await store.load(id: profile.id, canReadSales: false)

        XCTAssertEqual(store.employee, profile)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.evidenceErrorMessage)
        XCTAssertFalse(store.loading)
    }

    func testEvidenceFailureDoesNotHideSuccessfulHRProfile() async {
        let profile = makeEmployee()
        let store = EmployeeDetailStore(
            profileLoader: { _ in profile },
            commissionsLoader: { _ in throw APIError(status: 403, message: "Sales access changed") },
            payoutsLoader: { _ in [] }
        )

        await store.load(id: profile.id, canReadSales: true)

        XCTAssertEqual(store.employee, profile)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.evidenceErrorMessage)
        XCTAssertTrue(store.commissions.isEmpty)
    }

    func testRevokingAllSalesAccessRejectsInFlightEvidenceAndPreservesHRProfile() async throws {
        let profile = makeEmployee()
        let started = expectation(description: "Commission request started")
        var response: CheckedContinuation<[CommissionEntry], Error>?
        let store = EmployeeDetailStore(
            profileLoader: { _ in profile },
            commissionsLoader: { _ in
                try await withCheckedThrowingContinuation {
                    response = $0
                    started.fulfill()
                }
            },
            payoutsLoader: { _ in [] }
        )
        let oldLoad = Task { await store.load(id: profile.id, canReadSales: true) }
        await fulfillment(of: [started], timeout: 2)

        await store.load(id: profile.id, canReadSales: false)
        try XCTUnwrap(response).resume(returning: [makeCommission()])
        await oldLoad.value

        XCTAssertEqual(store.employee, profile)
        XCTAssertTrue(store.commissions.isEmpty)
        XCTAssertTrue(store.payouts.isEmpty)
        XCTAssertNil(store.evidenceErrorMessage)
        XCTAssertFalse(store.loading)
    }

    private func makeEmployee() -> Employee {
        Employee(
            id: "employee", employeeNo: nil, userId: nil, user: nil,
            fullName: "HR profile", phone: nil, email: nil, address: nil,
            position: nil, department: nil, status: "ACTIVE", hireDate: nil,
            endDate: nil, payType: "HOURLY", payRate: 20, commissionRate: 0.05,
            commissionBasis: "REVENUE", notes: nil, commissions: nil,
            createdAt: "2026-10-01T12:00:00Z", updatedAt: "2026-10-01T12:00:00Z"
        )
    }

    private func makeCommission() -> CommissionEntry {
        CommissionEntry(
            id: "commission", employeeId: "employee", saleId: "sale", basis: "REVENUE",
            basisAmount: 100, rate: 0.05, amount: 5, status: "ACCRUED", note: nil,
            payoutId: nil, paidAt: nil, createdAt: "2026-10-01T12:00:00Z", employee: nil, sale: nil
        )
    }
}
