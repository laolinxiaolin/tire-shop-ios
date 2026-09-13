import Foundation
import Combine

/// Totals and aging come from all matching bills, independent of loaded pages.
@MainActor
final class BalanceListStore<Row: Codable & Identifiable>: ObservableObject {
    typealias Loader = (Int, Int, String?) async throws -> BalancePage<Row>

    @Published private(set) var items: [Row] = []
    @Published private(set) var total = 0
    @Published private(set) var summary: BalanceSummary?
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?

    private let loader: Loader
    private let pageSize: Int
    private var query: String?
    private var page = 0
    private var generation = 0
    private var failedRequest: FailedRequest?

    private enum FailedRequest {
        case reload, loadMore
    }

    var hasMore: Bool { page > 0 && page * pageSize < total }

    init(pageSize: Int = 50, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
    }

    func reload(query: String, debounce: Bool = false) async {
        generation += 1
        let generation = generation
        let nextQuery = query.nilIfBlank
        if self.query != nextQuery {
            items = []
            total = 0
            summary = nil
            page = 0
            loaded = false
        }
        self.query = nextQuery
        loading = true
        errorMessage = nil
        failedRequest = nil
        defer { if generation == self.generation { loading = false; loaded = true } }
        do {
            if debounce { try await Task.sleep(nanoseconds: 300_000_000) }
            let result = try await loader(1, pageSize, nextQuery)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            items = Self.merging([], result.items)
            total = result.total
            summary = result.summary
            page = 1
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            failedRequest = .reload
        }
    }

    func loadMore() async {
        // A failed refresh must be retried before extending the old snapshot.
        // Otherwise scrolling could silently retain stale first-page balances.
        guard !loading, hasMore, failedRequest != .reload else { return }
        let generation = generation
        let nextPage = page + 1
        loading = true
        errorMessage = nil
        failedRequest = nil
        defer { if generation == self.generation { loading = false } }
        do {
            let result = try await loader(nextPage, pageSize, query)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            items = Self.merging(items, result.items)
            total = result.total
            summary = result.summary
            page = nextPage
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            failedRequest = .loadMore
        }
    }

    func retry() async {
        guard !loading else { return }
        if failedRequest == .loadMore {
            await loadMore()
        } else {
            await reload(query: query ?? "")
        }
    }

    private static func merging(_ current: [Row], _ incoming: [Row]) -> [Row] {
        var result = current
        var positions = Dictionary(uniqueKeysWithValues: current.enumerated().map { ($0.element.id, $0.offset) })
        for row in incoming {
            if let index = positions[row.id] {
                result[index] = row
            } else {
                positions[row.id] = result.count
                result.append(row)
            }
        }
        return result
    }
}
