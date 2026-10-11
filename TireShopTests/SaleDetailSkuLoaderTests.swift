import XCTest
@testable import TireShop

final class SaleDetailSkuLoaderTests: XCTestCase {
    func testDeletedItemNeverUsesSimilarCatalogResult() async throws {
        let result = try await loader().load(itemIDs: ["deleted-prefix"])
        XCTAssertTrue(result.isEmpty)
    }

    func testBatchLookupDeduplicatesIDsAndIgnoresUnrequestedItems() async throws {
        let result = try await loader().load(itemIDs: ["sku-1", "sku-2", "sku-1", ""])
        XCTAssertEqual(Set(result.keys), ["sku-1", "sku-2"])
    }

    func testBatchLookupHandlesMoreThanOneHundredSaleItems() async throws {
        let ids = (1...101).map { "sku-\($0)" }
        let result = try await loader().load(itemIDs: ids)
        XCTAssertEqual(Set(result.keys), Set(ids))
    }

    func testEmptySaleDoesNotFetchCatalog() async throws {
        let result = try await loader().load(itemIDs: [])
        XCTAssertTrue(result.isEmpty)
    }

    private func loader() -> SaleDetailSkuLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SaleDetailSkuProtocol.self]
        return SaleDetailSkuLoader(inventory: InventoryAPI(client: APIClient(session: URLSession(configuration: config))))
    }
}

private final class SaleDetailSkuProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/api/inventory/skus")
            let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertNil(params.first { $0.name == "q" }, "Sale IDs must never fall back to fuzzy search")
            let ids = try XCTUnwrap(params.first { $0.name == "ids" }?.value).split(separator: ",").map(String.init)
            XCTAssertLessThanOrEqual(ids.count, 100)
            var returnedIDs = ids.filter { $0 != "deleted-prefix" }
            returnedIDs.append("deleted-prefix-other")
            let items: [[String: Any]] = returnedIDs.map { id in
                ["id": id, "sku": id, "brand": "Example", "model": "Road", "size": "225/65R17",
                 "category": "PCR", "position": "ALL_POSITION", "priceRetail": "125.00",
                 "priceCost": "80.00", "reorderPoint": 2, "active": true, "inventory": []]
            }
            let body = try JSONSerialization.data(withJSONObject: ["items": items, "total": items.count,
                "page": 1, "pageSize": 1000])
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
