import SwiftUI

/// Only the date value carries the existing Paid/Invoiced background colors.
/// Surrounding labels and the date itself retain the normal text color.
struct CheckDepositDateLabel: View {
    let plannedDepositDate: String?
    let asOf: String

    @EnvironmentObject private var i18n: I18nStore

    private var status: CheckDepositStatus {
        CheckDates.status(plannedDepositDate: plannedDepositDate, asOf: asOf)
    }

    private var background: Color {
        switch status {
        case .dueToday, .overdue: return Theme.salesInvoicedBackground
        case .future, .unscheduled: return Theme.salesPaidBackground
        }
    }

    var body: some View {
        Text(plannedDepositDate.flatMap { CheckDates.isValid($0) ? Self.calendarLabel($0) : nil }
             ?? i18n.t("checks.unscheduled"))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    static func calendarLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return value }
        return "\(month)/\(day)/\(parts[0])"
    }
}
