import XCTest
@testable import TireShop

final class StockAdjustmentValueTests: XCTestCase {
    func testInvalidNonblankQuantityCannotBecomeANoChangeAdjustment() {
        for value in ["12.5", "abc", "1,000", "9223372036854775808"] {
            XCTAssertThrowsError(try StockAdjustmentValue.delta(value, counted: false, onHand: 10))
            XCTAssertThrowsError(try StockAdjustmentValue.delta(value, counted: true, onHand: 10))
        }
    }

    func testZeroPhysicalCountIsDistinctFromUntouchedBlankRow() throws {
        XCTAssertEqual(try StockAdjustmentValue.delta("0", counted: true, onHand: 10), -10)
        XCTAssertEqual(try StockAdjustmentValue.delta("  ", counted: true, onHand: 10), 0)
        XCTAssertEqual(try StockAdjustmentValue.delta("12", counted: true, onHand: 10), 2)
        XCTAssertThrowsError(try StockAdjustmentValue.delta("-1", counted: true, onHand: 10))
    }

    func testSignedStockChangesAndQuantityOverflowAreHandled() throws {
        XCTAssertEqual(try StockAdjustmentValue.delta(" -2 ", counted: false, onHand: 10), -2)
        XCTAssertEqual(try StockAdjustmentValue.delta("+3", counted: false, onHand: 10), 3)
        XCTAssertThrowsError(try StockAdjustmentValue.delta(String(Int.max), counted: false, onHand: 1))
        XCTAssertThrowsError(try StockAdjustmentValue.delta(String(Int.max), counted: true, onHand: -1))
    }
}
