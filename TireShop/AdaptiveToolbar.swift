import SwiftUI

/// Uses the system overflow when built with an iOS 27 SDK, while retaining
/// the same actions on iOS 17–26 and when building with an older SDK.
struct AppOverflowMenu<Content: View>: ToolbarContent {
    let title: String
    var isLoading = false
    var isDisabled = false
    @ViewBuilder let content: Content

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if TIRESHOP_HAS_TOOLBAR_OVERFLOW_MENU
        if #available(iOS 27.0, *) {
            ToolbarOverflowMenu {
                content.disabled(isDisabled || isLoading)
            }
            if isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityLabel(Text(LocalizedStringKey(title)))
                }
            }
        } else {
            legacyMenu
        }
        #else
        legacyMenu
        #endif
    }

    private var legacyMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                content
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Label(LocalizedStringKey(title), systemImage: "ellipsis")
                }
            }
            .accessibilityLabel(Text(LocalizedStringKey(title)))
            .disabled(isDisabled || isLoading)
        }
    }
}
