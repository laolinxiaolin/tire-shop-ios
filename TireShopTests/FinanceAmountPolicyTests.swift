import XCTest
@testable import TireShop

final class FinanceAmountPolicyTests: XCTestCase {
    func testAllocationAmountsTrimEntriesBeforeBuildingApplications() {
        let parsed = FinanceAllocationAmounts([
            "first": " 5 ", "second": "\n10.25\t", "fraction": "12.345"
        ])
        XCTAssertEqual(parsed.amounts, ["first": 5, "second": 10.25, "fraction": 12.345])
        XCTAssertTrue(parsed.invalidRows.isEmpty)
        XCTAssertTrue(parsed.canSubmit)
    }

    func testBlankAndZeroAllocationsCanBeSkipped() {
        let empty = FinanceAllocationAmounts(["blank": "", "space": " \n", "zero": "0.00"])
        XCTAssertTrue(empty.amounts.isEmpty)
        XCTAssertTrue(empty.invalidRows.isEmpty)
        XCTAssertFalse(empty.canSubmit)

        let mixed = FinanceAllocationAmounts(["blank": " ", "zero": "0", "payment": " 5 "])
        XCTAssertEqual(mixed.amounts, ["payment": 5])
        XCTAssertTrue(mixed.invalidRows.isEmpty)
        XCTAssertTrue(mixed.canSubmit)
    }

    func testInvalidAllocationBlocksSubmissionAlongsideValidPayments() {
        for invalid in ["bad", "-1", " -0.01 ", "NaN", "inf", "-inf", "1e309", "12.34.56"] {
            let parsed = FinanceAllocationAmounts(["valid": "10.25", "invalid": invalid])
            XCTAssertEqual(parsed.amounts, ["valid": 10.25], invalid)
            XCTAssertEqual(parsed.invalidRows, ["invalid"], invalid)
            XCTAssertFalse(parsed.canSubmit, invalid)
        }
    }

    func testCorrectingInvalidAllocationRestoresTheWholeSubmission() {
        var entries = ["first": " 5 ", "second": "bad", "skipped": "0"]
        XCTAssertFalse(FinanceAllocationAmounts(entries).canSubmit)
        entries["second"] = " 10 "
        let corrected = FinanceAllocationAmounts(entries)
        XCTAssertEqual(corrected.amounts, ["first": 5, "second": 10])
        XCTAssertTrue(corrected.invalidRows.isEmpty)
        XCTAssertTrue(corrected.canSubmit)
    }

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

    func testBulkOneCentOverpaymentIsRetainedAndRejectedBeforeSubmission() {
        let excess = ReceivableOverpaymentPolicy.excess(received: 1000.01, openBalance: 1000)
        let applications = [
            .init(invoiceId: "first", amount: 600), .init(invoiceId: "last", amount: 400)
        ] as [ReceivableApplication]
        XCTAssertThrowsError(try ReceivableOverpaymentPolicy.applicationsForSubmission(applications, excess: excess)) { error in
            XCTAssertEqual((error as? APIError)?.message, "payment.oneCentOverpaymentUnsupported")
        }
        XCTAssertEqual(applications[0].amount, 600)
        XCTAssertEqual(applications[1].amount, 400)
        XCTAssertEqual(excess, 0.01, accuracy: 0.000001)
        XCTAssertFalse(ReceivableOverpaymentPolicy.allowsStoreCredit(excess: excess,
            paymentMethodAccountCode: "2400"))
        XCTAssertTrue(ReceivableOverpaymentPolicy.allowsStoreCredit(excess: excess,
            paymentMethodAccountCode: "1000"))
    }

    func testSupportedBulkExcessIsPreservedInTheFinalInvoiceLine() throws {
        for excess in [0.02, 1, 25.5] {
            let applications = try ReceivableOverpaymentPolicy.applicationsForSubmission([
                .init(invoiceId: "first", amount: 600), .init(invoiceId: "last", amount: 400)
            ], excess: excess)
            XCTAssertEqual(applications[1].amount, 400 + excess, accuracy: 0.000001)
            XCTAssertEqual(applications.reduce(0) { $0 + $1.amount }, 1000 + excess, accuracy: 0.000001)
        }
    }
}
