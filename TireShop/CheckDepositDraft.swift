import Foundation

/// Approval for an early deposit belongs to the complete draft the operator
/// reviewed. Keep raw form values so even an edit with the same numeric value
/// requires another review, and include the shop day for midnight rollover.
struct CheckDepositDraft: Equatable {
    struct SelectedCheck: Equatable {
        let id: String
        let amount: Double
        let plannedDepositDate: String?
    }

    var fromCode: String
    var toCode: String
    var amount: String
    var fee: String
    var reference: String
    var note: String
    var today: String
    var selectedChecks: [SelectedCheck]

    var needsConfirmation: Bool {
        fromCode == "1010" && selectedChecks.contains { check in
            guard let date = check.plannedDepositDate, CheckDates.isValid(date) else { return true }
            return date > today
        }
    }

    func isConfirmed(by reviewedDraft: Self?) -> Bool {
        needsConfirmation && reviewedDraft == self
    }

    /// Explicit presets never fall back to an unrelated account if missing.
    static func initialAccountCode(preset: String?, accountCodes: [String], fallbackIndex: Int) -> String {
        if let preset { return accountCodes.contains(preset) ? preset : "" }
        return accountCodes.indices.contains(fallbackIndex) ? accountCodes[fallbackIndex] : ""
    }
}
