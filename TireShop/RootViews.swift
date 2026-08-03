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
    case bestSellers(months: Int)
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
    case vendorDetail(String)
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
                LoadingView(label: i18n.t("common.loading"))
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
                auth.restore()
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
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabsStore
    @EnvironmentObject private var i18n: I18nStore
    @State private var selectedTab = DestinationRegistry.defaultPinned.first ?? "dashboard"
    @State private var showTapToPayAnnouncement = false

    private var visiblePinned: [Destination] {
        tabs.pinned
            .compactMap(DestinationRegistry.destination(for:))
            .filter { DestinationRegistry.isVisible($0, auth: auth) }
    }

    var body: some View {
        if !tabs.ready {
            LoadingView(label: i18n.t("common.loading"))
        } else {
            TabView(selection: $selectedTab) {
                ForEach(visiblePinned) { destination in
                    NavigationShell(title: destination.localizedTitle(using: i18n)) {
                        DestinationView(destination: destination)
                    }
                    .tabItem {
                        Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                    }
                    .tag(destination.key)
                }

                NavigationShell(title: i18n.t("nav.more")) {
                    MoreMenuView()
                }
                .tabItem {
                    Label(i18n.t("nav.more"), systemImage: "line.3.horizontal")
                }
                .tag("more")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                handleKeyboardGeometry(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                handleKeyboardGeometry(note)
            }
            .tint(Theme.primary)
            .fullScreenCover(isPresented: $showTapToPayAnnouncement) {
                TapToPayLaunchAnnouncementView(
                    canManageSettings: auth.has("settings.manage"),
                    onDone: markTapToPayAnnouncementSeen
                )
            }
            .onAppear(perform: maybeShowTapToPayAnnouncement)
            .onChange(of: auth.user?.id) { _, _ in
                maybeShowTapToPayAnnouncement()
            }
            .debugLayoutProbe("RootNavigator")
        }
    }

    private func handleKeyboardGeometry(_ notification: Notification) {
        guard KeyboardSession.isOrphaned(notification) else { return }
        DebugLayoutLog.event("orphanedKeyboardDetected")
        // Let UIKit finish the in-flight show before reclaiming the session.
        Task { @MainActor in
            KeyboardSession.dismissOrphanedSession()
        }
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
    @EnvironmentObject private var i18n: I18nStore
    @State private var path: [AppRoute] = []

    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AvatarButton(name: auth.user?.fullName) {
                            path.append(.profile)
                        }
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    routeView(route)
                }
        }
        .debugLayoutProbe("NavigationShell[\(title)]")
    }

    @ViewBuilder
    private func routeView(_ route: AppRoute) -> some View {
        switch route {
        case .profile:
            ProfileView()
        case .customizeTabs:
            CustomizeTabsView()
        case .module(let key):
            if
                let destination = DestinationRegistry.destination(for: key),
                DestinationRegistry.isVisible(destination, auth: auth)
            {
                DestinationView(destination: destination)
                    .navigationTitle(destination.localizedTitle(using: i18n))
            } else if DestinationRegistry.destination(for: key) != nil {
                EmptyStateView(text: "You do not have permission to open this section.")
            } else {
                PlaceholderScreen(title: i18n.t("screen.fallbackTitle"))
            }
        case .tapToPayEducation:
            authorized(auth.has("payments.collect") || auth.has("settings.manage")) {
                TapToPayEducationView()
            }
        case .newInventoryCount:
            authorized(auth.has("inventory.count.manage")) {
                NewInventoryCountNativeView()
            }
        case .newTransfer:
            authorized(auth.has("transfers.manage")) {
                NewStockTransferNativeView()
            }
        case .skuPicker:
            authorized(auth.has("inventory.view")) {
                SkuPickerNativeView()
            }
        case .customerPicker:
            authorized(auth.has("customers.view")) {
                CustomerPickerNativeView()
            }
        case .newCustomer:
            authorized(auth.has("customers.manage")) {
                NewCustomerNativeView()
            }
        case .skuDetail(let id):
            authorized(auth.has("inventory.view")) {
                SkuLookupNativeView(idOrSku: id)
            }
        case .skuForm(let id):
            if auth.has("inventory.manage") {
                if let id {
                    SkuLookupEditNativeView(idOrSku: id)
                } else {
                    SkuFormNativeView(editing: nil)
                }
            } else {
                EmptyStateView(text: "You do not have permission to manage inventory.")
            }
        case .adjustStock(let id):
            if auth.canActOrRequest("inventory.adjust") {
                AdjustStockLookupNativeView(idOrSku: id)
            } else {
                EmptyStateView(text: "You do not have permission to adjust inventory.")
            }
        case .saleDetail(let id):
            authorized(auth.has("sales.view")) {
                SaleDetailNativeView(id: id)
            }
        case .bestSellers(let months):
            authorized(auth.has("sales.view")) {
                SalesListNativeView(showBestSellers: true, initialBestSellerMonths: months)
                    .navigationTitle(i18n.t("nav.sales"))
            }
        case .orderDetail(let id):
            authorized(auth.has("orders.manage")) {
                OrderDetailNativeView(id: id)
            }
        case .editSale(let id):
            if auth.has("sales.manage") {
                EditSaleNativeView(id: id)
            } else {
                EmptyStateView(text: "You do not have permission to manage sales.")
            }
        case .startReturn(let saleId, let saleRef):
            if auth.has("sales.manage") {
                StartReturnNativeView(saleId: saleId, saleRef: saleRef)
            } else {
                EmptyStateView(text: "You do not have permission to create returns.")
            }
        case .returnDetail(let id):
            authorized(auth.has("returns.view")) {
                ReturnDetailNativeView(id: id)
            }
        case .workOrderDetail(let id):
            authorized(auth.has("workorders.view")) {
                WorkOrderDetailNativeView(id: id)
            }
        case .inventoryCountDetail(let id):
            authorized(auth.has("inventory.count.view")) {
                InventoryCountDetailNativeView(id: id)
            }
        case .transferDetail(let id):
            authorized(auth.has("transfers.view")) {
                StockTransferDetailNativeView(id: id)
            }
        case .containerDetail(let id):
            authorized(auth.has("purchasing.view")) {
                ContainerDetailNativeView(id: id)
            }
        case .vendorDetail(let id):
            authorized(auth.has("vendors.view")) {
                VendorDetailNativeView(id: id)
            }
        case .tapToPay(let invoiceId, let amount, let saleId, let saleRef, let customerName):
            authorized(auth.has("payments.collect")) {
                TapToPayNativeView(
                    invoiceId: invoiceId,
                    amount: amount,
                    saleId: saleId,
                    saleRef: saleRef,
                    customerName: customerName
                )
            }
        case .customerDetail(let id, let name):
            authorized(auth.has("customers.view")) {
                CustomerDetailNativeView(id: id, fallbackName: name)
            }
        case .employeeDetail(let id):
            authorized(auth.has("employees.view")) {
                EmployeeDetailNativeView(id: id)
            }
        }
    }

    @ViewBuilder
    private func authorized<RouteContent: View>(
        _ allowed: Bool,
        @ViewBuilder content: () -> RouteContent
    ) -> some View {
        if allowed {
            content()
        } else {
            EmptyStateView(text: "You do not have permission to open this screen.")
        }
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
                NavigationLink(value: AppRoute.customizeTabs) {
                    Label(i18n.t("more.customizeTabs"), systemImage: "slider.horizontal.3")
                }
            }

            ForEach(groupedDestinations, id: \.0) { group, destinations in
                Section(group.localizedTitle(using: i18n)) {
                    ForEach(destinations) { destination in
                        NavigationLink(value: AppRoute.module(destination.key)) {
                            Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                        }
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
