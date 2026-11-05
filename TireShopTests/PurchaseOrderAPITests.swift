import XCTest
@testable import TireShop

final class PurchaseOrderAPITests: XCTestCase {
    func testOrderSearchPreservesLiteralPlusInSupplierReference() async throws {
        let supplierId = UUID().uuidString
        _ = try await makeAPI().list(q: "LR+A & B", supplierId: supplierId)
        let request = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/purchase-orders"))
        XCTAssertTrue(request.query.contains("q=LR%2BA%20%26%20B"), request.query)
        let components = try XCTUnwrap(URLComponents(string: "https://example.invalid/?" + request.query))
        XCTAssertEqual(components.queryItems?.first { $0.name == "q" }?.value, "LR+A & B")
        XCTAssertEqual(components.queryItems?.first { $0.name == "view" }?.value, "pending")
    }

    func testListAndExportRetainEachSelectedViewAndSearchScope() async throws {
        let api = makeAPI()
        let supplierId = UUID().uuidString
        for view in PurchaseOrderListView.allCases {
            _ = try await api.list(q: "LR+A & B", supplierId: supplierId, view: view, page: 3, pageSize: 25)
            let list = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/purchase-orders"))
            let url = try await api.export(q: "LR+A & B", supplierId: supplierId, view: view)
            TemporaryDownloadStore.remove(url)
            let export = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/purchase-orders/export"))
            let listQuery = try queryItems(list.query)
            let exportQuery = try queryItems(export.query)
            for key in ["q", "supplierId", "view"] {
                XCTAssertEqual(listQuery[key], exportQuery[key], key)
            }
            XCTAssertEqual(listQuery["view"], view.rawValue)
            XCTAssertEqual(listQuery["q"], "LR+A & B")
            XCTAssertEqual(listQuery["supplierId"], supplierId)
            XCTAssertEqual(listQuery["page"], "3")
            XCTAssertNil(exportQuery["page"])
            XCTAssertNil(exportQuery["pageSize"])
        }
    }

    func testContainerCandidatesDoNotInheritPurchaseOrderViewParameter() async throws {
        _ = try await makeAPI().candidates(supplierId: "supplier", excludingOrderId: "po")
        let request = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/containers"))
        XCTAssertNil(try queryItems(request.query)["view"])
    }

    func testMoveSubmitsReviewedParentAndBothVersions() async throws {
        let containerId = UUID().uuidString
        let body = PurchaseOrderMoveContainerInput(
            purchaseOrderId: "target", expectedPurchaseOrderId: "source", expectedVersion: 7,
            expectedSourceVersion: 3, plannedContainerCount: 4, reason: "Group supplier agreement"
        )
        _ = try await makeAPI().moveContainer(containerId: containerId, body: body)
        let request = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/containers/\(containerId)/purchase-order"))
        XCTAssertEqual(request.method, "POST")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(json["expectedPurchaseOrderId"] as? String, "source")
        XCTAssertEqual(json["expectedSourceVersion"] as? Int, 3)
        XCTAssertEqual(json["expectedVersion"] as? Int, 7)
    }

    func testStaleMutationIsNotAutomaticallyRetried() async throws {
        let id = "conflict-\(UUID().uuidString)"
        do {
            _ = try await makeAPI().issue(id: id, expectedVersion: 2)
            XCTFail("The stale version must be rejected")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 409)
        }
        XCTAssertEqual(PurchaseOrderTestProtocol.requestCount(path: "/api/purchase-orders/\(id)/issue"), 1)
    }

    func testOrderPaymentsPreserveReversedAllocationEvidence() async throws {
        let payments = try await makeAPI().payments(id: "payments")
        XCTAssertEqual(payments.first?.poAllocatedAmount, 25)
        XCTAssertEqual(payments.first?.allocations.map(\.surviving), [true, false])
        XCTAssertEqual(payments.first?.allocations.map(\.amount), [25, 100])
    }

    func testSharedDocumentImportSendsPurchaseOrderSourceTypeAndReturnsSnapshotLink() async throws {
        let id = UUID().uuidString
        let api = PaymentApplicationsAPI(client: makeAPI().client)
        let attachment = try await api.importAttachment(id: id, body: PaymentApplicationImportAttachmentInput(
            sourceAttachmentId: "shared-contract", sourceType: "PURCHASE_ORDER", kind: "CONTRACT"
        ))
        XCTAssertEqual(attachment.sourcePurchaseOrderAttachmentId, "shared-contract")
        let recorded = try XCTUnwrap(PurchaseOrderTestProtocol.lastRequest(path: "/api/payment-applications/\(id)/attachments/import"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        XCTAssertEqual(json["sourceType"] as? String, "PURCHASE_ORDER")
        XCTAssertEqual(json["sourceAttachmentId"] as? String, "shared-contract")
    }

    func testSharedDocumentRejectsFilesAboveItsTwentyMBLimitBeforeRequest() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(20 * 1_024 * 1_024 + 1))
        try handle.close()
        let id = UUID().uuidString
        do {
            _ = try await makeAPI().uploadAttachment(id: id, fileURL: url, fileName: "contract.pdf", mimeType: "application/pdf", kind: "CONTRACT")
            XCTFail("Shared order documents have a stricter upload limit")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 0)
            XCTAssertTrue(error.message.contains("20 MB"))
        }
        XCTAssertEqual(PurchaseOrderTestProtocol.requestCount(path: "/api/purchase-orders/\(id)/attachments"), 0)
    }

    private func makeAPI() -> PurchaseOrdersAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PurchaseOrderTestProtocol.self]
        return PurchaseOrdersAPI(client: APIClient(session: URLSession(configuration: configuration)))
    }

    private func queryItems(_ query: String) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(string: "https://example.invalid/?" + query))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

