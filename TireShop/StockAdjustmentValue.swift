import Foundation

enum StockAdjustmentValue {
    static func delta(_ value: String, counted: Bool, onHand: Int) throws -> Int {
        guard let text = value.nilIfBlank else { return 0 }
        guard let number = Int(text), !counted || number >= 0 else {
            throw APIError(status: 400, message: counted
                ? "Enter a whole counted quantity of zero or greater."
                : "Enter a whole-number stock change.")
        }
        let change = counted ? number.subtractingReportingOverflow(onHand) : (partialValue: number, overflow: false)
        guard !change.overflow, !onHand.addingReportingOverflow(change.partialValue).overflow else {
            throw APIError(status: 400, message: "The stock quantity is too large.")
        }
        return change.partialValue
    }
}
