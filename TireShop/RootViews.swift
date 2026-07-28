import SwiftUI

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

    var body: some View {
        Group {
            if !auth.ready {
                LoadingView(label: i18n.t("common.loading"))
            } else if auth.user != nil {
                RootNavigatorView()
            } else {
                LoginView()
            }
        }
        .task {
            if !auth.ready {
                auth.restore()
            }
        }
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
            .filter { destination in
                guard let permission = destination.permission else { return true }
                return auth.has(permission)
            }
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
    }

    @ViewBuilder
    private func routeView(_ route: AppRoute) -> some View {
        switch route {
        case .profile:
            ProfileView()
        case .customizeTabs:
            CustomizeTabsView()
        case .module(let key):
            if let destination = DestinationRegistry.destination(for: key) {
                DestinationView(destination: destination)
                    .navigationTitle(destination.localizedTitle(using: i18n))
            } else {
                PlaceholderScreen(title: i18n.t("screen.fallbackTitle"))
            }
        case .tapToPayEducation:
            TapToPayEducationView()
        case .newInventoryCount:
            NewInventoryCountNativeView()
        case .newTransfer:
            NewStockTransferNativeView()
        case .skuPicker:
            SkuPickerNativeView()
        case .customerPicker:
            CustomerPickerNativeView()
        case .newCustomer:
            NewCustomerNativeView()
        case .skuDetail(let id):
            SkuLookupNativeView(idOrSku: id)
        case .skuForm(let id):
            if let id {
                SkuLookupEditNativeView(idOrSku: id)
            } else {
                SkuFormNativeView(editing: nil)
            }
        case .adjustStock(let id):
            AdjustStockLookupNativeView(idOrSku: id)
        case .saleDetail(let id):
            SaleDetailNativeView(id: id)
        case .bestSellers(let months):
            SalesListNativeView(showBestSellers: true, initialBestSellerMonths: months)
                .navigationTitle(i18n.t("nav.sales"))
        case .orderDetail(let id):
            OrderDetailNativeView(id: id)
        case .editSale(let id):
            EditSaleNativeView(id: id)
        case .startReturn(let saleId, let saleRef):
            StartReturnNativeView(saleId: saleId, saleRef: saleRef)
        case .returnDetail(let id):
            ReturnDetailNativeView(id: id)
        case .workOrderDetail(let id):
            WorkOrderDetailNativeView(id: id)
        case .inventoryCountDetail(let id):
            InventoryCountDetailNativeView(id: id)
        case .transferDetail(let id):
            StockTransferDetailNativeView(id: id)
        case .containerDetail(let id):
            ContainerDetailNativeView(id: id)
        case .vendorDetail(let id):
            VendorDetailNativeView(id: id)
        case .tapToPay(let invoiceId, let amount, let saleId, let saleRef, let customerName):
            TapToPayNativeView(invoiceId: invoiceId, amount: amount, saleId: saleId, saleRef: saleRef, customerName: customerName)
        case .customerDetail(let id, let name):
            CustomerDetailNativeView(id: id, fallbackName: name)
        case .employeeDetail(let id):
            EmployeeDetailNativeView(id: id)
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
        case "tireAttributes":
            TireAttributesNativeView()
        case "brandInfo":
            BrandInfoNativeView()
        case "inventoryCounts":
            InventoryCountsListNativeView()
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
