import Foundation

struct CustomerAnalyticsQuery: Hashable {
    var filters = CustomerAnalyticsFilters()
    var q = ""
    var sort: CustomerAnalyticsSort = .sales
    var direction: CustomerAnalyticsDirection = .desc
    var page = 1
    var pageSize = 25

    var path: String {
        analyticsPath("/customer-analytics", filters: filters, parameters: rankingParameters + [
            ("page", String(page)), ("pageSize", String(pageSize))
        ])
    }

    /// Export every matching customer in the same server-side order, without paging.
    var exportPath: String {
        analyticsPath("/customer-analytics/export", filters: filters, parameters: rankingParameters)
    }

    private var rankingParameters: [(String, String?)] {
        [("q", q.nilIfBlank), ("sort", sort.rawValue), ("direction", direction.rawValue)]
    }
}

struct CustomerAnalyticsAPI {
    var client = APIClient.shared

    func rankings(_ query: CustomerAnalyticsQuery = .init()) async throws -> CustomerAnalyticsRankings {
        try validate(query.filters)
        return try await client.request(query.path, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    func summary(customerId: String, filters: CustomerAnalyticsFilters) async throws -> CustomerAnalyticsSummary {
        try validate(filters)
        return try await client.request(
            analyticsPath(customerPath(customerId, resource: "summary"), filters: filters),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    func products(
        customerId: String, filters: CustomerAnalyticsFilters, page: Int = 1, pageSize: Int = 10
    ) async throws -> CustomerAnalyticsPage<CustomerAnalyticsProduct> {
        try validate(filters)
        return try await client.request(
            analyticsPath(customerPath(customerId, resource: "products"), filters: filters, parameters: [
                ("page", String(page)), ("pageSize", String(pageSize))
            ]),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    func history(
        customerId: String, filters: CustomerAnalyticsFilters, page: Int = 1, pageSize: Int = 25
    ) async throws -> CustomerAnalyticsPage<CustomerAnalyticsHistoryEvent> {
        try validate(filters)
        return try await client.request(
            analyticsPath(customerPath(customerId, resource: "history"), filters: filters, parameters: [
                ("page", String(page)), ("pageSize", String(pageSize))
            ]),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    func export(_ query: CustomerAnalyticsQuery) async throws -> URL {
        try validate(query.filters)
        return try await client.download(query.exportPath, fileName: "customer-analytics.xlsx")
    }

    private func validate(_ filters: CustomerAnalyticsFilters) throws {
        guard filters.isValid else {
            throw APIError(status: 0, message: "Choose valid inclusive start and end dates, with start on or before end.")
        }
    }

    private func customerPath(_ id: String, resource: String) throws -> String {
        // Customer IDs are CUIDs. APIClient owns path encoding, so validate this
        // single component instead of passing already escaped path text to it.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw APIError(status: 0, message: "The customer identifier is invalid.")
        }
        return "/customer-analytics/\(id)/\(resource)"
    }
}

private func analyticsPath(
    _ path: String,
    filters: CustomerAnalyticsFilters,
    parameters: [(String, String?)] = []
) -> String {
    let values: [(String, String?)] = [
        ("period", filters.period.rawValue),
        ("start", filters.period == .custom ? filters.start : nil),
        ("end", filters.period == .custom ? filters.end : nil),
        ("priceLevel", filters.priceLevel?.rawValue)
    ] + parameters
    var components = URLComponents()
    components.queryItems = values.compactMap { name, value in
        value.map { URLQueryItem(name: name, value: $0) }
    }
    let query = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
    return query.isEmpty ? path : "\(path)?\(query)"
}
