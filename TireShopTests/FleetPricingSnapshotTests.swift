import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Native visual QA uses fixture responses on an invalid host. Every request is
/// intercepted and writes are rejected, so these captures cannot change records.
@MainActor
final class FleetPricingSnapshotTests: XCTestCase {
    func testFleetProductAndCustomerPhoneLayouts() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        let savedServer = UserDefaults.standard.object(forKey: "ts_server_url")
        XCTAssertTrue(URLProtocol.registerClass(FleetSnapshotProtocol.self))
        XCTAssertTrue(Server.setBaseURL("https://fleet-visual-qa.invalid"))
        defer {
            URLProtocol.unregisterClass(FleetSnapshotProtocol.self)
            restore(savedLanguage, for: "ts_lang")
            restore(savedServer, for: "ts_server_url")
        }

        for (language, scheme) in [(AppLanguage.en, ColorScheme.light), (.zh, .dark)] {
            let sku = try fixtureSku()
            let label = "\(language.rawValue)-\(scheme == .dark ? "dark" : "light")"
            try await capture(
                NavigationStack { SkuDetailNativeView(sku: sku) },
                name: "fleet-product-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852)
            )
            try await capture(
                NavigationStack { SkuFormNativeView(editing: sku) },
                name: "fleet-editor-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852)
            )
            try await capture(
                NavigationStack { SkuFormNativeView(editing: nil) },
                name: "sku-create-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852)
            )
            FleetSnapshotProtocol.resetRequests()
            try await capture(
                NavigationStack {
                    CustomerDetailNativeView(id: "visual-fleet-customer", fallbackName: "Fleet customer")
                },
                name: "fleet-customer-profile-\(label)", language: language, scheme: scheme,
                size: CGSize(width: 393, height: 852), expectedRequests: [
                    "/api/customers/visual-fleet-customer", "/api/price-tiers",
                    "/api/customers/visual-fleet-customer/users"
                ]
            )
            XCTAssertTrue(FleetSnapshotProtocol.unexpectedRequests.isEmpty,
                          "Unexpected visual QA requests: \(FleetSnapshotProtocol.unexpectedRequests.joined(separator: ", "))")
        }
    }

    func testFleetEditorAndCustomerTabletAccessibilityLayouts() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        let savedServer = UserDefaults.standard.object(forKey: "ts_server_url")
        XCTAssertTrue(URLProtocol.registerClass(FleetSnapshotProtocol.self))
        XCTAssertTrue(Server.setBaseURL("https://fleet-visual-qa.invalid"))
        defer {
            URLProtocol.unregisterClass(FleetSnapshotProtocol.self)
            restore(savedLanguage, for: "ts_lang")
            restore(savedServer, for: "ts_server_url")
        }
        FleetSnapshotProtocol.resetRequests()
        let sku = try fixtureSku()
        try await capture(
            NavigationStack { SkuFormNativeView(editing: sku) },
            name: "fleet-editor-ipad-accessibility", language: .en, scheme: .light,
            size: CGSize(width: 834, height: 1194), accessibility: true
        )
        try await capture(
            NavigationStack {
                CustomerDetailNativeView(id: "visual-fleet-customer", fallbackName: "Fleet customer")
            },
            name: "fleet-customer-profile-ipad-accessibility", language: .en, scheme: .light,
            size: CGSize(width: 834, height: 1194), accessibility: true, expectedRequests: [
                "/api/customers/visual-fleet-customer", "/api/price-tiers",
                "/api/customers/visual-fleet-customer/users"
            ]
        )
        XCTAssertTrue(FleetSnapshotProtocol.unexpectedRequests.isEmpty,
                      "Unexpected visual QA requests: \(FleetSnapshotProtocol.unexpectedRequests.joined(separator: ", "))")
    }

    private func fixtureSku() throws -> TireSku {
        let sku = try JSONDecoder().decode(TireSku.self, from: Data(FleetSnapshotProtocol.skuJSON.utf8))
        XCTAssertEqual(sku.priceFleet, "260.00")
        return sku
    }

    private func fakeAuth() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FleetSnapshotProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)),
                             storage: FleetSnapshotSessionStorage())
        auth.user = SessionUser(
            id: "fleet-visual-qa", email: "fleet-visual-qa@example.invalid", fullName: "Visual QA",
            roleId: "fleet-manager", roleName: "Fleet Manager", homeWarehouse: "MAIN", isAdmin: false,
            permissions: ["inventory.view", "inventory.manage", "pricing.manage", "customers.view",
                          "customers.manage", "customers.priceLevel.manage", "sales.view",
                          "sales.manage", "sales.price.override"],
            approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        return auth
    }

    private func capture<Content: View>(
        _ content: Content, name: String, language: AppLanguage, scheme: ColorScheme,
        size: CGSize, accessibility: Bool = false, expectedRequests: Set<String> = []
    ) async throws {
        let i18n = I18nStore()
        i18n.setLanguage(language)
        let quote = QuoteStore(pricingPolicyLoader: { FleetPricingPolicy(enabled: true) })
        let root = content
            .environmentObject(fakeAuth())
            .environmentObject(i18n)
            .environmentObject(quote)
            .environmentObject(AppNavigationModel())
            .environmentObject(ScenePresentationContext())
            .environment(\.locale, language.locale)
            .environment(\.colorScheme, scheme)
            .environment(\.horizontalSizeClass, size.width > 500 ? .regular : .compact)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility2 : .large)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
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
            previousKeyWindow?.makeKey()
        }

        for _ in 0..<40 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            if expectedRequests.isSubset(of: FleetSnapshotProtocol.requestedPaths) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(expectedRequests.isSubset(of: FleetSnapshotProtocol.requestedPaths),
                      "Fixture data must load before capturing the profile")
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        try saveSnapshot(controller.view, name: name + "-top")

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
                try saveSnapshot(controller.view, name: name + "-" + label)
            }
        }
    }

    private func scrollableList(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.scrollableList(in: $0) }.first
    }

    private func saveSnapshot(_ view: UIView, name: String) throws {
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
            .appendingPathComponent("FleetPricingVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("FLEET_PRICING_SNAPSHOT \(file.path)")
    }

    private func restore(_ saved: Any?, for key: String) {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

private enum FleetSnapshotError: Error { case unexpectedRequest }

private struct FleetSnapshotSessionStorage: SessionStorage {
    func load() throws -> SavedSession? { nil }
    func save(_ session: SavedSession) throws { throw FleetSnapshotError.unexpectedRequest }
    func clear() throws {}
}

private final class FleetSnapshotProtocol: URLProtocol {
    static let skuJSON = """
    {"id":"visual-fleet-sku","sku":"TBR-11R22.5-STEER","brand":"Long Road","model":"Commercial Steer",
     "size":"11R22.5","category":"TBR","position":"ALL_POSITION","priceRetail":"270.00",
     "priceWholesale":"245.00","priceFleet":"260.00","priceCost":"180.00","reorderPoint":8,
     "active":true,"inventory":[{"id":"visual-stock","location":"MAIN","qtyOnHand":60,
     "qtyReserved":4,"unitCost":"180.00"}]}
    """
    private static let lock = NSLock()
    private static var requests: Set<String> = []
    private static var unexpected: [String] = []

    static var requestedPaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static var unexpectedRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return unexpected
    }

    static func resetRequests() {
        lock.lock()
        defer { lock.unlock() }
        requests = []
        unexpected = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: FleetSnapshotError.unexpectedRequest)
            return
        }
        let path = url.path
        let json: String?
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/api/customers/visual-fleet-customer"):
            json = """
            {"id":"visual-fleet-customer","name":"North Coast Fleet","company":"北岸车队服务",
             "phone":"4045550198","email":"fleet@example.invalid","address":"142 Fleet Road",
             "taxExempt":false,"accountEnabled":true,"creditLimit":"20000.00","priceLevel":"FLEET",
             "createdAt":"2026-10-02T12:00:00Z","documents":[],"sales":[],"tags":["Commercial fleet"]}
            """
        case ("GET", "/api/customers/visual-fleet-customer/account"):
            json = """
            {"customer":{"id":"visual-fleet-customer","name":"North Coast Fleet","accountEnabled":true,
             "creditLimit":20000},"totalBalance":0,"openInvoices":[]}
            """
        case ("GET", "/api/customers/visual-fleet-customer/credit-balance"):
            json = "{\"balance\":0}"
        case ("GET", "/api/customers/visual-fleet-customer/tax-rate"):
            // The existing profile now displays the customer tax card. This
            // fixture has no verified delivery address, so its saved rate uses
            // the shop default rather than making an external address lookup.
            json = """
            {"rate":0.07,"source":"SHOP_DEFAULT","shopDefaultRate":0.07,
             "automatic":{"status":"SHOP_DEFAULT","rate":0.07},"resolution":null,"override":null}
            """
        case ("GET", "/api/customers/visual-fleet-customer/users"), ("GET", "/api/price-tiers"):
            json = "[]"
        default:
            json = nil
        }
        Self.lock.lock()
        Self.requests.insert(path)
        if json == nil { Self.unexpected.append("\(request.httpMethod ?? "GET") \(path)") }
        Self.lock.unlock()
        guard let json, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                      headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: FleetSnapshotError.unexpectedRequest)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
