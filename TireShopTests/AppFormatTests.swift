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

    func testDateDisplayUpdatesWhenLocaleAndTimeZoneChange() throws {
        let date = try XCTUnwrap(AppFormat.date("2026-10-11T02:30:00.000Z"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")

        let englishDate = AppFormat.shortDate(date, locale: english, timeZone: losAngeles)
        XCTAssertEqual(englishDate, "Oct 10, 2026")
        XCTAssertEqual(AppFormat.shortDate(date, locale: german, timeZone: utc), "11.10.2026")
        XCTAssertEqual(AppFormat.shortDate(date, locale: english, timeZone: losAngeles), englishDate)

        func expectedDateTime(locale: Locale, timeZone: TimeZone) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        XCTAssertEqual(AppFormat.dateTime(date, locale: english, timeZone: losAngeles),
                       expectedDateTime(locale: english, timeZone: losAngeles))
        XCTAssertEqual(AppFormat.dateTime(date, locale: german, timeZone: utc),
                       expectedDateTime(locale: german, timeZone: utc))
        XCTAssertEqual(AppFormat.shortDate(date, locale: english, timeZone: losAngeles), englishDate,
                       "Date-time formatting must not mutate the cached date-only format")
    }

    func testDefaultDateDisplayFollowsShopTimeZoneChange() throws {
        let previousTimeZone = UserDefaults.standard.object(forKey: "tireShop.shopTimeZone")
        defer { UserDefaults.standard.set(previousTimeZone, forKey: "tireShop.shopTimeZone") }
        let date = try XCTUnwrap(AppFormat.date("2026-10-11T02:30:00.000Z"))
        ShopClock.persist("America/Los_Angeles")
        let localDate = AppFormat.shortDate(date)
        ShopClock.persist("Etc/UTC")
        let utcDate = AppFormat.shortDate(date)
        XCTAssertNotEqual(localDate, utcDate, "Changing shop settings must refresh the displayed calendar day")
        ShopClock.persist("America/Los_Angeles")
        XCTAssertEqual(AppFormat.shortDate(date), localDate)
    }

    func testCalendarDatesKeepTheirDayAcrossCachedTimeZones() throws {
        let locale = Locale(identifier: "en_US")
        for identifier in ["America/Los_Angeles", "Asia/Shanghai", "Etc/UTC"] {
            let timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
            XCTAssertEqual(AppFormat.calendarDate("2026-10-11T00:00:00.000Z", locale: locale, timeZone: timeZone),
                           "Oct 11, 2026")
        }
    }
}
