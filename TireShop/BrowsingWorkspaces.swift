import SwiftUI

enum BrowsingRecordKind: String, Sendable {
    case sale
    case inventory
    case customer
}

struct BrowsingRecordChange: Sendable {
    let kind: BrowsingRecordKind
    let id: String
    let deleted: Bool
}

extension Notification.Name {
    static let browsingRecordDidChange = Notification.Name("tireShop.browsingRecordDidChange")
}

@MainActor
enum BrowsingRecords {
    static func changed(_ kind: BrowsingRecordKind, id: String, deleted: Bool = false) {
        NotificationCenter.default.post(
            name: .browsingRecordDidChange,
            object: BrowsingRecordChange(kind: kind, id: id, deleted: deleted)
        )
    }
}

enum BrowsingWorkspaceLayout {
    /// Leaves enough room for a useful scan column and a readable detail pane.
    /// The outer app sidebar can collapse independently before this workspace
    /// falls back to the compact push-navigation workflow.
    static func usesSplitView(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular && width >= 760
    }
}

enum SaleWorkspaceLayout {
    static func showsCatalog(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular && width >= 760
    }
}

/// The app shell already owns navigation. These panes share that stack so a
/// second split-view toolbar doesn't consume another row above the filters.
struct BrowsingWorkspaceColumns<ListPane: View, DetailPane: View>: View {
    let width: CGFloat
    @ViewBuilder let list: () -> ListPane
    @ViewBuilder let detail: () -> DetailPane

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(width: min(420, max(320, width * 0.38)))
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct BrowsingSelectionPrompt: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}
