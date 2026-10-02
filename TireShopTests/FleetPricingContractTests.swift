import XCTest
@testable import TireShop

final class FleetPricingContractTests: XCTestCase {
    func testFleetPricePatchDistinguishesUnchangedSetAndClear() throws {
        let unchanged = try object(TireSkuPatchInput())
        XCTAssertNil(unchanged["priceFleet"])
        XCTAssertNil(unchanged["priceWholesale"])

        let changed = try object(TireSkuPatchInput(priceFleet: 260))
        XCTAssertEqual(changed["priceFleet"] as? Double, 260)
        XCTAssertNil(changed["priceWholesale"])
        XCTAssertNil(changed["clearPriceFleet"])

        let cleared = try object(TireSkuPatchInput(priceFleet: 260, clearPriceFleet: true))
        XCTAssertTrue(cleared["priceFleet"] is NSNull)
        XCTAssertNil(cleared["clearPriceFleet"])
        XCTAssertNil(cleared["priceRetail"])
    }

    func testSkuCreateIncludesFleetWithoutChangingOtherStandardPrices() throws {
        let input = SkuInput(sku: "TBR-1", brand: "Example", model: "Road", size: "11R22.5",
                             category: "TBR", position: "ALL_POSITION", priceRetail: 270,
                             priceWholesale: 245, priceFleet: 260)
        let encoded = try object(input)
        XCTAssertEqual(encoded["priceWholesale"] as? Double, 245)
        XCTAssertEqual(encoded["priceFleet"] as? Double, 260)
        XCTAssertEqual(encoded["priceRetail"] as? Double, 270)
    }

    func testLegacySkuAndCustomerStayUnassignedWhenFieldsAreMissingOrNull() throws {
        for suffix in ["", ",\"priceFleet\":null"] {
            let sku = try decode(TireSku.self, String(FleetContractProtocol.skuJSON.dropLast()) + suffix + "}")
            XCTAssertNil(sku.priceFleet)
        }
        for suffix in ["", ",\"priceLevel\":null"] {
            let customer = try decode(Customer.self, String(FleetContractProtocol.customerJSON.dropLast()) + suffix + "}")
            XCTAssertNil(customer.priceLevel)
        }
        let sku = try decode(TireSku.self, String(FleetContractProtocol.skuJSON.dropLast()) + ",\"priceFleet\":\"260.00\"}")
        XCTAssertEqual(sku.priceFleet, "260.00")
    }

    func testCustomerCreationAndLevelPatchSendCanonicalEnum() throws {
        let created = try object(NewCustomerInput(name: "Fleet customer", priceLevel: .fleet))
        XCTAssertEqual(created["priceLevel"] as? String, "FLEET")
        let patch = try object(CustomerPriceLevelPatch(priceLevel: .wholesale))
        XCTAssertEqual(Set(patch.keys), ["priceLevel"])
        XCTAssertEqual(patch["priceLevel"] as? String, "WHOLESALE")
        XCTAssertThrowsError(try decode(PriceLevel.self, "\"UNKNOWN\""))
    }

    func testSaleLinesSubmitStableIdentityAndPreviewVersionWithoutClientBaselines() throws {
        let saved = NewSaleLine(id: "line-1", itemType: "SKU", itemId: "sku-1",
                                description: "Example", qty: 4, unitPrice: 255, discount: 2)
        let encoded = try object(saved)
        XCTAssertEqual(encoded["id"] as? String, "line-1")
        XCTAssertNil(encoded["priceVersion"])
        XCTAssertNil(encoded["standardUnitPrice"])
        XCTAssertNil(encoded["priceLevel"])

        let repriced = NewSaleLine(priceVersion: "reviewed-version", itemType: "SKU", itemId: "sku-1",
                                   description: "Example", qty: 4, unitPrice: 260, discount: nil)
        let fresh = try object(repriced)
        XCTAssertNil(fresh["id"])
        XCTAssertEqual(fresh["priceVersion"] as? String, "reviewed-version")
        XCTAssertNil(fresh["standardUnitPrice"])
    }

