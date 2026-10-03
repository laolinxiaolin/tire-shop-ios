import Foundation

/// The current standard-price assignment. Historical analytics also has an
/// UNKNOWN filter, which is deliberately separate from these saved levels.
enum PriceLevel: String, Codable, CaseIterable, Identifiable {
    case wholesale = "WHOLESALE"
    case fleet = "FLEET"
    case retail = "RETAIL"

    var id: String { rawValue }
    var localizationKey: String { "customers.level.\(rawValue)" }
}

struct CustomerPriceLevelPatch: Encodable {
    let priceLevel: PriceLevel
}

struct FleetPricingPolicy: Codable, Equatable {
    let enabled: Bool
}

/// The server owns the baseline and version. Sales submit only the version and
/// actual price; saved standard prices are returned as transaction evidence.
struct FleetPricePreview: Codable, Equatable {
    let skuId: String
    let priceLevel: PriceLevel
    let standardUnitPrice: String
    let unitPrice: String
    let priceSource: String
    let version: String
}
