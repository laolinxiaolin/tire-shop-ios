import Foundation

struct CustomerTaxDetails: Decodable, Equatable {
    struct Resolution: Decodable, Equatable {
        let id: String
        let status: String
        let problemCode: String?
        let normalizedAddress: [String: AddressComponent]?
        let reviewedAt: String?
        let reviewNotes: String?
        let reviewSourceUrl: String?

        var addressLabel: String? {
            guard let normalizedAddress else { return nil }
            func component(_ key: String) -> String? {
                normalizedAddress[key]?.text
            }
            var street = ["number", "predirectional", "streetName", "streetSuffix", "postdirectional"]
                .compactMap(component)
            if let unit = component("unit") { street.append("#\(unit)") }
            let locality = ["postalCity", "state", "postalCode"].compactMap(component).joined(separator: " ")
            return [street.joined(separator: " "), locality].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    enum AddressComponent: Decodable, Equatable {
        case text(String)
        case number(Double)
        case empty

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .empty
            } else if let value = try? container.decode(String.self) {
                self = .text(value)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }

        var text: String? {
            switch self {
            case .text(let value): return value.isEmpty ? nil : value
            case .number(let value): return value.formatted(.number.grouping(.never))
            case .empty: return nil
            }
        }
    }

    struct Automatic: Decodable, Equatable {
        struct Source: Decodable, Equatable {
            let label: String
            let dorCodes: [String?]
        }

        let status: String
        let rate: Double?
        let source: Source?
    }

    struct Override: Decodable, Equatable {
        let rate: Double
        let reason: String
        let expiresAt: String?
        let usesShopDefault: Bool
    }

    let rate: Double?
    let source: String
    let resolution: Resolution?
    let automatic: Automatic?
    let override: Override?
    let shopDefaultRate: Double

    var automaticRate: Double? {
        guard let automatic, ["RESOLVED", "SHOP_DEFAULT"].contains(automatic.status) else { return nil }
        return automatic.rate
    }

    var resolutionStatus: String {
        automatic?.status == "SHOP_DEFAULT" ? "SHOP_DEFAULT" : resolution?.status ?? "UNRESOLVED"
    }
}

enum CustomerTaxMode: String, CaseIterable {
    case automatic, shopDefault, manual
}

struct CustomerTaxOverrideInput: Encodable {
    let taxRateOverride: Double?
    let useShopDefault: Bool
    let reason: String
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case taxRateOverride, useShopDefault, reason, expiresAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // An explicit null revokes the active override. Omitting this key does not.
        try container.encode(taxRateOverride, forKey: .taxRateOverride)
        try container.encode(useShopDefault, forKey: .useShopDefault)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

struct CustomerAddressReviewInput: Encodable {
    let sourceUrl: String
    let notes: String
    let confirmedNoUncoveredSpecialDistrict: Bool
}

enum CustomerTaxValidation {
    static let expiryTimeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    static func rate(fromPercent text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(trimmed), percent.isFinite, (0...100).contains(percent),
              abs(percent * 100 - (percent * 100).rounded()) < 1e-8 else { return nil }
        return (percent * 100).rounded() / 10_000
    }

    static func evidenceURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = expiryTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func expiryDay(_ exclusiveEnd: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: exclusiveEnd)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: exclusiveEnd)
        }
        // The API stores midnight after the selected New York calendar day.
        return date?.addingTimeInterval(-0.001)
    }
}
