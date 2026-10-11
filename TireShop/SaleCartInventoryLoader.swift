import Foundation

struct SaleCartInventoryContext: Equatable {
    let location: String
    let skuIds: Set<String>
}

/// Resolves only the SKUs in the cart. Pagination still handles a server page
/// limit, but adding one tire never requires scanning the full catalog.
struct SaleCartInventoryLoader {
    typealias Loader = ([String], Int, Int) async throws -> InventorySkuPage
    private let loader: Loader

    init(loader: @escaping Loader = { ids, page, size in
        try await InventoryAPI().listSkus(ids: ids, page: page, pageSize: size)
    }) {
        self.loader = loader
    }

    func load(skuIds: Set<String>) async throws -> [String: TireSku] {
        guard !skuIds.isEmpty else { return [:] }
        let ids = skuIds.sorted()
        var matching: [String: TireSku] = [:]
        // Bound the query itself as well as the response page: hundreds of
        // CUIDs in one GET can exceed the server's request-line limit.
        let batchSize = 100
        for offset in stride(from: 0, to: ids.count, by: batchSize) {
            let batch = Array(ids[offset..<min(offset + batchSize, ids.count)])
            let requested = Set(batch)
            var matched = Set<String>()
            var pageNumber = 1
            while true {
                try Task.checkCancellation()
                let page = try await loader(batch, pageNumber, 1000)
                try Task.checkCancellation()
                for sku in page.items where requested.contains(sku.id) {
                    matching[sku.id] = sku
                    matched.insert(sku.id)
                }
                guard matched.count < requested.count,
                      page.page * page.pageSize < page.total,
                      !page.items.isEmpty,
                      page.page + 1 > pageNumber else { break }
                pageNumber = page.page + 1
            }
        }
        return matching
    }
}
