import Foundation

@main
enum CheckDepositDraftChecks {
    static func main() {
        let accountCodes = ["1040", "1000", "1020", "1010"]
        check(CheckDepositDraft.initialAccountCode(preset: "1010", accountCodes: accountCodes, fallbackIndex: 0) == "1010",
              "The checks preset follows account code, regardless of display order")
        check(CheckDepositDraft.initialAccountCode(preset: "1020", accountCodes: accountCodes, fallbackIndex: 1) == "1020",
              "The bank preset follows account code")
        check(CheckDepositDraft.initialAccountCode(preset: "1020", accountCodes: ["1040", "1000", "1010"], fallbackIndex: 1).isEmpty,
              "A missing preset stays blank instead of selecting cash")
        check(CheckDepositDraft.initialAccountCode(preset: nil, accountCodes: accountCodes, fallbackIndex: 0) == "1040",
              "Ordinary transfers preserve their first-account default")
        check(CheckDepositDraft.initialAccountCode(preset: nil, accountCodes: [], fallbackIndex: 1).isEmpty,
              "An empty account list has no selected account")

        let future = CheckDepositDraft.SelectedCheck(id: "future", amount: 125.5, plannedDepositDate: "2026-09-20")
        let undated = CheckDepositDraft.SelectedCheck(id: "undated", amount: 45, plannedDepositDate: nil)
        let due = CheckDepositDraft.SelectedCheck(id: "due", amount: 10, plannedDepositDate: "2026-09-12")
        let overdue = CheckDepositDraft.SelectedCheck(id: "overdue", amount: 20, plannedDepositDate: "2026-09-11")
        var draft = CheckDepositDraft(
            fromCode: "1010", toCode: "1020", amount: "", fee: "2.50", reference: "DEP-1", note: "Deposit",
            today: "2026-09-12", selectedChecks: [future, undated, due]
        )
        check(draft.needsConfirmation, "Selected future and undated checks require review")
        check(!draft.isConfirmed(by: nil), "A first submit does not approve an early deposit")
        check(draft.isConfirmed(by: draft), "An explicitly reviewed, unchanged draft may submit or retry")

        let edits: [(String, (inout CheckDepositDraft) -> Void)] = [
            ("source", { $0.fromCode = "1000" }),
            ("destination", { $0.toCode = "1040" }),
            ("amount", { $0.amount = "100" }),
            ("fee", { $0.fee = "2.5" }),
            ("reference", { $0.reference = "DEP-2" }),
            ("note", { $0.note = "Edited" }),
            ("shop midnight", { $0.today = "2026-09-13" }),
            ("selection", { $0.selectedChecks.append(overdue) }),
            ("check amount", {
                $0.selectedChecks[0] = .init(id: future.id, amount: 126, plannedDepositDate: future.plannedDepositDate)
            }),
            ("check date", {
                $0.selectedChecks[0] = .init(id: future.id, amount: future.amount, plannedDepositDate: "2026-09-21")
            })
        ]
        for (name, edit) in edits {
            var edited = draft
            edit(&edited)
            check(!edited.isConfirmed(by: draft), "Changing \(name) invalidates the reviewed draft")
        }

        draft.selectedChecks = [due, overdue]
        check(!draft.needsConfirmation, "Only selected dates matter; due and overdue checks submit directly")
        draft.selectedChecks = [undated]
        check(draft.needsConfirmation, "An undated check alone requires confirmation")
        draft.selectedChecks = [.init(id: "invalid", amount: 5, plannedDepositDate: "2026-02-30")]
        check(draft.needsConfirmation, "An invalid backend date is treated as unscheduled")
        draft.fromCode = "1000"
        check(!draft.needsConfirmation, "An ordinary cash transfer never asks for check approval")
        print("ok check deposit defaults and exact-draft confirmation checks")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("fail: \(message)") }
    }
}
