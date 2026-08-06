import XCTest
@testable import TireShop

final class AppFormatTests: XCTestCase {
    // MARK: - Locale-independent parsing

    func testParseAmountDotDecimal() {
        XCTAssertEqual(AppFormat.parseAmount("12.50"), 12.5)
        XCTAssertEqual(AppFormat.parseAmount("12"), 12)
        XCTAssertEqual(AppFormat.parseAmount("0"), 0)
        XCTAssertEqual(AppFormat.parseAmount("0.01"), 0.01)
    }

    func testParseAmountBlankAndGarbage() {
        XCTAssertNil(AppFormat.parseAmount(""))
        XCTAssertNil(AppFormat.parseAmount("   "))
        XCTAssertNil(AppFormat.parseAmount("abc"))
        XCTAssertNil(AppFormat.parseAmount("12.50.00"))
    }

    func testParseAmountTrimsWhitespace() {
        XCTAssertEqual(AppFormat.parseAmount("  12.50  "), 12.5)
    }

    // MARK: - Locale-specific parsing (deterministic via explicit locale)

    func testParseAmountEnUS() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(AppFormat.parseAmount("12.50", locale: enUS), 12.5)
        XCTAssertEqual(AppFormat.parseAmount("1,234.56", locale: enUS), 1234.56)
        // A comma-decimal string must NOT be misread as a grouped number.
        XCTAssertNil(AppFormat.parseAmount("12,50", locale: enUS))
    }

    func testParseAmountDeDE() {
        let deDE = Locale(identifier: "de_DE")
        XCTAssertEqual(AppFormat.parseAmount("12,50", locale: deDE), 12.5)
        XCTAssertEqual(AppFormat.parseAmount("1.234,56", locale: deDE), 1234.56)
        XCTAssertEqual(AppFormat.parseAmount("12.50", locale: deDE), 12.5)
    }
}
