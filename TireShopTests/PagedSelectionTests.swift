import XCTest
@testable import TireShop

final class PagedSelectionTests: XCTestCase {
    func testRefreshOfFirstPageRetainsTirePreviouslySelectedOnLaterPage() {
        let selected: Set<String> = ["page-two-tire"]
        let firstPage: Set<String> = ["page-one-tire"]
        XCTAssertEqual(PagedSelection.reconciled(selected, loadedIDs: firstPage, complete: false), selected)
        XCTAssertEqual(PagedSelection.reconciled(selected, loadedIDs: firstPage.union(selected), complete: true), selected)
    }

    func testCompleteRefreshPrunesDeletedSelection() {
        XCTAssertEqual(PagedSelection.reconciled(["present", "deleted"], loadedIDs: ["present"], complete: true), ["present"])
    }

    func testChangingWarehouseOrFilterStartsFreshSelection() {
        XCTAssertTrue(PagedSelection.reconciled(["old-warehouse-tire"], loadedIDs: ["old-warehouse-tire"],
                                                complete: false, scopeChanged: true).isEmpty)
    }
}
