import SwiftUI
import UIKit
import XCTest
@testable import TireShop

@MainActor
final class ContractReceivingTests: XCTestCase {
    func testSelectsOnlyEffectiveNativeShipmentsForThisContainerAndContractOwner() async throws {
        var events = [ContractReceivingFixtures.shipment(id: "eligible")]
        for (id, changes) in [
            ("reversed", ["reversedAt": "2026-11-03T12:00:00Z"]),
            ("archived", ["legacyMappingArchivedAt": "2026-11-03T12:00:00Z"]),
            ("foreign-batch", ["containerLineId": "another-batch"]),
            ("foreign-source", ["sourceDocument": ["type": "CONTAINER", "id": "other"]]),
            ("unknown", ["remainingProtectableQty": NSNull()]),
            ("empty", ["remainingProtectableQty": 0]),
            ("fractional", ["remainingProtectableQty": 1.5]),
            ("unknown-date", ["businessDate": NSNull()]),
            ("reversed-by-event", [:])
        ] as [(String, [String: Any])] {
            events.append(ContractReceivingFixtures.shipment(id: id).merging(changes) { _, new in new })
        }
        events.append(["id": "reversal", "kind": "REVERSE", "qty": 6, "originalEventId": "reversed-by-event"])
        let ledger = try ContractReceivingFixtures.ledger(events: events, extraLines: [
            ContractReceivingFixtures.line(owner: "other-order", events: [ContractReceivingFixtures.shipment(id: "wrong-owner")]),
            ContractReceivingFixtures.line(id: "wrong-contract-line", events: [ContractReceivingFixtures.shipment(id: "wrong-binding")])
        ])
        let store = try makeStore(ledger: ledger)
        await store.load()
        XCTAssertEqual(store.shipments.map(\.id), ["eligible"])
        XCTAssertEqual(store.shipments.first?.remainingQty, 4)
        XCTAssertEqual(store.shipments.first?.currentBusinessDate, "2026-11-04")
    }

    func testRejectsInvalidQuantitiesAndCalendarDatesBeforeAnyWrite() async throws {
        var requests: [ContractReceiptRequest] = []
        let store = try makeStore { request in
            requests.append(request)
            return try ContractReceivingFixtures.receipt(request)
        }
        await store.load()
        let shipment = try XCTUnwrap(store.shipments.first)
        for quantity in ["", "0", "-1", "1.5", "5", "2147483648", "1e1", "NaN"] {
            await store.submit(shipment: shipment, quantity: quantity, businessDate: "2026-11-04", disposition: .saleable)
            XCTAssertEqual(store.errorMessage, "purchasing.receipt.invalidQuantity", quantity)
        }
        for (date, key) in [
            ("2026-02-30", "invalidDate"), ("2026-2-3", "invalidDate"),
            ("2026-11-01", "beforeShipment"), ("2026-11-05", "futureDate")
        ] {
            await store.submit(shipment: shipment, quantity: "2", businessDate: date, disposition: .saleable)
            XCTAssertEqual(store.errorMessage, "purchasing.receipt.\(key)")
        }
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(store.pendingRequest)
        await store.submit(shipment: shipment, quantity: " 2 ", businessDate: "2026-11-04", disposition: .qc)
        XCTAssertEqual(requests.first?.qty, 2)
        XCTAssertEqual(requests.first?.disposition, .qc)
        XCTAssertTrue(store.saved)
    }

