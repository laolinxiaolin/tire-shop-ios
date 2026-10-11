import Foundation

enum CalendarDateInput {
    /// Forms accept one canonical calendar day, never DateFormatter's
    /// normalization of impossible days or a partially parsed timestamp.
    static func serverValue(_ value: String, label: String) throws -> String? {
        guard let day = value.nilIfBlank else { return nil }
        guard CheckDates.isValid(day) else {
            throw APIError(status: 400, message: "\(label) must be a valid date using YYYY-MM-DD.")
        }
        return "\(day)T00:00:00.000Z"
    }
}
