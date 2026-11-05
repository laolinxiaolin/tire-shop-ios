import SwiftUI
import UIKit
import XCTest
@testable import TireShop

/// These captures host the real collection forms with fixture readers. Collection
/// closures and the fallback URL protocol reject writes throughout visual QA.
@MainActor
final class CollectionAdjustmentSnapshotTests: XCTestCase {
    func testSalesCollapsedAndReducedEnglishPhone() async throws {
        try await withSnapshotEnvironment {
            try await captureSales(name: "sales-collapsed-en-light-phone", adjustment: .init(),
                language: .en, scheme: .light, size: phoneSize)
            try await captureSales(name: "sales-reduce-en-light-phone",
                adjustment: .init(direction: .reduce, amountText: "0.29"),
                language: .en, scheme: .light, size: phoneSize)
        }
    }

    func testSalesIncreasedChineseDarkPhone() async throws {
        try await withSnapshotEnvironment {
            try await captureSales(name: "sales-increase-zh-dark-phone",
                adjustment: .init(direction: .increase, amountText: "0.71"),
                language: .zh, scheme: .dark, size: phoneSize)
        }
    }

    func testSalesLargeBalanceReductionEnglishPhone() async throws {
        try await withSnapshotEnvironment {
            try await captureSales(name: "sales-reduce-large-en-light-phone",
                adjustment: .init(direction: .reduce, amountText: "0.01"),
                language: .en, scheme: .light, size: phoneSize, balance: 9_999_999_999.99)
        }
    }

    func testSalesReductionWithAccessibilityTextOnPhoneAndIPad() async throws {
        try await withSnapshotEnvironment {
            for (name, size) in [("phone", phoneSize), ("ipad", CGSize(width: 834, height: 1194))] {
                try await captureSales(name: "sales-reduce-en-light-accessibility-\(name)",
                    adjustment: .init(direction: .reduce, amountText: "0.29"),
                    language: .en, scheme: .light, size: size, accessibility: true)
            }
        }
    }

    func testReceivablesMixedInvoiceAdjustmentsEnglishPhone() async throws {
        try await withSnapshotEnvironment {
            let loads = CollectionSnapshotLoads()
            let invoices = receivableDetail.openInvoices
            var draft = ReceivableCollectionDraft()
            XCTAssertEqual(draft.split(invoices: invoices.map { (id: $0.id, balance: $0.balance) },
                totalCents: 39_258), 0)
            draft.setAdjustment(.init(direction: .reduce, amountText: "0.29"),
                invoiceId: invoices[0].id, original: invoices[0].balance)
            draft.setAdjustment(.init(direction: .increase, amountText: "0.71"),
                invoiceId: invoices[1].id, original: invoices[1].balance)
            let detail = receivableDetail
            let methods = paymentMethods
            let view = CollectReceivableSheet(
                customer: CustomerSummary(id: "visual-customer", name: "North Coast Fleet", company: "North Coast Fleet Services"),
                initialDraft: draft,
                detailLoader: { id in
                    XCTAssertEqual(id, "visual-customer")
                    await loads.record("detail")
                    return detail
                },
                methodsLoader: {
                    await loads.record("methods")
                    return methods
                },
                pricingPolicyLoader: {
                    await loads.record("policy")
                    return FleetPricingPolicy(enabled: true)
                },
                historyLoader: { throw CollectionSnapshotError.unexpectedRead },
                onPaid: { XCTFail("Visual QA must not complete a collection.") }
            )
            try await capture(view, name: "receivables-mixed-en-light-phone", language: .en,
                scheme: .light, size: phoneSize, loads: loads, expected: ["detail", "methods", "policy"])
        }
    }

    private var phoneSize: CGSize { CGSize(width: 393, height: 852) }

    private var paymentMethods: [PaymentMethod] {
        [PaymentMethod(id: "visual-cash", name: "Cash", feeRate: nil, isActive: true,
            processor: nil, account: .init(code: "1000", name: "Cash on hand")),
         PaymentMethod(id: "visual-check", name: "Check", feeRate: nil, isActive: true,
            processor: nil, account: .init(code: "1010", name: "Undeposited checks")),
         PaymentMethod(id: "visual-card", name: "Manual card", feeRate: "0.03", isActive: true,
            processor: nil, account: .init(code: "1020", name: "Card clearing"))]
    }

    private var receivableDetail: ReceivableCustomerDetail {
        ReceivableCustomerDetail(
            customer: .init(id: "visual-customer", name: "North Coast Fleet", company: "North Coast Fleet Services",
                phone: "4045550198", email: "fleet@example.invalid"),
            totalBalance: 392.58,
            openInvoices: [
                .init(id: "visual-invoice-a", ref: "INV-2026-11264", amountDue: 300, paidTotal: 56.71,
                    balance: 243.29, createdAt: "2026-11-04T14:00:00Z", ageDays: 1,
                    sale: .init(id: "visual-sale-a", ref: "S-2026-18421", status: "INVOICED")),
                .init(id: "visual-invoice-b", ref: "INV-2026-11265", amountDue: 199.29, paidTotal: 50,
                    balance: 149.29, createdAt: "2026-11-04T15:00:00Z", ageDays: 1,
                    sale: .init(id: "visual-sale-b", ref: "S-2026-18422", status: "INVOICED"))
            ])
    }

