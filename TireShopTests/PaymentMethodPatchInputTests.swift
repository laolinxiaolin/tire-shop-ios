import XCTest
@testable import TireShop

final class PaymentMethodPatchInputTests: XCTestCase {
    private func encode(_ input: PaymentMethodPatchInput) throws -> [String: Any] {
        let data = try JSONEncoder().encode(input)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object
    }

    func testToggleSendsOnlyIsActive() throws {
        let json = try encode(PaymentMethodPatchInput(isActive: false))
        XCTAssertEqual(json["isActive"] as? Bool, false)
        XCTAssertNil(json["name"])
        XCTAssertNil(json["accountCode"])
        XCTAssertNil(json["feeRate"])
        XCTAssertNil(json["payoutAccountCode"])
    }

    func testEditorSendsOnlyOwnedFields() throws {
        let json = try encode(
            PaymentMethodPatchInput(
                name: "Visa",
                accountCode: "1010",
                feeRate: 0.029,
                payoutAccountCode: "1020"
            )
        )
        XCTAssertEqual(json["name"] as? String, "Visa")
        XCTAssertEqual(json["accountCode"] as? String, "1010")
        XCTAssertEqual(json["feeRate"] as? Double, 0.029)
        XCTAssertEqual(json["payoutAccountCode"] as? String, "1020")
        // The editor does not own isActive, so it must not be sent at all.
        XCTAssertNil(json["isActive"])
    }

    func testBlankFieldEncodesExplicitNullToClear() throws {
        // `.some(nil)` is the tri-state "clear" — a bare `nil` would mean
        // "leave alone" and omit the key entirely.
        let json = try encode(
            PaymentMethodPatchInput(feeRate: .some(nil), payoutAccountCode: .some(nil))
        )
        XCTAssertTrue(json["feeRate"] is NSNull)
        XCTAssertTrue(json["payoutAccountCode"] is NSNull)
    }

    func testEmptyPatchEncodesEmptyObject() throws {
        let json = try encode(PaymentMethodPatchInput())
        XCTAssertTrue(json.isEmpty)
    }
}
