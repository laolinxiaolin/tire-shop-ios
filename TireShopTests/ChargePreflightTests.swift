import XCTest
@testable import TireShop

/// Pins the client to `GET /payments/stripe/preflight/:invoiceId`. The contract
/// that matters: `amount` is the card total and comes back exactly as it was
/// asked for, `applied` is what the invoice absorbs after the fee is divided
/// out, and both remainders are server-quoted so the client never reproduces
/// the fee math.
final class ChargePreflightTests: XCTestCase {
    func testCompletedPartialTerminalPaymentRequiresRecordedPaymentBeforeRemainder() {
        let approved = TapToPayOutcome(status: .approved, detail: "Approved", amount: 100,
            invoiceId: "invoice", paymentIntentId: "first", happenedAt: Date())
        func intent(id: String, balance: Double) -> TerminalIntent {
            TerminalIntent(paymentIntentId: id, clientSecret: "secret", balance: balance,
                surcharge: 0, amount: balance, readerId: nil, readerStatus: nil)
        }
        XCTAssertTrue(approved.isSuperseded(by: intent(id: "next", balance: 400), invoiceId: "invoice", recordedPaymentIntentId: "first"))
        XCTAssertFalse(approved.isSuperseded(by: intent(id: "first", balance: 400), invoiceId: "invoice", recordedPaymentIntentId: "first"))
        XCTAssertFalse(approved.isSuperseded(by: intent(id: "next", balance: 0), invoiceId: "invoice", recordedPaymentIntentId: "first"))
        XCTAssertFalse(approved.isSuperseded(by: intent(id: "next", balance: 400), invoiceId: "another", recordedPaymentIntentId: "first"))
        XCTAssertFalse(approved.isSuperseded(by: intent(id: "next", balance: 500), invoiceId: "invoice", recordedPaymentIntentId: nil))
        XCTAssertFalse(approved.isSuperseded(by: intent(id: "next", balance: 400), invoiceId: "invoice", recordedPaymentIntentId: "older-payment"))
    }

    func testFreshTerminalPreparationRevokesOlderScreenAuthorization() {
        let context = TapToPayChargeContext(invoiceId: "invoice", baselineIntentId: "remaining-400")
        XCTAssertTrue(context.accepts(invoiceId: "invoice", baselineIntentId: "remaining-400"))
        XCTAssertFalse(context.accepts(invoiceId: "invoice", baselineIntentId: "original-500"))
        XCTAssertFalse(context.accepts(invoiceId: "another", baselineIntentId: "remaining-400"))
    }

    func testKeyedCardPreparationKeepsAmountConfirmedBeforeGatewayLookup() async throws {
        var editableAmount = 100.0
        var submittedAmount: Double?
        let result = try await KeyedCardChargePreparation.prepare(
            grossAmount: editableAmount,
            gatewayStatus: {
                await Task.yield()
                editableAmount = 200
                return GatewayStatus(enabled: true, provider: "stripe", publishableKey: "pk_test")
            },
            createIntent: { amount in
                submittedAmount = amount
                return CardPaymentIntent(paymentIntentId: "pi_test", clientSecret: "secret",
                    balance: 500, surcharge: 0, amount: amount)
            }
        )
        XCTAssertEqual(editableAmount, 200)
        XCTAssertEqual(submittedAmount, 100)
        XCTAssertEqual(result.intent.amount, 100)
    }

