import Foundation

/// The shop's configured calendar is the source of truth for every operator,
/// regardless of the iPhone's own time zone.
enum ShopClock {
    static let defaultTimeZoneIdentifier = "America/Los_Angeles"

    private static let storageKey = "tireShop.shopTimeZone"

    static var timeZone: TimeZone {
        resolveTimeZone(UserDefaults.standard.string(forKey: storageKey))
    }

    static var calendar: Calendar {
        calendar(in: timeZone)
    }

    static func resolveTimeZone(_ identifier: String?) -> TimeZone {
        if let identifier, let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        return TimeZone(identifier: defaultTimeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    static func persist(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil else { return }
        UserDefaults.standard.set(identifier, forKey: storageKey)
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayString(from date: Date, in timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(in: timeZone ?? self.timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? self.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(fromDayString value: String, in timeZone: TimeZone? = nil) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar(in: timeZone ?? self.timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? self.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    static func startOfDay(for date: Date = Date(), in timeZone: TimeZone? = nil) -> Date {
        calendar(in: timeZone ?? self.timeZone).startOfDay(for: date)
    }

    static func monthStart(for date: Date = Date(), in timeZone: TimeZone? = nil) -> Date {
        let calendar = calendar(in: timeZone ?? self.timeZone)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
