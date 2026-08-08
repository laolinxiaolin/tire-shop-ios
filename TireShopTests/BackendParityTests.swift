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

    // MARK: - Supplier profiles & vendor pagination (#407)

    func testVendorDetailDecodesWithoutRecentLists() throws {
        // #407 removed the recentCosts/recentExpenses/recentRefunds arrays
        // from GET /api/vendors/:id — the client must decode the summary-only
        // response (the old non-optional fields would have crashed decode).
        let detail: VendorDetail = try decode(
            VendorDetail.self,
            """
            {"id":"v_1","name":"Trucking Co","category":"TRUCKING","contactName":null,
             "phone":null,"email":null,"address":null,"notes":null,"active":true,
             "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
             "summary":{"openAP":100,"paidOut":500,"refunds":50,"netSpend":450}}
            """
        )
        XCTAssertEqual(detail.summary.openAP, 100)
        XCTAssertEqual(detail.summary.netSpend, 450)
    }

    func testSupplierDetailDecodesSummary() throws {
        let detail: SupplierDetail = try decode(
            SupplierDetail.self,
            """
            {"id":"sup_1","name":"Linglong","contactName":null,"phone":null,"email":null,
             "country":"China","address":null,"currency":"USD","defaultDDP":true,"notes":null,
             "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
             "summary":{"supplierOpenAP":1000,"supplierBilled":5000,"supplierPaid":4000,
              "otherOpenAP":200,"otherBilled":800,"otherPaid":600,"landedValue":12000,
              "tiresReceived":400,"containerCount":3,"openContainerCount":1,
              "receivedContainerCount":2,"firstOrderAt":"2025-06-01T00:00:00.000Z",
              "lastOrderAt":"2026-07-01T00:00:00.000Z"}}
            """
        )
        XCTAssertEqual(detail.summary.supplierOpenAP, 1000)
        XCTAssertEqual(detail.summary.receivedContainerCount, 2)
        XCTAssertEqual(detail.summary.firstOrderAt, "2025-06-01T00:00:00.000Z")
        XCTAssertEqual(detail.defaultDDP, true)
    }

    func testSupplierContainerRowDecodes() throws {
        let row: SupplierContainerRow = try decode(
            SupplierContainerRow.self,
            """
            {"id":"c_1","ref":"CN-2026-001","reference":"PO-100","status":"RECEIVED",
             "bolNumber":"BOL-1","location":"MAIN","isDDP":true,
             "orderedAt":"2026-01-01T00:00:00.000Z","etaAt":null,"arrivedAt":null,
             "receivedAt":"2026-02-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z",
             "tireQty":120,"_count":{"lines":3,"costs":2}}
            """
        )
        XCTAssertEqual(row.status, "RECEIVED")
        XCTAssertEqual(row.tireQty, 120)
        XCTAssertEqual(row.count?.lines, 3)
        XCTAssertEqual(row.count?.costs, 2)
    }

    func testSupplierCostRowDecodes() throws {
        let row: SupplierCostRow = try decode(
            SupplierCostRow.self,
            """
            {"id":"cost_1","category":"BALANCE_PAYMENT","status":"DUE",
             "description":"Balance","amount":5000,"amountPaid":1000,
             "vendor":null,"vendorId":null,"dueAt":"2026-03-01T00:00:00.000Z",
             "paidAt":null,"reference":"REF-1","createdAt":"2026-01-01T00:00:00.000Z",
             "container":{"id":"c_1","ref":"CN-2026-001"}}
            """
        )
        XCTAssertEqual(row.amount, 5000)
        XCTAssertEqual(row.amountPaid, 1000)
        XCTAssertEqual(row.container?.ref, "CN-2026-001")
    }

    func testSupplierCostRowDecodesWithoutContainer() throws {
        // Transfer-freight bills are ContainerCosts with transferId set, so
        // the supplier-scoped list can still surface them with container null.
        let row: SupplierCostRow = try decode(
            SupplierCostRow.self,
            """
            {"id":"cost_2","category":"FREIGHT","status":"PAID",
             "description":null,"amount":300,"amountPaid":300,
             "vendor":"Trucking Co","vendorId":"v_1","dueAt":null,
             "paidAt":"2026-01-15T00:00:00.000Z","reference":null,
             "createdAt":"2026-01-01T00:00:00.000Z","container":null}
            """
        )
        XCTAssertNil(row.container)
        XCTAssertEqual(row.vendor, "Trucking Co")
    }

    func testSupplierPaymentRowDecodes() throws {
        let row: SupplierPaymentRow = try decode(
            SupplierPaymentRow.self,
            """
            {"id":"pmt_1","ref":"pmt-2026-0001","vendor":"Linglong","total":5000,
             "appliedToSupplier":3000,"status":"POSTED","reference":null,"paidBy":"Alice",
             "paidAt":"2026-03-01T00:00:00.000Z",
             "fundingAccount":{"code":"1020","name":"Bank Account"},
             "lines":[{"id":"l_1","amount":3000,"containerCost":{"id":"cost_1",
               "category":"BALANCE_PAYMENT","container":{"id":"c_1","ref":"CN-2026-001"}}}]}
            """
        )
        XCTAssertEqual(row.appliedToSupplier, 3000)
        XCTAssertEqual(row.fundingAccount?.code, "1020")
        XCTAssertEqual(row.lines.first?.containerCost.category, "BALANCE_PAYMENT")
        XCTAssertEqual(row.lines.first?.containerCost.container?.ref, "CN-2026-001")
    }

    func testSupplierReturnRowDecodes() throws {
        let row: SupplierReturnRow = try decode(
            SupplierReturnRow.self,
            """
            {"id":"ret_1","ref":"rt-2026-0001","type":"WARRANTY","status":"POSTED",
             "refundTotal":250,"warrantyDisposition":"SUPPLIER_CLAIM",
             "createdAt":"2026-04-01T00:00:00.000Z","postedAt":"2026-04-02T00:00:00.000Z",
             "sale":{"id":"s_1","ref":"s-2026-0100"},"_count":{"lines":2}}
            """
        )
        XCTAssertEqual(row.refundTotal, 250)
        XCTAssertEqual(row.sale.ref, "s-2026-0100")
        XCTAssertEqual(row.count?.lines, 2)
    }

    func testSupplierCostsPageDecodesPagedEnvelope() throws {
        let page: Paged<SupplierCostRow> = try decode(
            Paged<SupplierCostRow>.self,
            """
            {"items":[{"id":"cost_1","category":"BALANCE_PAYMENT","status":"DUE",
               "description":null,"amount":5000,"amountPaid":1000,"vendor":null,
               "vendorId":null,"dueAt":null,"paidAt":null,"reference":null,
               "createdAt":"2026-01-01T00:00:00.000Z","container":null}],
             "total":1,"page":1,"pageSize":25}
            """
        )
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.pageSize, 25)
        XCTAssertEqual(page.items.count, 1)
    }
}
