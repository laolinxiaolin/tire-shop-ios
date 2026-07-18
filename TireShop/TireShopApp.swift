import SwiftUI

@main
struct TireShopApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var auth = AuthStore()
    @StateObject private var tabs = TabsStore()
    @StateObject private var quote = QuoteStore()
    @StateObject private var i18n = I18nStore()

    var body: some Scene {
        WindowGroup {
            RootGateView()
                .environmentObject(auth)
                .environmentObject(tabs)
                .environmentObject(quote)
                .environmentObject(i18n)
                .environment(\.locale, i18n.language.locale)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await TapToPayTerminalController.shared.warmUpForForeground() }
                    }
                }
        }
    }
}
