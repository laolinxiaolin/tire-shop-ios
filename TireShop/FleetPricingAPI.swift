import Foundation

struct FleetPricingAPI {
    var client = APIClient.shared

    func policy() async throws -> FleetPricingPolicy {
        try await client.request("/pricing/policy", cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func preview(customerId: String, skuIds: [String]) async throws -> [FleetPricePreview] {
        // One result per product is enough even when several draft lines use it.
        // Preserve order while keeping each request within the server's limit.
        var seen = Set<String>()
        let ids = skuIds.filter { seen.insert($0).inserted }
        var results: [FleetPricePreview] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let prices: [FleetPricePreview] = try await client.request(
                "/pricing/quote-preview",
                method: "POST",
                body: PreviewInput(customerId: customerId, skuIds: batch)
            )
            results.append(contentsOf: prices)
        }
        return results
    }

    private struct PreviewInput: Encodable {
        let customerId: String
        let skuIds: [String]
    }
}
