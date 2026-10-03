import Combine
import Foundation

/// Each report section owns a resource so pagination and failures stay independent.
/// Values are visible only for the exact current request and session; a delayed
/// response cannot repopulate a different customer's or permission scope's report.
@MainActor
final class CustomerAnalyticsResource<Value, Scope: Hashable>: ObservableObject {
    @Published private(set) var loading = false
    @Published private(set) var revision = 0
    private var scope: Scope?
    private var result: Value?
    private var failure: String?
    private var generation = 0

    func value(for scope: Scope?) -> Value? {
        guard scope != nil, self.scope == scope else { return nil }
        return result
    }

    func error(for scope: Scope?) -> String? {
        guard scope != nil, self.scope == scope else { return nil }
        return failure
    }

    func load(scope: Scope?, debounce: Bool = false, operation: () async throws -> Value) async {
        generation += 1
        let request = generation
        self.scope = scope
        result = nil
        failure = nil
        loading = scope != nil
        revision += 1
        guard scope != nil else { return }
        defer {
            if generation == request {
                loading = false
                revision += 1
            }
        }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            let response = try await operation()
            try Task.checkCancellation()
            guard generation == request else { return }
            result = response
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            failure = error is CancellationError ? nil : error.localizedDescription
        }
    }
}
