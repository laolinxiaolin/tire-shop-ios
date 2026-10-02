import XCTest
@testable import TireShop

@MainActor
final class CustomerAnalyticsStoreTests: XCTestCase {
    func testChangingScopeImmediatelyHidesPreviousValuesAndErrors() async {
        let resource = CustomerAnalyticsResource<String, String>()
        await resource.load(scope: "customer-a:last-month") { "old report" }
        XCTAssertEqual(resource.value(for: "customer-a:last-month"), "old report")
        XCTAssertNil(resource.value(for: "customer-b:this-month"))
        XCTAssertNil(resource.value(for: nil))

        await resource.load(scope: "customer-b:this-month") { throw URLError(.timedOut) }
        XCTAssertNotNil(resource.error(for: "customer-b:this-month"))
        XCTAssertNil(resource.error(for: "customer-a:last-month"))
        XCTAssertNil(resource.value(for: "customer-a:last-month"))
    }

    func testLateResponseCannotReplaceNewFilterResults() async throws {
        let resource = CustomerAnalyticsResource<String, String>()
        let started = expectation(description: "Old filter request started")
        var oldResponse: CheckedContinuation<String, Error>?
        let oldRequest = Task {
            await resource.load(scope: "old") {
                try await withCheckedThrowingContinuation {
                    oldResponse = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await resource.load(scope: "new") { "current report" }
        try XCTUnwrap(oldResponse).resume(returning: "outdated report")
        await oldRequest.value

        XCTAssertEqual(resource.value(for: "new"), "current report")
        XCTAssertNil(resource.value(for: "old"))
        XCTAssertFalse(resource.loading)
        XCTAssertNil(resource.error(for: "new"))
    }

    func testPermissionRevocationInvalidatesInflightDataAndSkipsRequests() async throws {
        let resource = CustomerAnalyticsResource<String, String>()
        let started = expectation(description: "Permitted request started")
        var response: CheckedContinuation<String, Error>?
        let request = Task {
            await resource.load(scope: "staff-with-permission") {
                try await withCheckedThrowingContinuation {
                    response = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await resource.load(scope: nil) {
            XCTFail("Invalid filters or revoked permissions must not reach the API")
            return "unexpected"
        }
        try XCTUnwrap(response).resume(returning: "restricted report")
        await request.value

        XCTAssertNil(resource.value(for: "staff-with-permission"))
        XCTAssertNil(resource.value(for: nil))
        XCTAssertFalse(resource.loading)
    }

    func testCancelledOperationCannotPublishItsResult() async throws {
        let resource = CustomerAnalyticsResource<String, String>()
        let started = expectation(description: "Request started")
        var response: CheckedContinuation<String, Error>?
        let request = Task {
            await resource.load(scope: "report") {
                try await withCheckedThrowingContinuation {
                    response = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        try XCTUnwrap(response).resume(returning: "cancelled report")
        await request.value

        XCTAssertNil(resource.value(for: "report"))
        XCTAssertNil(resource.error(for: "report"))
        XCTAssertFalse(resource.loading)
    }

    func testIndependentSectionsRetainSuccessfulDataWhenAnotherSectionFails() async {
        let summary = CustomerAnalyticsResource<String, String>()
        let products = CustomerAnalyticsResource<String, String>()
        let history = CustomerAnalyticsResource<String, String>()
        await summary.load(scope: "period") { "summary" }
        await products.load(scope: "page-1") { "product page 1" }
        await history.load(scope: "page-1") { throw URLError(.cannotConnectToHost) }

        XCTAssertEqual(summary.value(for: "period"), "summary")
        XCTAssertEqual(products.value(for: "page-1"), "product page 1")
        XCTAssertNotNil(history.error(for: "page-1"))

        await products.load(scope: "page-2") { "product page 2" }
        await history.load(scope: "page-1") { "history page 1" }
        XCTAssertEqual(summary.value(for: "period"), "summary")
        XCTAssertEqual(products.value(for: "page-2"), "product page 2")
        XCTAssertEqual(history.value(for: "page-1"), "history page 1")
        XCTAssertNil(history.error(for: "page-1"))
    }

    func testSameScopeRefreshIgnoresOlderFailure() async throws {
        let resource = CustomerAnalyticsResource<String, String>()
        let started = expectation(description: "Original request started")
        var oldResponse: CheckedContinuation<String, Error>?
        let oldRequest = Task {
            await resource.load(scope: "same-period") {
                try await withCheckedThrowingContinuation {
                    oldResponse = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await resource.load(scope: "same-period") { "refreshed report" }
        try XCTUnwrap(oldResponse).resume(throwing: URLError(.timedOut))
        await oldRequest.value

        XCTAssertEqual(resource.value(for: "same-period"), "refreshed report")
        XCTAssertNil(resource.error(for: "same-period"))
        XCTAssertFalse(resource.loading)
    }

    func testEventDatesUseResponseTimezone() {
        XCTAssertEqual(
            AnalyticsDisplay.date("2026-10-01T00:30:00.000Z", timezone: "America/Los_Angeles", locale: Locale(identifier: "en_US")),
            "Sep 30, 2026"
        )
        XCTAssertEqual(
            AnalyticsDisplay.date("2026-10-01T00:30:00.000Z", timezone: "Asia/Shanghai", locale: Locale(identifier: "en_US")),
            "Oct 1, 2026"
        )
        XCTAssertEqual(AnalyticsDisplay.date(nil, timezone: "UTC", locale: Locale(identifier: "en_US")), "—")
    }
}
