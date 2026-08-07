import XCTest
@testable import TireShop

final class AppFormatTests: XCTestCase {
    // MARK: - Locale-independent parsing (pinned to en_US for determinism)

    func testParseAmountDotDecimal() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(AppFormat.parseAmount("12.50", locale: enUS), 12.5)
        XCTAssertEqual(AppFormat.parseAmount("12", locale: enUS), 12)
        XCTAssertEqual(AppFormat.parseAmount("0", locale: enUS), 0)
        XCTAssertEqual(AppFormat.parseAmount("0.01", locale: enUS), 0.01)
    }

    func testParseAmountBlankAndGarbage() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertNil(AppFormat.parseAmount("", locale: enUS))
        XCTAssertNil(AppFormat.parseAmount("   ", locale: enUS))
        XCTAssertNil(AppFormat.parseAmount("abc", locale: enUS))
        XCTAssertNil(AppFormat.parseAmount("12.50.00", locale: enUS))
    }

    func testParseAmountTrimsWhitespace() {
        let enUS = Locale(identifier: "en_US")
        XCTAssertEqual(AppFormat.parseAmount("  12.50  ", locale: enUS), 12.5)
    }

    func testParseAmountDefaultsToCurrentLocale() {
        // Locale-sensitive input: "12,50" is nil in en_US and 12.5 in de_DE, so a
        // change to the default parameter can't slip through.
        XCTAssertEqual(AppFormat.parseAmount("12,50"), AppFormat.parseAmount("12,50", locale: .current))
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
