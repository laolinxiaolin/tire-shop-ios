import Foundation

/// Inclusive dates in the shop's calendar; the API applies the correct local
/// midnight boundaries, including daylight-saving days.
struct SalesDateWindow: Equatable {
    let from: String
    let to: String

    init(from: Date, to: Date, timeZone: TimeZone = ShopClock.timeZone) {
        self.from = ShopClock.dayString(from: from, in: timeZone)
        self.to = ShopClock.dayString(from: to, in: timeZone)
    }

    var isValid: Bool { from <= to }
}

/// The export covers the complete filtered result, without page or cursor bounds.
struct SalesExportRequest: Equatable {
    var q: String?
    var status: SaleStatus?
    var fulfillment: SaleFulfillment?
    var paymentMethodIds: [String] = []
    var from: String?
    var to: String?
    var sortBy: String?
    var sortOrder: String?

    var path: String {
        var components = URLComponents()
        components.path = "/sales/export"
        let parameters: [(String, String?)] = [
            ("q", q?.nilIfBlank), ("status", status?.nilIfBlank),
            ("fulfillment", fulfillment?.rawValue),
            ("paymentMethodIds", paymentMethodIds.isEmpty ? nil : paymentMethodIds.joined(separator: ",")),
            ("from", from), ("to", to), ("sortBy", sortBy?.nilIfBlank),
            ("sortOrder", sortBy?.nilIfBlank == nil ? nil : sortOrder)
        ]
        let items = parameters.compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        components.queryItems = items.isEmpty ? nil : items
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.string ?? "/sales/export"
    }
}

extension SalesAPI {
    func export(_ request: SalesExportRequest) async throws -> URL {
        try await client.download(request.path, fileName: "sales.xlsx")
    }
}
