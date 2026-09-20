import SwiftUI

/// Navigation state owned by one app scene.
///
/// Compact tabs and the regular-width sidebar render the same destinations
/// from this model. Keeping paths here prevents a resize or presentation
/// change from discarding the user's logical place in a workflow.
@MainActor
final class AppNavigationModel: ObservableObject {
    static let moreKey = "more"

    @Published var selectedDestinationKey: String
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @Published private(set) var selectedSaleID: String?
    @Published private(set) var selectedInventoryID: String?
    @Published private(set) var selectedCustomerID: String?
    @Published private var paths: [String: [AppRoute]] = [:]

    init(selectedDestinationKey: String = DestinationRegistry.defaultPinned.first ?? "dashboard") {
        self.selectedDestinationKey = selectedDestinationKey
    }

    func path(for owner: String) -> Binding<[AppRoute]> {
        Binding(
            get: { [weak self] in self?.paths[owner] ?? [] },
            set: { [weak self] in self?.setPath($0, for: owner) }
        )
    }

    func selectDestination(_ key: String) {
        guard DestinationRegistry.destination(for: key) != nil else { return }
        selectedDestinationKey = key

        // In compact layouts an unpinned destination is presented from More.
        // Preparing that stack is harmless in regular layouts and lets the
        // same action adapt without knowing the current presentation.
        paths[Self.moreKey] = [.module(key)]
    }

    func selectCompactTab(_ key: String) {
        if key == Self.moreKey {
            selectedDestinationKey = Self.moreKey
        } else {
            selectDestination(key)
        }
    }

    func compactTab(pinnedKeys: [String]) -> String {
        pinnedKeys.contains(selectedDestinationKey) ? selectedDestinationKey : Self.moreKey
    }

    func append(_ route: AppRoute, to owner: String) {
        paths[owner, default: []].append(route)
    }

    func showChecks() {
        selectDestination("checks")
    }

    func rememberSale(_ id: String) {
        selectedSaleID = id
    }

    func rememberInventoryItem(_ id: String) {
        selectedInventoryID = id
    }

    func rememberCustomer(_ id: String) {
        selectedCustomerID = id
    }

    func sanitize(visibleDestinationKeys: Set<String>) {
        if selectedDestinationKey != Self.moreKey,
           !visibleDestinationKeys.contains(selectedDestinationKey) {
            selectedDestinationKey = visibleDestinationKeys.contains("dashboard")
                ? "dashboard"
                : visibleDestinationKeys.first ?? Self.moreKey
        }

        if !visibleDestinationKeys.contains("sales") {
            selectedSaleID = nil
        }
        if !visibleDestinationKeys.contains("inventory") {
            selectedInventoryID = nil
        }
        if !visibleDestinationKeys.contains("customers") {
            selectedCustomerID = nil
        }

        for owner in paths.keys {
            paths[owner] = paths[owner]?.filter { route in
                guard case .module(let key) = route else { return true }
                return visibleDestinationKeys.contains(key)
            }
        }
    }

    func resetForSessionChange() {
        selectedDestinationKey = DestinationRegistry.defaultPinned.first ?? "dashboard"
        sidebarVisibility = .automatic
        selectedSaleID = nil
        selectedInventoryID = nil
        selectedCustomerID = nil
        paths.removeAll()
    }

    private func setPath(_ path: [AppRoute], for owner: String) {
        paths[owner] = path
        if owner == Self.moreKey, path.isEmpty,
           DestinationRegistry.destination(for: selectedDestinationKey) != nil {
            selectedDestinationKey = Self.moreKey
        }
    }
}

/// Shared route renderer for both compact and regular app shells.
struct AppRouteDestinationView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @EnvironmentObject private var navigation: AppNavigationModel

    let route: AppRoute

    @ViewBuilder
    var body: some View {
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
                    .onAppear { navigation.rememberInventoryItem(id) }
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
                    .onAppear { navigation.rememberSale(id) }
            }
        case .bestSellers(let months, let warehouse):
            authorized(auth.has("sales.view")) {
                SalesListNativeView(
                    showBestSellers: true,
                    initialBestSellerMonths: months,
                    initialBestSellerWarehouse: warehouse
                )
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
        case .supplierDetail(let id):
            authorized(auth.has("purchasing.view")) {
                SupplierDetailNativeView(id: id)
            }
        case .vendorDetail(let id):
            authorized(auth.has("vendors.view")) {
                VendorDetailNativeView(id: id)
            }
        case .paymentApplicationDetail(let id):
            authorized(auth.has("paymentapps.view")) {
                PaymentApplicationDetailNativeView(id: id)
            }
        case .paymentApplicationEditor(let id, let vendorId):
            authorized(auth.has("paymentapps.manage")) {
                PaymentApplicationEditorNativeView(id: id, presetVendorId: vendorId)
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
                    .onAppear { navigation.rememberCustomer(id) }
            }
        case .employeeDetail(let id):
            authorized(auth.has("employees.view")) {
                EmployeeDetailNativeView(id: id)
            }
        }
    }

    @ViewBuilder
    private func authorized<Content: View>(
        _ allowed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if allowed {
            content()
        } else {
            EmptyStateView(text: "You do not have permission to open this screen.")
        }
    }
}
