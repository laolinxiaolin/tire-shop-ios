import XCTest
@testable import TireShop

@MainActor
final class ApprovalHistoryTests: XCTestCase {
    private func request(_ id: String, status: String, decidedAt: String) throws -> ApprovalRequest {
        try JSONDecoder().decode(ApprovalRequest.self, from: Data("""
        {"id":"\(id)","action":"inventory.adjust","status":"\(status)","requestedById":"user",
         "requestedBy":{"id":"user","fullName":"User","email":"user@example.com"},
         "requestedAt":"2026-09-01T12:00:00Z","decidedAt":"\(decidedAt)"}
        """.utf8))
    }

    func testHistoryFetchesEveryDecidedStatusAndLaterPagesInDecisionOrder() async throws {
        var requests: [String: [Int]] = [:]
        let rows = try await ApprovalHistoryLoader.load { status, page, size in
            XCTAssertEqual(size, 50)
            XCTAssertNotEqual(status, "PENDING")
            requests[status, default: []].append(page)
            switch status {
            case "EXECUTED":
                let ids = page == 1 ? (0..<50).map { "executed-\($0)" } : ["past-first-page"]
                return Paged(items: try ids.map { try self.request($0, status: status, decidedAt: "2026-09-20T12:00:00Z") },
                    total: 51, page: page, pageSize: size)
            case "DENIED":
                return Paged(items: [try self.request("new-denial", status: status, decidedAt: "2026-09-21T12:00:00Z")],
                    total: 1, page: page, pageSize: size)
            default:
                return Paged(items: [], total: 0, page: page, pageSize: size)
            }
        }
        XCTAssertEqual(Set(requests.keys), ["EXECUTED", "DENIED", "CANCELLED", "FAILED"])
        XCTAssertEqual(requests["EXECUTED"], [1, 2])
        XCTAssertEqual(rows.count, 52)
        XCTAssertEqual(rows.first?.id, "new-denial")
        XCTAssertTrue(rows.contains { $0.id == "past-first-page" })
    }

    func testLaterPageFailureDoesNotSilentlyPresentIncompleteHistory() async throws {
        do {
            _ = try await ApprovalHistoryLoader.load { status, page, size in
                if status == "EXECUTED" {
                    if page == 2 { throw URLError(.notConnectedToInternet) }
                    return Paged(items: [try self.request("first", status: status, decidedAt: "2026-09-20T12:00:00Z")],
                        total: 51, page: page, pageSize: size)
                }
                return Paged(items: [], total: 0, page: page, pageSize: size)
            }
            XCTFail("A failed page must offer retry instead of claiming history is complete")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }
}
