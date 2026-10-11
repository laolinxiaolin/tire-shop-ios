import Foundation

enum PagedSelection {
    /// A partial refresh cannot prove that an off-page selection disappeared.
    /// A different filter starts a new selection; a complete snapshot can prune.
    static func reconciled<ID: Hashable>(
        _ selected: Set<ID>, loadedIDs: Set<ID>, complete: Bool, scopeChanged: Bool = false
    ) -> Set<ID> {
        if scopeChanged { return [] }
        return complete ? selected.intersection(loadedIDs) : selected
    }
}
