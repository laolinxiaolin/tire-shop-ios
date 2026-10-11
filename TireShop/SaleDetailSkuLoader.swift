import Foundation

/// Supplemental catalog data must belong to the sale's exact item IDs. Missing
/// or deleted items use their historical line snapshots instead of fuzzy search.
struct SaleDetailSkuLoader {
    var inventory = InventoryAPI()

    func load(itemIDs: [String]) async throws -> [String: TireSku] {
        let ids = Set(itemIDs.compactMap(\.nilIfBlank)).sorted()
        var result: [String: TireSku] = [:]
        let batchSize = 100
        for offset in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[offset..<min(offset + batchSize, ids.count)])
            let requested = Set(batch)
            var pageNumber = 1
            while true {
                try Task.checkCancellation()
                let page = try await inventory.listSkus(ids: batch, page: pageNumber, pageSize: batchSize)
                try Task.checkCancellation()
                for sku in page.items where requested.contains(sku.id) {
                    result[sku.id] = sku
                }
                guard !page.items.isEmpty, page.page * page.pageSize < page.total,
                      page.page >= pageNumber else { break }
                pageNumber = page.page + 1
            }
        }
        return result
    }
}
