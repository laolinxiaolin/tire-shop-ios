import XCTest
@testable import TireShop

final class PurchaseOrderDraftTests: XCTestCase {
    func testAccountingAmountRejectsMalformedNegativeAndOverPrecisionValues() {
        var draft = PurchaseOrderHeaderDraft()
        for text in ["-1", "NaN", "inf", "1e3", "10.001", "1,000", "1000000000000"] {
            draft.agreedGoodsAmount = text
            XCTAssertFalse(draft.validAmount, text)
            XCTAssertNil(draft.createInput(supplierId: "supplier", idempotencyKey: "retry"), text)
        }
        for text in ["", "  ", "0", "100.5", "999999999999.99"] {
            draft.agreedGoodsAmount = text
            XCTAssertTrue(draft.validAmount, text)
        }
    }

    func testCreationRetainsRetryIdentityAndTrimsSharedTerms() throws {
        var draft = PurchaseOrderHeaderDraft()
        draft.plannedContainerCount = "4"
        draft.agreedGoodsAmount = "123.45"
        draft.supplierReference = "  Invoice 42  "
        draft.paymentTerms = " Deposit followed by balance\n"
        draft.notes = "  "
        let body = try XCTUnwrap(draft.createInput(supplierId: "supplier", idempotencyKey: "stable-retry"))
        XCTAssertEqual(body.plannedContainerCount, 4)
        XCTAssertEqual(body.agreedGoodsAmount, 123.45)
        XCTAssertEqual(body.idempotencyKey, "stable-retry")
        XCTAssertEqual(body.supplierReference, "Invoice 42")
        XCTAssertEqual(body.paymentTerms, "Deposit followed by balance")
        XCTAssertNil(body.notes)
        XCTAssertEqual(draft.createInput(supplierId: "supplier", idempotencyKey: "stable-retry"), body)
    }

    func testCreationAndAmendmentUseDifferentContainerLimits() {
        var draft = PurchaseOrderHeaderDraft()
        draft.plannedContainerCount = "101"
        XCTAssertNil(draft.createInput(supplierId: "supplier", idempotencyKey: "retry"))
        XCTAssertTrue(draft.valid(minimumCount: 10, maximumCount: 10000))
        draft.plannedContainerCount = "9"
        XCTAssertFalse(draft.valid(minimumCount: 10, maximumCount: 10000))
        draft.plannedContainerCount = "1.5"
        XCTAssertFalse(draft.valid(minimumCount: 1, maximumCount: 100))
        draft.plannedContainerCount = "0"
        XCTAssertFalse(draft.valid(minimumCount: 1, maximumCount: 100))
    }

    func testBlankAgreementRemainsUnavailableRatherThanBecomingZero() throws {
        let draft = PurchaseOrderHeaderDraft()
        let body = try XCTUnwrap(draft.createInput(supplierId: "supplier", idempotencyKey: "retry"))
        XCTAssertNil(body.agreedGoodsAmount)
        XCTAssertNil(draft.createInput(supplierId: "  ", idempotencyKey: "retry"))
    }
}
