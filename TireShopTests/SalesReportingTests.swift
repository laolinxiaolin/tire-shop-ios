import XCTest
@testable import TireShop

final class SalesReportingTests: XCTestCase {
    @MainActor
    func testNativeQuoteCannotSilentlyResaveAnIncompleteFreightDraft() {
        let quote = QuoteStore()
        quote.fulfillment = .freight
        XCTAssertThrowsError(try quote.saleInput()) { error in
            XCTAssertEqual((error as? APIError)?.message, "sales.freightEditInWeb")
        }
        XCTAssertEqual(SaleFulfillment.editableCases, [.delivery, .pickup])
    }

    func testCustomDatesUseInclusiveShopDaysAndRejectReversedRanges() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let lateEvening = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T03:30:00Z"))
        let earlyMorning = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T05:00:00Z"))
        let window = SalesDateWindow(from: lateEvening, to: earlyMorning, timeZone: zone)
        XCTAssertEqual(window.from, "2026-09-27")
        XCTAssertEqual(window.to, "2026-09-28")
        XCTAssertTrue(window.isValid)
        XCTAssertFalse(SalesDateWindow(from: earlyMorning, to: lateEvening, timeZone: zone).isValid)
        for day in ["2026-03-08", "2026-11-01"] {
            let date = try XCTUnwrap(ShopClock.date(fromDayString: day, in: zone))
            let sameDay = SalesDateWindow(from: date, to: date, timeZone: zone)
            XCTAssertTrue(sameDay.isValid)
            XCTAssertEqual(sameDay.from, day)
            XCTAssertEqual(sameDay.to, day)
        }
    }

    func testSalesExportPreservesFiltersWithoutPaginationOrCursor() throws {
        let request = SalesExportRequest(
            q: " Cash & carry ", status: "PAID", fulfillment: .pickup,
            paymentMethodIds: ["cash", "legacy-check"],
            from: "2026-09-01", to: "2026-09-27", sortBy: "total", sortOrder: "desc"
        )
        let components = try XCTUnwrap(URLComponents(string: request.path))
        XCTAssertEqual(components.path, "/sales/export")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, [
            "q": "Cash & carry", "status": "PAID", "fulfillment": "PICKUP",
            "paymentMethodIds": "cash,legacy-check", "from": "2026-09-01", "to": "2026-09-27",
            "sortBy": "total", "sortOrder": "desc"
        ])
        XCTAssertEqual(SalesExportRequest().path, "/sales/export")
        XCTAssertFalse(SalesExportRequest(sortOrder: "asc").path.contains("sortOrder"))
        XCTAssertEqual(SalesExportRequest(fulfillment: .freight).path, "/sales/export?fulfillment=FREIGHT")
        XCTAssertFalse(SaleFulfillment.editableCases.contains(.freight), "Freight creation needs the complete web editor")
    }

    func testFulfillmentFiltersPersistAcrossCursorPagesAndClearForAllSales() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SalesReportingStubProtocol.self]
        let api = SalesAPI(client: APIClient(session: URLSession(configuration: configuration)))

        let first = try await api.list(
            q: "Cash", status: "PAID", fulfillment: .pickup,
            paymentMethodIds: ["cash", "legacy-check"],
            from: "2026-09-01", to: "2026-09-27", page: 1, pageSize: 50
        )
        XCTAssertEqual(first.summary?.count, 75)

        let continuation = try await api.list(
            q: "Cash", status: "PAID", fulfillment: .pickup,
            paymentMethodIds: ["cash", "legacy-check"],
            from: "2026-09-01", to: "2026-09-27", page: 2, pageSize: 50,
            before: "2026-09-15T12:00:00Z", beforeId: "sale-50", summary: false
        )
        XCTAssertNil(continuation.summary)
        XCTAssertNil(continuation.total)
        XCTAssertEqual(continuation.page, 2)

        let delivery = try await api.list(fulfillment: .delivery, page: 1, pageSize: 50)
        XCTAssertEqual(delivery.summary?.count, 20)

        let all = try await api.list(fulfillment: nil, paymentMethodIds: [], page: 1, pageSize: 50)
        XCTAssertEqual(all.summary?.count, 95)
    }

    func testLiteralPlusAndPercentTextSurviveExportAndAPIQueryEncoding() async throws {
        let search = "A+B Tire %2B"
        let export = SalesExportRequest(q: search)
        let components = try XCTUnwrap(URLComponents(string: export.path))
        XCTAssertEqual(components.percentEncodedQuery, "q=A%2BB%20Tire%20%252B")
        let decoded = try XCTUnwrap(components.percentEncodedQuery)
            .replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        XCTAssertEqual(decoded, "q=\(search)")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SalesReportingStubProtocol.self]
        let api = SalesAPI(client: APIClient(session: URLSession(configuration: configuration)))
        let response = try await api.list(q: search)
        XCTAssertEqual(response.summary?.count, 1)
    }

    func testSaleAndListDecodeFulfillmentAndLegacySnapshots() throws {
        for (field, expected) in [
            (#", "fulfillment":"PICKUP""#, SaleFulfillment.pickup),
            (#", "fulfillment":"DELIVERY""#, SaleFulfillment.delivery),
            (#", "fulfillment":"FREIGHT""#, SaleFulfillment.freight),
            (#", "fulfillment":null"#, SaleFulfillment.delivery),
            ("", SaleFulfillment.delivery)
        ] {
            let json = """
            {"id":"sale-1","ref":"S-1","status":"PAID","location":"MAIN",
             "customer":{"id":"customer-1","name":"Customer"},"customerId":"customer-1",
             "subtotal":"100.00","taxRate":"0.00","taxAmount":"0.00","total":"100.00",
             "createdAt":"2026-09-27T12:00:00Z","lines":[],"invoice":null,
             "tireQty":0,"sampleDescription":null,"extraLineCount":0,"grossProfit":"50.00"
             \(field)}
            """
            let sale = try decode(Sale.self, json)
            let listItem = try decode(SaleListItem.self, json)
            XCTAssertEqual(sale.fulfillment ?? .delivery, expected)
            XCTAssertEqual(listItem.fulfillment ?? .delivery, expected)
            let roundTrip = try JSONDecoder().decode(SaleListItem.self, from: JSONEncoder().encode(listItem))
            XCTAssertEqual(roundTrip.fulfillment, listItem.fulfillment)
        }
    }

    func testReportsDecodeFulfillmentAndKeepLegacyDeliveryDefault() throws {
        for (field, expected, label) in [
            (#", "fulfillment":"PICKUP""#, SaleFulfillment.pickup, "Pickup"),
            (#", "fulfillment":"DELIVERY""#, SaleFulfillment.delivery, "Delivery"),
            (#", "fulfillment":"FREIGHT""#, SaleFulfillment.freight, "Freight / LTL"),
            (#", "fulfillment":null"#, SaleFulfillment.delivery, "Delivery"),
            ("", SaleFulfillment.delivery, "Delivery")
        ] {
            let eod = try decode(EodReport.Sales.Item.self, """
            {"saleRef":"S-1","customer":"Customer","soldBy":"Employee","status":"PAID",
             "subtotal":100,"tax":0,"total":100,"at":"2026-09-27T12:00:00Z"\(field)}
            """)
            XCTAssertEqual(eod.fulfillment ?? .delivery, expected)

            let monthly = try decode(MonthlySalesRow.self, """
            {"date":"2026-09-27","itemCode":"T1","productCode":"P1","invoiceNo":"INV-1",
             "brand":"Brand","pattern":"Pattern","size":"205/55R16","pr":"","loadIndex":"91",
             "salesPrice":100,"qty":1,"amount":100,"taxRate":0,"salesTax":0,"unitCost":60,
             "totalCost":60,"paymentMethod":"Cash","unitFet":0,"totalFet":0\(field)}
            """)
            XCTAssertEqual(monthly.fulfillment ?? .delivery, expected)
            XCTAssertEqual(MonthlySalesColumnKey.fulfillment.value(monthly), label)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

private final class SalesReportingStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let query = Dictionary(uniqueKeysWithValues:
                (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
            )
            guard request.httpMethod == "GET", url.path == "/api/sales" else {
                throw URLError(.unsupportedURL)
            }
            let body: String
            switch query {
            case ["q": "Cash", "status": "PAID", "fulfillment": "PICKUP", "paymentMethodIds": "cash,legacy-check",
                  "from": "2026-09-01", "to": "2026-09-27", "page": "1", "pageSize": "50"]:
                body = Self.fullResponse(count: 75)
            case ["q": "Cash", "status": "PAID", "fulfillment": "PICKUP", "paymentMethodIds": "cash,legacy-check",
                  "from": "2026-09-01", "to": "2026-09-27", "page": "2", "pageSize": "50",
                  "before": "2026-09-15T12:00:00Z", "beforeId": "sale-50", "summary": "false"]:
                body = #"{"items":[],"total":null,"page":2,"pageSize":50}"#
            case ["fulfillment": "DELIVERY", "page": "1", "pageSize": "50"]:
                body = Self.fullResponse(count: 20)
            case ["page": "1", "pageSize": "50"]:
                body = Self.fullResponse(count: 95)
            case ["q": "A+B Tire %2B"]:
                // URLComponents itself preserves raw '+'. Check the wire form
                // and form-style decoding used by the API, not just its items.
                let encoded = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
                guard encoded == "q=A%2BB%20Tire%20%252B",
                      encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding == "q=A+B Tire %2B" else {
                    throw URLError(.badURL)
                }
                body = Self.fullResponse(count: 1)
            default:
                throw URLError(.badURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func fullResponse(count: Int) -> String {
        """
        {"items":[],"total":\(count),"page":1,"pageSize":50,
         "summary":{"count":\(count),"tireQty":\(count),"taxAmount":"0","grossProfit":"50","total":"100"}}
        """
    }
}
