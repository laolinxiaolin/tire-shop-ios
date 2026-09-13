import Foundation

enum CheckDepositStatus: String, Codable, Equatable {
    case dueToday
    case overdue
    case unscheduled
    case future
}

/// Check schedules are calendar dates, never UTC timestamps. Keep validation
/// separate from DateFormatter, which accepts some noncanonical date strings.
enum CheckDates {
    static func isValid(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), year > 0,
              let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(value.suffix(2)) else { return false }
        let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }

    static func string(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        ShopClock.dayString(from: date, in: timeZone)
    }

    static func date(_ value: String, in timeZone: TimeZone? = nil) -> Date? {
        guard isValid(value) else { return nil }
        return ShopClock.date(fromDayString: value, in: timeZone)
    }

    static func status(plannedDepositDate: String?, asOf: String) -> CheckDepositStatus {
        guard let plannedDepositDate, isValid(plannedDepositDate) else { return .unscheduled }
        if plannedDepositDate < asOf { return .overdue }
        if plannedDepositDate == asOf { return .dueToday }
        return .future
    }
}

extension Notification.Name {
    static let checkRegisterDidChange = Notification.Name("tireShop.checkRegisterDidChange")
}

enum CheckRegisterEvents {
    /// NotificationCenter invokes subscribers synchronously. Deliver refreshes
    /// on the main actor because the check screens read their UI state there.
    @MainActor
    static func changed() {
        NotificationCenter.default.post(name: .checkRegisterDidChange, object: nil)
    }
}
