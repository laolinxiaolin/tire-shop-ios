import XCTest
@testable import TireShop

final class FleetSkuPriceInputTests: XCTestCase {
    func testStandardCatalogPricesAcceptPositiveCentsAndMaximum() {
        XCTAssertEqual(StandardSkuPrice.parse("0.01"), 0.01)
        XCTAssertEqual(StandardSkuPrice.parse(".25"), 0.25)
        XCTAssertEqual(StandardSkuPrice.parse("12."), 12)
        XCTAssertEqual(StandardSkuPrice.parse(" 125.50 "), 125.50)
        XCTAssertEqual(StandardSkuPrice.parse("12.340"), 12.34)
        XCTAssertEqual(StandardSkuPrice.parse("9999999999.99"), 9_999_999_999.99)
    }

    func testStandardCatalogPricesRejectZeroNegativeAndAboveMaximum() {
        for input in ["0", "0.00", "-0.01", "10000000000", "10000000000.00"] {
            XCTAssertNil(StandardSkuPrice.parse(input), input)
        }
    }

    func testStandardCatalogPricesRejectExtraPrecisionAndMalformedInput() {
        for input in ["", " ", "1.001", "12.345", "NaN", "inf", "1e2", "1,000.00", "1.2.3"] {
            XCTAssertNil(StandardSkuPrice.parse(input), input)
        }
    }
}
