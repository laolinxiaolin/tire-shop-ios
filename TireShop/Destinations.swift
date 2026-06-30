import Foundation
import SwiftUI

enum DestinationGroup: String, CaseIterable, Identifiable {
    case main
    case operations
    case finance
    case team
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return ""
        case .operations: return "Operations"
        case .finance: return "Finance"
        case .team: return "Team"
        case .admin: return "Admin"
        }
    }
}

struct Destination: Identifiable, Hashable {
    let key: String
    let title: String
    let systemImage: String
    let group: DestinationGroup
    let permission: String?
    let isBuilt: Bool
    let blurb: String?

    var id: String { key }
}

enum DestinationRegistry {
    static let all: [Destination] = [
        Destination(key: "dashboard", title: "Home", systemImage: "house", group: .main, permission: "dashboard.view", isBuilt: true, blurb: nil),
        Destination(key: "notifications", title: "Notifications", systemImage: "bell", group: .main, permission: nil, isBuilt: true, blurb: nil),
        Destination(key: "newQuote", title: "New Sale", systemImage: "plus.circle", group: .operations, permission: "sales.manage", isBuilt: true, blurb: nil),
        Destination(key: "sales", title: "Sales", systemImage: "creditcard", group: .operations, permission: "sales.view", isBuilt: true, blurb: nil),
        Destination(key: "orders", title: "Web Orders", systemImage: "cart", group: .operations, permission: "orders.manage", isBuilt: true, blurb: nil),
        Destination(key: "inventory", title: "Inventory", systemImage: "circle.grid.3x3", group: .operations, permission: "inventory.view", isBuilt: true, blurb: nil),
        Destination(key: "skuManagement", title: "SKU Management", systemImage: "tag", group: .operations, permission: "inventory.manage", isBuilt: true, blurb: nil),
        Destination(key: "tireAttributes", title: "Tire Attributes", systemImage: "gearshape", group: .operations, permission: "inventory.config", isBuilt: true, blurb: nil),
        Destination(key: "brandInfo", title: "Brand Info", systemImage: "book", group: .operations, permission: "brands.manage", isBuilt: true, blurb: nil),
        Destination(key: "inventoryCounts", title: "Inventory Counts", systemImage: "checkmark.circle", group: .operations, permission: "inventory.count.view", isBuilt: true, blurb: nil),
        Destination(key: "purchasing", title: "Purchasing", systemImage: "shippingbox", group: .operations, permission: "purchasing.view", isBuilt: true, blurb: nil),
        Destination(key: "vendors", title: "Vendors", systemImage: "truck.box", group: .operations, permission: "vendors.view", isBuilt: true, blurb: nil),
        Destination(key: "customers", title: "Customers", systemImage: "person", group: .operations, permission: "customers.view", isBuilt: true, blurb: nil),
        Destination(key: "customerRelations", title: "Customer Relations", systemImage: "heart", group: .operations, permission: "crm.view", isBuilt: false, blurb: nil),
        Destination(key: "workOrders", title: "Work Orders", systemImage: "wrench.adjustable", group: .operations, permission: "workorders.view", isBuilt: true, blurb: nil),
        Destination(key: "returns", title: "Returns", systemImage: "arrow.uturn.left", group: .operations, permission: "returns.view", isBuilt: true, blurb: nil),
        Destination(key: "money", title: "Money", systemImage: "dollarsign.circle", group: .finance, permission: "receivables.view", isBuilt: true, blurb: nil),
        Destination(key: "accounting", title: "Accounting", systemImage: "book.closed", group: .finance, permission: "accounting.view", isBuilt: true, blurb: nil),
        Destination(key: "cashAccounts", title: "Cash Accounts", systemImage: "building.columns", group: .finance, permission: "accounting.view", isBuilt: true, blurb: nil),
        Destination(key: "fet", title: "FET", systemImage: "doc.text", group: .finance, permission: "accounting.view", isBuilt: true, blurb: nil),
        Destination(key: "eod", title: "End of Day", systemImage: "moon", group: .finance, permission: "accounting.view", isBuilt: true, blurb: nil),
        Destination(key: "monthlySales", title: "Monthly Sales", systemImage: "square.grid.2x2", group: .finance, permission: "accounting.view", isBuilt: true, blurb: nil),
        Destination(key: "employees", title: "Employees", systemImage: "person.2", group: .team, permission: "employees.view", isBuilt: true, blurb: nil),
        Destination(key: "commissions", title: "Commissions", systemImage: "percent", group: .team, permission: "employees.view", isBuilt: true, blurb: nil),
        Destination(key: "approvals", title: "Approvals", systemImage: "checkmark.seal", group: .admin, permission: nil, isBuilt: true, blurb: nil),
        Destination(key: "activity", title: "Activity", systemImage: "waveform.path.ecg", group: .admin, permission: "activity.view", isBuilt: true, blurb: nil),
        Destination(key: "users", title: "Users", systemImage: "person.crop.circle", group: .admin, permission: "users.manage", isBuilt: true, blurb: nil),
        Destination(key: "roles", title: "Roles", systemImage: "shield", group: .admin, permission: "users.manage", isBuilt: true, blurb: nil),
        Destination(key: "apiKeys", title: "API Keys", systemImage: "key", group: .admin, permission: "apikeys.manage", isBuilt: true, blurb: nil),
        Destination(key: "shopSettings", title: "Shop Settings", systemImage: "gear", group: .admin, permission: "settings.manage", isBuilt: true, blurb: nil)
    ]

    static let defaultPinned = ["dashboard", "newQuote", "sales", "inventory"]
    static let maxPinned = 4

    static func destination(for key: String) -> Destination? {
        all.first { $0.key == key }
    }

    @MainActor
    static func visibleDestinations(auth: AuthStore) -> [Destination] {
        all.filter { destination in
            guard let permission = destination.permission else { return true }
            return auth.has(permission)
        }
    }
}

@MainActor
final class TabsStore: ObservableObject {
    private let storageKey = "ts_tabs"

    @Published var ready = false
    @Published var pinned = DestinationRegistry.defaultPinned

    init() {
        restore()
    }

    func restore() {
        defer { ready = true }

        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return
        }

        let sanitized = sanitize(decoded)
        if !sanitized.isEmpty {
            pinned = sanitized
        }
    }

    func setPinned(_ keys: [String]) {
        let next = sanitize(keys)
        pinned = next

        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func sanitize(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for key in keys where DestinationRegistry.destination(for: key) != nil && !seen.contains(key) {
            seen.insert(key)
            output.append(key)
        }

        return Array(output.prefix(DestinationRegistry.maxPinned))
    }
}
