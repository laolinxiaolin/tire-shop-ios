import XCTest
@testable import TireShop

final class CustomerAnalyticsTests: XCTestCase {
    func testCustomDatesUseStrictInclusiveCalendarDaysWithinServerBounds() {
        for day in ["0100-01-01", "2000-02-29", "2026-03-08", "2026-11-01", "9998-12-31"] {
            XCTAssertTrue(CustomerAnalyticsFilters(period: .custom, start: day, end: day).isValid, day)
        }
        for day in ["0099-12-31", "9999-01-01", "1900-02-29", "2026-02-29", "2026-04-31",
                    "2026-00-01", "2026-01-00", "2026-1-01", "2026-01-01T00:00:00Z", ""] {
            XCTAssertFalse(CustomerAnalyticsFilters(period: .custom, start: day, end: day).isValid, day)
        }
        XCTAssertFalse(CustomerAnalyticsFilters(period: .custom, start: "2026-10-02", end: "2026-10-01").isValid)
        XCTAssertTrue(CustomerAnalyticsFilters(period: .lifetime, start: "invalid", end: "").isValid)
    }

    func testExportMatchesRankingScopeAndOrderingWithoutPageBounds() throws {
        let filters = CustomerAnalyticsFilters(period: .custom, start: "2026-03-08", end: "2026-11-01", priceLevel: .unknown)
        let query = CustomerAnalyticsQuery(filters: filters, q: "  Rim + %2B & Sons  ", sort: .grossProfit,
                                          direction: .asc, page: 4, pageSize: 10)
        var expected = ["period": "CUSTOM", "start": "2026-03-08", "end": "2026-11-01",
                        "priceLevel": "UNKNOWN", "q": "Rim + %2B & Sons", "sort": "grossProfit", "direction": "asc"]
        XCTAssertEqual(try parameters(query.exportPath), expected)
        XCTAssertEqual(URLComponents(string: query.exportPath)?.path, "/customer-analytics/export")
        expected["page"] = "4"
        expected["pageSize"] = "10"
        XCTAssertEqual(try parameters(query.path), expected)
        XCTAssertTrue(query.exportPath.contains("Rim%20%2B%20%252B%20%26%20Sons"))

        for period in CustomerAnalyticsPreset.allCases where period != .custom {
            let preset = CustomerAnalyticsQuery(filters: .init(period: period, start: "stale", end: "stale"))
            let values = try parameters(preset.exportPath)
            XCTAssertEqual(values["period"], period.rawValue)
            XCTAssertNil(values["start"])
            XCTAssertNil(values["end"])
            XCTAssertNil(values["priceLevel"])
            XCTAssertNil(values["q"])
        }
    }

    func testProfitSortFallsBackAfterPermissionRevocation() {
        for sort in CustomerAnalyticsSort.allCases {
            let restricted = [CustomerAnalyticsSort.actualCogs, .grossProfit, .gpPercent].contains(sort)
            XCTAssertEqual(sort.allowed(canViewProfit: false), restricted ? .sales : sort)
            XCTAssertEqual(sort.allowed(canViewProfit: true), sort)
        }
    }

