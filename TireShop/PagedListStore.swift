import Combine
import Foundation
import SwiftUI

/// Keeps pagination tied to the filter that produced the first page.
@MainActor
final class PagedListStore<Row: Codable & Identifiable, Scope: Equatable>: ObservableObject {
    typealias Loader = (Scope, Int, Int) async throws -> Paged<Row>

    @Published private(set) var items: [Row] = []
    @Published private(set) var total = 0
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var errorMessage: String?

    private let loader: Loader
    private let pageSize: Int
    private var scope: Scope?
    private var page = 0
    private var generation = 0
    private var moreAvailable = false
    private var failedPage: Int?

    var hasMore: Bool { moreAvailable }

    init(pageSize: Int = 50, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
    }

    func reload(scope: Scope, debounce: Bool = false) async {
        generation += 1
        let request = generation
        if self.scope != scope {
            items = []
            total = 0
            page = 0
            loaded = false
            moreAvailable = false
        }
        self.scope = scope
        loading = true
        errorMessage = nil
        failedPage = nil
        defer { if request == generation { loading = false; loaded = true } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            let result = try await loader(scope, 1, pageSize)
            try Task.checkCancellation()
            guard request == generation else { return }
            accept(result, replacing: true)
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            failedPage = 1
        }
    }

    func loadMore() async {
        guard !loading, hasMore, failedPage != 1, let scope else { return }
        let request = generation
        let requestedPage = page + 1
        loading = true
        errorMessage = nil
        failedPage = nil
        defer { if request == generation { loading = false } }
        do {
            let result = try await loader(scope, requestedPage, pageSize)
            try Task.checkCancellation()
            guard request == generation else { return }
            accept(result, replacing: false)
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            failedPage = requestedPage
        }
    }

    func retry() async {
        guard !loading, let scope else { return }
        if let failedPage, failedPage > 1 { await loadMore() }
        else { await reload(scope: scope) }
    }

    private func accept(_ result: Paged<Row>, replacing: Bool) {
        var next = replacing ? [] : items
        var positions = Dictionary(uniqueKeysWithValues: next.enumerated().map { ($0.element.id, $0.offset) })
        for row in result.items {
            if let index = positions[row.id] { next[index] = row }
            else { positions[row.id] = next.count; next.append(row) }
        }
        items = next
        total = result.total
        page = result.page
        moreAvailable = !result.items.isEmpty && result.page * max(1, result.pageSize) < result.total
    }
}

struct PagedListFooter<Row: Codable & Identifiable, Scope: Equatable>: View {
    @ObservedObject var store: PagedListStore<Row, Scope>

    var body: some View {
        if store.loading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity)
        } else if let error = store.errorMessage {
            VStack(spacing: Theme.Space.xs) {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
                Button("Retry") { Task { await store.retry() } }
            }
            .frame(maxWidth: .infinity)
        } else if store.hasMore {
            Button("Load more (\(store.items.count) of \(store.total))") {
                Task { await store.loadMore() }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
