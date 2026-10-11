import XCTest
@testable import TireShop

final class CalendarDateInputTests: XCTestCase {
    func testImpossibleEmploymentAndExpirationDatesAreRejectedRatherThanNormalized() {
        for label in ["Hire date", "End date", "Expiration"] {
            for day in ["2026-02-30", "2026-02-29", "2026-04-31", "2026-00-12", "2026-13-01"] {
                XCTAssertThrowsError(try CalendarDateInput.serverValue(day, label: label), "\(label): \(day)")
            }
        }
    }

    func testValidLeapDayAndBlankDateRetainTheirCalendarMeaning() throws {
        XCTAssertEqual(try CalendarDateInput.serverValue("2028-02-29", label: "Hire date"), "2028-02-29T00:00:00.000Z")
        XCTAssertEqual(try CalendarDateInput.serverValue(" 2026-10-11 ", label: "End date"), "2026-10-11T00:00:00.000Z")
        XCTAssertNil(try CalendarDateInput.serverValue("  ", label: "Expiration"))
    }

    func testPartialDatesAndUnvalidatedTimestampsCannotBypassValidation() {
        for value in ["2026-1-2", "2026-10-11Tgarbage", "2026-10-11T12:00:00Z", "12/31/2026"] {
            XCTAssertThrowsError(try CalendarDateInput.serverValue(value, label: "Hire date"))
        }
    }
}
