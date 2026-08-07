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
        // `.some(nil)` is the tri-state "clear". A *literal* `nil` would mean
        // "leave alone" and omit the key entirely, but an optional expression
        // (like `feeRateValue`) is implicitly promoted to `.some(...)`.
        let json = try encode(
            PaymentMethodPatchInput(feeRate: .some(nil), payoutAccountCode: .some(nil))
        )
        XCTAssertTrue(json["feeRate"] is NSNull)
        XCTAssertTrue(json["payoutAccountCode"] is NSNull)
    }

    func testOptionalExpressionEncodesExplicitNullToClear() throws {
        // The call-site shape: `feeRateValue` is a `Double?` that is nil for an
        // empty field. Passing the optional expression promotes it to `.some(nil)`,
        // which encodes an explicit null (clear) rather than omitting the key.
        let blankFee: Double? = nil
        let blankPayout: String? = nil
        let json = try encode(PaymentMethodPatchInput(feeRate: blankFee, payoutAccountCode: blankPayout))
        XCTAssertTrue(json["feeRate"] is NSNull)
        XCTAssertTrue(json["payoutAccountCode"] is NSNull)
    }

    func testLiteralNilLeavesFieldAlone() throws {
        // A literal `nil` means "leave alone" — the key is omitted entirely.
        let json = try encode(PaymentMethodPatchInput(feeRate: nil))
        XCTAssertNil(json["feeRate"])
    }

    func testEmptyPatchEncodesEmptyObject() throws {
        let json = try encode(PaymentMethodPatchInput())
        XCTAssertTrue(json.isEmpty)
    }
}
