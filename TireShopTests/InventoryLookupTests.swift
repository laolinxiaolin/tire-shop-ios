import XCTest
@testable import TireShop

final class InventoryLookupTests: XCTestCase {
    func testSelectedDatabaseIDLoadsEvenWhenTextSearchCannotFindIt() async throws {
        let sku = try await api().resolveSku(idOrSku: "database-id-1")
        XCTAssertEqual(sku.id, "database-id-1")
        XCTAssertEqual(sku.sku, "TIRE-001")
        XCTAssertEqual(sku.inventory.first?.location, "MAIN")
    }

    func testGetSkuUsesTheSupportedIDsFilter() async throws {
        let sku = try await api().getSku(id: "database-id-1")
        XCTAssertEqual(sku.id, "database-id-1")
    }

    func testSkuCodeFallsBackToAnExactSearchMatch() async throws {
        let sku = try await api().resolveSku(idOrSku: "TIRE-001")
        XCTAssertEqual(sku.id, "database-id-1")
    }

    func testSimilarSearchResultCannotOpenTheWrongTire() async throws {
        await assertLookupError("TIRE", status: 404)
    }

    func testDeletedSelectionReportsNotFound() async throws {
        await assertLookupError("deleted-id", status: 404)
    }

    func testPermissionFailureIsNotMaskedBySearchFallback() async throws {
        await assertLookupError("forbidden-id", status: 403)
    }

    private func assertLookupError(_ identifier: String, status: Int) async {
        do {
            _ = try await api().resolveSku(idOrSku: identifier)
            XCTFail("Lookup should fail for \(identifier)")
        } catch let error as APIError {
            XCTAssertEqual(error.status, status)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func api() -> InventoryAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InventoryLookupProtocol.self]
        return InventoryAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }
}

private final class InventoryLookupProtocol: URLProtocol {
    private static let skuJSON = """
    {"id":"database-id-1","sku":"TIRE-001","brand":"Example","model":"Road",
     "size":"225/65R17","category":"PCR","position":"ALL_POSITION",
     "priceRetail":"125.00","priceCost":"80.00","reorderPoint":2,"active":true,
     "inventory":[{"id":"stock-1","location":"MAIN","qtyOnHand":12,
                   "qtyReserved":1,"unitCost":"80.00"}]}
    """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let status: Int
        let body: String
        switch url.path {
        case "/api/inventory/skus":
            let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let ids = params.first(where: { $0.name == "ids" })?.value
            let query = params.first(where: { $0.name == "q" })?.value
            if ids == "forbidden-id" {
                status = 403
                body = "{\"message\":\"Access denied\"}"
            } else {
                status = 200
                let matches = ids == "database-id-1" || ["TIRE-001", "TIRE"].contains(query ?? "")
                let items = matches ? Self.skuJSON : ""
                body = "{\"items\":[\(items)],\"total\":\(items.isEmpty ? 0 : 1),\"page\":1,\"pageSize\":50}"
            }
        default:
            // The backend exposes PATCH /skus/:id, but no GET /skus/:id.
            status = 404
            body = "{\"message\":\"Not found\"}"
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
