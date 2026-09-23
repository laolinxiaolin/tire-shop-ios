import XCTest
@testable import TireShop

@MainActor
final class AppNavigationModelTests: XCTestCase {
    func testSwitchingPinnedTabsPreservesMoreWorkflow() {
        let navigation = AppNavigationModel()
        navigation.selectDestination("employees")
        navigation.append(.employeeDetail("employee-1"), to: AppNavigationModel.moreKey)
        let originalPath = navigation.path(for: AppNavigationModel.moreKey).wrappedValue

        navigation.selectCompactTab("sales")
        XCTAssertEqual(navigation.selectedDestinationKey, "sales")
        XCTAssertEqual(navigation.path(for: AppNavigationModel.moreKey).wrappedValue, originalPath)
        navigation.selectCompactTab("inventory")
        navigation.selectCompactTab(AppNavigationModel.moreKey)
        XCTAssertEqual(navigation.compactTab(pinnedKeys: ["sales", "inventory"]), AppNavigationModel.moreKey)
        XCTAssertEqual(navigation.path(for: AppNavigationModel.moreKey).wrappedValue, originalPath)
    }

    func testMoreAndSidebarShareDetailPathAcrossResizingAndBackNavigation() {
        let navigation = AppNavigationModel()
        navigation.selectDestination("employees")
        let more = navigation.path(for: AppNavigationModel.moreKey)
        more.wrappedValue = [.module("employees"), .employeeDetail("employee-1")]
        XCTAssertEqual(navigation.path(for: "employees").wrappedValue, [.employeeDetail("employee-1")])

        navigation.selectCompactTab("sales")
        navigation.selectCompactTab(AppNavigationModel.moreKey)
        XCTAssertEqual(navigation.activeDestinationKey, "employees")
        XCTAssertEqual(navigation.compactTab(pinnedKeys: ["sales"]), AppNavigationModel.moreKey)

        // The regular sidebar stack pops the detail; compact More sees it too.
        navigation.path(for: "employees").wrappedValue = []
        XCTAssertEqual(more.wrappedValue, [.module("employees")])
        navigation.append(.employeeDetail("employee-2"), to: "employees")
        XCTAssertEqual(more.wrappedValue, [.module("employees"), .employeeDetail("employee-2")])
        more.wrappedValue = []
        XCTAssertTrue(navigation.path(for: "employees").wrappedValue.isEmpty)
        XCTAssertEqual(navigation.activeDestinationKey, AppNavigationModel.moreKey)
    }

    func testSidebarDestinationReusesItsOwnPathWhenReturningToCompact() {
        let navigation = AppNavigationModel()
        navigation.selectDestination("employees")
        navigation.append(.employeeDetail("employee-1"), to: "employees")
        navigation.selectDestination("sales")
        navigation.selectDestination("employees")
        XCTAssertEqual(navigation.path(for: AppNavigationModel.moreKey).wrappedValue,
            [.module("employees"), .employeeDetail("employee-1")])
        navigation.sanitize(visibleDestinationKeys: ["sales"])
        XCTAssertTrue(navigation.path(for: "employees").wrappedValue.isEmpty)
        XCTAssertTrue(navigation.path(for: AppNavigationModel.moreKey).wrappedValue.isEmpty)
    }

    func testDestinationSelectionAdaptsBetweenSidebarAndCompactMore() {
        let navigation = AppNavigationModel()

        navigation.selectDestination("customers")

        XCTAssertEqual(navigation.selectedDestinationKey, "customers")
        XCTAssertEqual(
            navigation.compactTab(pinnedKeys: DestinationRegistry.defaultPinned),
            AppNavigationModel.moreKey
        )
        XCTAssertEqual(
            navigation.path(for: AppNavigationModel.moreKey).wrappedValue,
            [.module("customers")]
        )
    }

    func testDestinationPathsAndRecordSelectionsSurvivePresentationChanges() {
        let navigation = AppNavigationModel()

        navigation.selectDestination("sales")
        navigation.append(.saleDetail("sale-1"), to: "sales")
        navigation.rememberSale("sale-1")
        navigation.selectDestination("inventory")
        navigation.append(.skuDetail("sku-1"), to: "inventory")
        navigation.rememberInventoryItem("sku-1")

        XCTAssertEqual(navigation.path(for: "sales").wrappedValue, [.saleDetail("sale-1")])
        XCTAssertEqual(navigation.path(for: "inventory").wrappedValue, [.skuDetail("sku-1")])
        XCTAssertEqual(navigation.selectedSaleID, "sale-1")
        XCTAssertEqual(navigation.selectedInventoryID, "sku-1")
    }

    func testSanitizeClearsInaccessibleDestinationAndRecordSelection() {
        let navigation = AppNavigationModel(selectedDestinationKey: "sales")
        navigation.rememberSale("sale-1")
        navigation.rememberCustomer("customer-1")
        navigation.append(.module("sales"), to: AppNavigationModel.moreKey)

        navigation.sanitize(visibleDestinationKeys: ["dashboard", "customers"])

        XCTAssertEqual(navigation.selectedDestinationKey, "dashboard")
        XCTAssertNil(navigation.selectedSaleID)
        XCTAssertEqual(navigation.selectedCustomerID, "customer-1")
        XCTAssertTrue(navigation.path(for: AppNavigationModel.moreKey).wrappedValue.isEmpty)
    }

    func testSessionResetClearsSceneNavigationState() {
        let navigation = AppNavigationModel(selectedDestinationKey: "customers")
        navigation.rememberCustomer("customer-1")
        navigation.append(.customerDetail(id: "customer-1", name: "Acme"), to: "customers")

        navigation.resetForSessionChange()

        XCTAssertEqual(navigation.selectedDestinationKey, DestinationRegistry.defaultPinned.first)
        XCTAssertNil(navigation.selectedCustomerID)
        XCTAssertTrue(navigation.path(for: "customers").wrappedValue.isEmpty)
    }

    func testDeletingRecordsOnlyClearsTheMatchingSelection() {
        let navigation = AppNavigationModel()
        navigation.rememberSale("sale-1")
        navigation.rememberInventoryItem("sku-1")
        navigation.rememberCustomer("customer-1")

        navigation.clearSale(ifSelected: "sale-2")
        navigation.clearInventoryItem(ifSelected: "sku-1")
        navigation.clearCustomer(ifSelected: "customer-2")

        XCTAssertEqual(navigation.selectedSaleID, "sale-1")
        XCTAssertNil(navigation.selectedInventoryID)
        XCTAssertEqual(navigation.selectedCustomerID, "customer-1")
    }

    func testBrowsingWorkspaceOnlySplitsWhenBothPanesRemainUseful() {
        XCTAssertTrue(BrowsingWorkspaceLayout.usesSplitView(width: 760, horizontalSizeClass: .regular))
        XCTAssertFalse(BrowsingWorkspaceLayout.usesSplitView(width: 759, horizontalSizeClass: .regular))
        XCTAssertFalse(BrowsingWorkspaceLayout.usesSplitView(width: 1_200, horizontalSizeClass: .compact))
    }

    func testSaleWorkspaceShowsCatalogOnlyWhenBothWorkAreasFit() {
        XCTAssertTrue(SaleWorkspaceLayout.showsCatalog(width: 760, horizontalSizeClass: .regular))
        XCTAssertFalse(SaleWorkspaceLayout.showsCatalog(width: 759, horizontalSizeClass: .regular))
        XCTAssertFalse(SaleWorkspaceLayout.showsCatalog(width: 1_200, horizontalSizeClass: .compact))
    }
}