    func testHistoricalPriceEvidenceRoundTripsWithoutInferringLegacyValues() throws {
        let legacy = try decode(Sale.self, FleetContractProtocol.saleJSON)
        XCTAssertNil(legacy.priceLevelAtQuote)
        XCTAssertNil(legacy.lines.first?.standardUnitPrice)
        XCTAssertNil(legacy.lines.first?.priceSource)

        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(FleetContractProtocol.saleJSON.utf8)) as? [String: Any])
        body["priceLevelAtQuote"] = "FLEET"
        var lines = try XCTUnwrap(body["lines"] as? [[String: Any]])
        lines[0]["standardUnitPrice"] = "260.00"
        lines[0]["priceSource"] = "OVERRIDE"
        lines[0]["priceOverrideById"] = "manager-1"
        lines[0]["priceOverrideAt"] = "2026-10-02T12:00:00Z"
        body["lines"] = lines
        let saved = try JSONDecoder().decode(Sale.self, from: JSONSerialization.data(withJSONObject: body))
        let roundTrip = try JSONDecoder().decode(Sale.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(roundTrip, saved)
        XCTAssertEqual(roundTrip.priceLevelAtQuote, .fleet)
        XCTAssertEqual(roundTrip.lines.first?.standardUnitPrice, "260.00")
        XCTAssertEqual(roundTrip.lines.first?.unitPrice, "255.00")
        XCTAssertEqual(roundTrip.lines.first?.priceOverrideById, "manager-1")
    }

    func testSaleCreateResultKeepsServerSavedLinesAndSupportsLegacyIdentityOnly() throws {
        let full = try decode(SaleCreateResult.self, FleetContractProtocol.saleJSON)
        XCTAssertEqual(full.savedSale?.lines.first?.id, "line-1")
        XCTAssertEqual(full.savedSale?.customerId, "customer-1")
        let encoded = try object(full)
        XCTAssertNotNil(encoded["lines"])
        XCTAssertNotNil(encoded["customer"])
        XCTAssertNil(encoded["savedSale"])
        XCTAssertEqual(try JSONDecoder().decode(SaleCreateResult.self, from: JSONEncoder().encode(full)), full)

        let legacy = try decode(SaleCreateResult.self, "{\"id\":\"sale-1\",\"status\":\"DRAFT\"}")
        XCTAssertEqual(legacy.id, "sale-1")
        XCTAssertNil(legacy.savedSale)
        let legacyEncoded = try object(SaleCreateResult(id: "sale-1", ref: nil, status: "DRAFT"))
        XCTAssertEqual(Set(legacyEncoded.keys), ["id", "status"])
    }

    func testPricingPolicyAndPreviewUseScopedServerContract() async throws {
        let api = FleetPricingAPI(client: client())
        let policy = try await api.policy()
        XCTAssertTrue(policy.enabled)
        let prices = try await api.preview(customerId: "customer-1", skuIds: ["sku-1"])
        let price = try XCTUnwrap(prices.first)
        XCTAssertEqual(price.priceLevel, .fleet)
        XCTAssertEqual(price.standardUnitPrice, "260.00")
        XCTAssertEqual(price.unitPrice, "255.00")
        XCTAssertEqual(price.priceSource, "AGREEMENT")
        XCTAssertEqual(price.version, "sku-1-batch-1")
    }

    func testPreviewBatchesWithinServerLimitAndDeduplicatesWhilePreservingOrder() async throws {
        let ids = (0..<205).map { "sku-\($0)" }
        let prices = try await FleetPricingAPI(client: client()).preview(
            customerId: "customer-1", skuIds: ids + [ids[100], ids[0]]
        )
        XCTAssertEqual(prices.map(\.skuId), ids)
        XCTAssertEqual(prices[0].version, "sku-0-batch-100")
        XCTAssertEqual(prices[100].version, "sku-100-batch-100")
        XCTAssertEqual(prices[200].version, "sku-200-batch-5")
        let empty = try await FleetPricingAPI(client: client()).preview(customerId: "customer-1", skuIds: [])
        XCTAssertTrue(empty.isEmpty)
    }

    func testPreviewPropagatesOwnershipAndMissingPriceErrors() async throws {
        for (customerId, status) in [("outside-scope", 404), ("missing-price", 400)] {
            do {
                _ = try await FleetPricingAPI(client: client()).preview(customerId: customerId, skuIds: ["sku-1"])
                XCTFail("A pricing failure must not become a fallback price")
            } catch let error as APIError {
                XCTAssertEqual(error.status, status)
            }
        }
    }

    func testCustomerLevelUpdateUsesTheExistingGuardedPatchEndpoint() async throws {
        let result = try await CustomersAPI(client: client()).updatePriceLevel(
            id: "customer-1", body: CustomerPriceLevelPatch(priceLevel: .fleet)
        )
        XCTAssertEqual(result.priceLevel, .fleet)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FleetContractProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }
}