    func testRedactedAndLegacyProfitStayUnavailableWithoutInventingValues() throws {
        let restricted = try decode(CustomerAnalyticsRankings.self, CustomerAnalyticsFixtures.rankings)
        XCTAssertFalse(restricted.canViewProfit)
        XCTAssertEqual(restricted.historyCoverage.status, .partial)
        let row = try XCTUnwrap(restricted.items.first)
        XCTAssertEqual(row.id, "customer-1")
        XCTAssertEqual(row.currentPriceLevel, .fleet)
        XCTAssertEqual(row.metrics.sales, -125.5)
        XCTAssertEqual(row.metrics.tiresSold, -2)
        XCTAssertNil(row.metrics.actualCogs)
        XCTAssertNil(row.metrics.bookedCogs)
        XCTAssertNil(row.metrics.grossProfit)
        XCTAssertNil(row.metrics.costCoverage)
        XCTAssertNil(row.metrics.unverifiedCostUnits)

        // A legacy response can still omit booked profit. Do not reconstruct it
        // from current catalog costs or treat missing server evidence as zero.
        var partial = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CustomerAnalyticsFixtures.metrics.utf8)) as? [String: Any])
        partial["actualCogs"] = NSNull()
        partial["grossProfit"] = NSNull()
        partial["gpPercent"] = NSNull()
        partial["bookedCogs"] = 72.5
        partial["costCoverage"] = 0.5
        partial["unverifiedCostUnits"] = 2
        let metrics = try JSONDecoder().decode(CustomerAnalyticsMetrics.self, from: JSONSerialization.data(withJSONObject: partial))
        XCTAssertNil(metrics.actualCogs)
        XCTAssertNil(metrics.grossProfit)
        XCTAssertNil(metrics.gpPercent)
        XCTAssertEqual(metrics.bookedCogs, 72.5)
        XCTAssertEqual(metrics.costCoverage, 0.5)
        XCTAssertEqual(metrics.unverifiedCostUnits, 2)
        // A genuine verified zero must remain distinguishable from unavailable evidence.
        partial["actualCogs"] = 0
        let verifiedZero = try JSONDecoder().decode(CustomerAnalyticsMetrics.self, from: JSONSerialization.data(withJSONObject: partial))
        XCTAssertEqual(verifiedZero.actualCogs, 0)
    }

    func testProductsAndEventsRetainReturnsUnknownSnapshotsAndUnavailableSourceLinks() throws {
        let product = try decode(CustomerAnalyticsProduct.self, """
        {"skuId":"sku-1","sku":null,"brand":null,"model":null,"size":null,
         "quantity":-2,"netRevenue":-125.5,"averageUnitPrice":null}
        """)
        XCTAssertEqual(product.quantity, -2)
        XCTAssertNil(product.averageUnitPrice)
        XCTAssertNil(product.sku)
        for kind in CustomerAnalyticsHistoryEvent.Kind.allCases {
            let event = try decode(CustomerAnalyticsHistoryEvent.self, """
            {"sourceAvailable":false,"eventId":"event-1","saleId":"sale-1","invoiceId":null,
             "ref":"INV-1","kind":"\(kind.rawValue)","date":"2026-10-02T02:00:00.000Z",
             "priceLevel":null,"fulfillment":"FREIGHT","sales":-125.5,"tireRevenue":-125.5,
             "serviceRevenue":0,"deliveryRevenue":0,"restockingFees":0,"tiresSold":-2}
            """)
            XCTAssertEqual(event.kind, kind)
            XCTAssertFalse(event.sourceAvailable)
            XCTAssertNil(event.priceLevel)
            XCTAssertNil(event.bookedCogs)
            XCTAssertEqual(event.fulfillment, "FREIGHT")
            XCTAssertEqual(event.sales, -125.5)
        }
    }

    func testBookedProfitRemainsAvailableWithUnverifiedActualCostsInRankingsAndSummaries() throws {
        // Match the current API's booked-cost contract, including signed returns
        // and a true loss. The client must retain the server's rounded values.
        let cases: [(sales: Double, bookedCogs: Double, grossProfit: Double, gpPercent: Double?)] = [
            (1020, 400, 620, 60.78),
            (100, 125, -25, -25),
            (-254.50, -100, -154.50, nil),
            (0, 100, -100, nil)
        ]
        for value in cases {
            var metrics = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CustomerAnalyticsFixtures.metrics.utf8)) as? [String: Any])
            metrics["sales"] = value.sales
            metrics["actualCogs"] = NSNull()
            metrics["bookedCogs"] = value.bookedCogs
            metrics["grossProfit"] = value.grossProfit
            metrics["gpPercent"] = value.gpPercent.map { $0 as Any } ?? NSNull()
            metrics["costCoverage"] = 0.75
            metrics["unverifiedCostUnits"] = 1

            var rankingsBody = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CustomerAnalyticsFixtures.rankings.utf8)) as? [String: Any])
            let row = metrics.merging(["customerId": "customer-1", "customerName": "Historical customer"]) { _, new in new }
            rankingsBody["items"] = [row]
            rankingsBody["totals"] = metrics
            rankingsBody["canViewProfit"] = true
            let rankings = try JSONDecoder().decode(CustomerAnalyticsRankings.self, from: JSONSerialization.data(withJSONObject: rankingsBody))

            var summaryBody = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CustomerAnalyticsFixtures.summary.utf8)) as? [String: Any])
            summaryBody["summary"] = metrics
            summaryBody["lifetime"] = metrics
            summaryBody["canViewProfit"] = true
            let summary = try JSONDecoder().decode(CustomerAnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: summaryBody))
            for result in [try XCTUnwrap(rankings.items.first).metrics, rankings.totals, summary.summary, summary.lifetime] {
                XCTAssertNil(result.actualCogs)
                XCTAssertEqual(result.bookedCogs, value.bookedCogs)
                XCTAssertEqual(result.grossProfit, value.grossProfit)
                XCTAssertEqual(result.gpPercent, value.gpPercent)
                XCTAssertEqual(result.costCoverage, 0.75)
                XCTAssertEqual(result.unverifiedCostUnits, 1)
            }
        }
    }

    func testAPIUsesServerRankingAndPreservesFiltersAcrossDetailPages() async throws {
        let api = makeAPI()
        let filters = CustomerAnalyticsFilters(period: .custom, start: "2026-03-08", end: "2026-11-01", priceLevel: .unknown)
        let rankings = try await api.rankings(.init(filters: filters, q: "Rim + %2B & Sons", sort: .lastOrder,
                                                  direction: .asc, page: 4, pageSize: 10))
        XCTAssertEqual(rankings.page, 4)
        XCTAssertEqual(rankings.total, 31)
        XCTAssertEqual(rankings.period.timezone, "America/New_York")
        let summary = try await api.summary(customerId: "customer-1", filters: filters)
        XCTAssertEqual(summary.customer.name, "Rim + %2B & Sons")
        XCTAssertFalse(summary.canViewProfit)
        XCTAssertEqual(summary.lifetime.sales, -125.5)
        let products = try await api.products(customerId: "customer-1", filters: filters, page: 2, pageSize: 10)
        XCTAssertEqual(products.page, 2)
        let history = try await api.history(customerId: "customer-1", filters: filters, page: 3, pageSize: 25)
        XCTAssertEqual(history.page, 3)
        XCTAssertEqual(history.items.map(\.kind), [
            .sale, .saleAdjustment, .saleAdjustmentReversal, .saleReversal, .returnEvent, .returnReversal
        ])
        XCTAssertEqual(history.total, 80)
        XCTAssertEqual(history.pageSize, 25)
        XCTAssertEqual(history.period.preset, .custom)
        XCTAssertEqual(history.period.start, "2026-03-08")
        XCTAssertEqual(history.period.end, "2026-11-01")
        XCTAssertEqual(history.period.timezone, "America/New_York")
        XCTAssertEqual(history.historyCoverage.status, .complete)

        // Corrections change revenue without adding sold units or current
        // costs, and retain the server's exact invoice-generation link policy.
        let adjustment = try XCTUnwrap(history.items.first { $0.kind == .saleAdjustment })
        XCTAssertEqual(adjustment.eventId, "adjustment-event")
        XCTAssertEqual(adjustment.saleId, "sale-1")
        XCTAssertEqual(adjustment.invoiceId, "invoice-1")
        XCTAssertEqual(adjustment.ref, "INV-1")
        XCTAssertEqual(adjustment.priceLevel, .unknown)
        XCTAssertTrue(adjustment.sourceAvailable)
        XCTAssertEqual(adjustment.sales, -0.29)
        XCTAssertEqual(adjustment.tireRevenue, -0.27)
        XCTAssertEqual(adjustment.serviceRevenue, -0.02)
        XCTAssertEqual(adjustment.tiresSold, 0)
        XCTAssertEqual(adjustment.deliveryRevenue, 0)
        XCTAssertEqual(adjustment.restockingFees, 0)
        XCTAssertEqual(adjustment.bookedCogs, 0)

        let reversal = try XCTUnwrap(history.items.first { $0.kind == .saleAdjustmentReversal })
        XCTAssertEqual(reversal.eventId, "adjustment-reversal-event")
        XCTAssertEqual(reversal.invoiceId, "invoice-1")
        XCTAssertFalse(reversal.sourceAvailable)
        XCTAssertEqual(reversal.sales, 0.29)
        XCTAssertEqual(reversal.tireRevenue, 0.27)
        XCTAssertEqual(reversal.serviceRevenue, 0.02)
        XCTAssertEqual(reversal.tiresSold, 0)
        XCTAssertNil(reversal.bookedCogs)
    }

    @MainActor
    func testCollectionPriceAdjustmentsHaveDistinctEnglishAndChineseLabels() {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer {
            if let savedLanguage { UserDefaults.standard.set(savedLanguage, forKey: "ts_lang") }
            else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
        }
        let i18n = I18nStore()
        for (language, adjustment, reversal) in [
            (AppLanguage.en, "Invoice price adjustment", "Invoice price adjustment reversal"),
            (.zh, "发票价格调整", "发票价格调整冲销")
        ] {
            i18n.setLanguage(language)
            XCTAssertEqual(i18n.t("analytics.event.\(CustomerAnalyticsHistoryEvent.Kind.saleAdjustment.rawValue)"), adjustment)
            XCTAssertEqual(i18n.t("analytics.event.\(CustomerAnalyticsHistoryEvent.Kind.saleAdjustmentReversal.rawValue)"), reversal)
        }
    }

    func testAPIRejectsInvalidCustomerPathComponents() async throws {
        for id in ["", "..", "customer/one", "customer?period=LIFETIME", "customer%2Fone"] {
            do {
                _ = try await makeAPI().summary(customerId: id, filters: .init(period: .lifetime))
                XCTFail("Invalid customer IDs must not change the endpoint: \(id)")
            } catch let error as APIError {
                XCTAssertEqual(error.message, "The customer identifier is invalid.")
            }
        }
    }

    func testAPIPropagatesPermissionAndOwnershipFailures() async throws {
        do {
            _ = try await makeAPI().rankings(.init(q: "forbidden"))
            XCTFail("A permission denial must not become an empty report")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
        do {
            _ = try await makeAPI().summary(customerId: "outside-scope", filters: .init())
            XCTFail("An ownership denial must not expose customer details")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
        }
    }

    func testInvalidCustomRangeIsRejectedBeforeFetching() async throws {
        do {
            _ = try await makeAPI().rankings(.init(filters: .init(period: .custom, start: "2026-10-02", end: "2026-10-01")))
            XCTFail("Reversed calendar dates must be rejected")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Choose valid inclusive start and end dates, with start on or before end.")
        }
    }

    private func parameters(_ path: String) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(string: path))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func makeAPI() -> CustomerAnalyticsAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CustomerAnalyticsProtocol.self]
        return CustomerAnalyticsAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }
}

