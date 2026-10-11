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
        var pageNumber = 1
        var matching: [String: TireSku] = [:]
        while true {
            try Task.checkCancellation()
            let page = try await loader(ids, pageNumber, 1000)
            try Task.checkCancellation()
            for sku in page.items where skuIds.contains(sku.id) {
                matching[sku.id] = sku
            }
            guard matching.count < skuIds.count,
                  page.page * page.pageSize < page.total,
                  !page.items.isEmpty,
                  page.page + 1 > pageNumber else { break }
            pageNumber = page.page + 1
        }
        return matching
    }
}
