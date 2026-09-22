import Foundation

private func query(_ params: [String: Any?]) -> String {
    var components = URLComponents()
    components.queryItems = params.compactMap { key, value in
        guard let value = unwrapOptional(value) else { return nil }
        let text = String(describing: value)
        guard !text.isEmpty else { return nil }
        return URLQueryItem(name: key, value: text)
    }
    return components.percentEncodedQuery.map { "?\($0)" } ?? ""
}

private func unwrapOptional(_ value: Any?) -> Any? {
    guard let value else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}

struct EmptyBody: Codable {}

struct TireSkuPatchInput: Codable {
    var sku: String?
    var brand: String?
    var model: String?
    var size: String?
    var category: TireCategory?
    var position: TirePosition?
    var segment: String?
    var loadIndex: String?
    var pattern: String?
    var treadDepth32: Double?
    var maxLoadSingleLb: Int?
    var weightLb: Double?
    var plyRating: String?
    var priceWholesale: Double?
    var clearPriceWholesale = false
    var priceRetail: Double?
    var priceCost: Double?
    var reorderPoint: Int?
    var active: Bool?

    private enum CodingKeys: String, CodingKey {
        case sku, brand, model, size, category, position, segment, loadIndex, pattern, treadDepth32, maxLoadSingleLb, weightLb, plyRating, priceRetail, priceCost, reorderPoint, active, priceWholesale
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sku, forKey: .sku)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(segment, forKey: .segment)
        try container.encodeIfPresent(loadIndex, forKey: .loadIndex)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(treadDepth32, forKey: .treadDepth32)
        try container.encodeIfPresent(maxLoadSingleLb, forKey: .maxLoadSingleLb)
        try container.encodeIfPresent(weightLb, forKey: .weightLb)
        try container.encodeIfPresent(plyRating, forKey: .plyRating)
        try container.encodeIfPresent(priceRetail, forKey: .priceRetail)
        try container.encodeIfPresent(priceCost, forKey: .priceCost)
        try container.encodeIfPresent(reorderPoint, forKey: .reorderPoint)
        try container.encodeIfPresent(active, forKey: .active)
        if clearPriceWholesale {
            try container.encodeNil(forKey: .priceWholesale)
        } else {
            try container.encodeIfPresent(priceWholesale, forKey: .priceWholesale)
        }
    }
}

struct CustomerTaxStatusInput: Codable {
    let taxExempt: Bool
    let taxExemptNumber: String?
    let taxExemptExpiresAt: String?
}

struct WorkOrderPatchInput: Codable {
    let status: WorkOrderStatus?
    let bay: String?
    let notes: String?
}

struct WarehouseCreateInput: Codable {
    let code: String
    let name: String
    let notes: String?
}

struct WarehousePatchInput: Codable {
    let name: String?
    let notes: String?
    let active: Bool?
}

struct StockTransferLineInput: Codable, Equatable {
    let skuId: String
    let qty: Int
}

struct StockTransferInput: Codable, Equatable {
    let fromLocation: String
    let toLocation: String
    let lines: [StockTransferLineInput]
    let costSpread: CostSpreadMethod?
    let freightAmount: Double?
    let freightVendorId: String?
    let freightVendorName: String?
    let freightDueAt: String?
    let notes: String?
}

struct InventoryCountCreateInput: Codable {
    let scopeCategory: TireCategory?
    let scopePosition: TirePosition?
    let location: String?
    let notes: String?
}

struct InventoryCountLineInput: Codable {
    let countExpr: String?
    let countedQty: Int?
}

struct PaymentRecordInput: Codable {
    let paymentMethodId: String
    let amount: Double
    let reference: String?
    let note: String?
    var plannedDepositDate: String? = nil
}

struct ReasonInput: Codable {
    let reason: String?
}

struct SupplierSaveInput: Encodable {
    var name: String
    var contactName: String?
    var phone: String?
    var email: String?
    var country: String?
    var address: String?
    var currency: String?
    var defaultDDP: Bool?
    var notes: String?
    var encodeNulls = false

    private enum CodingKeys: String, CodingKey {
        case name
        case contactName
        case phone
        case email
        case country
        case address
        case currency
        case defaultDDP
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try encode(contactName, forKey: .contactName, into: &container)
        try encode(phone, forKey: .phone, into: &container)
        try encode(email, forKey: .email, into: &container)
        try encode(country, forKey: .country, into: &container)
        try encode(address, forKey: .address, into: &container)
        try encode(currency, forKey: .currency, into: &container)
        try container.encodeIfPresent(defaultDDP, forKey: .defaultDDP)
        try encode(notes, forKey: .notes, into: &container)
    }

    private func encode<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if encodeNulls {
            try container.encodeNil(forKey: key)
        }
    }
}

struct ContainerCreateInput: Codable {
    let supplierId: String
    let reference: String?
}

struct ContainerDraftLineInput: Codable, Equatable {
    let skuId: String
    let qty: Int
    let unitCost: Double
    let fetPerUnit: Double?
}

struct ContainerPatchInput: Encodable {
    var reference: String?
    var bolNumber: String?
    var isDDP: Bool
    var costSpread: CostSpreadMethod
    var location: String? = nil
    var etaAt: String?
    var arrivedAt: String?
    var balanceDueAt: String?
    var notes: String?
    var lines: [ContainerDraftLineInput]?

    private enum CodingKeys: String, CodingKey {
        case reference
        case bolNumber
        case isDDP
        case costSpread
        case location
        case etaAt
        case arrivedAt
        case balanceDueAt
        case notes
        case lines
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encode(reference, forKey: .reference, into: &container)
        try encode(bolNumber, forKey: .bolNumber, into: &container)
        try container.encode(isDDP, forKey: .isDDP)
        try container.encode(costSpread, forKey: .costSpread)
        try container.encodeIfPresent(location, forKey: .location)
        try encode(etaAt, forKey: .etaAt, into: &container)
        try encode(arrivedAt, forKey: .arrivedAt, into: &container)
        try encode(balanceDueAt, forKey: .balanceDueAt, into: &container)
        try encode(notes, forKey: .notes, into: &container)
        try container.encodeIfPresent(lines, forKey: .lines)
    }

    private func encode<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

/// A deliberately narrow PATCH that reschedules one bill and nothing else.
///
/// A full cost edit carries the costing fields along with it and is refused once
/// the container is received. A due date *schedules* a payable rather than
/// valuing it — it feeds AP aging and the payment-application countdown but
/// never the landed cost that receipt froze — so the server still accepts this
/// one on a received container.
struct ContainerCostDueDateInput: Encodable {
    var dueAt: String?

    private enum CodingKeys: String, CodingKey {
        case dueAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always sent, null included: nil is "clear the date", not "leave it".
        try container.encodeNullable(dueAt, forKey: .dueAt)
    }
}

struct ContainerStatusInput: Codable {
    let status: ContainerStatus
}

struct ContainerCostSaveInput: Encodable {
    var category: ContainerCostCategory
    var amount: Double
    var description: String?
    var vendor: String?
    var vendorId: String?
    var occurredAt: String?
    var dueAt: String?
    var reference: String?
    var encodeNulls = false

    private enum CodingKeys: String, CodingKey {
        case category
        case amount
        case description
        case vendor
        case vendorId
        case occurredAt
        case dueAt
        case reference
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(amount, forKey: .amount)
        try encode(description, forKey: .description, into: &container)
        try encode(vendor, forKey: .vendor, into: &container)
        try encode(vendorId, forKey: .vendorId, into: &container)
        try encode(occurredAt, forKey: .occurredAt, into: &container)
        try encode(dueAt, forKey: .dueAt, into: &container)
        try encode(reference, forKey: .reference, into: &container)
    }

    private func encode<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if encodeNulls {
            try container.encodeNil(forKey: key)
        }
    }
}

struct NoteInput: Codable {
    let note: String?
}

struct DescriptionInput: Codable {
    let description: String
}

struct DoneInput: Codable {
    let done: Bool
}

struct FullNameInput: Codable {
    let fullName: String
}

struct PasswordInput: Codable {
    let password: String
}

struct GeneralPatchInput: Codable {
    let timezone: String?
    let defaultTaxRate: Double?
    let storefrontLocation: String?
    let storefrontHideOutOfStock: Bool?

    init(
        timezone: String?,
        defaultTaxRate: Double?,
        storefrontLocation: String? = nil,
        storefrontHideOutOfStock: Bool? = nil
    ) {
        self.timezone = timezone
        self.defaultTaxRate = defaultTaxRate
        self.storefrontLocation = storefrontLocation
        self.storefrontHideOutOfStock = storefrontHideOutOfStock
    }
}

struct TestMailInput: Codable {
    let to: String
}

struct InvoiceEmailInput: Codable {
    let to: String?
}

struct InvoiceIdInput: Codable {
    let invoiceId: String
}

/// `grossAmount` is what the card is charged, fee included — the server divides
/// the fee back out. Omitted charges the whole balance plus its fee. (The older
/// `amount`, the pre-fee portion, is still accepted by the server but can't
/// express every total, so nothing here sends it.)
struct PaymentIntentGrossInput: Codable {
    let invoiceId: String
    let grossAmount: Double?
}

struct PaymentIntentIdInput: Codable {
    let paymentIntentId: String
}

struct ManualSettleResult: Codable, Equatable {
    let booked: Bool
    let status: String
}

struct CustomerInteractionInput: Codable {
    let type: InteractionType?
    let summary: String
    let body: String?
    let occurredAt: String?
}

struct FollowUpPatchInput: Codable {
    let title: String?
    let note: String?
    let dueAt: String?
    let assignedToId: String?
    let status: FollowUpStatus?
}

struct FollowUpCreateInput: Codable {
    let title: String
    let note: String?
    let dueAt: String
    let assignedToId: String?
}

struct CrmEmailInput: Codable {
    let subject: String?
    let body: String?
    let templateId: String?
}

struct OutreachTemplateInput: Codable {
    let name: String
    let subject: String
    let body: String
    let active: Bool
}

