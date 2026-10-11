import XCTest
@testable import TireShop

final class SaleCartInventoryLoaderTests: XCTestCase {
    func testEveryPageUsesOnlySelectedIDsAndExcludesUnexpectedRows() async throws {
        var requests: [([String], Int)] = []
        let loader = SaleCartInventoryLoader { ids, page, size in
            requests.append((ids, page))
            XCTAssertEqual(size, 1000)
            let skus = try (page == 1 ? ["selected-a", "unrelated"] : ["selected-b"]).map(self.sku)
            return InventorySkuPage(items: skus, total: 3, page: page, pageSize: 2, totals: nil)
        }
        let loaded = try await loader.load(skuIds: ["selected-b", "selected-a"])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.0 }, [["selected-a", "selected-b"], ["selected-a", "selected-b"]])
        XCTAssertEqual(requests.map { $0.1 }, [1, 2])
        XCTAssertEqual(Set(loaded.keys), ["selected-a", "selected-b"])
    }

    func testEmptyCartMakesNoInventoryRequest() async throws {
        let loader = SaleCartInventoryLoader { _, _, _ in
            XCTFail("An empty cart must not scan inventory")
            return InventorySkuPage(items: [], total: 0, page: 1, pageSize: 1000, totals: nil)
        }
        let loaded = try await loader.load(skuIds: [])
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLargeCartUsesBoundedURLsAndPaginatesWithinEachIDBatch() async throws {
        let ids = Set((1...400).map { String(format: "c%024d", $0) })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedCartInventoryProtocol.self]
        let inventory = InventoryAPI(client: APIClient(session: URLSession(configuration: configuration)))
        let loader = SaleCartInventoryLoader { ids, page, size in
            try await inventory.listSkus(ids: ids, page: page, pageSize: size)
        }

        // The HTTP stub rejects requests larger than nginx's URI limit and
        // clamps each response to 25 rows, even when the client asks for 1000.
        let loaded = try await loader.load(skuIds: ids)
        XCTAssertEqual(Set(loaded.keys), ids)
        XCTAssertEqual(loaded.count, 400)
    }

    func testResponseCannotResolveAnIDFromAnotherBatch() async throws {
        let ids = Set((1...101).map { String(format: "c%024d", $0) })
        let absentID = try XCTUnwrap(ids.sorted().last)
        let loader = SaleCartInventoryLoader { requested, page, size in
            let returned = requested.contains(absentID) ? [] : requested + [absentID]
            let items = try returned.map(self.sku)
            return InventorySkuPage(items: items, total: items.count, page: page, pageSize: size, totals: nil)
        }

        let loaded = try await loader.load(skuIds: ids)
        XCTAssertEqual(Set(loaded.keys), ids.subtracting([absentID]))
        XCTAssertNil(loaded[absentID], "An item must be returned by its own requested batch")
    }

    func testCanceledLookupDoesNotRequestAnotherPage() async throws {
        let started = expectation(description: "First page started")
        var finish: CheckedContinuation<InventorySkuPage, Error>?
        var pages: [Int] = []
        let loader = SaleCartInventoryLoader { _, page, _ in
            pages.append(page)
            return try await withCheckedThrowingContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        let task = Task { try await loader.load(skuIds: ["a", "b"]) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        finish?.resume(returning: InventorySkuPage(items: [try sku("a")], total: 2, page: 1, pageSize: 1, totals: nil))
        do {
            _ = try await task.value
            XCTFail("Canceled inventory lookup should not finish successfully")
        } catch is CancellationError {
            XCTAssertEqual(pages, [1])
        }
    }

    private func sku(_ id: String) throws -> TireSku {
        try JSONDecoder().decode(TireSku.self, from: Data("""
        {"id":"\(id)","sku":"\(id)","brand":"Example","model":"Road","size":"225/65R17",
         "category":"PCR","position":"ALL_POSITION","priceRetail":"125.00","priceCost":"80.00",
         "reorderPoint":2,"active":true,"inventory":[]}
        """.utf8))
    }
}

private final class BoundedCartInventoryProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let params = components.queryItems ?? []
            XCTAssertEqual(components.path, "/api/inventory/skus")
            let idsValue = try XCTUnwrap(params.first { $0.name == "ids" }?.value)
            let ids = idsValue.split(separator: ",").map(String.init)
            let target = components.percentEncodedPath + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
            guard target.utf8.count <= 8192, ids.count <= 100 else {
                try complete(url: url, status: 414, body: Data("{\"message\":\"Request URI too large\"}".utf8))
                return
            }
            let page = try XCTUnwrap(Int(try XCTUnwrap(params.first { $0.name == "page" }?.value)))
            let pageSize = 25
            let start = min((page - 1) * pageSize, ids.count)
            let end = min(start + pageSize, ids.count)
            let items: [[String: Any]] = ids[start..<end].map { id in
                ["id": id, "sku": id, "brand": "Example", "model": "Road", "size": "225/65R17",
                 "category": "PCR", "position": "ALL_POSITION", "priceRetail": "125.00",
                 "priceCost": "80.00", "reorderPoint": 2, "active": true, "inventory": []]
            }
            let body = try JSONSerialization.data(withJSONObject: ["items": items, "total": ids.count,
                "page": page, "pageSize": pageSize])
            try complete(url: url, status: 200, body: body)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func complete(url: URL, status: Int, body: Data) throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