@MainActor
final class PurchaseOrderListStoreTests: XCTestCase {
    func testChangingViewResetsPaginationAndDoesNotKeepPreviousRowsOnFailure() async throws {
        var requests: [(PurchaseOrderListFilter, Int)] = []
        let store = PurchaseOrderListStore { filter, page, size in
            requests.append((filter, page))
            if filter.view == .history { throw URLError(.notConnectedToInternet) }
            return Paged(items: [try PurchaseOrderFixtures.order()], total: 100, page: page, pageSize: size)
        }
        let pending = PurchaseOrderListFilter(search: "Factory", supplierId: "supplier", view: .pending)
        await store.load(filter: pending, page: 1)
        await store.load(filter: pending, page: 3)
        XCTAssertEqual(store.data?.page, 3)
        let history = PurchaseOrderListFilter(search: "Factory", supplierId: "supplier", view: .history)
        await store.load(filter: history, page: 3)
        XCTAssertEqual(requests.map { $0.1 }, [1, 3, 1])
        XCTAssertEqual(requests.last?.0, history)
        XCTAssertNil(store.data)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.loading)
    }

    func testLatePreviousViewPageCannotReplaceNewView() async throws {
        let started = expectation(description: "Old pending page started")
        var completion: CheckedContinuation<Paged<PurchaseOrder>, Error>?
        let store = PurchaseOrderListStore { filter, page, size in
            if filter.view == .pending && page == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    completion = continuation
                    started.fulfill()
                }
            }
            return Paged(items: [try PurchaseOrderFixtures.order(id: filter.view.rawValue)], total: 30, page: page, pageSize: size)
        }
        await store.load(filter: PurchaseOrderListFilter(view: .pending), page: 1)
        let oldRequest = Task { await store.load(filter: PurchaseOrderListFilter(view: .pending), page: 2) }
        await fulfillment(of: [started], timeout: 1)
        await store.load(filter: PurchaseOrderListFilter(view: .all), page: 1)
        completion?.resume(returning: Paged(items: [try PurchaseOrderFixtures.order(id: "stale")], total: 99, page: 2, pageSize: 25))
        await oldRequest.value
        XCTAssertEqual(store.data?.items.map(\.id), ["all"])
        XCTAssertEqual(store.data?.page, 1)
        XCTAssertEqual(store.data?.total, 30)
        XCTAssertFalse(store.loading)
    }

    func testInvalidatedRequestCannotRestoreHiddenRowsOrErrors() async throws {
        let started = expectation(description: "Request started")
        var completion: CheckedContinuation<Paged<PurchaseOrder>, Error>?
        let store = PurchaseOrderListStore { _, _, _ in
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                started.fulfill()
            }
        }
        let request = Task { await store.load(filter: PurchaseOrderListFilter(view: .history), page: 1) }
        await fulfillment(of: [started], timeout: 1)
        store.invalidate(clearData: true)
        completion?.resume(throwing: URLError(.notConnectedToInternet))
        await request.value
        XCTAssertNil(store.data)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.loading)
    }
}

private final class PurchaseOrderTestProtocol: URLProtocol {
    struct RecordedRequest {
        let method: String
        let body: Data
        let query: String
    }

    private static let lock = NSLock()
    private static var requests: [String: [RecordedRequest]] = [:]

    static func lastRequest(path: String) -> RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[path]?.last
    }

    static func requestCount(path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests[path]?.count ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let record = RecordedRequest(method: request.httpMethod ?? "GET", body: requestData(), query: url.query ?? "")
        Self.lock.lock()
        Self.requests[url.path, default: []].append(record)
        Self.lock.unlock()

        let status: Int
        let json: String
        if url.path.contains("conflict-") {
            status = 409
            json = "{\"message\":\"Purchase order changed; refresh and review\"}"
        } else if url.path.hasSuffix("/payments") {
            status = 200
            json = """
            {"items":[{"id":"payment","ref":"sp-1","method":"WIRE","paidAt":"2026-10-06T12:00:00Z",
             "poAllocatedAmount":25,"allocations":[
              {"id":"paid","containerCostId":"bill","containerId":"cg","category":"BALANCE_PAYMENT","amount":25,"surviving":true},
              {"id":"reversed","containerCostId":"bill2","containerId":"cg2","category":"DOWN_PAYMENT","amount":100,"surviving":false}]}]}
            """
        } else if url.path.hasSuffix("/attachments/import") {
            status = 200
            json = """
            {"id":"evidence-copy","kind":"CONTRACT","filename":"contract.pdf","mimeType":"application/pdf",
             "sizeBytes":12,"sourcePurchaseOrderAttachmentId":"shared-contract","createdAt":"2026-10-06T12:00:00Z"}
            """
        } else if url.path == "/api/purchase-orders", request.httpMethod == "GET" {
            status = 200
            json = "{\"items\":[\(PurchaseOrderFixtures.json)],\"total\":1,\"page\":1,\"pageSize\":25}"
        } else if url.path == "/api/containers" {
            status = 200
            json = "{\"items\":[],\"total\":0,\"page\":1,\"pageSize\":100}"
        } else {
            status = 200
            json = PurchaseOrderFixtures.json
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestData() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
