import XCTest
@testable import TireShop

final class CustomerTaxTests: XCTestCase {
    func testAutomaticModeExplicitlyRevokesOverride() throws {
        let input = CustomerTaxOverrideInput(taxRateOverride: nil, useShopDefault: false, reason: "Address verified", expiresAt: nil)
        let json = try object(input)
        XCTAssertTrue(json["taxRateOverride"] is NSNull)
        XCTAssertEqual(json["useShopDefault"] as? Bool, false)
        XCTAssertEqual(json["reason"] as? String, "Address verified")
        XCTAssertNil(json["expiresAt"])
    }

    func testShopDefaultAuthorizationAndManualExpiryPayloads() throws {
        let shopDefault = try object(CustomerTaxOverrideInput(taxRateOverride: nil, useShopDefault: true, reason: "Authorized", expiresAt: nil))
        XCTAssertTrue(shopDefault["taxRateOverride"] is NSNull)
        XCTAssertEqual(shopDefault["useShopDefault"] as? Bool, true)
        let manual = try object(CustomerTaxOverrideInput(taxRateOverride: 0.0825, useShopDefault: false, reason: "Authorized", expiresAt: "2026-11-01"))
        XCTAssertEqual(manual["taxRateOverride"] as? Double, 0.0825)
        XCTAssertEqual(manual["expiresAt"] as? String, "2026-11-01")
    }

    func testPercentValidationRejectsNonFiniteAndExcessPrecision() {
        XCTAssertEqual(CustomerTaxValidation.rate(fromPercent: " 8.25 "), 0.0825)
        XCTAssertEqual(CustomerTaxValidation.rate(fromPercent: "0"), 0)
        XCTAssertEqual(CustomerTaxValidation.rate(fromPercent: "100.00"), 1)
        for invalid in ["", "  ", "nan", "inf", "-0.01", "100.01", "8.251"] {
            XCTAssertNil(CustomerTaxValidation.rate(fromPercent: invalid), invalid)
        }
    }

    func testExpiryRoundTripsNewYorkCalendarDayAcrossDST() throws {
        let examples = [
            ("2026-03-09T04:00:00.000Z", "2026-03-08"),
            ("2026-11-02T05:00:00Z", "2026-11-01"),
            ("2026-09-28T04:00:00.000Z", "2026-09-27")
        ]
        for (exclusiveEnd, expected) in examples {
            let date = try XCTUnwrap(CustomerTaxValidation.expiryDay(exclusiveEnd))
            XCTAssertEqual(CustomerTaxValidation.dateKey(date), expected)
        }
    }

    func testReviewEvidenceRequiresWebURL() {
        XCTAssertNotNil(CustomerTaxValidation.evidenceURL(" https://dor.georgia.gov/sales-tax "))
        XCTAssertNil(CustomerTaxValidation.evidenceURL("dor.georgia.gov"))
        XCTAssertNil(CustomerTaxValidation.evidenceURL("javascript:alert(1)"))
        XCTAssertNil(CustomerTaxValidation.evidenceURL("file:///private/tmp/evidence"))
        XCTAssertNil(CustomerTaxValidation.evidenceURL("https://"))
    }

    func testLookupSupportsShopDefaultWithoutResolutionAndDoesNotInventUnresolvedRate() throws {
        let fallback = try decode(#"{"rate":0.08,"source":"DEFAULT","resolution":null,"automatic":{"status":"SHOP_DEFAULT","rate":0.08},"override":null,"shopDefaultRate":0.08}"#)
        XCTAssertEqual(fallback.resolutionStatus, "SHOP_DEFAULT")
        XCTAssertEqual(fallback.automaticRate, 0.08)
        let unresolved = try decode(#"{"rate":null,"source":"UNRESOLVED","resolution":{"id":"r1","status":"NEEDS_CORRECTION","problemCode":"ADDRESS_COMPONENTS_INCOMPLETE"},"automatic":{"status":"UNRESOLVED","code":"ADDRESS_COMPONENTS_INCOMPLETE"},"override":null,"shopDefaultRate":0.08}"#)
        XCTAssertNil(unresolved.automaticRate)
        XCTAssertNil(unresolved.rate)
        XCTAssertEqual(unresolved.resolutionStatus, "NEEDS_CORRECTION")
    }

    func testVerifiedAddressAcceptsNumberAndStringComponentsAndNullDORCodes() throws {
        let details = try decode(#"{"rate":0.08,"source":"LOCATION","resolution":{"id":"r1","status":"VERIFIED","problemCode":null,"normalizedAddress":{"number":120,"streetName":"MAIN","streetSuffix":"ST","unit":"B","postalCity":"ATLANTA","postalCode":"30303","predirectional":null},"reviewSourceUrl":"https://dor.georgia.gov","reviewedAt":"2026-09-27T12:00:00Z"},"automatic":{"status":"RESOLVED","rate":0.08,"source":{"label":"Georgia DOR","dorCodes":["060",null]}},"override":null,"shopDefaultRate":0.07}"#)
        XCTAssertEqual(details.resolution?.addressLabel, "120 MAIN ST #B, ATLANTA 30303")
        XCTAssertEqual(details.automatic?.source?.dorCodes, ["060", nil])
        XCTAssertEqual(details.automaticRate, 0.08)
    }

    func testWarehouseAddressClearingSendsNullWithoutAffectingActivationPatch() throws {
        let activation = try object(WarehousePatchInput(name: nil, notes: nil, active: false))
        XCTAssertEqual(Set(activation.keys), ["active"])
        let cleared = try object(WarehousePatchInput(name: "Warehouse", notes: "", active: nil, replaceAddress: true))
        for key in ["address", "address2", "city", "state", "postalCode"] {
            XCTAssertTrue(cleared[key] is NSNull, "\(key) must clear the saved value")
        }
        XCTAssertNil(cleared["replaceAddress"])
        XCTAssertNil(cleared["active"])
    }

    func testWarehouseCreateAndEditSendPhysicalAddress() throws {
        let create = try object(WarehouseCreateInput(code: "EAST", name: "East", notes: nil, address: "120 Main St", address2: "Suite B", city: "Atlanta", state: "GA", postalCode: "30303-1234"))
        XCTAssertEqual(create["address"] as? String, "120 Main St")
        XCTAssertEqual(create["postalCode"] as? String, "30303-1234")
        let patch = try object(WarehousePatchInput(name: "East", notes: "", active: nil, address: "120 Main St", city: "Atlanta", state: "GA", postalCode: "30303", replaceAddress: true))
        XCTAssertEqual(patch["state"] as? String, "GA")
        XCTAssertTrue(patch["address2"] is NSNull)
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func decode(_ json: String) throws -> CustomerTaxDetails {
        try JSONDecoder().decode(CustomerTaxDetails.self, from: Data(json.utf8))
    }
}
