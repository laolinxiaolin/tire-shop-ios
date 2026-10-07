import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// Native visual QA uses in-memory analytics responses and a session that rejects
/// every network request. Capturing a report never logs in or downloads an export.
@MainActor
final class CustomerAnalyticsSnapshotTests: XCTestCase {
    func testCustomerAnalyticsPhoneLayouts() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer { restoreLanguage(savedLanguage) }

        for (language, scheme) in [(AppLanguage.en, ColorScheme.light), (.zh, .dark)] {
            let fixture = try AnalyticsScreenFixtures()
            let i18n = I18nStore()
            i18n.setLanguage(language)
            let auth = fakeAuth()
            let label = "\(language.rawValue)-\(scheme == .dark ? "dark" : "light")"

            let rankingLoads = AnalyticsSnapshotLoads()
            let rankings = NavigationStack {
                CustomerAnalyticsNativeView(initialQuery: .init(filters: fixture.filters), loader: { _ in
                    await rankingLoads.record("rankings")
                    return fixture.rankings
                })
            }
            .environmentObject(auth)
            .environmentObject(i18n)
            .environment(\.locale, language.locale)
            .environment(\.colorScheme, scheme)
            try await capture(rankings, name: "analytics-rankings-\(label)", scheme: scheme,
                              size: CGSize(width: 393, height: 852), loads: rankingLoads, expected: ["rankings"])

            let detailLoads = AnalyticsSnapshotLoads()
            let detail = detailView(fixture: fixture, loads: detailLoads)
                .environmentObject(auth)
                .environmentObject(i18n)
                .environment(\.locale, language.locale)
                .environment(\.colorScheme, scheme)
            try await capture(detail, name: "analytics-detail-\(label)", scheme: scheme,
                              size: CGSize(width: 393, height: 852), loads: detailLoads,
                              expected: ["summary", "products", "history"])
        }
    }

    func testCustomerAnalyticsTabletWithAccessibilityText() async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        defer { restoreLanguage(savedLanguage) }
        let fixture = try AnalyticsScreenFixtures()
        let i18n = I18nStore()
        i18n.setLanguage(.en)
        let loads = AnalyticsSnapshotLoads()
        let detail = detailView(fixture: fixture, loads: loads)
            .environmentObject(fakeAuth())
            .environmentObject(i18n)
            .environment(\.locale, AppLanguage.en.locale)
            .environment(\.colorScheme, .light)
            .environment(\.horizontalSizeClass, .regular)
            .environment(\.dynamicTypeSize, .accessibility2)
        try await capture(detail, name: "analytics-detail-ipad-accessibility", scheme: .light,
                          size: CGSize(width: 834, height: 1194), loads: loads,
                          expected: ["summary", "products", "history"])
    }

    private func detailView(fixture: AnalyticsScreenFixtures, loads: AnalyticsSnapshotLoads) -> some View {
        NavigationStack {
            CustomerAnalyticsDetailNativeView(
                customerId: "visual-customer-1", initialQuery: .init(filters: fixture.filters),
                summaryLoader: { _, _ in
                    await loads.record("summary")
                    return fixture.summary
                },
                productsLoader: { _, _, _, _ in
                    await loads.record("products")
                    return fixture.products
                },
                historyLoader: { _, _, _, _ in
                    await loads.record("history")
                    return fixture.history
                }
            )
        }
    }

    private func fakeAuth() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalyticsSnapshotNoNetworkProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)),
                             storage: AnalyticsSnapshotSessionStorage())
        auth.user = SessionUser(
            id: "analytics-visual-qa", email: "analytics-visual-qa@example.invalid", fullName: "Visual QA",
            roleId: "analyst", roleName: "Analyst", homeWarehouse: nil, isAdmin: false,
            permissions: ["customers.analytics.view", "customers.profit.view", "sales.view"],
            approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        return auth
    }

    private func capture<Content: View>(
        _ content: Content, name: String, scheme: ColorScheme, size: CGSize,
        loads: AnalyticsSnapshotLoads, expected: Set<String>
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        let controller = UIHostingController(rootView: content)
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

        for _ in 0..<20 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            if await loads.contains(expected) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let loaded = await loads.contains(expected)
        XCTAssertTrue(loaded, "All visible report sections must be fixture-loaded before capture")
        try await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()
        try saveSnapshot(controller.view, name: name + "-top")

        let scroll = try XCTUnwrap(scrollableList(in: controller.view), "The populated analytics report should scroll")
        for (fraction, label) in [(0.5, "middle"), (1.0, "bottom")] {
            // Native List adjusts estimated heights as off-screen rows materialize.
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
            .appendingPathComponent("CustomerAnalyticsVisualQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("CUSTOMER_ANALYTICS_SNAPSHOT \(file.path)")
    }

    private func restoreLanguage(_ saved: Any?) {
        if let saved { UserDefaults.standard.set(saved, forKey: "ts_lang") }
        else { UserDefaults.standard.removeObject(forKey: "ts_lang") }
    }
}

private struct AnalyticsScreenFixtures {
    let filters = CustomerAnalyticsFilters(period: .custom, start: "2026-09-01", end: "2026-09-30", priceLevel: .wholesale)
    let rankings: CustomerAnalyticsRankings
    let summary: CustomerAnalyticsSummary
    let products: CustomerAnalyticsPage<CustomerAnalyticsProduct>
    let history: CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent>

    init() throws {
        let period: [String: Any] = ["preset": "CUSTOM", "start": "2026-09-01", "end": "2026-09-30", "timezone": "America/New_York"]
        let coverage = ["status": "PARTIAL"]
        let customerName = "North Coast Interstate Commercial Truck and Fleet Services"
        let company = "北岸跨州商用车队与轮胎服务 · Regional Maintenance Division"
        let customer: [String: Any] = [
            "id": "visual-customer-1", "name": customerName,
            "company": company, "currentPriceLevel": "FLEET"
        ]
        var first = Self.metrics(sales: 40_012.45, verified: false)
        first.merge(["customerId": "visual-customer-1", "customerName": customerName,
                     "company": company, "currentPriceLevel": "FLEET"]) { _, new in new }
        var second = Self.metrics(sales: -245.25, verified: true)
        second.merge(["customerId": "visual-customer-2", "customerName": "Golden State Independent Owner-Operator Tire Cooperative",
                      "company": NSNull(), "currentPriceLevel": NSNull()]) { _, new in new }
        rankings = try Self.decode([
            "items": [first, second], "total": 2, "page": 1, "pageSize": 25,
            "period": period, "historyCoverage": coverage, "totals": Self.metrics(sales: 39_767.2, verified: false),
            "canViewProfit": true
        ])
        summary = try Self.decode([
            "customer": customer, "period": period, "historyCoverage": coverage,
            "summary": Self.metrics(sales: 40_012.45, verified: false),
            "lifetime": Self.metrics(sales: 195_480.85, verified: false), "canViewProfit": true
        ])
        products = try Self.decode([
            "items": [
                ["skuId": "visual-sku-1", "sku": "COMMERCIAL-LONG-HAUL-29575R225-16PLY",
                 "brand": "Long Road Commercial Tires", "model": "Regional All-Position Heavy-Duty Steer",
                 "size": "295/75R22.5", "quantity": 40, "netRevenue": 12_345.6, "averageUnitPrice": 308.64],
                ["skuId": "visual-sku-2", "sku": NSNull(), "brand": NSNull(), "model": NSNull(),
                 "size": NSNull(), "quantity": -2, "netRevenue": -245.25, "averageUnitPrice": NSNull()]
            ],
            "total": 2, "page": 1, "pageSize": 10, "period": period, "historyCoverage": coverage
        ])
        let kinds = ["SALE", "RETURN", "SALE_REVERSAL", "RETURN_REVERSAL"]
        let events: [[String: Any]] = kinds.enumerated().map { index, kind in
            let sales = [12_345.6, -245.25, -680.50, 245.25][index]
            return [
                "eventId": "visual-event-\(index)", "saleId": "visual-sale-\(index)", "invoiceId": NSNull(),
                "ref": "INV-2026-REGIONAL-FLEET-00\(840 + index)", "kind": kind,
                "sourceAvailable": index == 0, "date": "2026-09-\(28 - index)T02:00:00.000Z",
                "priceLevel": index == 0 ? "WHOLESALE" : NSNull(), "fulfillment": index == 0 ? "FREIGHT" : "PICKUP",
                "sales": sales, "tireRevenue": sales, "serviceRevenue": 0, "deliveryRevenue": 0,
                "restockingFees": 0, "tiresSold": index == 0 ? 40 : (sales < 0 ? -2 : 2), "bookedCogs": sales * 0.7
            ]
        }
        history = try Self.decode([
            "items": events, "total": 4, "page": 1, "pageSize": 25,
            "period": period, "historyCoverage": coverage
        ])
    }

    private static func metrics(sales: Double, verified: Bool) -> [String: Any] {
        let costs = (sales * 0.7 * 100).rounded() / 100
        return [
            "sales": sales, "tireRevenue": sales - (sales > 0 ? 380.5 : 0),
            "serviceRevenue": sales > 0 ? 280.5 : 0, "deliveryRevenue": sales > 0 ? 100 : 0,
            "restockingFees": 0, "tiresSold": sales > 0 ? 128 : -2, "orders": sales > 0 ? 16 : 0,
            "averageOrder": sales > 0 ? (sales / 16 * 100).rounded() / 100 : NSNull(),
            "lastOrder": sales > 0 ? "2026-09-28T02:00:00.000Z" : NSNull(), "bookedCogs": costs,
            "actualCogs": verified ? costs : NSNull(), "grossProfit": sales - costs,
            "gpPercent": sales > 0 ? 30 : NSNull(),
            "costCoverage": verified ? 1 : 0.875, "unverifiedCostUnits": verified ? 0 : 16
        ]
    }

    private static func decode<T: Decodable>(_ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private actor AnalyticsSnapshotLoads {
    private var sections: Set<String> = []
    func record(_ section: String) { sections.insert(section) }
    func contains(_ expected: Set<String>) -> Bool { sections.isSuperset(of: expected) }
}

private enum AnalyticsSnapshotError: Error { case unexpectedRequest }

private final class AnalyticsSnapshotNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: AnalyticsSnapshotError.unexpectedRequest)
    }
    override func stopLoading() {}
}

private struct AnalyticsSnapshotSessionStorage: SessionStorage {
    func load() throws -> SavedSession? { nil }
    func save(_ session: SavedSession) throws { throw AnalyticsSnapshotError.unexpectedRequest }
    func clear() throws {}
}
