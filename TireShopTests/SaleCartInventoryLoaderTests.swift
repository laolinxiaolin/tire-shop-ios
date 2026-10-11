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
