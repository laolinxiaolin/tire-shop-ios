import SwiftUI

@main
struct TireShopApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var auth = AuthStore()
    @StateObject private var tabs = TabsStore()
    @StateObject private var i18n = I18nStore()
    @StateObject private var shopClock = ShopClockStore()

    var body: some Scene {
        WindowGroup {
            TireShopSceneRoot()
                .environmentObject(auth)
                .environmentObject(tabs)
                .environmentObject(i18n)
                .environmentObject(shopClock)
                .environment(\.locale, i18n.language.locale)
                .environment(\.timeZone, shopClock.timeZone)
                .environment(\.calendar, shopClock.calendar)
                .onChange(of: scenePhase) { _, phase in
                    DebugLayoutLog.event("scenePhase=\(String(describing: phase))")
                    if phase == .active {
                        Task { await TapToPayTerminalController.shared.warmUpForForeground() }
                    }
                }
        }
    }
}

private struct TireShopSceneRoot: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var quote = QuoteStore()
    @StateObject private var navigation = AppNavigationModel()

    var body: some View {
        RootGateView()
            .environmentObject(quote)
            .environmentObject(navigation)
            .debugLayoutProbe("SceneRoot")
            .debugKeyboardDiagnostics()
            .onChange(of: auth.user?.id) { oldUserID, newUserID in
                guard oldUserID != newUserID else { return }
                navigation.resetForSessionChange()
            }
    }
}
