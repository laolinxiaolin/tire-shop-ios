import XCTest
@testable import TireShop

/// Pins the client to the backend response contracts added after the last
/// parity point:
/// - #403: Best Sellers accepts a warehouse scope and echoes it back as
///   `warehouse` (null for the combined all-warehouse view).
/// - #406: `GET /sales` supports `summary=false` light mode, where the server
///   returns `total: null` and omits the financial `summary` entirely.
final class BackendParityTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: XCTUnwrap(json.data(using: .utf8)))
    }

    // MARK: - Sales list light mode (#406)

    func testSalesListDecodesFullMode() throws {
        let response: SalesListResponse = try decode(
            SalesListResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"count":0,"tireQty":0,"taxAmount":"0.00","grossProfit":"0.00","total":"0.00"}}
            """
        )
        XCTAssertEqual(response.total, 0)
        XCTAssertEqual(response.summary?.count, 0)
    }

    func testSalesListDecodesLightMode() throws {
        // summary=false: the server skips the whole-set count and the
        // financial aggregates, so total is null and summary is absent.
        let response: SalesListResponse = try decode(
            SalesListResponse.self,
            """
            {"items":[],"total":null,"page":1,"pageSize":50}
            """
        )
        XCTAssertNil(response.total)
        XCTAssertNil(response.summary)
    }

    // MARK: - Best Sellers warehouse scope (#403)

    func testBestSellersDecodesWarehouseScope() throws {
        let response: BestSellersResponse = try decode(
            BestSellersResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"skuCount":0,"qty":0,"saleCount":0,"revenue":"0.00","grossProfit":"0.00"},
             "period":{"months":3,"from":"2026-05-08","to":"2026-08-07","timezone":"America/New_York"},
             "warehouse":{"code":"MAIN","name":"Main Warehouse"}}
            """
        )
        XCTAssertEqual(response.warehouse?.code, "MAIN")
        XCTAssertEqual(response.warehouse?.name, "Main Warehouse")
    }

    func testBestSellersDecodesCombinedView() throws {
        // Omitted location → warehouse: null. An older server omits the key
        // entirely, which must decode the same way.
        let response: BestSellersResponse = try decode(
            BestSellersResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"skuCount":0,"qty":0,"saleCount":0,"revenue":"0.00","grossProfit":"0.00"},
             "period":{"months":null,"from":null,"to":"2026-08-07","timezone":"America/New_York"},
             "warehouse":null}
            """
        )
        XCTAssertNil(response.warehouse)
    }

    // MARK: - Sales list continuation paging (#406, review P1/P2)

    func testDefaultOrderContinuationUsesCursor() {
        let cursor = SalesCursor(before: "2026-08-07T12:00:00Z", beforeId: "sale-9")
        let request = SalesContinuationRequest(
            sortBy: nil,
            sortOrder: nil,
            page: 3,
            cursor: cursor
        )
        // Keyset mode: the cursor rides alongside the offset page (the
        // compatibility contract), and no sort is sent (the server's cursor
        // ordering is fixed at createdAt desc, id desc).
        XCTAssertEqual(request.page, 3)
        XCTAssertEqual(request.before, cursor.before)
        XCTAssertEqual(request.beforeId, cursor.beforeId)
        XCTAssertNil(request.sortBy)
        XCTAssertNil(request.sortOrder)
    }

    func testCustomSortContinuationPagesByOffset() {
        let cursor = SalesCursor(before: "2026-08-07T12:00:00Z", beforeId: "sale-9")
        let request = SalesContinuationRequest(
            sortBy: "total",
            sortOrder: "desc",
            page: 2,
            cursor: cursor
        )
        // A keyset continuation would be reordered to (createdAt desc, id
        // desc), silently dropping the sort — so custom sorts must page by
        // offset with no cursor.
        XCTAssertEqual(request.page, 2)
        XCTAssertNil(request.before)
        XCTAssertNil(request.beforeId)
        XCTAssertEqual(request.sortBy, "total")
        XCTAssertEqual(request.sortOrder, "desc")
    }

    func testDefaultOrderWithoutCursorPagesByOffset() {
        // Defensive path: no cursor available but hasMore said there is more;
        // the request must still advance by page rather than stall.
        let request = SalesContinuationRequest(
            sortBy: nil,
            sortOrder: nil,
            page: 4,
            cursor: nil
        )
        XCTAssertEqual(request.page, 4)
        XCTAssertNil(request.before)
        XCTAssertNil(request.beforeId)
        XCTAssertNil(request.sortBy)
    }
}