    func testUncertainRetryPreservesExactPayloadAcrossRefreshAndBlocksChangedSubmission() async throws {
        var requests: [ContractReceiptRequest] = []
        var ledger = try ContractReceivingFixtures.ledger()
        let api = ContractReceivingAPI(loadLedger: { _ in ledger }, recordReceipt: { _, _, body in
            requests.append(body)
            if requests.count == 1 { throw APIError(status: 503, message: "Unavailable") }
            return try ContractReceivingFixtures.receipt(body)
        })
        let store = ContractReceivingStore(container: try ContractReceivingFixtures.container(), api: api)
        await store.load()
        let shipment = try XCTUnwrap(store.shipments.first)
        await store.submit(shipment: shipment, quantity: "2", businessDate: "2026-11-03", disposition: .damaged)
        let frozen = try XCTUnwrap(store.pendingRequest)
        await store.submit(shipment: shipment, quantity: "1", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertEqual(requests.count, 1)
        ledger = try ContractReceivingFixtures.ledger(version: 8)
        await store.load()
        XCTAssertEqual(store.pendingRequest, frozen)
        await store.retry()
        XCTAssertEqual(requests, [frozen.body, frozen.body])
        XCTAssertEqual(requests.last?.expectedVersion, 7)
        XCTAssertTrue(store.saved)
        XCTAssertNil(store.pendingRequest)
        await store.retry()
        await store.submit(shipment: shipment, quantity: "1", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertEqual(requests.count, 2)
    }

    func testStaleVersionRequiresRefreshBeforeCreatingANewRequest() async throws {
        var requests: [ContractReceiptRequest] = []
        var ledger = try ContractReceivingFixtures.ledger()
        let store = ContractReceivingStore(container: try ContractReceivingFixtures.container(), api: ContractReceivingAPI(
            loadLedger: { _ in ledger }, recordReceipt: { _, _, body in
                requests.append(body)
                if requests.count == 1 { throw APIError(status: 409, message: "Contract changed") }
                return try ContractReceivingFixtures.receipt(body)
            }
        ))
        await store.load()
        let shipment = try XCTUnwrap(store.shipments.first)
        await store.submit(shipment: shipment, quantity: "2", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertNil(store.pendingRequest)
        XCTAssertTrue(store.requiresRefresh)
        await store.retry()
        await store.submit(shipment: shipment, quantity: "2", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertEqual(requests.count, 1)
        ledger = try ContractReceivingFixtures.ledger(version: 9)
        await store.load()
        await store.submit(shipment: try XCTUnwrap(store.shipments.first), quantity: "2", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertEqual(requests.last?.expectedVersion, 9)
        XCTAssertNotEqual(requests.first?.sourceEventId, requests.last?.sourceEventId)
        XCTAssertTrue(store.saved)
    }

    func testLedgerReconcilesAnUncertainSavedReceiptWithoutPostingAgain() async throws {
        var body: ContractReceiptRequest?
        var postCount = 0
        let store = ContractReceivingStore(container: try ContractReceivingFixtures.container(), api: ContractReceivingAPI(
            loadLedger: { _ in
                var events = [ContractReceivingFixtures.shipment()]
                if let body { events.append(ContractReceivingFixtures.receiptObject(body)) }
                return try ContractReceivingFixtures.ledger(version: body == nil ? 7 : 8, events: events)
            }, recordReceipt: { _, _, request in
                body = request
                postCount += 1
                throw URLError(.networkConnectionLost)
            }
        ))
        await store.load()
        await store.submit(shipment: try XCTUnwrap(store.shipments.first), quantity: "1", businessDate: "2026-11-04", disposition: .saleable)
        XCTAssertNotNil(store.pendingRequest)
        await store.load()
        XCTAssertTrue(store.saved)
        XCTAssertNil(store.pendingRequest)
        await store.retry()
        XCTAssertEqual(postCount, 1)
    }

    func testNativeReceiptAPIUsesLedgerAndReceiptEndpoints() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContractReceivingWireProtocol.self]
        let api = ContractReceivingAPI(client: APIClient(session: URLSession(configuration: config)))
        let ledger = try await api.loadLedger("po")
        XCTAssertEqual(ledger.version, 7)
        let body = ContractReceiptRequest(expectedVersion: 7, qty: 2, sourceEventId: UUID().uuidString,
            shipmentId: "ship", containerLineId: "native", businessDate: "2026-11-04", disposition: .qc)
        let response = try await api.recordReceipt("po", "cl", body)
        XCTAssertTrue(response.matches(body))
        let recorded = try XCTUnwrap(ContractReceivingWireProtocol.lastReceipt())
        XCTAssertEqual(recorded.0.url?.path, "/api/purchase-orders/po/contract-lines/cl/receipts")
        XCTAssertEqual(recorded.0.httpMethod, "POST")
        XCTAssertEqual(recorded.1["kind"] as? String, "RECEIVE")
        XCTAssertEqual(recorded.1["qty"] as? Int, 2)
        XCTAssertEqual(recorded.1["expectedVersion"] as? Int, 7)
        XCTAssertEqual(recorded.1["sourceEventId"] as? String, body.sourceEventId)
        XCTAssertEqual(recorded.1["disposition"] as? String, "QC")
        XCTAssertNil(recorded.1["warehouseId"])
    }

    func testReceivingSheetPhoneAndChineseAccessibilitySnapshots() async throws {
        let originalLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer {
            if let originalLanguage { UserDefaults.standard.set(originalLanguage, forKey: "ts_lang") }
            else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
        }
        for language in [AppLanguage.en, .zh] {
            let container = try ContractReceivingFixtures.container()
            let store = try makeStore()
            let i18n = I18nStore()
            i18n.setLanguage(language)
            XCTAssertNotEqual(i18n.t("purchasing.receipt.quantity"), "purchasing.receipt.quantity")
            let root = ContractReceivingSheet(container: container, store: store, onSaved: { XCTFail("Read-only snapshot must not submit") })
                .environmentObject(i18n)
                .environment(\.locale, language.locale)
                .environment(\.dynamicTypeSize, language == .zh ? .accessibility2 : .large)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            for _ in 0..<30 {
                if !store.loading && !store.shipments.isEmpty { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            XCTAssertEqual(store.shipments.count, 1)
            let name = "contract-receiving-\(language.rawValue)-\(language == .zh ? "accessibility" : "phone")"
            let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
                .appendingPathComponent("ContractReceivingQA", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func capture(_ position: String) throws {
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = name + "-" + position
                attachment.lifetime = .keepAlways
                add(attachment)
                let file = directory.appendingPathComponent(name + "-" + position + ".png")
                try XCTUnwrap(image.pngData()).write(to: file)
                print("CONTRACT_RECEIVING_SNAPSHOT \(file.path)")
            }
            try capture("top")
            if let scroll = scrollableList(in: host.view) {
                for _ in 0..<20 {
                    let top = -scroll.adjustedContentInset.top
                    let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    try await Task.sleep(for: .milliseconds(100))
                    host.view.layoutIfNeeded()
                    scroll.layoutIfNeeded()
                    let updatedBottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    if abs(scroll.contentOffset.y - updatedBottom) < 1 { break }
                }
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                XCTAssertLessThanOrEqual(abs(scroll.contentOffset.y - bottom), 1, "Receipt fields at the bottom must remain reachable")
            }
            try capture("bottom")
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
    }

    private func scrollableList(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.scrollableList(in: $0) }.first
    }

    private func makeStore(
        ledger: ContractReceiptLedger? = nil,
        record: @escaping (ContractReceiptRequest) async throws -> ContractReceiptEvent = { try ContractReceivingFixtures.receipt($0) }
    ) throws -> ContractReceivingStore {
        let ledger = try ledger ?? ContractReceivingFixtures.ledger()
        return ContractReceivingStore(container: try ContractReceivingFixtures.container(), api: ContractReceivingAPI(
            loadLedger: { _ in ledger }, recordReceipt: { _, _, request in try await record(request) }
        ))
    }
}

private enum ContractReceivingFixtures {
    static func container() throws -> Container {
        try JSONDecoder().decode(Container.self, from: Data("""
        {"id":"container","ref":"cg-1","supplier":{"id":"supplier","name":"Factory"},
         "purchaseOrderId":"po","status":"ARRIVED","isDDP":false,"location":"MAIN","costSpread":"BY_QTY",
         "createdAt":"2026-11-02T12:00:00Z","costs":[],"lines":[{"id":"native","skuId":"sku","qty":6,
         "contractLineId":"cl","unitCost":"100.00","fetPerUnit":"0.00",
         "sku":{"id":"sku","sku":"LONG-MODEL-11R22.5-16PR","brand":"Brand","model":"Model",
         "size":"11R22.5","category":"TBR","position":"DRIVE"}}]}
        """.utf8))
    }

    static func shipment(id: String = "ship") -> [String: Any] {
        ["id": id, "kind": "SHIP", "qty": 6, "containerLineId": "native", "remainingProtectableQty": 4,
         "businessDate": "2026-11-02", "currentBusinessDate": "2026-11-04",
         "sourceDocument": ["type": "CONTAINER", "id": "container"]]
    }

    static func line(id: String = "cl", owner: String = "po", events: [[String: Any]]) -> [String: Any] {
        ["id": id, "purchaseOrderId": owner, "skuLabel": "LONG-MODEL-11R22.5-16PR",
         "currentBusinessDate": "2026-11-04", "events": events]
    }

    static func ledger(version: Int = 7, events: [[String: Any]]? = nil, extraLines: [[String: Any]] = []) throws -> ContractReceiptLedger {
        try decode(["version": version, "lines": [line(events: events ?? [shipment()])] + extraLines])
    }

    static func receiptObject(_ request: ContractReceiptRequest) -> [String: Any] {
        ["id": "receipt", "kind": "RECEIVE", "qty": request.qty, "sourceEventId": request.sourceEventId,
         "shipmentId": request.shipmentId, "containerLineId": request.containerLineId,
         "businessDate": request.businessDate, "disposition": request.disposition.rawValue]
    }

    static func receipt(_ request: ContractReceiptRequest) throws -> ContractReceiptEvent {
        try decode(receiptObject(request))
    }

    static func decode<T: Decodable>(_ value: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

private final class ContractReceivingWireProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var receipt: (URLRequest, [String: Any])?

    static func lastReceipt() -> (URLRequest, [String: Any])? {
        lock.lock()
        defer { lock.unlock() }
        return receipt
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let data: Data
            if request.url?.path == "/api/purchase-orders/po/quantity-ledger" {
                data = try JSONSerialization.data(withJSONObject: ["version": 7,
                    "lines": [ContractReceivingFixtures.line(events: [ContractReceivingFixtures.shipment()])]])
            } else if request.url?.path == "/api/purchase-orders/po/contract-lines/cl/receipts", request.httpMethod == "POST" {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData()) as? [String: Any])
                Self.lock.lock()
                Self.receipt = (request, json)
                Self.lock.unlock()
                data = try JSONSerialization.data(withJSONObject: json.merging(["id": "receipt"]) { _, new in new })
            } else {
                throw URLError(.unsupportedURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func requestData() -> Data {
        if let body = request.httpBody { return body }
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