private enum CustomerAnalyticsFixtures {
    static let metrics = """
    {"sales":-125.5,"tireRevenue":-125.5,"serviceRevenue":0,"deliveryRevenue":0,
     "restockingFees":0,"tiresSold":-2,"orders":0,"averageOrder":null,"lastOrder":null}
    """
    static let period = """
    {"preset":"CUSTOM","start":"2026-03-08","end":"2026-11-01","timezone":"America/New_York"}
    """
    static let rankings = """
    {"items":[{"customerId":"customer-1","customerName":"Rim + %2B & Sons","company":null,
      "currentPriceLevel":"FLEET",\(metrics.dropFirst().dropLast())}],
     "total":31,"page":4,"pageSize":10,"period":\(period),
     "historyCoverage":{"status":"PARTIAL"},"totals":\(metrics),"canViewProfit":false}
    """
    static let summary = """
    {"customer":{"id":"customer-1","name":"Rim + %2B & Sons","company":null,"currentPriceLevel":null},
     "period":\(period),"historyCoverage":{"status":"NOT_BACKFILLED"},
     "summary":\(metrics),"lifetime":\(metrics),"canViewProfit":false}
    """

    static func page(_ page: Int, pageSize: Int) -> String {
        """
        {"items":[],"total":80,"page":\(page),"pageSize":\(pageSize),"period":\(period),
         "historyCoverage":{"status":"COMPLETE"}}
        """
    }

