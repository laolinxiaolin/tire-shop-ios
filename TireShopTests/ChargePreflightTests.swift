import XCTest
@testable import TireShop

/// Pins the client to `GET /payments/stripe/preflight/:invoiceId`. The contract
/// that matters: `amount` is the card total and comes back exactly as it was
/// asked for, `applied` is what the invoice absorbs after the fee is divided
/// out, and both remainders are server-quoted so the client never reproduces
/// the fee math.
final class ChargePreflightTests: XCTestCase {
    private func decode(_ json: String) throws -> ChargePreflight {
        try JSONDecoder().decode(ChargePreflight.self, from: XCTUnwrap(json.data(using: .utf8)))
    }

    func testDecodesSplitQuote() throws {
        // $2,000.00 charged on a $4,680.00 balance at 3%.
        let preflight = try decode(
            """
            {"balance":4680,"applied":1941.75,"surcharge":58.25,"amount":2000,
             "remaining":2738.25,"remainingGross":2820.40,"warnings":[]}
            """
        )
        XCTAssertEqual(preflight.balance, 4680)
        XCTAssertEqual(preflight.applied, 1941.75)
        XCTAssertEqual(preflight.surcharge, 58.25)
        XCTAssertEqual(preflight.amount, 2000)
        XCTAssertEqual(preflight.remaining, 2738.25)
        XCTAssertEqual(preflight.remainingGross, 2820.40)
        XCTAssertTrue(preflight.isPartial)
        // The fee is taken out of the card total, never added to it.
        XCTAssertEqual(preflight.applied + preflight.surcharge, preflight.amount, accuracy: 0.0001)
    }

    func testFullBalanceQuoteIsNotPartial() throws {
        let preflight = try decode(
            """
            {"balance":4680,"applied":4680,"surcharge":140.40,"amount":4820.40,
             "remaining":0,"remainingGross":0,"warnings":[]}
            """
        )
        XCTAssertFalse(preflight.isPartial)
        // Quoted with no amount, this is the ceiling the entry field defaults to.
        XCTAssertEqual(preflight.amount, 4820.40)
    }

    func testOlderServerWithoutRemaindersStillDecodes() throws {
        // `remaining` is derivable without the fee rate; `remainingGross` isn't,
        // so it stays nil rather than being guessed at.
        let preflight = try decode(
            """
            {"balance":500,"applied":33.33,"surcharge":1,"amount":34.33,"warnings":[]}
            """
        )
        XCTAssertEqual(preflight.remaining, 466.67)
        XCTAssertNil(preflight.remainingGross)
        XCTAssertTrue(preflight.isPartial)
    }

    func testDecodesWarningsAndRendersThem() throws {
        let preflight = try decode(
            """
            {"balance":500,"applied":200,"surcharge":0,"amount":200,"remaining":300,
             "remainingGross":300,"warnings":[
              {"code":"recentPayment","params":{"amount":"120.00","minutes":"3"}},
              {"code":"partiallyPaid","params":{"amount":"80.00","methods":"Cash, Visa"}}
            ]}
            """
        )
        XCTAssertEqual(preflight.warnings.map(\.code), ["recentPayment", "partiallyPaid"])
        XCTAssertTrue(preflight.warnings[0].message.contains("$120.00"))
        XCTAssertTrue(preflight.warnings[0].message.contains("3 min ago"))
        XCTAssertTrue(preflight.warnings[1].message.contains("(Cash, Visa)"))
    }

    func testUnknownWarningCodeStillWarns() throws {
        let preflight = try decode(
            """
            {"balance":10,"applied":10,"surcharge":0,"amount":10,"remaining":0,
             "remainingGross":0,"warnings":[{"code":"somethingNew","params":{}}]}
            """
        )
        // An unrecognized code must still surface as a warning to acknowledge,
        // never as an empty row the operator can't see.
        XCTAssertFalse(preflight.warnings[0].message.isEmpty)
    }

    func testWarningWithoutParamsDecodes() throws {
        let warning = try JSONDecoder().decode(
            ChargeWarning.self,
            from: XCTUnwrap(#"{"code":"recentPayment"}"#.data(using: .utf8))
        )
        XCTAssertEqual(warning.params, [:])
    }

    func testPartiallyPaidWithoutMethodsOmitsTheParenthetical() {
        let warning = ChargeWarning(code: "partiallyPaid", params: ["amount": "40.00", "methods": ""])
        XCTAssertTrue(warning.message.contains("$40.00 in payments."))
        XCTAssertFalse(warning.message.contains("()"))
    }
}
