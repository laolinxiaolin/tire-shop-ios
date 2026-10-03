import XCTest
@testable import TireShop

@MainActor
final class CustomerAnalyticsNavigationTests: XCTestCase {
    func testAnalyticsDestinationIsAvailableWithoutCustomerProfileAccess() throws {
        let auth = makeAuth(permissions: ["customers.analytics.view"])
        let visible = Set(DestinationRegistry.visibleDestinations(auth: auth).map(\.key))
        XCTAssertTrue(visible.contains("customerAnalytics"))
        XCTAssertFalse(visible.contains("customers"))

        auth.user = makeUser(permissions: ["customers.view", "customers.profit.view"])
        XCTAssertFalse(DestinationRegistry.visibleDestinations(auth: auth).contains { $0.key == "customerAnalytics" })
    }

    func testAnalyticsDrilldownPreservesFiltersAcrossCompactAndSidebarNavigation() {
        let navigation = AppNavigationModel()
        let query = CustomerAnalyticsQuery(filters: CustomerAnalyticsFilters(
            period: .custom, start: "2026-09-01", end: "2026-09-30", priceLevel: .unknown
        ))
        let detail = AppRoute.customerAnalyticsDetail(customerId: "historical-customer", query: query)
        navigation.selectDestination("customerAnalytics")
        navigation.append(detail, to: AppNavigationModel.moreKey)
        XCTAssertEqual(navigation.path(for: "customerAnalytics").wrappedValue, [detail])

        navigation.selectCompactTab("sales")
        navigation.selectCompactTab(AppNavigationModel.moreKey)
        XCTAssertEqual(navigation.path(for: AppNavigationModel.moreKey).wrappedValue,
                       [.module("customerAnalytics"), detail])

        navigation.sanitize(visibleDestinationKeys: ["sales"])
        XCTAssertTrue(navigation.path(for: "customerAnalytics").wrappedValue.isEmpty)
        XCTAssertTrue(navigation.path(for: AppNavigationModel.moreKey).wrappedValue.isEmpty)
    }

    func testSessionDecodesDemoExportRestrictionAndOlderPayloads() throws {
        let base = """
        {"id":"user","email":"user@example.invalid","fullName":"Analytics user",
         "roleId":"staff","roleName":"Staff","isAdmin":false,"permissions":[]}
        """
        XCTAssertNil(try JSONDecoder().decode(SessionUser.self, from: Data(base.utf8)).demo)
        let demo = base.replacingOccurrences(of: "\"permissions\":[]", with: "\"permissions\":[],\"demo\":true")
        XCTAssertEqual(try JSONDecoder().decode(SessionUser.self, from: Data(demo.utf8)).demo, true)
    }

    private func makeAuth(permissions: [String]) -> AuthStore {
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: .ephemeral)))
        auth.user = makeUser(permissions: permissions)
        auth.ready = true
        return auth
    }

    private func makeUser(permissions: [String]) -> SessionUser {
        SessionUser(id: "analytics-user", email: "analytics@example.invalid", fullName: "Analytics user",
                    roleId: "staff", roleName: "Staff", homeWarehouse: nil, isAdmin: false,
                    permissions: permissions, approvalPermissions: [], mfaMethod: nil)
    }
}
