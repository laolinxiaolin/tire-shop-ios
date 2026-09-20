import XCTest
@testable import TireShop

@MainActor
final class AppNavigationModelTests: XCTestCase {
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
}
