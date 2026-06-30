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
    var priceRetail: Double?
    var priceCost: Double?
    var reorderPoint: Int?
    var active: Bool?
}

struct CustomerTaxStatusInput: Codable {
    let taxExempt: Bool
    let taxExemptNumber: String?
}

struct WorkOrderPatchInput: Codable {
    let status: WorkOrderStatus?
    let bay: String?
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
}

struct ReasonInput: Codable {
    let reason: String?
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

struct TimezoneInput: Codable {
    let timezone: String
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

struct UserCreateInput: Codable {
    let email: String
    let password: String
    let fullName: String
    let roleId: String
}

struct UserPatchInput: Codable {
    let fullName: String?
    let roleId: String?
    let active: Bool?
}

struct RoleCreateInput: Codable {
    let name: String
    let description: String?
    let permissions: [String]
    let approvalPermissions: [String]?
}

struct RolePatchInput: Codable {
    let name: String?
    let description: String?
    let permissions: [String]?
    let approvalPermissions: [String]?
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
    let host: String?
    let port: Int?
    let secure: Bool?
    let user: String?
    let password: String?
    let from: String?
}

struct DashboardAPI {
    var client = APIClient.shared

    func summary() async throws -> DashboardSummary {
        try await client.request("/dashboard/summary")
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
}

struct InventoryAPI {
    var client = APIClient.shared

    func listSkus(
        q: String? = nil,
        category: TireCategory? = nil,
        position: TirePosition? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<TireSku> {
        let qs = query([
            "q": q,
            "category": category,
            "position": position,
            "page": page,
            "pageSize": pageSize
        ])
        return try await client.request("/inventory/skus\(qs)")
    }

    func createSku(_ body: SkuInput) async throws -> TireSku {
        try await client.request("/inventory/skus", method: "POST", body: body)
    }

    func updateSku(id: String, body: TireSkuPatchInput) async throws -> TireSku {
        try await client.request("/inventory/skus/\(id)", method: "PATCH", body: body)
    }

    func adjust(id: String, delta: Int, reason: StockAdjustReason, note: String? = nil) async throws -> ImmediateOrApproval<InventoryItem> {
        try await client.request(
            "/inventory/skus/\(id)/adjust",
            method: "POST",
            body: StockAdjustmentInput(delta: delta, reason: reason, note: note)
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

struct SalesAPI {
    var client = APIClient.shared

    func list(q: String? = nil, status: SaleStatus? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<SaleListItem> {
        try await client.request("/sales\(query(["q": q, "status": status, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> Sale {
        try await client.request("/sales/\(id)")
    }

    func create(_ body: SaleUpsertInput) async throws -> Sale {
        try await client.request("/sales", method: "POST", body: body)
    }

    func update(id: String, body: SaleUpsertInput) async throws -> Sale {
        try await client.request("/sales/\(id)", method: "PATCH", body: body)
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

    func setTaxStatus(id: String, body: CustomerTaxStatusInput) async throws -> Customer {
        try await client.request("/customers/\(id)/tax-status", method: "PATCH", body: body)
    }

    func remove(id: String) async throws -> OkResponse {
        try await client.request("/customers/\(id)", method: "DELETE")
    }

    func creditBalance(id: String) async throws -> CreditBalance {
        try await client.request("/customers/\(id)/credit-balance")
    }

    func uploadDocument(
        id: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        kind: CustomerDocumentKind = "ST5_EXEMPTION"
    ) async throws -> CustomerDocument {
        try await client.uploadMultipart(
            "/customers/\(id)/documents",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType,
            fields: ["kind": kind]
        )
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

    func list(status: WorkOrderStatus? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<WorkOrder> {
        try await client.request("/work-orders\(query(["status": status, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> WorkOrder {
        try await client.request("/work-orders/\(id)")
    }

    func update(id: String, body: WorkOrderPatchInput) async throws -> WorkOrder {
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
        try await client.request("/returns/\(id)/post", method: "POST", body: body ?? PostReturnInput(netPayment: nil, netRefund: nil))
    }
}

struct SuppliersAPI {
    var client = APIClient.shared

    func list() async throws -> Paged<Supplier> {
        try await client.request("/suppliers\(query(["pageSize": 1000]))")
    }
}

struct MoneyAPI {
    var client = APIClient.shared

    func receivables(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<ReceivableCustomer> {
        try await client.request("/receivables\(query(["page": page, "pageSize": pageSize]))")
    }

    func payables(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<PayableVendor> {
        try await client.request("/payables\(query(["page": page, "pageSize": pageSize]))")
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

    func list(status: ContainerStatus? = nil, q: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<Container> {
        try await client.request("/containers\(query(["status": status, "q": q, "page": page, "pageSize": pageSize]))")
    }

    func get(id: String) async throws -> Container {
        try await client.request("/containers/\(id)")
    }
}

struct AccountingAPI {
    var client = APIClient.shared

    func accounts() async throws -> [Account] {
        try await client.request("/accounting/accounts")
    }

    func journal(page: Int? = nil, pageSize: Int? = nil) async throws -> Paged<JournalEntry> {
        try await client.request("/accounting/journal\(query(["page": page, "pageSize": pageSize]))")
    }

    func pnl(from: String? = nil, to: String? = nil) async throws -> Pnl {
        try await client.request("/accounting/reports/pnl\(query(["from": from, "to": to]))")
    }
}

struct CashAccountsAPI {
    var client = APIClient.shared

    func list() async throws -> [CashAccount] {
        try await client.request("/accounting/cash-accounts")
    }

    func transfers(limit: Int? = nil) async throws -> [CashTransfer] {
        try await client.request("/accounting/transfers\(query(["limit": limit]))")
    }

    func methods() async throws -> [PaymentMethod] {
        try await client.request("/accounting/payment-methods")
    }
}

struct FetAPI {
    var client = APIClient.shared

    func status() async throws -> FetStatus {
        try await client.request("/accounting/fet")
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

    func pendingCount() async throws -> CountResponse {
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

    func updateGeneral(timezone: String) async throws -> GeneralSettings {
        try await client.request("/settings/general", method: "PATCH", body: TimezoneInput(timezone: timezone))
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

    func terminalIntent(invoiceId: String) async throws -> TerminalIntent {
        try await client.request("/payments/stripe/terminal/intent", method: "POST", body: InvoiceIdInput(invoiceId: invoiceId))
    }

    func invoicePayments(invoiceId: String) async throws -> [InvoicePayment] {
        try await client.request("/invoices/\(invoiceId)/payments")
    }

    func record(invoiceId: String, body: PaymentRecordInput) async throws -> InvoicePayment {
        try await client.request("/invoices/\(invoiceId)/payments", method: "POST", body: body)
    }

    func reverse(paymentId: String, reason: String? = nil) async throws -> ReverseResult {
        try await client.request("/payments/\(paymentId)/reverse", method: "POST", body: ReasonInput(reason: reason))
    }

    func refundProcessor(paymentId: String, reason: String? = nil) async throws -> ReverseResult {
        try await client.request("/payments/\(paymentId)/refund", method: "POST", body: ReasonInput(reason: reason))
    }
}
