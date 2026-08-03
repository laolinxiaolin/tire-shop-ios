import Foundation

enum AppFormat {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // The NestJS backend serializes timestamps via Date.toISOString(), which
    // always includes milliseconds; ISO8601DateFormatter needs a separate
    // configuration for each variant.
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    // Plain calendar dates (yyyy-MM-dd) parse in the local time zone so the
    // displayed day matches the stored day.
    private static let dayOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func money(_ value: String?) -> String {
        guard let value, let number = Double(value) else { return "-" }
        return money(number)
    }

    static func money(_ value: Double?) -> String {
        guard let value else { return "-" }
        return currencyFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    static func shortDate(_ value: String?) -> String {
        guard let date = parseDate(value) else { return "-" }
        return dateFormatter.string(from: date)
    }

    /// Format a value that represents a calendar day rather than an instant
    /// (hire dates, due dates, accounting dates). Reads only the yyyy-MM-dd
    /// part so UTC-midnight timestamps like "2026-07-03T00:00:00.000Z" render
    /// as Jul 3 in every time zone instead of shifting a day.
    static func calendarDate(_ value: String?) -> String {
        guard
            let value,
            let date = dayOnlyFormatter.date(from: String(value.prefix(10)))
        else { return "-" }
        return dateFormatter.string(from: date)
    }

    static func dateTime(_ value: String?) -> String {
        guard let date = parseDate(value) else { return "-" }
        return dateTimeFormatter.string(from: date)
    }

    static func date(_ value: String?) -> Date? {
        parseDate(value)
    }

    static func phone(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let digits = value.filter(\.isNumber)
        guard digits.count == 10 else { return value }
        let area = digits.prefix(3)
        let middle = digits.dropFirst(3).prefix(3)
        let last = digits.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }

    static func normalizeUSPhone(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var digits = trimmed.filter(\.isNumber)
        if digits.count == 11, digits.first == "1" {
            digits.removeFirst()
        }
        guard digits.count == 10 else {
            throw APIError(status: 0, message: "Phone must be a 10-digit US number")
        }
        return String(digits)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return isoFractionalFormatter.date(from: value)
            ?? isoFormatter.date(from: value)
            ?? dayOnlyFormatter.date(from: value)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