struct VendorSaveInput: Encodable {
    var name: String
    var category: VendorCategory?
    var contactName: String?
    var phone: String?
    var email: String?
    var address: String?
    var notes: String?
    var active: Bool?
    var encodeNulls = false

    private enum CodingKeys: String, CodingKey {
        case name
        case category
        case contactName
        case phone
        case email
        case address
        case notes
        case active
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try encode(category, forKey: .category, into: &container)
        try encode(contactName, forKey: .contactName, into: &container)
        try encode(phone, forKey: .phone, into: &container)
        try encode(email, forKey: .email, into: &container)
        try encode(address, forKey: .address, into: &container)
        try encode(notes, forKey: .notes, into: &container)
        try container.encodeIfPresent(active, forKey: .active)
    }

    private func encode<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if encodeNulls {
            try container.encodeNil(forKey: key)
        }
    }
}

struct VendorRefundInput: Codable {
    let amount: Double
    let depositToCode: String
    let creditCode: String
    let date: String?
    let reference: String?
    let note: String?
}

struct UserCreateInput: Codable {
    let email: String
    let password: String
    let fullName: String
    let roleId: String
    let homeWarehouse: String?
    let demo: Bool?

    init(
        email: String,
        password: String,
        fullName: String,
        roleId: String,
        homeWarehouse: String? = nil,
        demo: Bool? = nil
    ) {
        self.email = email
        self.password = password
        self.fullName = fullName
        self.roleId = roleId
        self.homeWarehouse = homeWarehouse
        self.demo = demo
    }
}

struct UserPatchInput: Codable {
    let fullName: String?
    let roleId: String?
    let active: Bool?
    let homeWarehouse: String?
    let demo: Bool?

    init(fullName: String?, roleId: String?, active: Bool?, homeWarehouse: String? = nil, demo: Bool? = nil) {
        self.fullName = fullName
        self.roleId = roleId
        self.active = active
        self.homeWarehouse = homeWarehouse
        self.demo = demo
    }
}

struct RoleCreateInput: Codable {
    let name: String
    let description: String?
    let permissions: [String]
    let approvalPermissions: [String]?
}

struct RolePatchInput: Encodable {
    let name: String?
    let description: String?
    let permissions: [String]?
    let approvalPermissions: [String]?
    let clearsDescription: Bool

    init(
        name: String?,
        description: String?,
        permissions: [String]?,
        approvalPermissions: [String]?,
        clearsDescription: Bool = false
    ) {
        self.name = name
        self.description = description
        self.permissions = permissions
        self.approvalPermissions = approvalPermissions
        self.clearsDescription = clearsDescription
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case permissions
        case approvalPermissions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        if let description {
            try container.encode(description, forKey: .description)
        } else if clearsDescription {
            try container.encodeNil(forKey: .description)
        }
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(approvalPermissions, forKey: .approvalPermissions)
    }
}

struct ApiKeyCreateInput: Codable {
    let name: String
    let scopes: [String]
}

struct BrandingPatchInput: Codable {
    let shopName: String?
    let shopAddress: String?
    let shopPhone: String?
    let shopEmail: String?
}

struct MailPatchInput: Codable {
    let provider: String?
    let host: String?
    let port: Int?
    let secure: Bool?
    let user: String?
    let password: String?
    let from: String?
    let resendApiKey: String?
}

struct InvoiceTemplatePatchInput: Codable {
    let subject: String?
    let body: String?
}

struct DashboardAPI {
    var client = APIClient.shared

    func summary(months: Int = 1) async throws -> DashboardSummary {
        try await client.request("/dashboard/summary?months=\(months)")
    }
}

struct TireAttributeCreateInput: Codable {
    let kind: TireAttributeKind
    let value: String
    let label: String
}

struct TireAttributePatchInput: Codable {
    var label: String?
    var active: Bool?
}

struct TireAttributesAPI {
    var client = APIClient.shared

    func list(kind: TireAttributeKind? = nil) async throws -> [TireAttribute] {
        try await client.request("/tire-attributes\(query(["kind": kind]))")
    }

    func create(_ body: TireAttributeCreateInput) async throws -> TireAttribute {
        try await client.request("/tire-attributes", method: "POST", body: body)
    }

    func update(id: String, body: TireAttributePatchInput) async throws -> TireAttribute {
        try await client.request("/tire-attributes/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> EmptyResponse {
        try await client.request("/tire-attributes/\(id)", method: "DELETE")
    }
}

struct OrdersAPI {
    var client = APIClient.shared