    // Match the complete history envelope, including the additive event kinds
    // emitted after collection-time repricing and a later sale reversal.
    static let history = """
    {"items":[
      {"sourceAvailable":true,"eventId":"sale-event","saleId":"sale-1","invoiceId":"invoice-1",
       "ref":"INV-1","kind":"SALE","date":"2026-10-02T02:00:00.000Z",
       "priceLevel":"UNKNOWN","fulfillment":"DELIVERY","sales":227.37,"tireRevenue":202.37,
       "serviceRevenue":5,"deliveryRevenue":20,"restockingFees":0,"tiresSold":2,"bookedCogs":150},
      {"sourceAvailable":true,"eventId":"adjustment-event","saleId":"sale-1","invoiceId":"invoice-1",
       "ref":"INV-1","kind":"SALE_ADJUSTMENT","date":"2026-10-02T02:00:00.000Z",
       "priceLevel":"UNKNOWN","fulfillment":"DELIVERY","sales":-0.29,"tireRevenue":-0.27,
       "serviceRevenue":-0.02,"deliveryRevenue":0,"restockingFees":0,"tiresSold":0,"bookedCogs":0},
      {"sourceAvailable":false,"eventId":"adjustment-reversal-event","saleId":"sale-1","invoiceId":"invoice-1",
       "ref":"INV-1","kind":"SALE_ADJUSTMENT_REVERSAL","date":"2026-10-03T02:00:00.000Z",
       "priceLevel":"UNKNOWN","fulfillment":"DELIVERY","sales":0.29,"tireRevenue":0.27,
       "serviceRevenue":0.02,"deliveryRevenue":0,"restockingFees":0,"tiresSold":0,"bookedCogs":null},
      {"sourceAvailable":false,"eventId":"sale-reversal-event","saleId":"sale-1","invoiceId":"invoice-1",
       "ref":"INV-1","kind":"SALE_REVERSAL","date":"2026-10-03T02:00:00.000Z",
       "priceLevel":"UNKNOWN","fulfillment":"DELIVERY","sales":-227.37,"tireRevenue":-202.37,
       "serviceRevenue":-5,"deliveryRevenue":-20,"restockingFees":0,"tiresSold":-2},
      {"sourceAvailable":false,"eventId":"return-event","saleId":"sale-2","invoiceId":"invoice-2",
       "ref":"INV-2","kind":"RETURN","date":"2026-10-04T02:00:00.000Z",
       "priceLevel":null,"fulfillment":"PICKUP","sales":-125.5,"tireRevenue":-125.5,
       "serviceRevenue":0,"deliveryRevenue":0,"restockingFees":0,"tiresSold":-1},
      {"sourceAvailable":false,"eventId":"return-reversal-event","saleId":"sale-2","invoiceId":"invoice-2",
       "ref":"INV-2","kind":"RETURN_REVERSAL","date":"2026-10-05T02:00:00.000Z",
       "priceLevel":null,"fulfillment":"PICKUP","sales":125.5,"tireRevenue":125.5,
       "serviceRevenue":0,"deliveryRevenue":0,"restockingFees":0,"tiresSold":1}
    ],"total":80,"page":3,"pageSize":25,"period":\(period),"historyCoverage":{"status":"COMPLETE"}}
    """
}

