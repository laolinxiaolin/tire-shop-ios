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

    func testStandardCatalogPricesKeepCentPrecisionInSkuPatches() throws {
        let cases = [
            (entered: "288.58", encoded: "288.58"),
            (entered: "288.59", encoded: "288.59"),
            (entered: "0.07", encoded: "0.07"),
            (entered: "1.13", encoded: "1.13"),
            (entered: "288.580", encoded: "288.58"),
            (entered: "9999999999.99", encoded: "9999999999.99")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for testCase in cases {
            let amount = try XCTUnwrap(StandardSkuPrice.parse(testCase.entered))
            let patch = TireSkuPatchInput(priceWholesale: amount, priceFleet: amount, priceRetail: amount)
            let json = try XCTUnwrap(String(data: encoder.encode(patch), encoding: .utf8))
            XCTAssertEqual(
                json,
                "{\"priceFleet\":\(testCase.encoded),\"priceRetail\":\(testCase.encoded),\"priceWholesale\":\(testCase.encoded)}",
                testCase.entered
            )
        }
    }
}
