import SwiftUI
import UIKit
import XCTest
@testable import TireShop

@MainActor
final class SaleDetailSnapshotTests: XCTestCase {
    func testSalespersonControlsAndHistoricalLinesOnPhoneAndTablet() async throws {
        let sale = try JSONDecoder().decode(Sale.self, from: Data(Self.saleJSON.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SaleDetailSnapshotNoNetworkProtocol.self]
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: config)), storage: SnapshotSessionStorage())
        auth.user = SessionUser(id: "visual-qa", email: "visual@example.invalid", fullName: "Visual QA",
            roleId: "staff", roleName: "Staff", homeWarehouse: "MAIN", isAdmin: false,
            permissions: ["sales.view", "sales.salesperson.assign", "employees.view"],
            approvalPermissions: [], mfaMethod: nil)
        auth.ready = true
        for (name, size) in [("phone", CGSize(width: 393, height: 852)), ("tablet", CGSize(width: 1024, height: 1366))] {
            var loadedSalespeople = false
            let view = NavigationStack {
                SaleDetailNativeView(id: sale.id, saleLoader: { _ in sale }, skuDetailsLoader: { _ in [:] },
                    salespersonLoader: {
                        loadedSalespeople = true
                        return [CustomerSalesperson(id: "employee-1", fullName: "Alex Rivera", status: "ACTIVE"),
                                CustomerSalesperson(id: "employee-2", fullName: "Jamie Chen", status: "ACTIVE")]
                    })
            }
            .environmentObject(auth)
            .environmentObject(I18nStore())
            .environmentObject(ScenePresentationContext())
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US"))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            let container = UIViewController()
            let controller = UIHostingController(rootView: view)
            controller.safeAreaRegions = []
            window.rootViewController = container
            window.makeKeyAndVisible()
            container.addChild(controller)
            container.view.addSubview(controller.view)
            controller.didMove(toParent: container)
            controller.view.frame = CGRect(origin: .zero, size: size)
            for _ in 0..<20 {
                controller.view.layoutIfNeeded()
                if loadedSalespeople { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(loadedSalespeople)
            try await Task.sleep(for: .milliseconds(250))
            controller.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "sale-detail-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
                .appendingPathComponent("SaleDetailVisualQA", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("sale-detail-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: file)
            print("SALE_DETAIL_SNAPSHOT \(file.path)")
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
    }

    private static let saleJSON = """
    {"id":"sale-visual","ref":"S-1026","status":"INVOICED","location":"MAIN",
     "customer":{"id":"customer","name":"North Coast Fleet","company":null},
     "customerId":"customer","subtotal":"100.00","taxRate":"0.00","taxAmount":"0.00",
     "total":"100.00","createdAt":"2026-10-11T12:00:00Z","salespersonId":"employee-1",
     "salesperson":{"id":"employee-1","fullName":"Alex Rivera","status":"ACTIVE"},
     "lines":[{"id":"line","itemType":"SKU","itemId":"deleted-tire","description":"Example Road 225/65R17",
               "brand":"Example","model":"Road","size":"225/65R17","qty":1,"unitPrice":"100.00",
               "discount":"0.00","lineTotal":"100.00"}],"invoice":null}
    """
}

private struct SnapshotSessionStorage: SessionStorage {
    func load() throws -> SavedSession? { nil }
    func save(_ session: SavedSession) throws {}
    func clear() throws {}
}

private final class SaleDetailSnapshotNoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    override func stopLoading() {}
}
