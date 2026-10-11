import XCTest
@testable import TireShop

@MainActor
final class PagedListStoreTests: XCTestCase {
    private struct Row: Codable, Identifiable, Equatable {
        let id: String
        var name: String = "Row"
    }

    func testFirstPageIsUsableBeforeLaterPagesAreRequested() async {
        var requests: [Int] = []
        let store = PagedListStore<Row, String>(pageSize: 50) { scope, page, size in
            XCTAssertEqual(scope, "matching")
            requests.append(page)
            let rows = page == 1 ? (1...50).map { Row(id: "\($0)") } : [Row(id: "51")]
            return Paged(items: rows, total: 51, page: page, pageSize: size)
        }
        await store.reload(scope: "matching")
        XCTAssertEqual(requests, [1])
        XCTAssertEqual(store.items.count, 50)
        XCTAssertEqual(store.total, 51)
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(requests, [1, 2])
        XCTAssertEqual(store.items.last?.id, "51")
        XCTAssertFalse(store.hasMore)
    }

    func testFailedLaterPageCanRetryWithoutDroppingOrDuplicatingRows() async {
        var fail = true
        var requests: [Int] = []
        let store = PagedListStore<Row, String>(pageSize: 2) { _, page, size in
            requests.append(page)
            if page == 2 && fail { throw URLError(.notConnectedToInternet) }
            let rows = page == 1 ? [Row(id: "a"), Row(id: "b")]
                : [Row(id: "b", name: "Updated"), Row(id: "c")]
            return Paged(items: rows, total: 3, page: page, pageSize: size)
        }
        await store.reload(scope: "all")
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        XCTAssertNotNil(store.errorMessage)
        fail = false
        await store.retry()
        XCTAssertEqual(requests, [1, 2, 2])
        XCTAssertEqual(store.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(store.items[1].name, "Updated")
        XCTAssertNil(store.errorMessage)
    }

    func testChangingFilterRejectsLateContinuationFromOldFilter() async {
        let started = expectation(description: "Old continuation started")
        var completion: CheckedContinuation<Paged<Row>, Error>?
        let store = PagedListStore<Row, String>(pageSize: 1) { scope, page, size in
            if scope == "old", page == 2 {
                return try await withCheckedThrowingContinuation { continuation in
                    completion = continuation
                    started.fulfill()
                }
            }
            return Paged(items: [Row(id: scope)], total: 2, page: page, pageSize: size)
        }
        await store.reload(scope: "old")
        let continuation = Task { await store.loadMore() }
        await fulfillment(of: [started], timeout: 1)
        await store.reload(scope: "new")
        completion?.resume(returning: Paged(items: [Row(id: "stale")], total: 99, page: 2, pageSize: 1))
        await continuation.value
        XCTAssertEqual(store.items.map(\.id), ["new"])
        XCTAssertEqual(store.total, 2)
        XCTAssertFalse(store.loading)
    }

    func testFailedRefreshMustBeRetriedBeforeExtendingOldSnapshot() async {
        var requests: [Int] = []
        var fail = false
        let store = PagedListStore<Row, String>(pageSize: 1) { _, page, size in
            requests.append(page)
            if fail { throw URLError(.notConnectedToInternet) }
            return Paged(items: [Row(id: "a")], total: 3, page: page, pageSize: size)
        }
        await store.reload(scope: "all")
        fail = true
        await store.reload(scope: "all")
        await store.loadMore()
        XCTAssertEqual(requests, [1, 1])
        XCTAssertEqual(store.items.map(\.id), ["a"])
        fail = false
        await store.retry()
        XCTAssertEqual(requests, [1, 1, 1])
        XCTAssertNil(store.errorMessage)
    }

    func testServerPageSizeDeterminesContinuationWhenRequestedSizeIsClamped() async {
        let store = PagedListStore<Row, String>(pageSize: 50) { _, page, _ in
            Paged(items: [Row(id: "\(page)")], total: 2, page: page, pageSize: 1)
        }
        await store.reload(scope: "all")
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["1", "2"])
        XCTAssertFalse(store.hasMore)
    }
}
