import XCTest
@testable import TireShop

@MainActor
final class OrdersListStoreTests: XCTestCase {
    private func order(_ id: String, status: String = "PENDING") throws -> Order {
        try JSONDecoder().decode(Order.self, from: Data("""
        {"id":"\(id)","customerId":"customer","customer":{"id":"customer","name":"Customer"},
         "status":"\(status)","location":"MAIN","fulfillment":"PICKUP","subtotal":"100",
         "total":"100","createdAt":"2026-09-22T12:00:00Z","lines":[]}
        """.utf8))
    }

    func testLoadsLaterPagesAndRetriesFailedPageWithoutDuplicates() async throws {
        var requests: [Int] = []
        var fail = true
        let store = OrdersListStore(pageSize: 2) { status, page, size in
            XCTAssertEqual(status, "PENDING")
            XCTAssertEqual(size, 2)
            requests.append(page)
            if page == 2 && fail { throw URLError(.notConnectedToInternet) }
            return Paged(items: try (page == 1 ? ["a", "b"] : ["b", "c"]).map { try self.order($0) },
                total: 3, page: page, pageSize: size)
        }
        await store.reload(status: "PENDING")
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        XCTAssertNotNil(store.errorMessage)
        fail = false
        await store.retry()
        XCTAssertEqual(requests, [1, 2, 2])
        XCTAssertEqual(store.items.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(store.hasMore)
        XCTAssertNil(store.errorMessage)
    }

    func testFailedRefreshMustRetryFirstPageBeforeLoadingMore() async throws {
        var pages: [Int] = []
        var fail = false
        let store = OrdersListStore(pageSize: 1) { _, page, size in
            pages.append(page)
            if fail { throw URLError(.notConnectedToInternet) }
            return Paged(items: [try self.order("a")], total: 3, page: page, pageSize: size)
        }
        await store.reload(status: "PENDING")
        fail = true
        await store.reload(status: "PENDING")
        await store.loadMore()
        XCTAssertEqual(pages, [1, 1])
        fail = false
        await store.retry()
        XCTAssertEqual(pages, [1, 1, 1])
        XCTAssertNil(store.errorMessage)
    }

    func testStatusChangeRejectsAnOlderPageResponse() async throws {
        let started = expectation(description: "Older page started")
        var completion: CheckedContinuation<Paged<Order>, Error>?
        let store = OrdersListStore(pageSize: 1) { status, page, size in
            if status == "PENDING" && page == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    completion = continuation
                    started.fulfill()
                }
            }
            return Paged(items: [try self.order(status, status: status)], total: 2, page: page, pageSize: size)
        }
        await store.reload(status: "PENDING")
        let oldRequest = Task { await store.loadMore() }
        await fulfillment(of: [started], timeout: 1)
        await store.reload(status: "CONFIRMED")
        completion?.resume(returning: Paged(items: [try order("stale")], total: 99, page: 2, pageSize: 1))
        await oldRequest.value
        XCTAssertEqual(store.items.map(\.id), ["CONFIRMED"])
        XCTAssertEqual(store.total, 2)
        XCTAssertFalse(store.loading)
    }
}
