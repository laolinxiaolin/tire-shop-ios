import SwiftUI
import UIKit

enum AppRoute: Hashable {
    case profile
    case customizeTabs
    case module(String)
    case tapToPayEducation
    case skuDetail(String)
    case skuForm(String?)
    case adjustStock(String)
    case saleDetail(String)
    case bestSellers(months: Int, warehouse: String?)
    case orderDetail(String)
    case editSale(String)
    case startReturn(saleId: String, saleRef: String?)
    case returnDetail(String)
    case workOrderDetail(String)
    case inventoryCountDetail(String)
    case newInventoryCount
    case transferDetail(String)
    case newTransfer
    case containerDetail(String)
    case supplierDetail(String)
    case vendorDetail(String)
    case paymentApplicationDetail(String)
    case paymentApplicationEditor(id: String?, vendorId: String?)
    case tapToPay(invoiceId: String, amount: Double, saleId: String?, saleRef: String?, customerName: String?)
    case customerDetail(id: String, name: String)
    case employeeDetail(String)
    case skuPicker
    case customerPicker
    case newCustomer
}

struct RootGateView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @EnvironmentObject private var quote: QuoteStore
    @EnvironmentObject private var shopClock: ShopClockStore

    var body: some View {
        Group {
            if !auth.ready {
                if let error = auth.restoreError {
                    VStack(spacing: Theme.Space.md) {
                        Text(i18n.t("login.restoreTitle"))
                            .font(.headline)
                        Text(i18n.t(error))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        PrimaryButton(title: i18n.t("common.retry")) {
                            if error == "login.sessionRemovalFailed" {
                                auth.signOut()
                            } else {
                                Task { await auth.restore() }
                            }
                        }
                        SecondaryButton(title: i18n.t("login.signIn")) {
                            auth.signOut()
                        }
                    }
                    .padding(Theme.Space.lg)
                } else {
                    LoadingView(label: i18n.t("common.loading"))
                }
            } else if let user = auth.user {
                if shopClock.isReady(for: user.id) {
                    RootNavigatorView()
                } else {
                    LoadingView(label: i18n.t("common.loading"))
                }
            } else {
                LoginView()
            }
        }
        .task {
            if !auth.ready {
                await auth.restore()
            }
        }
        .task(id: auth.user?.id) {
            if let userID = auth.user?.id {
                await shopClock.refresh(for: userID)
            } else {
                shopClock.resetSession()
            }
        }
        .onChange(of: auth.user?.id) { oldUserID, newUserID in
            guard oldUserID != newUserID else { return }
            DebugLayoutLog.event("authUserChanged old=\(oldUserID ?? "nil") new=\(newUserID ?? "nil")")
            quote.clear()
            TapToPayTerminalController.shared.resetForSessionChange()
        }
        .debugLayoutProbe("RootGate")
    }
}

/// App-level keyboard session state.
///
/// Submitting the login form arms iOS's AutoFill "save this password?" flow.
/// Because a successful sign-in immediately swaps `LoginView` for the
/// authenticated hierarchy, AutoFill can end up presenting its hidden save
/// controller into a hierarchy that no longer exists — the console shows
/// "Keyboard cannot present view controllers". The presentation fails, but the
/// keyboard session is left half-open: UIKit posts `keyboardWillShow` with a
/// 320–347pt frame and never posts the matching hide, so SwiftUI's keyboard
/// avoidance shrinks the authenticated root until the app is backgrounded.
///
/// A keyboard that is coming on screen while nothing in the app is first
/// responder is always one of these orphans, which is what `isOrphaned` detects.
enum KeyboardSession {
    /// Resigns first responder app-wide, synchronously.
    ///
    /// SwiftUI's `@FocusState` is only applied on the next update pass, which is
    /// too late to matter here — this lets AutoFill start and finish its
    /// save-password work while the login hierarchy is still mounted.
    @MainActor
    static func dismiss() {
        for window in windows {
            window.endEditing(true)
        }
    }