private final class CustomerAnalyticsProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            guard request.httpMethod == "GET", request.cachePolicy == .reloadIgnoringLocalCacheData else {
                throw URLError(.badURL)
            }
            let filters = ["period": "CUSTOM", "start": "2026-03-08", "end": "2026-11-01", "priceLevel": "UNKNOWN"]
            let body: String
            let status: Int
            if url.path == "/api/customer-analytics", query["q"] == "forbidden" {
                status = 403
                body = #"{"message":"Permission denied"}"#
            } else if url.path == "/api/customer-analytics/outside-scope/summary" {
                status = 404
                body = #"{"message":"Customer not found"}"#
            } else {
                status = 200
                switch components.percentEncodedPath {
                case "/api/customer-analytics":
                    let expected = filters.merging(["q": "Rim + %2B & Sons", "sort": "lastOrder", "direction": "asc",
                                                    "page": "4", "pageSize": "10"]) { _, new in new }
                    guard query == expected,
                          components.percentEncodedQuery?.contains("Rim%20%2B%20%252B%20%26%20Sons") == true else {
                        throw URLError(.badURL)
                    }
                    body = CustomerAnalyticsFixtures.rankings
                case "/api/customer-analytics/customer-1/summary":
                    guard query == filters else { throw URLError(.badURL) }
                    body = CustomerAnalyticsFixtures.summary
                case "/api/customer-analytics/customer-1/products":
                    guard query == filters.merging(["page": "2", "pageSize": "10"], uniquingKeysWith: { _, new in new }) else {
                        throw URLError(.badURL)
                    }
                    body = CustomerAnalyticsFixtures.page(2, pageSize: 10)
                case "/api/customer-analytics/customer-1/history":
                    guard query == filters.merging(["page": "3", "pageSize": "25"], uniquingKeysWith: { _, new in new }) else {
                        throw URLError(.badURL)
                    }
                    body = CustomerAnalyticsFixtures.history
                default:
                    throw URLError(.unsupportedURL)
                }
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                        headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
