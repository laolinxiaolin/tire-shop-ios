import XCTest
@testable import TireShop

final class FinanceAmountPolicyTests: XCTestCase {
    func testOneCentOverpaymentIsDetectedAtDifferentBalances() {
        for balance in [1.0, 100, 1000, 10_000] {
            XCTAssertEqual(FinanceMoney.excess(amount: balance + 0.01, balance: balance), 0.01,
                accuracy: 0.000001)
            XCTAssertEqual(ReceivableOverpaymentPolicy.excess(received: balance + 0.01, openBalance: balance),
                0.01, accuracy: 0.000001)
        }
    }

    func testFloatingPointNoiseAndUnderpaymentsDoNotCreateCredit() {
        XCTAssertEqual(FinanceMoney.excess(amount: 0.1 + 0.2, balance: 0.3), 0)
        XCTAssertEqual(FinanceMoney.excess(amount: 99.99, balance: 100), 0)
        XCTAssertEqual(FinanceMoney.excess(amount: 100, balance: 100), 0)
    }

    func testBulkOneCentOverpaymentIsIncludedInSubmissionAndCannotRecycleStoreCredit() {
        let excess = ReceivableOverpaymentPolicy.excess(received: 1000.01, openBalance: 1000)
        let applications = ReceivableOverpaymentPolicy.applicationsForSubmission([
            .init(invoiceId: "first", amount: 600), .init(invoiceId: "last", amount: 400)
        ], excess: excess)
        XCTAssertEqual(applications[0].amount, 600)
        XCTAssertEqual(applications[1].amount, 400.01, accuracy: 0.000001)
        XCTAssertEqual(applications.reduce(0) { $0 + $1.amount }, 1000.01, accuracy: 0.000001)
        XCTAssertFalse(ReceivableOverpaymentPolicy.allowsStoreCredit(excess: excess,
            paymentMethodAccountCode: "2400"))
        XCTAssertTrue(ReceivableOverpaymentPolicy.allowsStoreCredit(excess: excess,
            paymentMethodAccountCode: "1000"))
    }
}
