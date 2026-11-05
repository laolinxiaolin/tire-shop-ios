import XCTest
@testable import TireShop

final class ContainerCompatibilityTests: XCTestCase {
    private let reviewedToken = "2026-11-04T02:29:11.123Z"

    func testContainerLinesDecodeContractBindingsAndPhysicalReceivedQuantity() throws {
        let container = try JSONDecoder().decode(Container.self, from: Data(ContainerCompatibilityFixtures.container.utf8))
        let line = try XCTUnwrap(container.lines.first)
        XCTAssertEqual(line.contractLineId, "contract-line")
        XCTAssertEqual(line.contractPlanId, "contract-plan")
        XCTAssertEqual(line.qty, 80)
        XCTAssertEqual(line.actualReceivedQty, 64)
        XCTAssertEqual(line.unitCost, "100.25")
        XCTAssertEqual(line.sku.sku, "TIRE-1")
        XCTAssertEqual(container.purchaseOrderId, "purchase-order")
        XCTAssertEqual(container.purchaseOrder?.version, 7)
        XCTAssertEqual(container.updatedAt, reviewedToken)
    }

    func testLegacyAndUnboundLinesDecodeWithoutContractFactsOrInventedReceipts() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(ContainerCompatibilityFixtures.line.utf8)
        ) as? [String: Any])
        let fields = ["contractLineId", "contractPlanId", "actualReceivedQty"]
        for useNull in [false, true] {
            for field in fields {
                if useNull { json[field] = NSNull() }
                else { json.removeValue(forKey: field) }
            }
            let line = try JSONDecoder().decode(ContainerLine.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(line.contractLineId)
            XCTAssertNil(line.contractPlanId)
            XCTAssertNil(line.actualReceivedQty, "Unknown receipt quantity must remain distinct from zero")
            XCTAssertEqual(line.qty, 80)
            XCTAssertEqual(line.skuId, "sku-1")
        }
        json["actualReceivedQty"] = 0
        let zero = try JSONDecoder().decode(ContainerLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(zero.actualReceivedQty, 0)
    }

    func testStatusSendsBothReviewedContractVersionAndExactContainerTimestamp() async throws {
        let id = UUID().uuidString
        let container = try await makeAPI().setStatus(
            id: id, status: "IN_TRANSIT", expectedContractVersion: 7,
            expectedContainerUpdatedAt: reviewedToken
        )
        let json = try requestJSON(id: id, action: "status", method: "POST")
        XCTAssertEqual(json as NSDictionary, [
            "status": "IN_TRANSIT", "expectedContractVersion": 7,
            "expectedContainerUpdatedAt": reviewedToken
        ] as NSDictionary)
        XCTAssertEqual(container.lines.first?.contractLineId, "contract-line")
    }

    func testReceiveAndCancelSendTheReviewedContainerTimestamp() async throws {
        let api = makeAPI()
        for action in ["receive", "cancel"] {
            let id = UUID().uuidString
            if action == "receive" {
                _ = try await api.receive(id: id, expectedContainerUpdatedAt: reviewedToken)
            } else {
                _ = try await api.cancel(id: id, expectedContainerUpdatedAt: reviewedToken)
            }
            let json = try requestJSON(id: id, action: action, method: "POST")
            XCTAssertEqual(json as NSDictionary, ["expectedContainerUpdatedAt": reviewedToken] as NSDictionary)
        }
    }

    func testLegacyMutationCallersOmitOptionalReviewFields() async throws {
        let api = makeAPI()
        let statusID = UUID().uuidString
        _ = try await api.setStatus(id: statusID, status: "ORDERED")
        let status = try requestJSON(id: statusID, action: "status", method: "POST")
        XCTAssertEqual(status as NSDictionary, ["status": "ORDERED"] as NSDictionary)

        for action in ["receive", "cancel"] {
            let id = UUID().uuidString
            if action == "receive" { _ = try await api.receive(id: id) }
            else { _ = try await api.cancel(id: id) }
            XCTAssertTrue(try requestJSON(id: id, action: action, method: "POST").isEmpty)
        }
    }

    func testContainerPatchCarriesReviewTokenWithoutDroppingEditsOrExplicitClears() async throws {
        for token in [String?.some(reviewedToken), nil] {
            let id = UUID().uuidString
            let patch = ContainerPatchInput(
                reference: "CONT+REF", bolNumber: nil, isDDP: true, costSpread: "VALUE", location: "EAST",
                etaAt: "2026-11-20", arrivedAt: nil, balanceDueAt: "2026-12-01", notes: "Reviewed manifest",
                lines: [.init(skuId: "sku-1", qty: 80, unitCost: 100.25, fetPerUnit: nil)],
                expectedContainerUpdatedAt: token
            )
            _ = try await makeAPI().update(id: id, body: patch)
            let json = try requestJSON(id: id, method: "PATCH")
            var expected: [String: Any] = [
                "reference": "CONT+REF", "bolNumber": NSNull(), "isDDP": true, "costSpread": "VALUE",
                "location": "EAST", "etaAt": "2026-11-20", "arrivedAt": NSNull(),
                "balanceDueAt": "2026-12-01", "notes": "Reviewed manifest",
                "lines": [["skuId": "sku-1", "qty": 80, "unitCost": 100.25]]
            ]
            if let token { expected["expectedContainerUpdatedAt"] = token }
            XCTAssertEqual(json as NSDictionary, expected as NSDictionary)
        }
    }

    private func makeAPI() -> ContainersAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContainerCompatibilityProtocol.self]
        return ContainersAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }

    private func requestJSON(id: String, action: String? = nil, method: String) throws -> [String: Any] {
        let path = "/api/containers/\(id)" + (action.map { "/\($0)" } ?? "")
        let request = try XCTUnwrap(ContainerCompatibilityProtocol.takeRequest(path: path))
        XCTAssertEqual(request.method, method)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }
}

private enum ContainerCompatibilityFixtures {
    static let line = """
    {"id":"container-line","skuId":"sku-1","qty":80,"unitCost":"100.25","fetPerUnit":"1.50",
     "landedUnitCost":null,"landedTotal":null,"prevPriceCost":null,
     "contractLineId":"contract-line","contractPlanId":"contract-plan","actualReceivedQty":64,
     "sku":{"id":"sku-1","sku":"TIRE-1","brand":"Brand","model":"Model","size":"295/75R22.5",
            "category":"TRUCK","position":"DRIVE","priceCost":"98.00","fetPerUnit":"1.50"}}
    """

    static let container = """
    {"id":"container-1","ref":"c-261104001","reference":"CONT+REF","supplierId":"supplier",
     "supplier":{"id":"supplier","name":"Factory"},"purchaseOrderId":"purchase-order",
     "purchaseOrder":{"id":"purchase-order","ref":"po-261104001","version":7},
     "status":"ORDERED","isDDP":false,"location":"MAIN","costSpread":"VALUE",
     "lines":[\(line)],"costs":[],"createdAt":"2026-10-01T12:00:00.000Z",
     "updatedAt":"2026-11-04T02:29:11.123Z"}
    """
}

private final class ContainerCompatibilityProtocol: URLProtocol {
    struct RecordedRequest {
        let method: String?
        let body: Data
    }

    private static let lock = NSLock()
    private static var requests: [String: RecordedRequest] = [:]

    static func takeRequest(path: String) -> RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.removeValue(forKey: path)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let record = RecordedRequest(method: request.httpMethod, body: try requestData())
            Self.lock.lock()
            Self.requests[url.path] = record
            Self.lock.unlock()
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(ContainerCompatibilityFixtures.container.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func requestData() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
