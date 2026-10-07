import Foundation

enum CustomerAnalyticsPreset: String, Codable, CaseIterable {
    case thisMonth = "THIS_MONTH"
    case lastMonth = "LAST_MONTH"
    case yearToDate = "YTD"
    case last12Months = "LAST_12_MONTHS"
    case custom = "CUSTOM"
    case lifetime = "LIFETIME"
}

enum CustomerAnalyticsPriceLevel: String, Codable, CaseIterable {
    case wholesale = "WHOLESALE"
    case fleet = "FLEET"
    case retail = "RETAIL"
    case unknown = "UNKNOWN"
}

struct CustomerAnalyticsFilters: Hashable {
    var period: CustomerAnalyticsPreset = .thisMonth
    var start = ""
    var end = ""
    var priceLevel: CustomerAnalyticsPriceLevel?

    /// Inclusive shop-calendar days. Preset boundaries are calculated by the server.
    var isValid: Bool {
        period != .custom || (Self.isValidDay(start) && Self.isValidDay(end) && start <= end)
    }

    static func isValidDay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), (100...9998).contains(year),
              let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(value.suffix(2)) else { return false }
        let leapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }
}

enum CustomerAnalyticsSort: String, Codable, CaseIterable {
    case customer, priceLevel, sales, tiresSold, orders, averageOrder
    case actualCogs, grossProfit, gpPercent, lastOrder

    var requiresProfitPermission: Bool {
        [.actualCogs, .grossProfit, .gpPercent].contains(self)
    }

    func allowed(canViewProfit: Bool) -> Self {
        requiresProfitPermission && !canViewProfit ? .sales : self
    }
}

enum CustomerAnalyticsDirection: String, Codable, CaseIterable {
    case asc, desc
}

struct CustomerAnalyticsPeriod: Decodable, Equatable {
    let preset: CustomerAnalyticsPreset
    let start: String?
    let end: String?
    let timezone: String
}

struct CustomerAnalyticsHistoryCoverage: Decodable, Equatable {
    enum Status: String, Decodable {
        case notBackfilled = "NOT_BACKFILLED"
        case partial = "PARTIAL"
        case complete = "COMPLETE"
    }

    let status: Status
}

/// Values come from immutable recognized events, including returns and reversals.
/// Missing or null profit evidence remains unavailable rather than becoming zero.
/// Server gross profit uses booked COGS independently of actual-cost verification;
/// a null actualCogs value must not hide grossProfit or gpPercent.
struct CustomerAnalyticsMetrics: Decodable, Equatable {
    let sales: Double
    let tireRevenue: Double
    let serviceRevenue: Double
    let deliveryRevenue: Double
    let restockingFees: Double
    let tiresSold: Int
    let orders: Int
    let averageOrder: Double?
    let lastOrder: String?
    let actualCogs: Double?
    let bookedCogs: Double?
    let grossProfit: Double?
    let gpPercent: Double?
    let costCoverage: Double?
    let unverifiedCostUnits: Int?
}

struct CustomerAnalyticsCustomer: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let company: String?
    let currentPriceLevel: CustomerAnalyticsPriceLevel?
}

struct CustomerAnalyticsRankingRow: Decodable, Equatable, Identifiable {
    let customerId: String
    let customerName: String
    let company: String?
    let currentPriceLevel: CustomerAnalyticsPriceLevel?
    let metrics: CustomerAnalyticsMetrics

    var id: String { customerId }

    private enum CodingKeys: String, CodingKey {
        case customerId, customerName, company, currentPriceLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customerId = try container.decode(String.self, forKey: .customerId)
        customerName = try container.decode(String.self, forKey: .customerName)
        company = try container.decodeIfPresent(String.self, forKey: .company)
        currentPriceLevel = try container.decodeIfPresent(CustomerAnalyticsPriceLevel.self, forKey: .currentPriceLevel)
        metrics = try CustomerAnalyticsMetrics(from: decoder)
    }
}

struct CustomerAnalyticsRankings: Decodable, Equatable {
    let items: [CustomerAnalyticsRankingRow]
    let total: Int
    let page: Int
    let pageSize: Int
    let period: CustomerAnalyticsPeriod
    let historyCoverage: CustomerAnalyticsHistoryCoverage
    let totals: CustomerAnalyticsMetrics
    let canViewProfit: Bool
}

struct CustomerAnalyticsSummary: Decodable, Equatable {
    let customer: CustomerAnalyticsCustomer
    let period: CustomerAnalyticsPeriod
    let historyCoverage: CustomerAnalyticsHistoryCoverage
    let summary: CustomerAnalyticsMetrics
    let lifetime: CustomerAnalyticsMetrics
    let canViewProfit: Bool
}

struct CustomerAnalyticsPage<Item: Decodable & Equatable>: Decodable, Equatable {
    let items: [Item]
    let total: Int
    let page: Int
    let pageSize: Int
    let period: CustomerAnalyticsPeriod
    let historyCoverage: CustomerAnalyticsHistoryCoverage
}

struct CustomerAnalyticsProduct: Decodable, Equatable, Identifiable {
    let skuId: String
    let sku: String?
    let brand: String?
    let model: String?
    let size: String?
    let quantity: Int
    let netRevenue: Double
    let averageUnitPrice: Double?

    var id: String { skuId }
}

struct CustomerAnalyticsHistoryEvent: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable, CaseIterable {
        case sale = "SALE"
        case saleReversal = "SALE_REVERSAL"
        case returnEvent = "RETURN"
        case returnReversal = "RETURN_REVERSAL"
    }

    /// The current sale still represents this exact recognized invoice generation.
    let sourceAvailable: Bool
    let eventId: String
    let saleId: String
    let invoiceId: String?
    let ref: String?
    let kind: Kind
    let date: String
    let priceLevel: CustomerAnalyticsPriceLevel?
    let fulfillment: String?
    let sales: Double
    let tireRevenue: Double
    let serviceRevenue: Double
    let deliveryRevenue: Double
    let restockingFees: Double
    let tiresSold: Int
    let bookedCogs: Double?

    var id: String { eventId }
}
