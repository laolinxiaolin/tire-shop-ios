import XCTest
@testable import TireShop

/// Pins the client to `POST /invoices/:id/payment-link`. Emailing is a flag on
/// the create call, not a second request, and the server picks the recipient —
/// so `emailed` coming back false is the only signal that nothing was sent.
final class PayLinkTests: XCTestCase {
    private func decode(_ json: String) throws -> PayLink {
        try JSONDecoder().decode(PayLink.self, from: XCTUnwrap(json.data(using: .utf8)))
    }

    private func encode(_ input: PayLinkCreateInput) throws -> [String: Any] {
        let data = try JSONEncoder().encode(input)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDecodesPartialLink() throws {
        let link = try decode(
            """
            {"url":"https://checkout.stripe.com/c/pay/abc","sessionId":"cs_test_1",
             "balance":500,"applied":200,"surcharge":6,"amount":206,"emailed":true}
            """
        )
        XCTAssertEqual(link.url, "https://checkout.stripe.com/c/pay/abc")
        XCTAssertEqual(link.sessionId, "cs_test_1")
        XCTAssertEqual(link.applied, 200)
        XCTAssertEqual(link.surcharge, 6)
        // The customer is billed the gross, not the amount that was typed in.
        XCTAssertEqual(link.amount, 206)
        XCTAssertEqual(link.remaining, 300)
        XCTAssertTrue(link.emailed)
    }

    func testDecodesSessionWithoutURL() throws {
        let link = try decode(
            """
            {"url":null,"sessionId":"cs_test_2","balance":80,"applied":80,
             "surcharge":0,"amount":80,"emailed":false}
            """
        )
        XCTAssertNil(link.url)
        XCTAssertEqual(link.remaining, 0)
        XCTAssertFalse(link.emailed)
    }

    func testRemainingRoundsToCents() throws {
        let link = try decode(
            """
            {"url":"https://x","sessionId":"cs_test_3","balance":500,"applied":33.33,
             "surcharge":0,"amount":33.33,"emailed":false}
            """
        )
        XCTAssertEqual(link.remaining, 466.67)
    }

    func testCreateInputSendsEmailFlagAndCardTotal() throws {
        let json = try encode(PayLinkCreateInput(email: true, grossAmount: 2000))
        XCTAssertEqual(json["email"] as? Bool, true)
        XCTAssertEqual(json["grossAmount"] as? Double, 2000)
        // Never the legacy pre-fee `amount` — sending both is a 400, and it
        // can't express every card total anyway.
        XCTAssertFalse(json.keys.contains("amount"))
        // There is no recipient field — the server emails the customer on file.
        XCTAssertNil(json["to"])
    }

    func testCreateInputOmitsAmountForFullBalance() throws {
        let json = try encode(PayLinkCreateInput(email: false, grossAmount: nil))
        XCTAssertEqual(json["email"] as? Bool, false)
        // A missing amount is what tells the server to bill the whole balance;
        // sending an explicit null would fail its number validation.
        XCTAssertFalse(json.keys.contains("grossAmount"))
    }
}