    /// Closes a keyboard session that has no first responder.
    ///
    /// The orphaned session can't be dismissed with `endEditing` — there is
    /// nothing to resign. Instead, give the keyboard a real responder to attach
    /// to and immediately resign it, which makes UIKit run its normal teardown
    /// and post the `keyboardWillHide` that never arrived. The stand-in field
    /// carries an empty `inputView`, so no keyboard becomes visible.
    @MainActor
    static func dismissOrphanedSession() {
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }

        let field = UITextField(frame: .zero)
        field.inputView = UIView()
        field.inputAccessoryView = UIView()
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.isHidden = true
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
        DebugLayoutLog.event("dismissOrphanedSession ran")
    }

    /// True when a keyboard geometry notification describes a keyboard moving on
    /// screen with no text input focused anywhere in the app.
    @MainActor
    static func isOrphaned(_ notification: Notification) -> Bool {
        guard
            let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
            let window = windows.first(where: \.isKeyWindow) ?? windows.first
        else { return false }

        // A keyboard parked at or below the bottom edge is on its way out.
        guard endFrame.height > 0, endFrame.minY < window.bounds.height else { return false }

        // `sendAction(to: nil)` walks the responder chain from the first
        // responder. Verified on device: with a field focused this captures the
        // `UITextField`; with nothing focused the box stays nil. Testing for
        // `UITextInput` rather than non-nil keeps it failing closed either way.
        let box = FirstResponderBox()
        UIApplication.shared.sendAction(
            #selector(UIResponder.tireShopCaptureFirstResponder(_:)),
            to: nil,
            from: box,
            for: nil
        )
        return !(box.responder is UITextInput)
    }

    #if DEBUG
    /// Names the responder `isOrphaned` resolves to, so the physical-device
    /// console can show whether detection is behaving.
    @MainActor
    static var debugFirstResponderDescription: String {
        let box = FirstResponderBox()
        UIApplication.shared.sendAction(
            #selector(UIResponder.tireShopCaptureFirstResponder(_:)),
            to: nil,
            from: box,
            for: nil
        )
        guard let responder = box.responder else { return "nil" }
        return "\(type(of: responder))\(responder is UITextInput ? "(textInput)" : "")"
    }
    #endif

    @MainActor
    private static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }
}

private final class FirstResponderBox {
    var responder: UIResponder?
}

private extension UIResponder {
    @objc func tireShopCaptureFirstResponder(_ sender: Any?) {
        (sender as? FirstResponderBox)?.responder = self
    }
}

