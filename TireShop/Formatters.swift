import Foundation

enum AppFormat {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let dateDisplayFormatterCache = DateDisplayFormatterCache()

    // The NestJS backend serializes timestamps via Date.toISOString(), which
    // always includes milliseconds; ISO8601DateFormatter needs a separate
    // configuration for each variant.
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    static func money(_ value: String?) -> String {
        guard let value, let number = Double(value) else { return "-" }
        return money(number)
    }

    static func money(_ value: Double?) -> String {
        guard let value else { return "-" }
        return currencyFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    /// Parse a user-entered amount using the given locale's decimal separator
    /// (so `"12,50"` works in comma-decimal locales), falling back to a plain
    /// `Double` parse. Returns `nil` for blank or unparseable input.
    static func parseAmount(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let number = amountFormatter(for: locale).number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed)
    }

    // Cached per-locale formatters so view-body computed properties that call
    // parseAmount on every keystroke don't allocate a NumberFormatter each time.
    // Keyed on the locale identifier so a region change without relaunch is picked
    // up rather than captured once in a `static let`.
    private static let amountFormatterLock = NSLock()
    private static var amountFormatterCache: [String: NumberFormatter] = [:]

    private static func amountFormatter(for locale: Locale) -> NumberFormatter {
        let key = locale.identifier
        amountFormatterLock.lock()
        defer { amountFormatterLock.unlock() }
        if let cached = amountFormatterCache[key] {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        amountFormatterCache[key] = formatter
        return formatter
    }

    static func shortDate(_ value: String?) -> String {
        guard let date = parseDate(value) else { return "-" }
        return shortDate(date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDate(date, locale: .current, timeZone: ShopClock.timeZone)
    }

    static func shortDate(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        dateDisplayFormatterCache.string(from: date, locale: locale, timeZone: timeZone, includesTime: false)
    }

    /// Format a value that represents a calendar day rather than an instant
    /// (hire dates and report bounds). Reads only the yyyy-MM-dd
    /// part so UTC-midnight timestamps like "2026-07-03T00:00:00.000Z" render
    /// as Jul 3 in every time zone instead of shifting a day.
    static func calendarDate(_ value: String?) -> String {
        calendarDate(value, locale: .current, timeZone: ShopClock.timeZone)
    }

    static func calendarDate(_ value: String?, locale: Locale, timeZone: TimeZone) -> String {
        guard
            let value,
            let date = ShopClock.date(fromDayString: String(value.prefix(10)), in: timeZone)
        else { return "-" }
        return shortDate(date, locale: locale, timeZone: timeZone)
    }

    static func dateTime(_ value: String?) -> String {
        guard let date = parseDate(value) else { return "-" }
        return dateTime(date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTime(date, locale: .current, timeZone: ShopClock.timeZone)
    }

    static func dateTime(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        dateDisplayFormatterCache.string(from: date, locale: locale, timeZone: timeZone, includesTime: true)
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
            ?? ShopClock.date(fromDayString: value)
    }
}

/// Reuse display formatters while keeping region and shop time-zone changes live.
private final class DateDisplayFormatterCache {
    private struct Key: Hashable {
        let locale: String
        let timeZone: String
        let includesTime: Bool
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]
    private var localeObserver: NSObjectProtocol?

    init() {
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.clear()
        }
    }

    deinit {
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
    }

    func string(from date: Date, locale: Locale, timeZone: TimeZone, includesTime: Bool) -> String {
        let key = Key(locale: locale.identifier, timeZone: timeZone.identifier, includesTime: includesTime)
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = includesTime ? .short : .none
            formatters[key] = formatter
        }
        return formatter.string(from: date)
    }

    private func clear() {
        lock.lock()
        defer { lock.unlock() }
        formatters.removeAll()
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
