import XCTest
@testable import TireShop

@MainActor
final class SalesVisibilityAccessTests: XCTestCase {
    private let globalModules = [
        "orders", "accounting", "cashAccounts", "checks", "fet", "eod",
        "monthlySales", "commissions", "activity"
    ]
    private let modulePermissions = [
        "orders.manage", "accounting.view", "payments.collect", "employees.view", "activity.view"
    ]

    func testGlobalModulesRequireAllSalesAccessAsWellAsModulePermission() {
        let scoped = makeAuth(permissions: modulePermissions)
        let allSales = makeAuth(permissions: modulePermissions + ["sales.viewAll"])
        let visibilityOnly = makeAuth(permissions: ["sales.viewAll"])

        for key in globalModules {
            XCTAssertFalse(DestinationRegistry.isVisible(key, auth: scoped), key)
            XCTAssertTrue(DestinationRegistry.isVisible(key, auth: allSales), key)
            XCTAssertFalse(DestinationRegistry.isVisible(key, auth: visibilityOnly), key)
        }
    }

    func testChecksRetainCollectionAlternativeWithMandatoryAllSalesAccess() {
        XCTAssertTrue(DestinationRegistry.isVisible("checks", auth: makeAuth(
            permissions: ["payments.collect", "sales.viewAll"]
        )))
        XCTAssertFalse(DestinationRegistry.isVisible("checks", auth: makeAuth(
            permissions: ["payments.collect"]
        )))
    }

    func testOwnSalesHRAndAnalyticsRemainAvailableAndKeepTheirNavigationPaths() {
        let auth = makeAuth(permissions: modulePermissions + [
            "sales.view", "sales.manage", "customers.analytics.view", "receivables.view"
        ])
        let visible = Set(DestinationRegistry.visibleDestinations(auth: auth).map(\.key))
        XCTAssertTrue(Set(["sales", "newQuote", "employees", "customerAnalytics", "money"]).isSubset(of: visible))

        let navigation = AppNavigationModel(selectedDestinationKey: "sales")
        navigation.append(.saleDetail("own-sale"), to: "sales")
        navigation.append(.employeeDetail("employee"), to: "employees")
        navigation.append(.orderDetail("global-order"), to: "orders")
        navigation.sanitize(visibleDestinationKeys: visible)

        XCTAssertEqual(navigation.selectedDestinationKey, "sales")
        XCTAssertEqual(navigation.path(for: "sales").wrappedValue, [.saleDetail("own-sale")])
        XCTAssertEqual(navigation.path(for: "employees").wrappedValue, [.employeeDetail("employee")])
        XCTAssertTrue(navigation.path(for: "orders").wrappedValue.isEmpty)
    }

    func testAdminWildcardCanStillOpenGlobalModules() {
        let auth = makeAuth(permissions: [], isAdmin: true)
        XCTAssertTrue(globalModules.allSatisfy { DestinationRegistry.isVisible($0, auth: auth) })
    }

    private func makeAuth(permissions: [String], isAdmin: Bool = false) -> AuthStore {
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: .ephemeral)))
        auth.user = SessionUser(
            id: "staff", email: "staff@example.invalid", fullName: "Staff",
            roleId: "role", roleName: "Staff", homeWarehouse: nil, isAdmin: isAdmin,
            permissions: permissions, approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        return auth
    }
}
