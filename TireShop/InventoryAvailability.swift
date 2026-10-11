enum InventoryAvailability {
    struct Summary {
        let quantity: Int
        let title: String
    }

    static func quantity(for sku: TireSku, location: String?) -> Int {
        guard let location else {
            return sku.inventory.reduce(0) { total, inventory in
                total + max(0, inventory.qtyOnHand - inventory.qtyReserved)
            }
        }
        guard let inventory = sku.inventory.first(where: { $0.location == location }) else { return 0 }
        return max(0, inventory.qtyOnHand - inventory.qtyReserved)
    }

    static func summary(items: [TireSku], location: String?, hasMorePages: Bool) -> Summary {
        // The API's signed aggregate can offset sellable tires with another
        // SKU's excess reservations. Sum the same clamped values as the rows.
        Summary(
            quantity: items.reduce(0) { $0 + quantity(for: $1, location: location) },
            title: hasMorePages ? "Available in loaded items" : "Available inventory"
        )
    }
}
