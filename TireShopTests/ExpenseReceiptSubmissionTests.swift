import XCTest
@testable import TireShop

@MainActor
final class ExpenseReceiptSubmissionTests: XCTestCase {
    private enum Failure: Error {
        case offline
    }

    private func draft(_ name: String) -> DocumentUploadDraft {
        DocumentUploadDraft(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            filename: name,
            mimeType: "image/jpeg"
        )
    }

    func testCreationResponseDecodesExpenseWithoutHistoryReceiptCount() throws {
        let json = Data("""
        {"id":"expense-1","amount":12.5,"expenseCode":"6010","paidFromCode":"1000"}
        """.utf8)
        let response = try JSONDecoder().decode(ExpenseCreateResponse.self, from: json)
        XCTAssertEqual(response.id, "expense-1")
    }

    func testReceiptRetryReusesExpenseAndOnlyUploadsRemainingReceipts() async throws {
        let submission = ExpenseReceiptSubmission()
        submission.pendingReceipts = [draft("first.jpg"), draft("second.jpg")]
        var creates = 0
        var uploads: [String] = []

        do {
            try await submission.submit {
                creates += 1
                return ExpenseCreateResponse(id: "expense-1")
            } upload: { expenseId, receipt in
                XCTAssertEqual(expenseId, "expense-1")
                if receipt.filename == "second.jpg" { throw Failure.offline }
                uploads.append(receipt.filename)
            }
            XCTFail("The second upload should fail")
        } catch Failure.offline {
            // The expense and first attachment have already been saved.
        }

        XCTAssertFalse(submission.saving)
        XCTAssertEqual(submission.createdExpenseId, "expense-1")
        XCTAssertEqual(submission.pendingReceipts.map(\.filename), ["second.jpg"])

        try await submission.submit {
            creates += 1
            return ExpenseCreateResponse(id: "duplicate-expense")
        } upload: { expenseId, receipt in
            XCTAssertEqual(expenseId, "expense-1")
            uploads.append(receipt.filename)
        }

        XCTAssertEqual(creates, 1)
        XCTAssertEqual(uploads, ["first.jpg", "second.jpg"])
        XCTAssertTrue(submission.pendingReceipts.isEmpty)
        XCTAssertFalse(submission.saving)
    }

    func testFailedExpenseCreationKeepsReceiptsAndDoesNotUpload() async {
        let submission = ExpenseReceiptSubmission()
        submission.pendingReceipts = [draft("receipt.jpg")]
        do {
            try await submission.submit {
                throw Failure.offline
            } upload: { _, _ in
                XCTFail("Do not upload before the expense is saved")
            }
            XCTFail("Creation should fail")
        } catch {}

        XCTAssertNil(submission.createdExpenseId)
        XCTAssertEqual(submission.pendingReceipts.count, 1)
        XCTAssertFalse(submission.saving)
    }

    func testDiscardingPreparedReceiptRemovesTemporaryFile() throws {
        let submission = ExpenseReceiptSubmission()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("receipt".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        submission.pendingReceipts = [DocumentUploadDraft(url: url, filename: "receipt.jpg", mimeType: "image/jpeg")]

        submission.pendingReceipts.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
