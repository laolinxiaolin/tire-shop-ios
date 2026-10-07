import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Capture production screens using an invalid host and read-only fixture routes.
@MainActor
final class PurchaseOrderSnapshotTests: XCTestCase {
    func testRegisterAndDetailPhoneLayoutsAndTabletAccessibility() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        let savedServer = UserDefaults.standard.object(forKey: "ts_server_url")
        XCTAssertTrue(URLProtocol.registerClass(PurchaseOrderSnapshotProtocol.self))
        XCTAssertTrue(Server.setBaseURL("https://purchase-order-visual-qa.invalid"))
        defer {
            URLProtocol.unregisterClass(PurchaseOrderSnapshotProtocol.self)
            restore(savedLanguage, for: "ts_lang")
            restore(savedServer, for: "ts_server_url")
        }
        let fixture = try JSONDecoder().decode(PurchaseOrder.self, from: Data(PurchaseOrderSnapshotProtocol.orderJSON.utf8))
        XCTAssertEqual(fixture.containers.count, 2)
        XCTAssertEqual(fixture.summary.paidDiscrepancyCount, 1)

        for (language, scheme) in [(AppLanguage.en, ColorScheme.light), (.zh, .dark)] {
            let label = "\(language.rawValue)-\(scheme == .dark ? "dark" : "light")"
            try await capture(
                NavigationStack {
                    PurchaseOrdersListNativeView()
                        .navigationTitle(language == .en ? "Purchase orders" : "采购订单")
                },
                name: "purchase-order-register-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852), expectedPath: "/api/purchase-orders"
            )
            try await capture(
                NavigationStack { PurchaseOrderDetailNativeView(id: "visual-order") },
                name: "purchase-order-detail-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852), expectedPath: "/api/purchase-orders/visual-order"
            )
        }
        try await capture(
            NavigationStack { PurchaseOrderDetailNativeView(id: "visual-order") },
            name: "purchase-order-detail-ipad-accessibility", language: .en, scheme: .light,
            size: CGSize(width: 834, height: 1194), accessibility: true,
            expectedPath: "/api/purchase-orders/visual-order"
        )
        XCTAssertTrue(PurchaseOrderSnapshotProtocol.unexpectedRequests.isEmpty,
                      "Screens must render fixture reads without mutating records")
    }

    private func capture<Content: View>(
        _ content: Content, name: String, language: AppLanguage, scheme: ColorScheme,
        size: CGSize, accessibility: Bool = false, expectedPath: String
    ) async throws {
        PurchaseOrderSnapshotProtocol.resetPaths()
        let i18n = I18nStore()
        i18n.setLanguage(language)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PurchaseOrderSnapshotProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)),
                             storage: PurchaseOrderSnapshotStorage())
        auth.user = SessionUser(
            id: "purchase-order-visual-qa", email: "qa@example.invalid", fullName: "Purchasing QA",
            roleId: "qa", roleName: "Purchasing Manager", homeWarehouse: "MAIN", isAdmin: false,
            permissions: ["purchasing.view", "purchasing.manage", "purchasing.receive", "payables.view"],
            approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        let root = content
            .environmentObject(auth)
            .environmentObject(i18n)
            .environmentObject(AppNavigationModel())
            .environmentObject(ScenePresentationContext())
            .environment(\.locale, language.locale)
            .environment(\.colorScheme, scheme)
            .environment(\.horizontalSizeClass, size.width > 500 ? .regular : .compact)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility2 : .large)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        let controller = UIHostingController(rootView: root)
        controller.safeAreaRegions = []
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        controller.view.frame = CGRect(origin: .zero, size: size)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        for _ in 0..<40 {
            controller.view.layoutIfNeeded()
            if PurchaseOrderSnapshotProtocol.requestedPaths.contains(expectedPath) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(PurchaseOrderSnapshotProtocol.requestedPaths.contains(expectedPath), "Fixture must load before capture")
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        try save(controller.view, name: name + "-top")
        if let scroll = scrollableList(in: controller.view) {
            for (fraction, label) in [(0.5, "middle"), (1.0, "bottom")] {
                for _ in 0..<(fraction == 1 ? 20 : 3) {
                    let top = -scroll.adjustedContentInset.top
                    let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: top + (bottom - top) * fraction), animated: false)
                    try await Task.sleep(for: .milliseconds(100))
                    controller.view.layoutIfNeeded()
                    scroll.layoutIfNeeded()
                    let updatedBottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    if fraction == 1, abs(scroll.contentOffset.y - updatedBottom) < 1 { break }
                }
                try save(controller.view, name: name + "-" + label)
            }
        }
    }

    private func scrollableList(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled, scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.scrollableList(in: $0) }.first
    }

    private func save(_ view: UIView, name: String) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(image.size.width, 300)
        XCTAssertGreaterThan(image.size.height, 700)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("PurchaseOrderVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("PURCHASE_ORDER_SNAPSHOT \(file.path)")
    }

    private func restore(_ saved: Any?, for key: String) {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

private enum PurchaseOrderSnapshotError: Error { case unexpectedRequest }

private struct PurchaseOrderSnapshotStorage: SessionStorage {
    func load() throws -> SavedSession? { nil }
    func save(_ session: SavedSession) throws { throw PurchaseOrderSnapshotError.unexpectedRequest }
    func clear() throws {}
}

private final class PurchaseOrderSnapshotProtocol: URLProtocol {
    static let orderJSON = """
    {"id":"visual-order","ref":"po-261006018","supplierId":"visual-supplier",
     "supplier":{"id":"visual-supplier","name":"Long Road Tire Manufacturing · 长路轮胎","currency":"USD"},
     "supplierReference":"LR-2026-1042 / Autumn replacement order","plannedContainerCount":2,
     "agreedGoodsAmount":"48000.00","paymentTerms":"30% deposit. Balance due after each container arrives.",
     "notes":"Two independent shipments for the Atlanta and Dallas warehouses.","orderedAt":"2026-09-12T14:00:00Z",
     "version":7,"createdAt":"2026-09-10T14:00:00Z","updatedAt":"2026-10-06T14:00:00Z",
     "summary":{"status":"PARTIALLY_RECEIVED","plannedCount":2,"containerCount":2,"activeCount":2,
      "cancelledCount":0,"receivedCount":1,"unassignedCount":0,"totalQty":1000,"receivedQty":480,
      "manifestedGoodsAmount":45000,"goodsAmount":48000,"goodsAmountSource":"AGREEMENT","manifestComplete":true,
      "supplierPaid":16000,"legacySupplierPaid":500,"activeSupplierPaid":16000,"cancelledSupplierPaid":0,
      "goodsRemaining":32000,"openPayable":30000,"dueNow":5000,"futureDue":24000,"undatedPayable":1000,
      "excludedOpenPayable":500,"paidDiscrepancyCount":1,"nextEtaAt":"2026-10-01T14:00:00Z",
      "missingEtaCount":0,"lateCount":1},
     "containers":[
      {"id":"visual-received","ref":"cg-260912021","reference":"ATL-SHIPMENT-01","status":"RECEIVED",
       "bolNumber":"BOL-LR-1042-A","etaAt":"2026-09-28T14:00:00Z","arrivedAt":"2026-09-28T14:00:00Z",
       "receivedAt":"2026-09-29T14:00:00Z","orderedAt":"2026-09-12T14:00:00Z","isDDP":false,
       "location":"ATLANTA","totalQty":480,"goodsAmount":23040,"canRemove":false},
      {"id":"visual-in-transit","ref":"cg-260912022","reference":"DAL-SHIPMENT-02","status":"IN_TRANSIT",
       "bolNumber":"BOL-LR-1042-B","etaAt":"2026-10-01T14:00:00Z","orderedAt":"2026-09-12T14:00:00Z",
       "isDDP":true,"location":"DALLAS","totalQty":520,"goodsAmount":21960,"canRemove":false}],
     "attachments":[{"id":"visual-contract","purchaseOrderId":"visual-order","kind":"OTHER",
       "filename":"Supplier agreement · 供应商合同.pdf","mimeType":"application/pdf","sizeBytes":236544,
       "note":"Signed agreement for both shipments","createdAt":"2026-09-12T14:00:00Z"}],
     "auditHistory":[{"id":"visual-audit","action":"purchaseOrder.issue","entity":"PurchaseOrder",
       "entityId":"visual-order","data":{"containerIds":["visual-received","visual-in-transit"]},
       "createdAt":"2026-09-12T14:00:00Z","user":{"id":"qa","fullName":"Purchasing manager"}}]}
    """
    private static let lock = NSLock()
    private static var paths: Set<String> = []
    private static var unexpected: [String] = []
    static var requestedPaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
    static var unexpectedRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return unexpected
    }
    static func resetPaths() {
        lock.lock()
        defer { lock.unlock() }
        paths = []
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "purchase-order-visual-qa.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let json: String?
        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/api/purchase-orders"):
            json = "{\"items\":[\(Self.orderJSON)],\"total\":1,\"page\":1,\"pageSize\":25}"
        case ("GET", "/api/purchase-orders/visual-order"):
            json = Self.orderJSON
        default:
            json = nil
        }
        Self.lock.lock()
        Self.paths.insert(url.path)
        if json == nil { Self.unexpected.append("\(request.httpMethod ?? "GET") \(url.path)") }
        Self.lock.unlock()
        guard let json, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                      headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: PurchaseOrderSnapshotError.unexpectedRequest)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
