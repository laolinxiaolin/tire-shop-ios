import SwiftUI

enum AppRoute: Hashable {
    case profile
    case customizeTabs
    case module(String)
    case skuDetail(String)
    case skuForm(String?)
    case adjustStock(String)
    case saleDetail(String)
    case orderDetail(String)
    case editSale(String)
    case startReturn(saleId: String, saleRef: String?)
    case workOrderDetail(String)
    case inventoryCountDetail(String)
    case newInventoryCount
    case containerDetail(String)
    case tapToPay(invoiceId: String, amount: Double)
    case customerDetail(id: String, name: String)
    case skuPicker
    case customerPicker
    case newCustomer
}

struct RootGateView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        Group {
            if !auth.ready {
                LoadingView(label: "Loading...")
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
    @State private var selectedTab = DestinationRegistry.defaultPinned.first ?? "dashboard"

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
            LoadingView(label: "Loading...")
        } else {
            TabView(selection: $selectedTab) {
                ForEach(visiblePinned) { destination in
                    NavigationShell(title: destination.title) {
                        DestinationView(destination: destination)
                    }
                    .tabItem {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                    .tag(destination.key)
                }

                NavigationShell(title: "More") {
                    MoreMenuView()
                }
                .tabItem {
                    Label("More", systemImage: "line.3.horizontal")
                }
                .tag("more")
            }
            .tint(Theme.primary)
        }
    }
}

struct NavigationShell<Content: View>: View {
    @EnvironmentObject private var auth: AuthStore
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
                    .navigationTitle(destination.title)
            } else {
                PlaceholderScreen(title: "Tire Force US")
            }
        case .newInventoryCount:
            NewInventoryCountNativeView()
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
        case .orderDetail(let id):
            OrderDetailNativeView(id: id)
        case .editSale(let id):
            EditSaleNativeView(id: id)
        case .startReturn(let saleId, let saleRef):
            StartReturnNativeView(saleId: saleId, saleRef: saleRef)
        case .workOrderDetail(let id):
            WorkOrderDetailNativeView(id: id)
        case .inventoryCountDetail(let id):
            InventoryCountDetailNativeView(id: id)
        case .containerDetail(let id):
            ContainerDetailNativeView(id: id)
        case .tapToPay(let invoiceId, let amount):
            TapToPayNativeView(invoiceId: invoiceId, amount: amount)
        case .customerDetail(let id, let name):
            CustomerDetailNativeView(id: id, fallbackName: name)
        }
    }
}

struct DestinationView: View {
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
        case "shopSettings":
            ShopSettingsNativeView()
        default:
            PlaceholderScreen(title: destination.title, blurb: destination.blurb)
        }
    }
}

struct MoreMenuView: View {
    @EnvironmentObject private var auth: AuthStore

    private var groupedDestinations: [(DestinationGroup, [Destination])] {
        DestinationGroup.allCases.compactMap { group in
            let items = DestinationRegistry.visibleDestinations(auth: auth).filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.customizeTabs) {
                    Label("Customize tabs", systemImage: "slider.horizontal.3")
                }
            }

            ForEach(groupedDestinations, id: \.0) { group, destinations in
                Section(group.title) {
                    ForEach(destinations) { destination in
                        NavigationLink(value: AppRoute.module(destination.key)) {
                            Label(destination.title, systemImage: destination.systemImage)
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

    private var destinations: [Destination] {
        DestinationRegistry.visibleDestinations(auth: auth)
    }

    var body: some View {
        List {
            Section {
                Text("Pick up to \(DestinationRegistry.maxPinned) screens to keep on the bottom tab bar. A More tab always holds the rest. (\(tabs.pinned.count)/\(DestinationRegistry.maxPinned) pinned)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(destinations) { destination in
                Button {
                    toggle(destination)
                } label: {
                    HStack {
                        Label(destination.title, systemImage: destination.systemImage)
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
        .navigationTitle("Customize tabs")
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
                Section("Your account") {
                    LabeledContent("Display name", value: user.fullName)
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Role", value: user.roleName)
                }

                Section("Two-step verification") {
                    LabeledContent("Status", value: mfaStatus(user.mfaMethod))
                }
            }

            Section("Language") {
                Picker("Language", selection: Binding(
                    get: { i18n.language },
                    set: { i18n.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text("Sign out")
                }
            }
        }
        .navigationTitle("Profile")
    }

    private func mfaStatus(_ method: String?) -> String {
        switch method {
        case "TOTP": return "On - Authenticator app"
        case "EMAIL": return "On - Email codes"
        default: return "Off"
        }
    }
}