struct RootNavigatorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabsStore
    @EnvironmentObject private var i18n: I18nStore
    @EnvironmentObject private var navigation: AppNavigationModel
    @State private var showTapToPayAnnouncement = false
    @StateObject private var checkReminders = CheckReminderStore()

    private var visiblePinned: [Destination] {
        tabs.pinned
            .compactMap(DestinationRegistry.destination(for:))
            .filter { DestinationRegistry.isVisible($0, auth: auth) }
    }

    private var visibleDestinations: [Destination] {
        DestinationRegistry.visibleDestinations(auth: auth)
    }

    private var groupedDestinations: [(DestinationGroup, [Destination])] {
        let byGroup = Dictionary(grouping: visibleDestinations, by: \.group)
        return DestinationGroup.allCases.compactMap { group in
            guard let items = byGroup[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    private var compactSelection: Binding<String> {
        Binding(
            get: { navigation.compactTab(pinnedKeys: visiblePinned.map(\.key)) },
            set: { navigation.selectCompactTab($0) }
        )
    }

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: {
                DestinationRegistry.destination(for: navigation.selectedDestinationKey) == nil
                    ? nil
                    : navigation.selectedDestinationKey
            },
            set: { key in
                if let key { navigation.selectDestination(key) }
            }
        )
    }

    var body: some View {
        if !tabs.ready {
            LoadingView(label: i18n.t("common.loading"))
        } else {
            GeometryReader { proxy in
                Group {
                    if usesSidebar(availableWidth: proxy.size.width) {
                        regularNavigation
                    } else {
                        compactNavigation
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                handleKeyboardGeometry(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                handleKeyboardGeometry(note)
            }
            .tint(Theme.primary)
            .environmentObject(checkReminders)
            .task(id: auth.user?.id) {
                checkReminders.reset(for: auth.user?.id)
                if auth.has("payments.collect") || auth.has("accounting.view") {
                    await checkReminders.refresh()
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                refreshCheckReminders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .checkRegisterDidChange)) { _ in
                refreshCheckReminders()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshCheckReminders() }
            }
            .fullScreenCover(isPresented: $showTapToPayAnnouncement) {
                TapToPayLaunchAnnouncementView(
                    canManageSettings: auth.has("settings.manage"),
                    onDone: markTapToPayAnnouncementSeen
                )
            }
            .onAppear {
                navigation.sanitize(visibleDestinationKeys: Set(visibleDestinations.map(\.key)))
                maybeShowTapToPayAnnouncement()
            }
            .onChange(of: auth.user?.id) { _, _ in
                maybeShowTapToPayAnnouncement()
            }
            .onChange(of: visibleDestinations.map(\.key)) { _, keys in
                navigation.sanitize(visibleDestinationKeys: Set(keys))
            }
            .debugLayoutProbe("RootNavigator")
        }
    }

    private var compactNavigation: some View {
        TabView(selection: compactSelection) {
            ForEach(visiblePinned) { destination in
                NavigationShell(
                    title: destination.localizedTitle(using: i18n),
                    pathOwner: destination.key
                ) {
                    DestinationView(destination: destination)
                }
                .tabItem {
                    Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                }
                .tag(destination.key)
            }

            NavigationShell(title: i18n.t("nav.more"), pathOwner: AppNavigationModel.moreKey) {
                MoreMenuView()
            }
            .tabItem {
                Label(i18n.t("nav.more"), systemImage: "line.3.horizontal")
            }
            .tag(AppNavigationModel.moreKey)
        }
    }

    private var regularNavigation: some View {
        NavigationSplitView(columnVisibility: $navigation.sidebarVisibility) {
            List(selection: sidebarSelection) {
                ForEach(groupedDestinations, id: \.0) { group, destinations in
                    Section(group.localizedTitle(using: i18n)) {
                        ForEach(destinations) { destination in
                            Label(
                                destination.localizedTitle(using: i18n),
                                systemImage: destination.systemImage
                            )
                            .tag(destination.key)
                        }
                    }
                }
            }
            .navigationTitle("TireShop")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    navigation.append(.customizeTabs, to: navigation.selectedDestinationKey)
                } label: {
                    Label(i18n.t("more.customizeTabs"), systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, Theme.Space.md)
                }
                .buttonStyle(.plain)
                .background(.bar)
            }
        } detail: {
            if let destination = selectedDestination {
                NavigationShell(
                    title: destination.localizedTitle(using: i18n),
                    pathOwner: destination.key
                ) {
                    DestinationView(destination: destination)
                }
            } else {
                ContentUnavailableView(
                    i18n.t("screen.fallbackTitle"),
                    systemImage: "sidebar.left"
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var selectedDestination: Destination? {
        DestinationRegistry.destination(for: navigation.selectedDestinationKey).flatMap { destination in
            DestinationRegistry.isVisible(destination, auth: auth) ? destination : nil
        }
    }

    private func usesSidebar(availableWidth: CGFloat) -> Bool {
        horizontalSizeClass == .regular && availableWidth >= 700
    }

    private func handleKeyboardGeometry(_ notification: Notification) {
        guard KeyboardSession.isOrphaned(notification) else { return }
        DebugLayoutLog.event("orphanedKeyboardDetected")
        // Let UIKit finish the in-flight show before reclaiming the session.
        Task { @MainActor in
            KeyboardSession.dismissOrphanedSession()
        }
    }

    private func refreshCheckReminders() {
        guard scenePhase == .active, auth.has("payments.collect") || auth.has("accounting.view") else { return }
        Task { await checkReminders.refresh() }
    }

    private var tapToPayAnnouncementKey: String? {
        guard let userId = auth.user?.id else { return nil }
        return "ttpoiLaunchAnnouncementSeen.v1.\(userId)"
    }

    private func maybeShowTapToPayAnnouncement() {
        guard auth.has("payments.collect") || auth.has("settings.manage"), let key = tapToPayAnnouncementKey else { return }
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        showTapToPayAnnouncement = true
    }

    private func markTapToPayAnnouncementSeen() {
        if let key = tapToPayAnnouncementKey {
            UserDefaults.standard.set(true, forKey: key)
        }
        showTapToPayAnnouncement = false
    }
}

struct NavigationShell<Content: View>: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var navigation: AppNavigationModel

    let title: String
    let pathOwner: String
    let content: Content

    init(title: String, pathOwner: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.pathOwner = pathOwner
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: navigation.path(for: pathOwner)) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if auth.has("payments.collect") || auth.has("accounting.view") {
                        CheckReminderBanner {
                            NotificationCenter.default.post(name: .showCurrentChecks, object: nil)
                            navigation.showChecks()
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AvatarButton(name: auth.user?.fullName) {
                            navigation.append(.profile, to: pathOwner)
                        }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestinationView(route: route)
                }
        }
        .debugLayoutProbe("NavigationShell[\(title)]")
    }
}

struct DestinationView: View {
    @EnvironmentObject private var i18n: I18nStore

    let destination: Destination

    var body: some View {
        switch destination.key {
        case "dashboard":
            DashboardNativeView()
        case "notifications":
            NotificationsNativeView()
        case "newQuote":
            NewQuoteNativeView()
        case "sales":
            SalesListNativeView()
        case "orders":
            OrdersListNativeView()
        case "inventory":
            InventoryListNativeView()
        case "transfers":
            StockTransfersListNativeView()
        case "skuManagement":
            SkuManagementNativeView()
        case "storefrontManage":
            StorefrontManagementNativeView()
        case "tireAttributes":
            TireAttributesNativeView()
        case "brandInfo":
            BrandInfoNativeView()
        case "inventoryCounts":
            InventoryCountsListNativeView()
        case "stockAdjustments":
            StockAdjustmentsLogNativeView()
        case "purchasing":
            PurchasingNativeView()
        case "vendors":
            VendorsListNativeView()
        case "customers":
            CustomersListNativeView()
        case "customerRelations":
            CustomerRelationsNativeView()
        case "workOrders":
            WorkOrdersListNativeView()
        case "returns":
            ReturnsListNativeView()
        case "money":
            MoneyNativeView()
        case "accounting":
            AccountingNativeView()
        case "cashAccounts":
            CashAccountsNativeView()
        case "checks":
            ChecksNativeView()
        case "fet":
            FetNativeView()
        case "eod":
            EodNativeView()
        case "monthlySales":
            MonthlySalesNativeView()
        case "tapToPay":
            TapToPayEducationView()
        case "employees":
            EmployeesListNativeView()
        case "commissions":
            CommissionsNativeView()
        case "approvals":
            ApprovalsNativeView()
        case "activity":
            ActivityNativeView()
        case "users":
            UsersNativeView()
        case "roles":
            RolesNativeView()
        case "apiKeys":
            ApiKeysNativeView()
        case "warehouses":
            WarehousesNativeView()
        case "shopSettings":
            ShopSettingsNativeView()
        default:
            PlaceholderScreen(
                title: destination.localizedTitle(using: i18n),
                blurb: destination.blurb ?? i18n.t("placeholder.comingSoon")
            )
        }
    }
}

struct MoreMenuView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @EnvironmentObject private var navigation: AppNavigationModel

    private var groupedDestinations: [(DestinationGroup, [Destination])] {
        let byGroup = Dictionary(grouping: DestinationRegistry.visibleDestinations(auth: auth), by: \.group)
        return DestinationGroup.allCases.compactMap { group in
            guard let items = byGroup[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    navigation.append(.customizeTabs, to: AppNavigationModel.moreKey)
                } label: {
                    Label(i18n.t("more.customizeTabs"), systemImage: "slider.horizontal.3")
                }
                .foregroundStyle(Theme.text)
            }

            ForEach(groupedDestinations, id: \.0) { group, destinations in
                Section(group.localizedTitle(using: i18n)) {
                    ForEach(destinations) { destination in
                        Button {
                            navigation.selectDestination(destination.key)
                        } label: {
                            Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                        }
                        .foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct CustomizeTabsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabsStore
    @EnvironmentObject private var i18n: I18nStore

    private var destinations: [Destination] {
        DestinationRegistry.visibleDestinations(auth: auth)
    }

    var body: some View {
        List {
            Section {
                Text(i18n.t("customize.intro", [
                    "max": DestinationRegistry.maxPinned,
                    "count": tabs.pinned.count
                ]))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(destinations) { destination in
                Button {
                    toggle(destination)
                } label: {
                    HStack {
                        Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                            .foregroundStyle(Theme.text)

                        Spacer()

                        if tabs.pinned.contains(destination.key) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(i18n.t("screen.customizeTabs"))
    }

    private func toggle(_ destination: Destination) {
        if tabs.pinned.contains(destination.key) {
            tabs.setPinned(tabs.pinned.filter { $0 != destination.key })
            return
        }

        guard tabs.pinned.count < DestinationRegistry.maxPinned else { return }
        tabs.setPinned(tabs.pinned + [destination.key])
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    var body: some View {
        List {
            if let user = auth.user {
                Section(i18n.t("profile.account")) {
                    LabeledContent(i18n.t("profile.displayName"), value: user.fullName)
                    LabeledContent(i18n.t("profile.email"), value: user.email)
                    LabeledContent(i18n.t("profile.role"), value: user.roleName)
                    if let homeWarehouse = user.homeWarehouse?.nilIfBlank {
                        LabeledContent("Home warehouse", value: homeWarehouse)
                    }
                }

                Section(i18n.t("profile.mfaTitle")) {
                    LabeledContent(i18n.t("profile.mfaStatus"), value: mfaStatus(user.mfaMethod))
                }
            }

            Section {
                Picker(i18n.t("profile.language"), selection: Binding(
                    get: { i18n.language },
                    set: { i18n.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
            } header: {
                Text(i18n.t("profile.language"))
            } footer: {
                Text(i18n.t("profile.languageNote"))
            }

            Section(i18n.t("profile.helpLegal")) {
                if let privacyURL = URL(string: "https://laolin.net/privacy") {
                    Link(destination: privacyURL) {
                        Label(i18n.t("profile.privacyPolicy"), systemImage: "hand.raised")
                    }
                }

                if let supportURL = URL(string: "https://laolin.net/support") {
                    Link(destination: supportURL) {
                        Label(i18n.t("profile.support"), systemImage: "questionmark.circle")
                    }
                }

                LabeledContent(i18n.t("profile.version"), value: AppVersion.displayValue)
            }

            Section {
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text(i18n.t("profile.signOut"))
                }
            }
        }
        .navigationTitle(i18n.t("screen.profile"))
    }

    private func mfaStatus(_ method: String?) -> String {
        switch method {
        case "TOTP": return i18n.t("profile.mfaOnTotp")
        case "EMAIL": return i18n.t("profile.mfaOnEmail")
        default: return i18n.t("profile.mfaOff")
        }
    }
}