private final class FleetContractProtocol: URLProtocol {
    static let skuJSON = """
    {"id":"sku-1","sku":"TBR-1","brand":"Example","model":"Road","size":"11R22.5",
     "category":"TBR","position":"ALL_POSITION","priceRetail":"270.00","priceCost":"100.00",
     "reorderPoint":2,"active":true,"inventory":[]}
    """
    static let customerJSON = """
    {"id":"customer-1","name":"Fleet customer","taxExempt":false,"accountEnabled":false,
     "createdAt":"2026-10-02T12:00:00Z"}
    """
    static let saleJSON = """
    {"id":"sale-1","status":"DRAFT","location":"MAIN","customer":{"id":"customer-1","name":"Fleet customer"},
     "customerId":"customer-1","subtotal":"1020.00","taxRate":"0","taxAmount":"0.00","total":"1020.00",
     "createdAt":"2026-10-02T12:00:00Z","lines":[{"id":"line-1","itemType":"SKU","itemId":"sku-1",
       "description":"Example","qty":4,"unitPrice":"255.00","discount":"0.00","lineTotal":"1020.00"}]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let responseData: Data
            var status = 200
            switch (request.httpMethod, url.path) {
            case ("GET", "/api/pricing/policy"):
                responseData = Data("{\"enabled\":true}".utf8)
            case ("POST", "/api/pricing/quote-preview"):
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
                let customerId = try XCTUnwrap(body["customerId"] as? String)
                let ids = try XCTUnwrap(body["skuIds"] as? [String])
                guard Set(body.keys) == ["customerId", "skuIds"], (1...100).contains(ids.count) else {
                    throw URLError(.badServerResponse)
                }
                if customerId == "outside-scope" {
                    status = 404
                    responseData = Data("{\"message\":\"Customer not found\"}".utf8)
                } else if customerId == "missing-price" {
                    status = 400
                    responseData = Data("{\"message\":\"Configure the FLEET price before quoting\"}".utf8)
                } else {
                    responseData = try JSONSerialization.data(withJSONObject: ids.map { id in
                        ["skuId": id, "priceLevel": "FLEET", "standardUnitPrice": "260.00",
                         "unitPrice": "255.00", "priceSource": "AGREEMENT", "version": "\(id)-batch-\(ids.count)"]
                    })
                }
            case ("PATCH", "/api/customers/customer-1"):
                let body = try JSONDecoder().decode([String: String].self, from: bodyData())
                guard body == ["priceLevel": "FLEET"] else { throw URLError(.badServerResponse) }
                responseData = Data((Self.customerJSON.dropLast() + ",\"priceLevel\":\"FLEET\"}").utf8)
            default:
                throw URLError(.unsupportedURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                        headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseData)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData() throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