    func testKeyedCardPreparationRejectsChangedIntentAmount() async {
        do {
            _ = try await KeyedCardChargePreparation.prepare(
                grossAmount: 100,
                gatewayStatus: { GatewayStatus(enabled: true, provider: "stripe", publishableKey: "pk_test") },
                createIntent: { _ in
                    CardPaymentIntent(paymentIntentId: "pi_test", clientSecret: "secret",
                        balance: 500, surcharge: 0, amount: 200)
                }
            )
            XCTFail("A different amount must never reach the card sheet")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("amount changed"))
        }
    }

    func testKeyedCardPreparationSupportsLegacyIntentWithoutAmount() async throws {
        let result = try await KeyedCardChargePreparation.prepare(
            grossAmount: 100,
            gatewayStatus: { GatewayStatus(enabled: true, provider: "stripe", publishableKey: "pk_test") },
            createIntent: { amount in
                XCTAssertEqual(amount, 100)
                return CardPaymentIntent(paymentIntentId: "pi_test", clientSecret: "secret",
                    balance: nil, surcharge: nil, amount: nil)
            }
        )
        XCTAssertEqual(result.intent.clientSecret, "secret")
    }

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

    private func terminalQuote(_ amount: Double, warns: Bool = false) -> ChargePreflight {
        ChargePreflight(
            balance: 500,
            applied: amount,
            surcharge: 0,
            amount: amount,
            remaining: 500 - amount,
            remainingGross: 500 - amount,
            warnings: warns ? [ChargeWarning(code: "recentPayment", params: [:])] : []
        )
    }

    func testTerminalPreflightsCompletingOutOfOrderCannotChangeReviewedCharge() throws {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let first = selection.beginPreflight(grossAmount: 100)
        selection.editAmount("200")
        let second = selection.beginPreflight(grossAmount: 200)

        selection.completePreflight(terminalQuote(200, warns: true), for: second)
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))
        selection.acknowledgeWarnings()
        let confirmed = try XCTUnwrap(selection.authorization(fullBalanceAmount: 500))

        selection.completePreflight(terminalQuote(100), for: first)
        selection.failPreflight("Old request failed", for: first)

        XCTAssertEqual(selection.preflight?.amount, 200)
        XCTAssertEqual(selection.displayedAmount(fullBalanceAmount: 500), 200)
        XCTAssertEqual(selection.authorization(fullBalanceAmount: 500), confirmed)
        XCTAssertEqual(confirmed.grossAmount, 200)
        XCTAssertFalse(confirmed.usesFullBalanceIntent)
        XCTAssertTrue(selection.acknowledgedWarnings)
        XCTAssertNil(selection.errorMessage)
    }

    func testTerminalEditingInvalidatesPendingResponseAndCompletedQuote() {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let pending = selection.beginPreflight(grossAmount: 100)
        selection.editAmount("200")
        selection.completePreflight(terminalQuote(100), for: pending)
        selection.failPreflight("Old request failed", for: pending)

        XCTAssertNil(selection.preflight)
        XCTAssertNil(selection.errorMessage)
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))

        let next = selection.beginPreflight(grossAmount: 200)
        selection.completePreflight(terminalQuote(200, warns: true), for: next)
        selection.acknowledgeWarnings()
        XCTAssertNotNil(selection.authorization(fullBalanceAmount: 500))

        selection.editAmount("300")
        XCTAssertNil(selection.preflight)
        XCTAssertFalse(selection.acknowledgedWarnings)
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))
    }

    func testTerminalFullBalanceIgnoresPendingSplitAndUsesRefreshedFullAmount() throws {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let pending = selection.beginPreflight(grossAmount: 100)
        selection.useFullBalance()
        selection.completePreflight(terminalQuote(100), for: pending)
        selection.failPreflight("Old request failed", for: pending)

        XCTAssertEqual(selection.amountText, "")
        XCTAssertNil(selection.preflight)
        XCTAssertNil(selection.errorMessage)
        XCTAssertEqual(selection.displayedAmount(fullBalanceAmount: 500), 500)
        let full = try XCTUnwrap(selection.authorization(fullBalanceAmount: 500))
        XCTAssertEqual(full.grossAmount, 500)
        XCTAssertTrue(full.usesFullBalanceIntent)

        let refreshed = try XCTUnwrap(selection.authorization(fullBalanceAmount: 400))
        XCTAssertEqual(refreshed.grossAmount, 400)
        XCTAssertTrue(refreshed.usesFullBalanceIntent)
        XCTAssertEqual(selection.displayedAmount(fullBalanceAmount: 400), 400)
    }

    func testTerminalRepeatedApplyOfSameAmountStillInvalidatesEarlierWarnings() {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let first = selection.beginPreflight(grossAmount: 100)
        let second = selection.beginPreflight(grossAmount: 100)
        selection.completePreflight(terminalQuote(100, warns: true), for: second)
        selection.completePreflight(terminalQuote(100), for: first)

        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))
        XCTAssertEqual(selection.preflight?.warnings.count, 1)
        selection.acknowledgeWarnings()
        XCTAssertNotNil(selection.authorization(fullBalanceAmount: 500))
    }

    func testTerminalAuthorizationKeepsConfirmedAmountAndRejectsChangedIntent() throws {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let request = selection.beginPreflight(grossAmount: 100)
        selection.completePreflight(terminalQuote(100), for: request)
        let authorization = try XCTUnwrap(selection.authorization(fullBalanceAmount: 500))

        selection.editAmount("200")
        XCTAssertEqual(authorization.grossAmount, 100)
        XCTAssertTrue(authorization.acceptsIntentAmount(100))
        XCTAssertFalse(authorization.acceptsIntentAmount(100.01))
        XCTAssertFalse(authorization.acceptsIntentAmount(200))
        XCTAssertFalse(authorization.acceptsIntentAmount(.nan))
        XCTAssertFalse(authorization.acceptsIntentAmount(.infinity))
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))
    }

    func testTerminalMismatchedQuoteAndCurrentFailureCannotAuthorizeCharge() {
        var selection = TapToPayChargeSelection()
        selection.editAmount("100")
        let request = selection.beginPreflight(grossAmount: 100)
        selection.completePreflight(terminalQuote(200), for: request)
        XCTAssertNil(selection.preflight)
        XCTAssertNotNil(selection.errorMessage)
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))

        let retry = selection.beginPreflight(grossAmount: 100)
        XCTAssertNil(selection.errorMessage)
        selection.failPreflight("Current request failed", for: retry)
        XCTAssertEqual(selection.errorMessage, "Current request failed")
        XCTAssertNil(selection.authorization(fullBalanceAmount: 500))
    }
}