    private func captureSales(name: String, adjustment: CollectionAdjustmentDraft,
                              language: AppLanguage, scheme: ColorScheme, size: CGSize,
                              accessibility: Bool = false, balance: Double = 243.29) async throws {
        let loads = CollectionSnapshotLoads()
        let methods = paymentMethods
        let store = ManualReceiptStore { _ in
            XCTFail("A visual snapshot must never submit a financial POST.")
            throw CollectionSnapshotError.unexpectedWrite
        }
        let view = PaymentSheetNativeView(invoiceId: "visual-invoice-a", balance: balance,
            customerId: "visual-customer", onPaid: {
                XCTFail("Visual QA must not complete a collection.")
                throw CollectionSnapshotError.unexpectedWrite
            }, initialAdjustment: adjustment,
            methodsLoader: {
                await loads.record("methods")
                return methods
            }, pricingPolicyLoader: {
                await loads.record("policy")
                return FleetPricingPolicy(enabled: true)
            }, creditLoader: { id in
                XCTAssertEqual(id, "visual-customer")
                await loads.record("credit")
                return 0
            }, receiptStore: store)
        try await capture(view, name: name, language: language, scheme: scheme, size: size,
            accessibility: accessibility, loads: loads, expected: ["methods", "policy", "credit"])
        XCTAssertFalse(store.recording)
        XCTAssertFalse(store.completed)
        XCTAssertFalse(store.needsReconciliation)
    }

    private func capture<Content: View>(
        _ content: Content, name: String, language: AppLanguage, scheme: ColorScheme, size: CGSize,
        accessibility: Bool = false, loads: CollectionSnapshotLoads, expected: Set<String>
    ) async throws {
        let i18n = I18nStore()
        i18n.setLanguage(language)
        let root = content
            .environmentObject(fakeAuth())
            .environmentObject(i18n)
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
            if await loads.contains(expected) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let loaded = await loads.contains(expected)
        XCTAssertTrue(loaded, "Fixture readers must finish before the collection form is captured.")
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        try saveSnapshot(controller.view, name: name + "-top")

        if let scroll = scrollableList(in: controller.view) {
            for _ in 0..<20 {
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(100))
                controller.view.layoutIfNeeded()
                scroll.layoutIfNeeded()
                let updatedBottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                if abs(scroll.contentOffset.y - updatedBottom) < 1 { break }
            }
        }
        try saveSnapshot(controller.view, name: name + "-bottom")
        XCTAssertTrue(CollectionSnapshotNoNetworkProtocol.requests.isEmpty,
            "All visual QA reads must be injected; financial writes must never be sent: \(CollectionSnapshotNoNetworkProtocol.requests)")
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
            .appendingPathComponent("CollectionAdjustmentQA", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name + ".png")
        try XCTUnwrap(image.pngData()).write(to: file)
        print("COLLECTION_ADJUSTMENT_SNAPSHOT \(file.path)")
    }

    private func fakeAuth() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollectionSnapshotNoNetworkProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: configuration)),
            storage: CollectionSnapshotSessionStorage())
        auth.user = SessionUser(id: "collection-visual-qa", email: "visual@example.invalid", fullName: "Visual QA",
            roleId: "collector", roleName: "Collector", homeWarehouse: "MAIN", isAdmin: false,
            permissions: ["payments.collect", "sales.price.override", "sales.view", "receivables.view"],
            approvalPermissions: [], mfaMethod: nil)
        auth.ready = true
        return auth
    }

    private func withSnapshotEnvironment(_ capture: () async throws -> Void) async throws {
        let savedLanguage = UserDefaults.standard.object(forKey: "ts_lang")
        let savedServer = UserDefaults.standard.object(forKey: "ts_server_url")
        CollectionSnapshotNoNetworkProtocol.reset()
        XCTAssertTrue(URLProtocol.registerClass(CollectionSnapshotNoNetworkProtocol.self))
        XCTAssertTrue(Server.setBaseURL("https://collection-adjustment-qa.invalid"))
        defer {
            URLProtocol.unregisterClass(CollectionSnapshotNoNetworkProtocol.self)
            restore(savedLanguage, key: "ts_lang")
            restore(savedServer, key: "ts_server_url")
        }
        try await capture()
        XCTAssertTrue(CollectionSnapshotNoNetworkProtocol.requests.isEmpty)
    }

    private func restore(_ value: Any?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

private actor CollectionSnapshotLoads {
    private var loaded = Set<String>()
    func record(_ name: String) { loaded.insert(name) }
    func contains(_ expected: Set<String>) -> Bool { expected.isSubset(of: loaded) }
}

private enum CollectionSnapshotError: Error { case unexpectedRead, unexpectedWrite }

private struct CollectionSnapshotSessionStorage: SessionStorage {
    func load() throws -> SavedSession? { nil }
    func save(_ session: SavedSession) throws { throw CollectionSnapshotError.unexpectedWrite }
    func clear() throws {}
}

private final class CollectionSnapshotNoNetworkProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recordedRequests: [String] = []

    static var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "collection-adjustment-qa.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: CollectionSnapshotError.unexpectedRead)
    }

    override func stopLoading() {}
}
