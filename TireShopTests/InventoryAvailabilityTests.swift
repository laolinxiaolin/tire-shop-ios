import XCTest
@testable import TireShop

final class InventoryAvailabilityTests: XCTestCase {
    func testExcessReservationsDoNotHideAnotherTiresSellableStock() throws {
        let overreserved = try sku("a", inventory: [stock("MAIN", onHand: 2, reserved: 6)])
        let sellable = try sku("b", inventory: [stock("MAIN", onHand: 5, reserved: 0)])
        let summary = InventoryAvailability.summary(items: [overreserved, sellable], location: "MAIN", hasMorePages: false)

        XCTAssertEqual(InventoryAvailability.quantity(for: overreserved, location: "MAIN"), 0)
        XCTAssertEqual(InventoryAvailability.quantity(for: sellable, location: "MAIN"), 5)
        XCTAssertEqual(summary.quantity, 5)
    }

    func testWarehouseScopeClampsEachStockRowBeforeSumming() throws {
        let tire = try sku("a", inventory: [stock("MAIN", onHand: 2, reserved: 6), stock("OTHER", onHand: 5, reserved: 1)])

        XCTAssertEqual(InventoryAvailability.quantity(for: tire, location: "MAIN"), 0)
        XCTAssertEqual(InventoryAvailability.quantity(for: tire, location: "OTHER"), 4)
        XCTAssertEqual(InventoryAvailability.quantity(for: tire, location: "MISSING"), 0)
        XCTAssertEqual(InventoryAvailability.quantity(for: tire, location: nil), 4)
    }

    func testPartialSummaryBecomesCompleteAfterRemainingItemsLoad() throws {
        let firstPage = [try sku("a", inventory: [stock("MAIN", onHand: 5, reserved: 1)])]
        let partial = InventoryAvailability.summary(items: firstPage, location: "MAIN", hasMorePages: true)
        XCTAssertEqual(partial.quantity, 4)
        XCTAssertEqual(partial.title, "Available in loaded items")

        let allItems = firstPage + [try sku("b", inventory: [stock("MAIN", onHand: 8, reserved: 2)])]
        let complete = InventoryAvailability.summary(items: allItems, location: "MAIN", hasMorePages: false)
        XCTAssertEqual(complete.quantity, 10)
        XCTAssertEqual(complete.title, "Available inventory")
    }

    private func stock(_ location: String, onHand: Int, reserved: Int) -> [String: Any] {
        ["id": location, "location": location, "qtyOnHand": onHand, "qtyReserved": reserved, "unitCost": "80.00"]
    }

    private func sku(_ id: String, inventory: [[String: Any]]) throws -> TireSku {
        let json: [String: Any] = [
            "id": id, "sku": id, "brand": "Example", "model": "Road", "size": "225/65R17",
            "category": "PCR", "position": "ALL_POSITION", "priceRetail": "125.00", "priceCost": "80.00",
            "reorderPoint": 2, "active": true, "inventory": inventory
        ]
        return try JSONDecoder().decode(TireSku.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
