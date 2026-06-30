import SwiftUI

@main
struct TireShopApp: App {
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
        }
    }
}