    func list(status: OrderStatus? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<Order> {
        try await client.request("/orders\(query(["status": status, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> Order {
        try await client.request("/orders/\(id)")
    }

    func confirm(id: String) async throws -> Order {
        try await client.request("/orders/\(id)/confirm", method: "POST")
    }

    func cancel(id: String) async throws -> Order {
        try await client.request("/orders/\(id)/cancel", method: "POST")
    }
}

struct NotificationsAPI {
    var client = APIClient.shared

    func list(page: Int? = nil, pageSize: Int? = nil) async throws -> NotificationsPage {
        try await client.request("/notifications\(query(["page": page, "pageSize": pageSize]))")
    }

    func markAllRead() async throws -> EmptyResponse {
        try await client.request("/notifications/read-all", method: "POST")
    }
}

struct BrandCreateInput: Codable {
    var name: String
    var introEn: String
    var introZh: String
    var country: String?
    var foundedYear: Int?
    var website: String?
    var active: Bool
}

struct BrandsAPI {
    var client = APIClient.shared

    func list() async throws -> [BrandInfo] {
        try await client.request("/brands")
    }

    func create(_ body: BrandCreateInput) async throws -> BrandInfo {
        try await client.request("/brands", method: "POST", body: body)
    }

    func update(id: String, body: BrandCreateInput) async throws -> BrandInfo {
        try await client.request("/brands/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> EmptyResponse {
        try await client.request("/brands/\(id)", method: "DELETE")
    }
}

struct MonthlySalesAPI {
    var client = APIClient.shared

    func report(from: String, to: String) async throws -> MonthlySalesReport {
        try await client.request("/accounting/reports/monthly-sales\(query(["from": from, "to": to]))")
    }

    /// Spreadsheet export of the Monthly Sales report. `columns` selects which
    /// columns to include (empty = all columns).
    func export(
        from: String,
        to: String,
        columns: [String]? = nil,
        fileName: String = "monthly-sales.xlsx"
    ) async throws -> URL {
        var params: [String: Any?] = ["from": from, "to": to]
        if let columns, !columns.isEmpty {
            params["columns"] = columns.joined(separator: ",")
        }
        return try await client.download("/accounting/reports/monthly-sales/export\(query(params))", fileName: fileName)
    }
}

struct EmployeeSaveInput: Encodable {
    var fullName: String
    var employeeNo: String?
    var userId: String?
    var includeUserId = false
    var phone: String?
    var email: String?
    var address: String?
    var position: String?
    var department: String?
    var status: EmployeeStatus
    var hireDate: String?
    var endDate: String?
    var payType: PayType
    var payRate: Double
    var commissionRate: Double
    var commissionBasis: CommissionBasis
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case fullName
        case employeeNo
        case userId
        case phone
        case email
        case address
        case position
        case department
        case status
        case hireDate
        case endDate
        case payType
        case payRate
        case commissionRate
        case commissionBasis
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullName, forKey: .fullName)
        try container.encodeIfPresent(employeeNo, forKey: .employeeNo)
        if includeUserId {
            if let userId {
                try container.encode(userId, forKey: .userId)
            } else {
                try container.encodeNil(forKey: .userId)
            }
        }
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(department, forKey: .department)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(hireDate, forKey: .hireDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(payType, forKey: .payType)
        try container.encode(payRate, forKey: .payRate)
        try container.encode(commissionRate, forKey: .commissionRate)
        try container.encode(commissionBasis, forKey: .commissionBasis)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

struct EmployeesAPI {
    var client = APIClient.shared

    func list(q: String? = nil, status: EmployeeStatus? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<Employee> {
        let qs = query([
            "q": q,
            "status": status,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/employees\(qs)")
    }

    func get(id: String) async throws -> Employee {
        try await client.request("/employees/\(id)")
    }

    func create(_ body: EmployeeSaveInput) async throws -> Employee {
        try await client.request("/employees", method: "POST", body: body)
    }

    func update(id: String, body: EmployeeSaveInput) async throws -> Employee {
        try await client.request("/employees/\(id)", method: "PATCH", body: body)
    }

    /// Payout history, newest first.
    func payouts(id: String) async throws -> [CommissionPayout] {
        try await client.request("/employees/\(id)/payouts")
    }

    /// One payout document, with the commission lines it reserved.
    func payout(id: String, payoutId: String) async throws -> CommissionPayout {
        try await client.request("/employees/\(id)/payouts/\(payoutId)")
    }

    /// Every commission entry whose sale falls in the period, plus the
    /// outstanding rollovers that ride along with any payout.
    func payoutPreview(id: String, from: String, to: String) async throws -> CommissionPayoutPreview {
        try await client.request("/employees/\(id)/payout-preview\(query(["from": from, "to": to]))")
    }

    /// Open a numbered draft that reserves the selected lines.
    func createPayout(
        id: String,
        body: CommissionPayoutCreateInput,
        idempotencyKey: String? = nil
    ) async throws -> CommissionPayout {
        try await client.request(
            "/employees/\(id)/payout",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    /// Post the payout journal and settle the draft.
    func payPayout(id: String, payoutId: String) async throws -> CommissionPayout {
        try await client.request("/employees/\(id)/payouts/\(payoutId)/pay", method: "POST", body: EmptyBody())
    }

    /// Release a draft's lines, or reverse a paid payout's accounting and
    /// re-accrue the eligible lines. Voiding a PAID payout reverses a posted
    /// cash journal, so it can come back as an approval request instead.
    func voidPayout(id: String, payoutId: String, reason: String?) async throws -> ImmediateOrApproval<CommissionPayout> {
        try await client.request(
            "/employees/\(id)/payouts/\(payoutId)/void",
            method: "POST",
            body: CommissionPayoutVoidInput(reason: reason)
        )
    }
}

struct CommissionsAPI {
    var client = APIClient.shared

    func list(
        employeeId: String? = nil,
        status: CommissionStatus? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<CommissionEntry> {
        let qs = query([
            "employeeId": employeeId,
            "status": status,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/employees/commissions\(qs)")
    }

}

struct CrmAPI {
    var client = APIClient.shared

    func relationshipSummary(customerId: String) async throws -> RelationshipSummary {
        try await client.request("/crm/customers/\(customerId)/summary")
    }

    func interactions(customerId: String) async throws -> [CustomerInteraction] {
        try await client.request("/crm/customers/\(customerId)/interactions")
    }

    func followUps(
        status: FollowUpStatus? = nil,
        assignedToId: String? = nil,
        overdue: Bool? = nil,
        customerId: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<CustomerFollowUp> {
        let qs = query([
            "status": status,
            "assignedToId": assignedToId,
            "overdue": overdue,
            "customerId": customerId,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/crm/follow-ups\(qs)")
    }

    func updateFollowUp(id: String, body: FollowUpPatchInput) async throws -> CustomerFollowUp {
        try await client.request("/crm/follow-ups/\(id)", method: "PATCH", body: body)
    }

    func addFollowUp(customerId: String, body: FollowUpCreateInput) async throws -> CustomerFollowUp {
        try await client.request("/crm/customers/\(customerId)/follow-ups", method: "POST", body: body)
    }

    func addInteraction(customerId: String, body: CustomerInteractionInput) async throws -> CustomerInteraction {
        try await client.request("/crm/customers/\(customerId)/interactions", method: "POST", body: body)
    }

    func updateInteraction(id: String, body: CustomerInteractionInput) async throws -> CustomerInteraction {
        try await client.request("/crm/interactions/\(id)", method: "PATCH", body: body)
    }

    func deleteInteraction(id: String) async throws -> EmptyResponse {
        try await client.request("/crm/interactions/\(id)", method: "DELETE")
    }

    func assignableUsers() async throws -> [AssignableUser] {
        try await client.request("/crm/assignable-users")
    }

    func atRisk(page: Int? = nil, pageSize: Int? = nil) async throws -> AtRiskCustomersPage {
        try await client.request("/crm/at-risk\(query(["page": page, "pageSize": pageSize]))")
    }

    func sendEmail(customerId: String, body: CrmEmailInput) async throws -> CustomerInteraction {
        try await client.request("/crm/customers/\(customerId)/email", method: "POST", body: body)
    }

    func templates() async throws -> [OutreachTemplate] {
        try await client.request("/crm/templates")
    }

    func createTemplate(_ body: OutreachTemplateInput) async throws -> OutreachTemplate {
        try await client.request("/crm/templates", method: "POST", body: body)
    }

    func updateTemplate(id: String, body: OutreachTemplateInput) async throws -> OutreachTemplate {
        try await client.request("/crm/templates/\(id)", method: "PATCH", body: body)
    }

    func deleteTemplate(id: String) async throws -> OkResponse {
        try await client.request("/crm/templates/\(id)", method: "DELETE")
    }
}

struct InventoryAPI {
    var client = APIClient.shared

    func listSkus(
        ids: [String]? = nil,
        q: String? = nil,
        category: TireCategory? = nil,
        position: TirePosition? = nil,
        brand: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        inStock: Bool? = nil,
        location: String? = nil,
        storefrontVisible: Bool? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> InventorySkuPage {
        let qs = query([
            "ids": ids?.joined(separator: ","),
            "q": q,
            "category": category,
            "position": position,
            "brand": brand,
            "sortBy": sortBy,
            "sortOrder": sortOrder,
            "inStock": inStock == true ? "1" : nil,
            "location": location,
            "storefrontVisible": storefrontVisible.map { $0 ? "1" : "0" },
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/inventory/skus\(qs)")
    }

    func listStorefrontSkus(
        q: String? = nil,
        storefrontVisible: Bool? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> StorefrontSkuPage {
        let qs = query([
            "q": q,
            "storefrontVisible": storefrontVisible.map { $0 ? "1" : "0" },
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/inventory/storefront-skus\(qs)")
    }

    func exportSkus(
        ids: [String]? = nil,
        q: String? = nil,
        category: TireCategory? = nil,
        position: TirePosition? = nil,
        brand: String? = nil,
        inStock: Bool = false,
        location: String? = nil
    ) async throws -> URL {
        let qs = query([
            "ids": ids?.joined(separator: ","),
            "q": q,
            "category": category,
            "position": position,
            "brand": brand,
            "inStock": inStock ? "1" : nil,
            "location": location
        ])
        let fileName = location.map { "inventory-\($0).xlsx" } ?? "inventory.xlsx"
        return try await client.download("/inventory/skus/export\(qs)", fileName: fileName)
    }

    func listBrands() async throws -> [String] {
        try await client.request("/inventory/brands")
    }

    func getSku(id: String) async throws -> TireSku {
        // The backend reads individual SKUs through the list's IDs filter;
        // /inventory/skus/:id only supports mutations, not GET.
        let page = try await listSkus(ids: [id], pageSize: 1)
        guard let sku = page.items.first(where: { $0.id == id }) else {
            throw APIError(status: 404, message: "Tire not found.")
        }
        return sku
    }

    func resolveSku(idOrSku: String) async throws -> TireSku {
        // Inventory selections carry database IDs, which text search does not
        // match. Only fall back to a SKU-code search when the ID is absent.
        do {
            return try await getSku(id: idOrSku)
        } catch let error as APIError where error.status == 404 {
            let page = try await listSkus(q: idOrSku, pageSize: 50)
            guard let exact = page.items.first(where: { $0.id == idOrSku || $0.sku == idOrSku }) else {
                throw APIError(status: 404, message: "Tire not found.")
            }
            return exact
        }
    }

    func createSku(_ body: SkuInput) async throws -> TireSku {
        try await client.request("/inventory/skus", method: "POST", body: body)
    }

    func updateSku(id: String, body: TireSkuPatchInput) async throws -> TireSku {
        try await client.request("/inventory/skus/\(id)", method: "PATCH", body: body)
    }

    func adjust(
        id: String,
        delta: Int,
        reason: StockAdjustReason,
        location: String? = nil,
        note: String? = nil
    ) async throws -> ImmediateOrApproval<InventoryItem> {
        try await client.request(
            "/inventory/skus/\(id)/adjust",
            method: "POST",
            body: StockAdjustmentInput(delta: delta, reason: reason, location: location, note: note)
        )
    }

    func adjustBatch(_ body: StockAdjustBatchInput) async throws -> ImmediateOrApproval<StockAdjustBatchResult> {
        try await client.request("/inventory/adjust-batch", method: "POST", body: body)
    }

    func listAdjustmentBatches(
        q: String? = nil,
        location: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<StockAdjustBatch> {
        let qs = query([
            "q": q,
            "location": location,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/inventory/adjustments\(qs)")
    }

    func skuHistory(
        id: String,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> SkuHistory {
        let qs = query(["page": page, "pageSize": pageSize])
        return try await client.request("/inventory/skus/\(id)/history\(qs)")
    }

    func updateStorefront(id: String, body: StorefrontSkuPatchInput) async throws -> StorefrontSkuPatchResult {
        try await client.request("/inventory/skus/\(id)/storefront", method: "PATCH", body: body)
    }

    func setStorefrontVisibility(ids: [String], visible: Bool) async throws -> StorefrontVisibilityResult {
        try await client.request(
            "/inventory/skus/storefront-visibility",
            method: "POST",
            body: StorefrontVisibilityInput(ids: ids, visible: visible)
        )
    }

    func listSkuImages(skuId: String) async throws -> [SkuImage] {
        try await client.request("/inventory/skus/\(skuId)/images")
    }

    func uploadSkuImage(
        skuId: String,
        fileURL: URL,
        fileName: String,
        mimeType: String
    ) async throws -> SkuImage {
        try await client.uploadMultipart(
            "/inventory/skus/\(skuId)/images",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func addSkuImageLink(skuId: String, url: String) async throws -> SkuImage {
        try await client.request(
            "/inventory/skus/\(skuId)/image-links",
            method: "POST",
            body: SkuImageLinkInput(url: url)
        )
    }

    func updateSkuImageLink(imageId: String, url: String) async throws -> SkuImage {
        try await client.request(
            "/inventory/sku-images/\(imageId)",
            method: "PATCH",
            body: SkuImageLinkInput(url: url)
        )
    }

    func reorderSkuImages(skuId: String, ids: [String]) async throws -> [SkuImage] {
        try await client.request(
            "/inventory/skus/\(skuId)/images/reorder",
            method: "POST",
            body: SkuImageReorderInput(ids: ids)
        )
    }

    func deleteSkuImage(imageId: String) async throws -> EmptyResponse {
        try await client.request("/inventory/sku-images/\(imageId)", method: "DELETE")
    }

    func checkSkuImageLinks(skuId: String? = nil) async throws -> SkuImageLinkReport {
        if let skuId {
            return try await client.request(
                "/inventory/image-links/check",
                method: "POST",
                body: SkuImageLinkCheckInput(skuId: skuId)
            )
        }
        return try await client.request(
            "/inventory/image-links/check",
            method: "POST",
            body: EmptyBody()
        )
    }

    func importSkus(fileURL: URL, fileName: String, mimeType: String) async throws -> ImportSummary {
        try await client.uploadMultipart(
            "/inventory/skus/import",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType
        )
    }
}

struct WarehousesAPI {
    var client = APIClient.shared

    func list(activeOnly: Bool = false) async throws -> [Warehouse] {
        let suffix = activeOnly ? "?active=true" : ""
        return try await client.request("/warehouses\(suffix)")
    }

    func create(_ body: WarehouseCreateInput) async throws -> Warehouse {
        try await client.request("/warehouses", method: "POST", body: body)
    }

    func update(id: String, body: WarehousePatchInput) async throws -> Warehouse {
        try await client.request("/warehouses/\(id)", method: "PATCH", body: body)
    }

    func setDefault(id: String) async throws -> Warehouse {
        try await client.request("/warehouses/\(id)/set-default", method: "POST", body: EmptyBody())
    }
}

struct SalesAPI {
    var client = APIClient.shared

    func list(
        q: String? = nil,
        status: SaleStatus? = nil,
        from: String? = nil,
        to: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        before: String? = nil,
        beforeId: String? = nil,
        summary: Bool? = nil
    ) async throws -> SalesListResponse {
        let qs = query([
            "q": q,
            "status": status,
            "from": from,
            "to": to,
            "sortBy": sortBy,
            "sortOrder": sortOrder,
            "page": page,
            "pageSize": pageSize,
            "before": before,
            "beforeId": beforeId,
            "summary": summary.map { $0 ? "true" : "false" }
        ])
        let response: SalesListResponse = try await client.request("/sales\(qs)")
        return response
    }

    func bestSellers(
        months: Int? = nil,
        from: String? = nil,
        to: String? = nil,
        location: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> BestSellersResponse {
        let qs = query([
            "months": months,
            "from": from,
            "to": to,
            "location": location,
            "sortBy": sortBy,
            "sortOrder": sortOrder,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/sales/best-sellers\(qs)")
    }

    func exportBestSellers(
        months: Int? = nil,
        from: String? = nil,
        to: String? = nil,
        location: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        fileName: String = "best-sellers.xlsx"
    ) async throws -> URL {
        let qs = query([
            "months": months,
            "from": from,
            "to": to,
            "location": location,
            "sortBy": sortBy,
            "sortOrder": sortOrder
        ])
        return try await client.download("/sales/best-sellers/export\(qs)", fileName: fileName)
    }

    func get(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)")
    }

    func create(_ body: SaleUpsertInput, idempotencyKey: String? = nil) async throws -> SaleCreateResult {
        try await client.request(
            "/sales",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func update(id: String, body: SaleUpsertInput) async throws -> Sale {
        try await client.request("/sales/\(id)", method: "PATCH", body: body)
    }

    /// Reassign (or clear, via explicit `null`) a confirmed sale's salesperson.
    func assignSalesperson(id: String, body: SaleSalespersonPatch) async throws -> Sale {
        try await client.request("/sales/\(id)/salesperson", method: "PATCH", body: body)
    }

    func promoteToQuote(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)/quote", method: "POST")
    }

    func confirm(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)/confirm", method: "POST")
    }

    func reverseToDraft(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)/reverse-to-draft", method: "POST")
    }

    func revertQuoteToDraft(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)/revert-draft", method: "POST")
    }

    func cancelQuote(id: String, reason: String? = nil) async throws -> Sale {
        try await client.request("/sales/\(id)/cancel", method: "POST", body: ReasonInput(reason: reason))
    }

    func deleteDraft(id: String) async throws -> OkResponse {
        try await client.request("/sales/\(id)", method: "DELETE")
    }

    func voidSale(id: String, reason: String? = nil) async throws -> ImmediateOrApproval<Sale> {
        try await client.request("/sales/\(id)/void", method: "POST", body: ReasonInput(reason: reason))
    }
}

struct CustomersAPI {
    var client = APIClient.shared

    func taxRate(
        customerId: String,
        fulfillment: SaleFulfillment,
        location: String? = nil
    ) async throws -> CustomerTaxRateResponse {
        let search = query([
            "fulfillment": fulfillment.rawValue,
            "location": fulfillment == .pickup ? location : nil
        ])
        return try await client.request("/customers/\(customerId)/tax-rate\(search)")
    }

    func lastSalePrices(customerId: String, skuIds: [String]) async throws -> [CustomerLastSalePrice] {
        let ids = Array(Set(skuIds)).sorted()
        var result: [CustomerLastSalePrice] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            try Task.checkCancellation()
            let batch = ids[start..<min(start + 100, ids.count)].joined(separator: ",")
            let prices: [CustomerLastSalePrice] = try await client.request(
                "/customers/\(customerId)/last-sale-prices\(query(["skuIds": batch]))"
            )
            result.append(contentsOf: prices)
        }
        return result
    }

    func list(q: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<Customer> {
        try await client.request("/customers\(query(["q": q, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> Customer {
        try await client.request("/customers/\(id)")
    }

    func create(_ body: NewCustomerInput) async throws -> Customer {
        try await client.request("/customers", method: "POST", body: body)
    }

    func update(id: String, body: CustomerProfilePatch) async throws -> Customer {
        try await client.request("/customers/\(id)", method: "PATCH", body: body)
    }

    func updateTags(id: String, body: CustomerTagsPatch) async throws -> Customer {
        try await client.request("/customers/\(id)", method: "PATCH", body: body)
    }

    func updateAccount(id: String, body: CustomerAccountPatch) async throws -> Customer {
        try await client.request("/customers/\(id)", method: "PATCH", body: body)
    }

    func updatePriceTier(id: String, body: CustomerPriceTierPatch) async throws -> Customer {
        try await client.request("/customers/\(id)", method: "PATCH", body: body)
    }

    func updateSalesperson(id: String, body: CustomerSalespersonPatch) async throws -> Customer {
        try await client.request("/customers/\(id)", method: "PATCH", body: body)
    }

    func setTaxStatus(id: String, body: CustomerTaxStatusInput) async throws -> Customer {
        try await client.request("/customers/\(id)/tax-status", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> OkResponse {
        try await client.request("/customers/\(id)", method: "DELETE")
    }

    func creditBalance(id: String) async throws -> CreditBalance {
        try await client.request("/customers/\(id)/credit-balance")
    }

    func account(id: String) async throws -> CustomerAccount {
        try await client.request("/customers/\(id)/account")
    }

    func uploadDocument(
        id: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        kind: CustomerDocumentKind = "ST5_EXEMPTION",
        note: String? = nil
    ) async throws -> CustomerDocument {
        var fields = ["kind": kind]
        if let note, !note.isEmpty {
            fields["note"] = note
        }
        return try await client.uploadMultipart(
            "/customers/\(id)/documents",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
    }

    func downloadDocument(id: String, document: CustomerDocument) async throws -> URL {
        let safeName = document.filename.replacingOccurrences(of: "/", with: "-")
        return try await client.download("/customers/\(id)/documents/\(document.id)", fileName: safeName)
    }

    func deleteDocument(id: String, documentId: String) async throws -> OkResponse {
        try await client.request("/customers/\(id)/documents/\(documentId)", method: "DELETE")
    }

    func users(id: String) async throws -> [CustomerUser] {
        try await client.request("/customers/\(id)/users")
    }

    func createUser(id: String, body: CustomerUserCreateInput) async throws -> CustomerUser {
        try await client.request("/customers/\(id)/users", method: "POST", body: body)
    }

    func resetUserPassword(id: String, userId: String, password: String) async throws -> EmptyResponse {
        try await client.request("/customers/\(id)/users/\(userId)/reset-password", method: "POST", body: PasswordInput(password: password))
    }

    func setUserActive(id: String, userId: String, body: CustomerUserActiveInput) async throws -> EmptyResponse {
        try await client.request("/customers/\(id)/users/\(userId)/toggle-active", method: "POST", body: body)
    }

    func unlockUser(id: String, userId: String) async throws -> EmptyResponse {
        try await client.request("/customers/\(id)/users/\(userId)/unlock", method: "POST")
    }
}

struct ZipLocationsAPI {
    var client = APIClient.shared

    func lookup(postalCode: String, state: String = "GA") async throws -> ZipLookupResult {
        try await client.request("/zip-locations/lookup\(query(["postalCode": postalCode, "state": state]))")
    }
}

struct TaxRatesAPI {
    var client = APIClient.shared

    func lookup(state: String? = nil, county: String? = nil, city: String? = nil, postalCode: String? = nil) async throws -> SalesTaxRate? {
        let search = query([
            "state": state,
            "county": county,
            "city": city,
            "postalCode": postalCode
        ])
        return try await client.request("/settings/tax-rates/lookup\(search)")
    }
}

struct PriceTiersAPI {
    var client = APIClient.shared

    func list() async throws -> [PriceTier] {
        try await client.request("/price-tiers")
    }
}

struct ServicesAPI {
    var client = APIClient.shared

    func list() async throws -> [ServiceItem] {
        try await client.request("/services")
    }
}

struct WorkOrdersAPI {
    var client = APIClient.shared

    func list(status: WorkOrderStatus? = nil) async throws -> [WorkOrder] {
        try await client.request("/work-orders\(query(["status": status]))")
    }

    func get(id: String) async throws -> WorkOrder {
        try await client.request("/work-orders/\(id)")
    }

    func update(id: String, body: WorkOrderPatchInput) async throws -> EmptyResponse {
        try await client.request("/work-orders/\(id)", method: "PATCH", body: body)
    }

    func addTask(id: String, description: String) async throws -> WorkOrderTask {
        try await client.request("/work-orders/\(id)/tasks", method: "POST", body: DescriptionInput(description: description))
    }

    func toggleTask(workOrderId: String, taskId: String, done: Bool) async throws -> WorkOrderTask {
        try await client.request("/work-orders/\(workOrderId)/tasks/\(taskId)", method: "PATCH", body: DoneInput(done: done))
    }

    func deleteTask(workOrderId: String, taskId: String) async throws -> EmptyResponse {
        try await client.request("/work-orders/\(workOrderId)/tasks/\(taskId)", method: "DELETE")
    }
}

struct ReturnsAPI {
    var client = APIClient.shared

    func list(status: ReturnStatus? = nil, saleId: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<ReturnRecord> {
        try await client.request("/returns\(query(["status": status, "saleId": saleId, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> ReturnRecord {
        try await client.request("/returns/\(id)")
    }

    func returnable(saleId: String) async throws -> Returnable {
        try await client.request("/sales/\(saleId)/returnable")
    }

    func create(saleId: String, body: CreateReturnInput) async throws -> ReturnRecord {
        try await client.request("/sales/\(saleId)/returns", method: "POST", body: body)
    }

    func post(id: String, body: PostReturnInput? = nil) async throws -> ReturnRecord {
        let result: ReturnRecord = try await client.request("/returns/\(id)/post", method: "POST", body: body ?? PostReturnInput(netPayment: nil, netRefund: nil))
        await CheckRegisterEvents.changed()
        return result
    }

    func void(id: String, reason: String? = nil) async throws -> ReturnRecord {
        try await client.request("/returns/\(id)/void", method: "POST", body: ReasonInput(reason: reason))
    }
}

struct SuppliersAPI {
    var client = APIClient.shared

    func list(q: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<Supplier> {
        try await client.request("/suppliers\(query(["q": q, "page": page, "pageSize": pageSize ?? 1000]))")
    }

    func get(id: String) async throws -> SupplierDetail {
        try await client.request("/suppliers/\(id)")
    }

    func containers(id: String, page: Int? = nil, pageSize: Int? = nil, status: String? = nil) async throws -> Paged<SupplierContainerRow> {
        try await client.request("/suppliers/\(id)/containers\(query(["page": page, "pageSize": pageSize, "status": status]))")
    }

    func costs(id: String, page: Int? = nil, pageSize: Int? = nil, scope: String? = nil, status: String? = nil) async throws -> Paged<SupplierCostRow> {
        try await client.request("/suppliers/\(id)/costs\(query(["page": page, "pageSize": pageSize, "scope": scope, "status": status]))")
    }

    func payments(id: String, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<SupplierPaymentRow> {
        try await client.request("/suppliers/\(id)/payments\(query(["page": page, "pageSize": pageSize]))")
    }

    func returns(id: String, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<SupplierReturnRow> {
        try await client.request("/suppliers/\(id)/returns\(query(["page": page, "pageSize": pageSize]))")
    }

    func create(_ body: SupplierSaveInput) async throws -> Supplier {
        try await client.request("/suppliers", method: "POST", body: body)
    }

    func update(id: String, body: SupplierSaveInput) async throws -> Supplier {
        try await client.request("/suppliers/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> Supplier {
        try await client.request("/suppliers/\(id)", method: "DELETE")
    }
}

struct VendorsAPI {
    var client = APIClient.shared

    func list(
        q: String? = nil,
        category: VendorCategory? = nil,
        active: Bool? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<Vendor> {
        let qs = query([
            "q": q,
            "category": category,
            "active": active,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/vendors\(qs)")
    }

    func get(id: String) async throws -> VendorDetail {
        try await client.request("/vendors/\(id)")
    }

    func costs(id: String, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<VendorRecentCost> {
        try await client.request("/vendors/\(id)/costs\(query(["page": page, "pageSize": pageSize]))")
    }

    func expenses(id: String, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<VendorRecentExpense> {
        try await client.request("/vendors/\(id)/expenses\(query(["page": page, "pageSize": pageSize]))")
    }

    func refunds(id: String, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<VendorRefundRecord> {
        try await client.request("/vendors/\(id)/refunds\(query(["page": page, "pageSize": pageSize]))")
    }

    func create(_ body: VendorSaveInput) async throws -> Vendor {
        try await client.request("/vendors", method: "POST", body: body)
    }

    func update(id: String, body: VendorSaveInput) async throws -> Vendor {
        try await client.request("/vendors/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> OkResponse {
        try await client.request("/vendors/\(id)", method: "DELETE")
    }

    func recordRefund(id: String, body: VendorRefundInput) async throws -> VendorRefundResult {
        try await client.request("/vendors/\(id)/refund", method: "POST", body: body)
    }

    func reverseRefund(id: String, reason: String? = nil) async throws -> OkResponse {
        try await client.request("/vendors/refunds/\(id)/reverse", method: "POST", body: ReasonInput(reason: reason))
    }
}

struct ReceivableApplication: Codable, Equatable {
    let invoiceId: String
    let amount: Double
}

struct ReceivablesPayInput: Codable {
    let customerId: String
    let paymentMethodId: String
    let applications: [ReceivableApplication]
    let reference: String?
    let note: String?
    var plannedDepositDate: String? = nil
}

struct StatementEmailInput: Codable {
    let to: String?
    let subject: String?
    let message: String?
}

struct PayableApplication: Codable {
    let costId: String
    let amount: Double
}

struct PayablesPayInput: Codable {
    var expectedVendorKey: String? = nil
    let applications: [PayableApplication]
    let paidAt: String?
    let reference: String?
    let note: String?
    let accountId: String?
}

struct MoneyAPI {
    var client = APIClient.shared

    func receivables(page: Int? = nil, pageSize: Int? = nil, q: String? = nil) async throws -> BalancePage<ReceivableCustomer> {
        try await client.request("/receivables\(query(["page": page, "pageSize": pageSize, "q": q]))")
    }

    func receivable(customerId: String) async throws -> ReceivableCustomerDetail {
        try await client.request("/receivables/\(customerId)")
    }

    func payReceivables(
        _ body: ReceivablesPayInput,
        idempotencyKey: String? = nil
    ) async throws -> SettlementResult {
        let result: SettlementResult = try await client.request(
            "/receivables/pay",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
        await CheckRegisterEvents.changed()
        return result
    }

    func downloadStatement(customerId: String) async throws -> URL {
        try await client.download("/receivables/\(customerId)/statement.pdf", fileName: "statement-\(customerId).pdf")
    }

    func emailStatement(customerId: String, body: StatementEmailInput) async throws -> OkResponse {
        try await client.request("/receivables/\(customerId)/statement/email", method: "POST", body: body)
    }

    func payables(page: Int? = nil, pageSize: Int? = nil, q: String? = nil) async throws -> BalancePage<PayableVendor> {
        try await client.request("/payables\(query(["page": page, "pageSize": pageSize, "q": q]))")
    }

    func payable(vendorKey: String) async throws -> PayableVendorDetail {
        let encoded = vendorKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vendorKey
        return try await client.request("/payables/\(encoded)")
    }

    func payPayables(
        _ body: PayablesPayInput,
        idempotencyKey: String? = nil
    ) async throws -> SettlementResult {
        try await client.request(
            "/payables/pay",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func receipts(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<CustomerReceipt> {
        try await client.request("/receipts\(query(["page": page, "pageSize": pageSize]))")
    }

    func receipt(id: String) async throws -> CustomerReceiptDetail {
        try await client.request("/receipts/\(id)")
    }

    func reverseReceipt(id: String) async throws -> SettlementResult {
        let result: SettlementResult = try await client.request("/receipts/\(id)/reverse", method: "POST", body: EmptyBody())
        await CheckRegisterEvents.changed()
        return result
    }

    func supplierPayments(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<SupplierPayment> {
        try await client.request("/payables/payments\(query(["page": page, "pageSize": pageSize]))")
    }

    func supplierPayment(id: String) async throws -> SupplierPaymentDetail {
        try await client.request("/payables/payments/\(id)")
    }

    func reverseSupplierPayment(id: String) async throws -> SettlementResult {
        try await client.request("/payables/payments/\(id)/reverse", method: "POST", body: EmptyBody())
    }
}

struct TransfersAPI {
    var client = APIClient.shared

    func list(
        status: StockTransferStatus? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<StockTransfer> {
        try await client.request(
            "/transfers\(query(["status": status, "page": page, "pageSize": pageSize]))"
        )
    }

    func get(id: String) async throws -> StockTransfer {
        try await client.request("/transfers/\(id)")
    }

    func create(_ body: StockTransferInput) async throws -> StockTransfer {
        try await client.request("/transfers", method: "POST", body: body)
    }

    func update(id: String, body: StockTransferInput) async throws -> StockTransfer {
        try await client.request("/transfers/\(id)", method: "PATCH", body: body)
    }

    func deleteDraft(id: String) async throws -> OkResponse {
        try await client.request("/transfers/\(id)", method: "DELETE")
    }

    func post(id: String) async throws -> ImmediateOrApproval<StockTransfer> {
        try await client.request("/transfers/\(id)/post", method: "POST", body: EmptyBody())
    }

    func void(id: String, reason: String? = nil) async throws -> StockTransfer {
        try await client.request(
            "/transfers/\(id)/void",
            method: "POST",
            body: ReasonInput(reason: reason)
        )
    }
}

struct InventoryCountsAPI {
    var client = APIClient.shared

    func list(status: InventoryCountStatus? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<InventoryCountListItem> {
        try await client.request("/inventory-counts\(query(["status": status, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> InventoryCountDetail {
        try await client.request("/inventory-counts/\(id)")
    }

    func create(_ body: InventoryCountCreateInput) async throws -> ApprovalRequestRef {
        try await client.request("/inventory-counts", method: "POST", body: body)
    }

    func updateLine(id: String, lineId: String, body: InventoryCountLineInput) async throws -> InventoryCountLine {
        try await client.request("/inventory-counts/\(id)/lines/\(lineId)", method: "PATCH", body: body)
    }

    func post(id: String) async throws -> ImmediateOrApproval<InventoryCountDetail> {
        try await client.request("/inventory-counts/\(id)/post", method: "POST")
    }

    func reverse(id: String, reason: String? = nil) async throws -> ImmediateOrApproval<InventoryCountDetail> {
        try await client.request("/inventory-counts/\(id)/reverse", method: "POST", body: ReasonInput(reason: reason))
    }

    func remove(id: String) async throws -> OkResponse {
        try await client.request("/inventory-counts/\(id)", method: "DELETE")
    }
}

struct ContainersAPI {
    var client = APIClient.shared

    func list(
        status: ContainerStatus? = nil,
        q: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<ContainerListItem> {
        let qs = query([
            "status": status,
            "q": q,
            "sortBy": sortBy,
            "sortOrder": sortOrder,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/containers\(qs)")
    }

    func get(id: String) async throws -> Container {
        try await client.request("/containers/\(id)")
    }

    func incoming(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<IncomingInventoryLine> {
        try await client.request("/containers/incoming\(query(["page": page, "pageSize": pageSize]))")
    }

    func incomingCombined(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<IncomingInventoryCombined> {
        try await client.request("/containers/incoming/combined\(query(["page": page, "pageSize": pageSize]))")
    }

    func create(_ body: ContainerCreateInput) async throws -> Container {
        try await client.request("/containers", method: "POST", body: body)
    }

    func update(id: String, body: ContainerPatchInput) async throws -> Container {
        try await client.request("/containers/\(id)", method: "PATCH", body: body)
    }

    func setStatus(id: String, status: ContainerStatus) async throws -> Container {
        try await client.request("/containers/\(id)/status", method: "POST", body: ContainerStatusInput(status: status))
    }

    func receive(id: String) async throws -> Container {
        try await client.request("/containers/\(id)/receive", method: "POST", body: EmptyBody())
    }

    func unreceive(id: String, reason: String? = nil) async throws -> Container {
        try await client.request("/containers/\(id)/unreceive", method: "POST", body: ReasonInput(reason: reason))
    }

    func cancel(id: String) async throws -> Container {
        try await client.request("/containers/\(id)/cancel", method: "POST", body: EmptyBody())
    }

    func addCost(id: String, body: ContainerCostSaveInput) async throws -> ContainerCost {
        try await client.request("/containers/\(id)/costs", method: "POST", body: body)
    }

    func updateCost(id: String, costId: String, body: ContainerCostSaveInput) async throws -> ContainerCost {
        try await client.request("/containers/\(id)/costs/\(costId)", method: "PATCH", body: body)
    }

    /// Reschedule (or clear) one bill's due date, which stays allowed after
    /// receipt when every costing field is frozen.
    func setCostDueDate(id: String, costId: String, dueAt: String?) async throws -> ContainerCost {
        try await client.request(
            "/containers/\(id)/costs/\(costId)",
            method: "PATCH",
            body: ContainerCostDueDateInput(dueAt: dueAt)
        )
    }

    func deleteCost(id: String, costId: String) async throws -> OkResponse {
        try await client.request("/containers/\(id)/costs/\(costId)", method: "DELETE")
    }

    func uploadAttachment(
        id: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        kind: ContainerAttachmentKind,
        note: String? = nil
    ) async throws -> ContainerAttachment {
        var fields = ["kind": kind]
        if let note {
            fields["note"] = note
        }
        return try await client.uploadMultipart(
            "/containers/\(id)/attachments",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
    }

    func downloadAttachment(id: String, attachment: ContainerAttachment) async throws -> URL {
        let safeName = attachment.filename.replacingOccurrences(of: "/", with: "-")
        return try await client.download(
            "/containers/\(id)/attachments/\(attachment.id)/download",
            fileName: safeName
        )
    }

    func deleteAttachment(id: String, attachmentId: String) async throws -> OkResponse {
        try await client.request("/containers/\(id)/attachments/\(attachmentId)", method: "DELETE")
    }
}

struct AccountingAPI {
    var client = APIClient.shared

    func accounts() async throws -> [Account] {
        try await client.request("/accounting/accounts")
    }

    func expenseAccounts() async throws -> [ExpenseAccount] {
        try await client.request("/accounting/expense-accounts")
    }

    func journal(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<JournalEntry> {
        try await client.request("/accounting/journal\(query(["page": page, "pageSize": pageSize]))")
    }

    func pnl(from: String? = nil, to: String? = nil) async throws -> Pnl {
        try await client.request("/accounting/reports/pnl\(query(["from": from, "to": to]))")
    }

    func accountHistory(code: String, page: Int? = nil, pageSize: Int? = nil) async throws -> AccountHistory {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await client.request("/accounting/accounts/\(encoded)/history\(query(["page": page, "pageSize": pageSize]))")
    }

    func checkReminders() async throws -> CheckReminderSummary {
        try await client.request("/accounting/check-reminders")
    }

    func undepositedCheckReport(asOf: String) async throws -> UndepositedCheckReport {
        try await client.request("/accounting/reports/undeposited-checks\(query(["asOf": asOf]))")
    }

    func exportUndepositedChecks(asOf: String) async throws -> URL {
        try await client.download(
            "/accounting/reports/undeposited-checks/export\(query(["asOf": asOf]))",
            fileName: "undeposited-checks-\(asOf).xlsx"
        )
    }

    func updatePlannedDepositDate(paymentId: String, plannedDepositDate: String) async throws -> CheckPlannedDateResult {
        let result: CheckPlannedDateResult = try await client.request(
            "/accounting/checks/\(paymentId)/planned-deposit-date",
            method: "PATCH",
            body: ["plannedDepositDate": plannedDepositDate]
        )
        await CheckRegisterEvents.changed()
        return result
    }
}

struct TransferCreateInput: Codable {
    let fromCode: String
    let toCode: String
    let amount: Double
    let fee: Double
    let note: String?
    let reference: String?
    let paymentIds: [String]?
}

struct VendorBankAccountCreateInput: Codable {
    let label: String?
    let beneficiaryName: String
    let bankName: String
    let accountNumber: String
    let bankCountry: String
    let currency: String
    let routingNumber: String?
    let swift: String?
    let bankAddress: String?
    let intermediaryBankName: String?
    let intermediarySwift: String?
    let intermediaryAccount: String?
    let financeContactName: String?
    let financeContactEmail: String?
    let isDefault: Bool
    let note: String?
}

struct VendorBankAccountPatchInput: Encodable {
    let label: String?
    let beneficiaryName: String
    let bankName: String
    let accountNumber: String?
    let bankCountry: String
    let currency: String
    let routingNumber: String?
    let swift: String?
    let bankAddress: String?
    let intermediaryBankName: String?
    let intermediarySwift: String?
    let intermediaryAccount: String?
    let financeContactName: String?
    let financeContactEmail: String?
    let isDefault: Bool
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case label
        case beneficiaryName
        case bankName
        case accountNumber
        case bankCountry
        case currency
        case routingNumber
        case swift
        case bankAddress
        case intermediaryBankName
        case intermediarySwift
        case intermediaryAccount
        case financeContactName
        case financeContactEmail
        case isDefault
        case note
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(label, forKey: .label)
        try container.encode(beneficiaryName, forKey: .beneficiaryName)
        try container.encode(bankName, forKey: .bankName)
        try container.encodeIfPresent(accountNumber, forKey: .accountNumber)
        try container.encode(bankCountry, forKey: .bankCountry)
        try container.encode(currency, forKey: .currency)
        try container.encodeNullable(routingNumber, forKey: .routingNumber)
        try container.encodeNullable(swift, forKey: .swift)
        try container.encodeNullable(bankAddress, forKey: .bankAddress)
        try container.encodeNullable(intermediaryBankName, forKey: .intermediaryBankName)
        try container.encodeNullable(intermediarySwift, forKey: .intermediarySwift)
        // Account-number fields are replacement-only in the editor: blank
        // means keep the masked value already on file, not clear it.
        try container.encodeIfPresent(intermediaryAccount, forKey: .intermediaryAccount)
        try container.encodeNullable(financeContactName, forKey: .financeContactName)
        try container.encodeNullable(financeContactEmail, forKey: .financeContactEmail)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encodeNullable(note, forKey: .note)
    }
}

struct PaymentApplicationLineInput: Codable, Equatable {
    let containerCostId: String
    let amount: Double
    let note: String?
}

struct PaymentApplicationCreateInput: Codable, Equatable {
    let vendorId: String
    let bankAccountId: String?
    let currency: String
    let purpose: String
    let requestedAt: String
    let plannedPayAt: String?
    let note: String?
    let lines: [PaymentApplicationLineInput]
}

struct PaymentApplicationUpdateInput: Encodable, Equatable {
    let bankAccountId: String?
    let currency: String
    let purpose: String
    let requestedAt: String
    let plannedPayAt: String?
    let note: String?
    let lines: [PaymentApplicationLineInput]

    private enum CodingKeys: String, CodingKey {
        case bankAccountId
        case currency
        case purpose
        case requestedAt
        case plannedPayAt
        case note
        case lines
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bankAccountId, forKey: .bankAccountId)
        try container.encode(currency, forKey: .currency)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(requestedAt, forKey: .requestedAt)
        try container.encodeNullable(plannedPayAt, forKey: .plannedPayAt)
        try container.encodeNullable(note, forKey: .note)
        try container.encode(lines, forKey: .lines)
    }
}

struct PaymentApplicationRejectInput: Codable {
    let comment: String
}

struct PaymentApplicationEmailInput: Codable, Equatable {
    let idempotencyKey: String
    let to: String?
    let cc: String?
    let variant: String
    let subject: String?
    let body: String?
    let attachmentIds: [String]?
}

struct ExpenseCreateInput: Codable {
    let amount: Double
    let expenseCode: String
    let paidFromCode: String
    let date: String?
    let payee: String?
    let vendorId: String?
    let reference: String?
    let note: String?
}

struct PaymentMethodCreateInput: Codable {
    let name: String
    let accountCode: String
    let feeRate: Double?
    let payoutAccountCode: String?
}

/// Tri-state PATCH body for a payment method. Each field is double-optional:
/// `.none` = leave the field alone, `.some(nil)` = clear it, `.some(x)` = set it.
/// Only fields that were supplied are encoded, so a partial PATCH never nulls
/// fields the caller didn't intend to touch.
struct PaymentMethodPatchInput: Encodable {
    var isActive: Bool?? = nil
    var name: String?? = nil
    var accountCode: String?? = nil
    var feeRate: Double?? = nil
    var payoutAccountCode: String?? = nil

    init(
        isActive: Bool?? = nil,
        name: String?? = nil,
        accountCode: String?? = nil,
        feeRate: Double?? = nil,
        payoutAccountCode: String?? = nil
    ) {
        self.isActive = isActive
        self.name = name
        self.accountCode = accountCode
        self.feeRate = feeRate
        self.payoutAccountCode = payoutAccountCode
    }

    private enum CodingKeys: String, CodingKey {
        case isActive
        case name
        case accountCode
        case feeRate
        case payoutAccountCode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let isActive { try container.encodeNullable(isActive, forKey: .isActive) }
        if let name { try container.encodeNullable(name, forKey: .name) }
        if let accountCode { try container.encodeNullable(accountCode, forKey: .accountCode) }
        if let feeRate { try container.encodeNullable(feeRate, forKey: .feeRate) }
        if let payoutAccountCode { try container.encodeNullable(payoutAccountCode, forKey: .payoutAccountCode) }
    }
}

struct CashAccountCreateInput: Codable {
    let name: String
}

struct CashAccountsAPI {
    var client = APIClient.shared

    func createAccount(name: String) async throws -> CashAccount {
        try await client.request("/accounting/cash-accounts", method: "POST", body: CashAccountCreateInput(name: name))
    }

    func list() async throws -> [CashAccount] {
        try await client.request("/accounting/cash-accounts")
    }

    /// Paged transfer history for the Funds & Accounts screen.
    func transfersPaged(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<CashTransfer> {
        try await client.request("/accounting/transfers\(query(["page": page, "pageSize": pageSize]))")
    }

    /// Filtered on the server before pagination, including reversed deposits.
    func checkDeposits(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<CashTransferDetail> {
        try await client.request("/accounting/check-deposits\(query(["page": page, "pageSize": pageSize]))")
    }

    func transfer(id: String) async throws -> CashTransferDetail {
        try await client.request("/accounting/transfers/\(id)")
    }

    func createTransfer(
        _ body: TransferCreateInput,
        idempotencyKey: String? = nil
    ) async throws -> OkResponse {
        let result: OkResponse = try await client.request(
            "/accounting/transfers",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
        await CheckRegisterEvents.changed()
        return result
    }

    func reverseTransfer(id: String) async throws -> OkResponse {
        let result: OkResponse = try await client.request("/accounting/transfers/\(id)/reverse", method: "POST", body: EmptyBody())
        await CheckRegisterEvents.changed()
        return result
    }

    func undepositedChecks() async throws -> UndepositedChecks {
        try await client.request("/accounting/undeposited-checks")
    }

    /// Paged expense history. The backend returns a paged envelope, so this is
    /// used by Funds & Accounts; legacy flat loading is removed.
    func expenses(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<ExpensePayment> {
        try await client.request("/accounting/expenses\(query(["page": page, "pageSize": pageSize]))")
    }

    func createExpense(
        _ body: ExpenseCreateInput,
        idempotencyKey: String? = nil
    ) async throws -> ExpenseCreateResponse {
        try await client.request(
            "/accounting/expenses",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func reverseExpense(id: String) async throws -> OkResponse {
        try await client.request("/accounting/expenses/\(id)/reverse", method: "POST", body: EmptyBody())
    }

    func expenseReceipts(expenseId: String) async throws -> [ExpenseReceipt] {
        try await client.request("/accounting/expenses/\(expenseId)/receipts")
    }

    func uploadExpenseReceipt(expenseId: String, fileURL: URL, fileName: String, mimeType: String) async throws -> ExpenseReceipt {
        try await client.uploadMultipart(
            "/accounting/expenses/\(expenseId)/receipts",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func deleteExpenseReceipt(id: String) async throws -> OkResponse {
        try await client.request("/accounting/expense-receipts/\(id)", method: "DELETE")
    }

    func downloadExpenseReceipt(_ receipt: ExpenseReceipt) async throws -> URL {
        try await client.download("/accounting/expense-receipts/\(receipt.id)", fileName: receipt.filename)
    }

    func methods() async throws -> [PaymentMethod] {
        try await client.request("/accounting/payment-methods")
    }

    /// Paged payment methods for the Funds & Accounts screen.
    func methodsPaged(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<PaymentMethod> {
        try await client.request("/accounting/payment-methods\(query(["page": page, "pageSize": pageSize]))")
    }

    func createMethod(_ body: PaymentMethodCreateInput) async throws -> PaymentMethod {
        try await client.request("/accounting/payment-methods", method: "POST", body: body)
    }

    func updateMethod(id: String, body: PaymentMethodPatchInput) async throws -> PaymentMethod {
        try await client.request("/accounting/payment-methods/\(id)", method: "PATCH", body: body)
    }

    func deleteMethod(id: String) async throws -> OkResponse {
        try await client.request("/accounting/payment-methods/\(id)", method: "DELETE")
    }
}

struct VendorBankAccountsAPI {
    var client = APIClient.shared

    func list(vendorId: String) async throws -> [VendorBankAccount] {
        try await client.request("/vendors/\(vendorId)/bank-accounts")
    }

    func create(vendorId: String, body: VendorBankAccountCreateInput) async throws -> VendorBankAccount {
        try await client.request("/vendors/\(vendorId)/bank-accounts", method: "POST", body: body)
    }

    func update(vendorId: String, id: String, body: VendorBankAccountPatchInput) async throws -> VendorBankAccount {
        try await client.request("/vendors/\(vendorId)/bank-accounts/\(id)", method: "PATCH", body: body)
    }

    func setDefault(vendorId: String, id: String) async throws -> VendorBankAccount {
        try await client.request("/vendors/\(vendorId)/bank-accounts/\(id)/default", method: "POST", body: EmptyBody())
    }

    func deactivate(vendorId: String, id: String) async throws -> VendorBankAccount {
        try await client.request("/vendors/\(vendorId)/bank-accounts/\(id)/deactivate", method: "POST", body: EmptyBody())
    }
}

struct PaymentApplicationsAPI {
    var client = APIClient.shared

    func list(
        view: String = "mine",
        q: String? = nil,
        status: String? = nil,
        page: Int = 1,
        pageSize: Int = 30
    ) async throws -> Paged<PaymentApplicationRow> {
        let suffix = query([
            "view": view,
            "q": q,
            "status": view == "todo" ? nil : status,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/payment-applications\(suffix)")
    }

    func get(id: String) async throws -> PaymentApplicationDetail {
        try await client.request("/payment-applications/\(id)")
    }

    func openBillVendors() async throws -> [PaymentApplicationOpenBillVendor] {
        try await client.request("/payment-applications/open-bill-vendors")
    }

    func openBills(vendorId: String) async throws -> [PaymentApplicationOpenBill] {
        try await client.request("/payment-applications/open-bills\(query(["vendorId": vendorId]))")
    }

    func bankOptions(vendorId: String, currency: String) async throws -> [PaymentApplicationBankOption] {
        let suffix = query([
            "vendorId": vendorId,
            "currency": currency
        ])
        return try await client.request("/payment-applications/bank-options\(suffix)")
    }

    func create(_ body: PaymentApplicationCreateInput) async throws -> PaymentApplicationDetail {
        try await client.request("/payment-applications", method: "POST", body: body)
    }

    func update(id: String, body: PaymentApplicationUpdateInput) async throws -> PaymentApplicationDetail {
        try await client.request("/payment-applications/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> OkResponse {
        try await client.request("/payment-applications/\(id)", method: "DELETE")
    }

    func action(id: String, name: String) async throws -> PaymentApplicationDetail {
        try await client.request("/payment-applications/\(id)/\(name)", method: "POST", body: EmptyBody())
    }

    func reject(id: String, comment: String) async throws -> PaymentApplicationDetail {
        try await client.request(
            "/payment-applications/\(id)/reject",
            method: "POST",
            body: PaymentApplicationRejectInput(comment: comment)
        )
    }

    func payoutAccounts() async throws -> [PaymentFundingAccount] {
        try await client.request("/accounting/payout-accounts")
    }

    func registerPayment(
        id: String,
        proofURL: URL,
        fileName: String,
        mimeType: String,
        idempotencyKey: String,
        amount: Double,
        paidAt: String,
        accountId: String,
        method: String?,
        reference: String?,
        note: String?
    ) async throws -> PaymentApplicationDetail {
        var fields = [
            "idempotencyKey": idempotencyKey,
            "amount": String(format: "%.2f", amount),
            "paidAt": paidAt,
            "accountId": accountId
        ]
        if let method { fields["method"] = method }
        if let reference { fields["reference"] = reference }
        if let note { fields["note"] = note }
        return try await client.uploadMultipart(
            "/payment-applications/\(id)/payments",
            fileURL: proofURL,
            fieldName: "proof",
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
    }

    func uploadAttachment(
        id: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        kind: String = "OTHER",
        note: String? = nil
    ) async throws -> PaymentApplicationAttachment {
        var fields = ["kind": kind]
        if let note { fields["note"] = note }
        return try await client.uploadMultipart(
            "/payment-applications/\(id)/attachments",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields
        )
    }

    func removeAttachment(id: String, attachmentId: String) async throws -> OkResponse {
        try await client.request(
            "/payment-applications/\(id)/attachments/\(attachmentId)",
            method: "DELETE"
        )
    }

    func downloadAttachment(id: String, attachment: PaymentApplicationAttachment) async throws -> URL {
        let safeName = attachment.filename.replacingOccurrences(of: "/", with: "-")
        return try await client.download(
            "/payment-applications/\(id)/attachments/\(attachment.id)",
            fileName: safeName
        )
    }

    func downloadPDF(id: String, ref: String, variant: String = "application") async throws -> URL {
        try await client.download(
            "/payment-applications/\(id)/pdf\(query(["variant": variant]))",
            fileName: "\(ref)-\(variant).pdf"
        )
    }

    func emailPreview(id: String) async throws -> PaymentApplicationEmailPreview {
        try await client.request("/payment-applications/\(id)/email-preview")
    }

    func sendEmail(id: String, body: PaymentApplicationEmailInput) async throws -> PaymentApplicationEmailResult {
        try await client.request("/payment-applications/\(id)/email", method: "POST", body: body)
    }
}

struct FetPayInput: Codable {
    let amount: Double
    let date: String?
    let reference: String?
    let note: String?
    let quarterKey: String?
}

struct FetAPI {
    var client = APIClient.shared

    func status() async throws -> FetStatus {
        try await client.request("/accounting/fet")
    }

    func pay(
        _ body: FetPayInput,
        idempotencyKey: String? = nil
    ) async throws -> OkResponse {
        try await client.request(
            "/accounting/fet/pay",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func reversePayment(refId: String, reason: String? = nil) async throws -> OkResponse {
        try await client.request("/accounting/fet/pay/\(refId)/reverse", method: "POST", body: ReasonInput(reason: reason))
    }
}

struct EodAPI {
    var client = APIClient.shared

    func report(date: String) async throws -> EodReport {
        try await client.request("/accounting/reports/eod\(query(["date": date]))")
    }
}

struct ActivityAPI {
    var client = APIClient.shared

    func list(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<AuditLog> {
        try await client.request("/audit\(query(["page": page, "pageSize": pageSize]))")
    }
}

struct ApprovalsAPI {
    var client = APIClient.shared

    func list(status: ApprovalStatus? = nil, mine: Bool = false, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<ApprovalRequest> {
        let qs = query([
            "status": status,
            "mine": mine ? "1" : nil,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/approvals\(qs)")
    }

    func pendingCount() async throws -> ApprovalPendingCount {
        try await client.request("/approvals/pending-count")
    }

    func get(id: String) async throws -> ApprovalRequest {
        try await client.request("/approvals/\(id)")
    }

    func approve(id: String, note: String? = nil) async throws -> ApprovalRequest {
        try await client.request("/approvals/\(id)/approve", method: "POST", body: NoteInput(note: note))
    }

    func deny(id: String, note: String? = nil) async throws -> ApprovalRequest {
        try await client.request("/approvals/\(id)/deny", method: "POST", body: NoteInput(note: note))
    }

    func cancel(id: String) async throws -> ApprovalRequest {
        try await client.request("/approvals/\(id)/cancel", method: "POST")
    }
}

struct UsersAPI {
    var client = APIClient.shared

    func list() async throws -> [UserAccount] {
        try await client.request("/users")
    }

    func updateMe(fullName: String) async throws -> UserAccount {
        try await client.request("/users/me", method: "PATCH", body: FullNameInput(fullName: fullName))
    }

    func create(_ body: UserCreateInput) async throws -> UserAccount {
        try await client.request("/users", method: "POST", body: body)
    }

    func update(id: String, body: UserPatchInput) async throws -> UserAccount {
        try await client.request("/users/\(id)", method: "PATCH", body: body)
    }

    func resetPassword(id: String, password: String) async throws -> EmptyResponse {
        try await client.request("/users/\(id)/reset-password", method: "POST", body: PasswordInput(password: password))
    }

    func resetMfa(id: String) async throws -> EmptyResponse {
        try await client.request("/users/\(id)/reset-mfa", method: "POST")
    }

    func preferences() async throws -> UserPreferences {
        try await client.request("/users/me/preferences")
    }

    func updatePreferences(_ body: UserPreferencesPatch) async throws -> UserPreferences {
        try await client.request("/users/me/preferences", method: "PATCH", body: body)
    }
}

struct RolesAPI {
    var client = APIClient.shared

    func list() async throws -> [Role] {
        try await client.request("/roles")
    }

    func catalog() async throws -> [PermissionGroup] {
        try await client.request("/permissions")
    }

    func create(_ body: RoleCreateInput) async throws -> Role {
        try await client.request("/roles", method: "POST", body: body)
    }

    func update(id: String, body: RolePatchInput) async throws -> Role {
        try await client.request("/roles/\(id)", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> EmptyResponse {
        try await client.request("/roles/\(id)", method: "DELETE")
    }
}

struct ApiKeysAPI {
    var client = APIClient.shared

    func list() async throws -> [ApiKey] {
        try await client.request("/api-keys")
    }

    func scopes() async throws -> [AiScopeGroup] {
        try await client.request("/api-keys/scopes")
    }

    func create(_ body: ApiKeyCreateInput) async throws -> ApiKeyCreated {
        try await client.request("/api-keys", method: "POST", body: body)
    }

    func revoke(id: String) async throws -> EmptyResponse {
        try await client.request("/api-keys/\(id)", method: "DELETE")
    }
}

struct SettingsAPI {
    var client = APIClient.shared

    func general() async throws -> GeneralSettings {
        try await client.request("/settings/general")
    }

    func updateGeneral(_ body: GeneralPatchInput) async throws -> GeneralSettings {
        try await client.request("/settings/general", method: "PATCH", body: body)
    }

    func branding() async throws -> BrandingSettings {
        try await client.request("/settings/branding")
    }

    func updateBranding(_ body: BrandingPatchInput) async throws -> BrandingSettings {
        try await client.request("/settings/branding", method: "PATCH", body: body)
    }

    func mail() async throws -> MailConfig {
        try await client.request("/settings/mail")
    }

    func updateMail(_ body: MailPatchInput) async throws -> MailConfig {
        try await client.request("/settings/mail", method: "PATCH", body: body)
    }

    func testMail(to: String) async throws -> [String: Bool] {
        try await client.request("/settings/mail/test", method: "POST", body: TestMailInput(to: to))
    }

    func invoiceTemplate() async throws -> InvoiceEmailTemplate {
        try await client.request("/settings/invoice-template")
    }

    func updateInvoiceTemplate(_ body: InvoiceTemplatePatchInput) async throws -> InvoiceEmailTemplate {
        try await client.request("/settings/invoice-template", method: "PATCH", body: body)
    }

    func logoData() async throws -> Data {
        try await client.data("/settings/logo?_=\(Int(Date().timeIntervalSince1970))")
    }

    func uploadLogo(fileURL: URL, fileName: String, mimeType: String) async throws -> OkResponse {
        try await client.uploadMultipart(
            "/settings/logo",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func deleteLogo() async throws -> OkResponse {
        try await client.request("/settings/logo", method: "DELETE")
    }
}

struct InvoicesAPI {
    var client = APIClient.shared

    func pdfPath(invoiceId: String) -> String {
        "/invoices/\(invoiceId)/pdf"
    }

    func email(invoiceId: String, to: String? = nil) async throws -> InvoiceEmailResult {
        try await client.request("/invoices/\(invoiceId)/email", method: "POST", body: InvoiceEmailInput(to: to))
    }

    func downloadPDF(invoiceId: String, fileName: String? = nil) async throws -> URL {
        try await client.download(pdfPath(invoiceId: invoiceId), fileName: fileName ?? "invoice-\(invoiceId).pdf")
    }
}

struct PaymentsAPI {
    var client = APIClient.shared

    func gatewayStatus() async throws -> GatewayStatus {
        try await client.request("/payments/gateway/status")
    }

    func connectionToken() async throws -> ConnectionToken {
        try await client.request("/payments/stripe/connection-token", method: "POST")
    }

    func terminalIntent(invoiceId: String, grossAmount: Double? = nil) async throws -> TerminalIntent {
        try await client.request(
            "/payments/stripe/terminal/intent",
            method: "POST",
            body: PaymentIntentGrossInput(invoiceId: invoiceId, grossAmount: grossAmount)
        )
    }

    func cardIntent(invoiceId: String, grossAmount: Double? = nil) async throws -> CardPaymentIntent {
        try await client.request(
            "/payments/stripe/card/intent",
            method: "POST",
            body: PaymentIntentGrossInput(invoiceId: invoiceId, grossAmount: grossAmount)
        )
    }

    /// Server quote + risk check for a card / Tap to Pay charge. `grossAmount`
    /// is what the card is charged, fee included; omit it to quote the whole
    /// balance, which also yields the ceiling a split can't exceed. Read-only —
    /// it never touches Stripe.
    func chargePreflight(
        invoiceId: String,
        processor: ChargeProcessor,
        grossAmount: Double? = nil
    ) async throws -> ChargePreflight {
        let params = query([
            "processor": processor.rawValue,
            "grossAmount": grossAmount.map { String(format: "%.2f", $0) },
        ])
        return try await client.request("/payments/stripe/preflight/\(invoiceId)\(params)")
    }

    /// Create a Stripe-hosted pay link for the invoice. Emailing it to the
    /// customer is part of this one call — there is no separate send route.
    func payLink(invoiceId: String, body: PayLinkCreateInput) async throws -> PayLink {
        try await client.request("/invoices/\(invoiceId)/payment-link", method: "POST", body: body)
    }

    /// Book a confirmed keyed-card intent immediately; idempotent with the
    /// `payment_intent.succeeded` webhook, so failures here are safe to ignore.
    func settleManual(paymentIntentId: String) async throws -> ManualSettleResult {
        try await client.request("/payments/stripe/manual/settle", method: "POST", body: PaymentIntentIdInput(paymentIntentId: paymentIntentId))
    }

    func invoicePayments(invoiceId: String) async throws -> [InvoicePayment] {
        try await client.request("/invoices/\(invoiceId)/payments")
    }

    func record(
        invoiceId: String,
        body: PaymentRecordInput,
        idempotencyKey: String? = nil
    ) async throws -> InvoicePayment {
        let result: InvoicePayment = try await client.request(
            "/invoices/\(invoiceId)/payments",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
        await CheckRegisterEvents.changed()
        return result
    }

    func reverse(paymentId: String, reason: String? = nil) async throws -> ReverseResult {
        let result: ReverseResult = try await client.request("/payments/\(paymentId)/reverse", method: "POST", body: ReasonInput(reason: reason))
        await CheckRegisterEvents.changed()
        return result
    }

    func refundProcessor(paymentId: String, reason: String? = nil) async throws -> ReverseResult {
        try await client.request("/payments/\(paymentId)/refund", method: "POST", body: ReasonInput(reason: reason))
    }
}
