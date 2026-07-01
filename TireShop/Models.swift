import Foundation

struct Paged<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int
}

struct ApprovalRequestRef: Codable, Equatable {
    let id: String
}

enum ImmediateOrApproval<T: Codable>: Codable {
    case immediate(T)
    case approval(ApprovalRequestRef)

    private enum CodingKeys: String, CodingKey {
        case approvalRequest
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let approval = try container?.decodeIfPresent(ApprovalRequestRef.self, forKey: .approvalRequest) {
            self = .approval(approval)
            return
        }

        self = .immediate(try T(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .immediate(let value):
            try value.encode(to: encoder)
        case .approval(let request):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(request, forKey: .approvalRequest)
        }
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

typealias TireCategory = String
typealias TirePosition = String
typealias TireAttributeKind = String
typealias SaleStatus = String
typealias CustomerDocumentKind = String
typealias StockAdjustReason = String
typealias WorkOrderStatus = String
typealias ReturnType = String
typealias ReturnStatus = String
typealias RefundMethod = String
typealias InventoryDisposition = String
typealias WarrantyDisposition = String
typealias InventoryCountStatus = String
typealias ContainerStatus = String
typealias AccountType = String
typealias ApprovalStatus = String
typealias InteractionType = String
typealias FollowUpStatus = String
typealias VendorCategory = String
typealias EmployeeStatus = String
typealias PayType = String
typealias CommissionBasis = String
typealias CommissionStatus = String

struct TireAttribute: Codable, Identifiable, Equatable {
    let id: String
    let kind: TireAttributeKind
    let value: String
    let label: String
    let sortOrder: Int
    let active: Bool
    let usageCount: Int
}

struct TireSkuInventory: Codable, Identifiable, Equatable {
    let id: String
    let location: String
    let qtyOnHand: Int
    let qtyReserved: Int
}

struct TireSku: Codable, Identifiable, Equatable {
    let id: String
    let sku: String
    let brand: String
    let model: String
    let size: String
    let category: TireCategory
    let position: TirePosition
    let segment: String?
    let loadIndex: String?
    let pattern: String?
    let treadDepth32: String?
    let maxLoadSingleLb: Int?
    let weightLb: String?
    let plyRating: String?
    let priceRetail: String
    let priceCost: String
    let reorderPoint: Int
    let active: Bool
    let inventory: [TireSkuInventory]
}

struct SkuInput: Codable {
    var sku: String
    var brand: String
    var model: String
    var size: String
    var category: TireCategory
    var position: TirePosition
    var segment: String?
    var loadIndex: String?
    var pattern: String?
    var treadDepth32: Double?
    var maxLoadSingleLb: Int?
    var weightLb: Double?
    var plyRating: String?
    var priceRetail: Double
    var priceCost: Double?
    var reorderPoint: Int?
    var active: Bool?
}

struct InventoryItem: Codable, Identifiable, Equatable {
    let id: String
    let location: String
    let qtyOnHand: Int
    let qtyReserved: Int
}

struct StockAdjustmentInput: Codable {
    let delta: Int
    let reason: StockAdjustReason
    let note: String?
}

struct ImportSummary: Codable, Equatable {
    struct RowError: Codable, Equatable {
        let row: Int
        let message: String
    }

    let total: Int
    let created: Int
    let updated: Int
    let errorCount: Int
    let errors: [RowError]
}

struct CustomerSummary: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let company: String?
}

struct SaleLine: Codable, Identifiable, Equatable {
    let id: String
    let itemType: String
    let itemId: String
    let description: String
    let qty: Int
    let unitPrice: String
    let discount: String
    let lineTotal: String
}

struct SaleInvoice: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let amountDue: String
    let paidTotal: String
}

struct Sale: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let status: SaleStatus
    let customer: CustomerSummary
    let customerId: String
    let subtotal: String
    let taxRate: String
    let taxAmount: String
    let total: String
    let createdAt: String
    let lines: [SaleLine]
    let invoice: SaleInvoice?
}

struct SaleListItem: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let status: SaleStatus
    let customer: CustomerSummary
    let customerId: String
    let subtotal: String
    let taxRate: String
    let taxAmount: String
    let total: String
    let createdAt: String
    let lines: [SaleLine]
    let invoice: SaleInvoice?
    let tireQty: Int
    let sampleDescription: String?
    let extraLineCount: Int
    let grossProfit: String
}

struct CustomerSaleSummary: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let status: SaleStatus
    let subtotal: String
    let taxRate: String
    let taxAmount: String
    let total: String
    let createdAt: String
    let lines: [SaleLine]
}

struct CustomerDocument: Codable, Identifiable, Equatable {
    let id: String
    let kind: CustomerDocumentKind
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let note: String?
    let createdAt: String
}

struct Customer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let company: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let taxExempt: Bool
    let taxExemptNumber: String?
    let accountEnabled: Bool
    let creditLimit: String?
    let sales: [CustomerSaleSummary]?
    let documents: [CustomerDocument]?
    let createdAt: String
}

struct NewCustomerInput: Codable {
    var name: String
    var company: String?
    var phone: String?
    var email: String?
    var address: String?
    var notes: String?
    var taxExempt: Bool?
    var taxExemptNumber: String?
}

struct CustomerProfilePatch: Codable {
    var name: String
    var company: String
    var phone: String
    var email: String
    var address: String
    var notes: String
}

// MARK: - Customer relations

struct CustomerInteraction: Codable, Identifiable, Equatable {
    let id: String
    let customerId: String
    let type: InteractionType
    let summary: String
    let body: String?
    let occurredAt: String
    let createdById: String?
    let createdByName: String?
    let createdAt: String
}

struct CrmCustomerRef: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let company: String?
}

struct CustomerFollowUp: Codable, Identifiable, Equatable {
    let id: String
    let customerId: String
    let title: String
    let note: String?
    let dueAt: String
    let status: FollowUpStatus
    let assignedToId: String?
    let assignedToName: String?
    let createdById: String?
    let createdByName: String?
    let completedAt: String?
    let completedById: String?
    let completedByName: String?
    let createdAt: String
    let updatedAt: String
    let customer: CrmCustomerRef?
}

struct OutreachTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let subject: String
    let body: String
    let active: Bool
    let createdAt: String
    let updatedAt: String
}

struct RelationshipSummary: Codable, Equatable {
    let lastPurchaseAt: String?
    let lifetimeSpend: Double
    let saleCount: Int
    let openFollowUpCount: Int
    let lapsedDays: Int
    let atRisk: Bool
}

struct AtRiskCustomer: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let name: String
    let company: String?
    let email: String?
    let lastPurchaseAt: String?
    let lifetimeSpend: Double
    let saleCount: Int
}

struct AtRiskCustomersPage: Codable, Equatable {
    let items: [AtRiskCustomer]
    let total: Int
    let page: Int
    let pageSize: Int
    let lapsedDays: Int
}

struct AssignableUser: Codable, Identifiable, Equatable {
    let id: String
    let fullName: String
}

struct ServiceItem: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let name: String
    let price: String
    let defaultMinutes: Int
    let active: Bool
}

struct NewSaleLine: Codable, Equatable {
    let itemType: String
    let itemId: String
    let description: String
    let qty: Int
    let unitPrice: Double
    let discount: Double?
}

struct SaleUpsertInput: Codable {
    let customerId: String
    let taxRate: Double?
    let lines: [NewSaleLine]
}

struct DashboardSummary: Codable, Equatable {
    struct Metric: Codable, Equatable {
        let revenue: Double
        let saleCount: Int
    }

    struct OpenAR: Codable, Equatable {
        let total: Double
        let invoiceCount: Int
    }

    struct LowStockSku: Codable, Identifiable, Equatable {
        let id: String
        let sku: String
        let brand: String
        let model: String
        let size: String
        let reorderPoint: Int
        let onHand: Int
    }

    struct TopSku: Codable, Identifiable, Equatable {
        let id: String
        let sku: String
        let brand: String
        let model: String
        let size: String
        let qty: Int
    }

    let today: Metric
    let month: Metric
    let openAR: OpenAR
    let paidInvoiceCount: Int
    let openQuotes: Int
    let lowStockCount: Int
    let lowStock: [LowStockSku]
    let topSkus: [TopSku]
}

struct GatewayStatus: Codable, Equatable {
    let enabled: Bool
    let provider: String
    let publishableKey: String?
}

struct TerminalIntent: Codable, Equatable {
    let paymentIntentId: String
    let clientSecret: String?
    let balance: Double
    let surcharge: Double
    let amount: Double
    let readerId: String?
    let readerStatus: String?
}

struct InvoicePayment: Codable, Identifiable, Equatable {
    struct Method: Codable, Equatable {
        let name: String
    }

    let id: String
    let externalId: String?
    let amount: String
    let status: String
    let createdAt: String?
    let reference: String?
    let note: String?
    let processor: String?
    let paymentMethod: Method?
}

struct ReverseResult: Codable, Equatable {
    let approvalRequest: ApprovalRequestRef?
}

struct WorkOrderTask: Codable, Identifiable, Equatable {
    let id: String
    let description: String
    let done: Bool
    let doneAt: String?
}

struct WorkOrder: Codable, Identifiable, Equatable {
    struct SaleInfo: Codable, Identifiable, Equatable {
        struct Line: Codable, Identifiable, Equatable {
            let id: String
            let description: String
            let qty: Int
            let itemType: String
        }

        let id: String
        let ref: String?
        let total: String
        let customer: CustomerSummary
        let lines: [Line]
    }

    let id: String
    let status: WorkOrderStatus
    let bay: String?
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let tasks: [WorkOrderTask]
    let sale: SaleInfo
}

struct Returnable: Codable, Equatable {
    struct Line: Codable, Equatable {
        let saleLineId: String
        let skuId: String
        let description: String
        let unitPrice: Double
        let qtySold: Int
        let qtyAlreadyReturned: Int
        let qtyRemaining: Int
    }

    let saleId: String
    let saleRef: String?
    let saleStatus: String
    let taxRate: Double
    let originalPaymentMethodId: String?
    let originalPaymentMethodName: String?
    let lines: [Line]
}

struct ReturnLine: Codable, Identifiable, Equatable {
    let id: String
    let saleLineId: String
    let skuId: String
    let qty: Int
    let unitRefund: String
    let inventoryDisposition: InventoryDisposition
}

struct ReturnRecord: Codable, Identifiable, Equatable {
    struct SaleInfo: Codable, Identifiable, Equatable {
        let id: String
        let ref: String?
        let customer: CustomerSummary?
    }

    struct ReplacementSale: Codable, Identifiable, Equatable {
        let id: String
        let ref: String?
        let total: String
        let status: String
    }

    let id: String
    let ref: String?
    let saleId: String
    let type: ReturnType
    let status: ReturnStatus
    let reason: String?
    let notes: String?
    let restockingFee: String
    let refundSubtotal: String
    let refundTax: String
    let refundTotal: String
    let refundMethod: RefundMethod
    let paymentMethod: InvoicePayment.Method?
    let postedAt: String?
    let voidedAt: String?
    let createdAt: String
    let sale: SaleInfo?
    let replacementSale: ReplacementSale?
    let lines: [ReturnLine]
}

struct ReturnLineInput: Codable, Equatable {
    let saleLineId: String
    let qty: Int
    let inventoryDisposition: InventoryDisposition?
}

struct ReplacementLineInput: Codable, Equatable {
    let skuId: String
    let qty: Int
    let unitPrice: Double?
}

struct CreateReturnInput: Codable, Equatable {
    let type: ReturnType
    let reason: String?
    let restockingFee: Double?
    let refundMethod: RefundMethod
    let paymentMethodId: String?
    let notes: String?
    let lines: [ReturnLineInput]
    let replacementLines: [ReplacementLineInput]?
    let warrantyDisposition: WarrantyDisposition?
    let supplierId: String?
}

struct PostReturnInput: Codable, Equatable {
    struct NetPayment: Codable, Equatable {
        let paymentMethodId: String
        let amount: Double
        let reference: String?
        let note: String?
    }

    struct NetRefund: Codable, Equatable {
        let paymentMethodId: String
        let reference: String?
        let note: String?
    }

    let netPayment: NetPayment?
    let netRefund: NetRefund?
}

struct Supplier: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct ReceivableCustomer: Codable, Equatable {
    let customer: CustomerSummary
    let openBalance: Double
    let openCount: Int
    let oldestAt: String
    let ageDays: Int
}

struct PayableVendor: Codable, Equatable {
    let vendor: String?
    let vendorKey: String
    let totalDue: Double
    let count: Int
    let oldestAt: String
    let ageDays: Int
}

struct VendorCounts: Codable, Equatable {
    let costs: Int
    let expenses: Int
    let refunds: Int
}

struct Vendor: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: VendorCategory?
    let contactName: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let active: Bool
    let counts: VendorCounts?
    let createdAt: String
    let updatedAt: String
}

struct VendorSpendSummary: Codable, Equatable {
    let openAP: Double
    let paidOut: Double
    let refunds: Double
    let netSpend: Double
}

struct VendorContainerRef: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
}

struct VendorRecentCost: Codable, Identifiable, Equatable {
    let id: String
    let category: String
    let status: String
    let amount: Double
    let amountPaid: Double
    let description: String?
    let container: VendorContainerRef?
    let createdAt: String
}

struct VendorRecentExpense: Codable, Identifiable, Equatable {
    let id: String
    let amount: Double
    let expenseCode: String
    let paidFromCode: String
    let reference: String?
    let reversedAt: String?
    let date: String
}

struct VendorRefundRecord: Codable, Identifiable, Equatable {
    let id: String
    let ref: String
    let amount: Double
    let depositToCode: String
    let creditCode: String
    let reference: String?
    let reversedAt: String?
    let date: String
}

struct VendorDetail: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: VendorCategory?
    let contactName: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let active: Bool
    let counts: VendorCounts?
    let createdAt: String
    let updatedAt: String
    let summary: VendorSpendSummary
    let recentCosts: [VendorRecentCost]
    let recentExpenses: [VendorRecentExpense]
    let recentRefunds: [VendorRefundRecord]
}

struct VendorRefundResult: Codable, Identifiable, Equatable {
    let id: String
    let ref: String
    let vendorId: String?
    let amount: Double
    let depositToCode: String
    let creditCode: String
    let date: String
}

struct CountLines: Codable, Equatable {
    let lines: Int
}

struct InventoryCountListItem: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let status: InventoryCountStatus
    let scopeCategory: TireCategory?
    let scopePosition: TirePosition?
    let location: String
    let notes: String?
    let costVariance: String
    let postedAt: String?
    let voidedAt: String?
    let createdAt: String
    let count: CountLines

    enum CodingKeys: String, CodingKey {
        case id
        case ref
        case status
        case scopeCategory
        case scopePosition
        case location
        case notes
        case costVariance
        case postedAt
        case voidedAt
        case createdAt
        case count = "_count"
    }
}

struct InventoryCountLine: Codable, Identifiable, Equatable {
    struct Sku: Codable, Identifiable, Equatable {
        let id: String
        let sku: String
        let brand: String
        let model: String
        let size: String
        let category: TireCategory
        let position: TirePosition
    }

    let id: String
    let countId: String
    let skuId: String
    let expectedQty: Int
    let unitCost: String
    let countExpr: String?
    let countedQty: Int?
    let sku: Sku
}

struct InventoryCountDetail: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let status: InventoryCountStatus
    let scopeCategory: TireCategory?
    let scopePosition: TirePosition?
    let location: String
    let notes: String?
    let costVariance: String
    let postedAt: String?
    let voidedAt: String?
    let createdAt: String
    let count: CountLines
    let lines: [InventoryCountLine]

    enum CodingKeys: String, CodingKey {
        case id
        case ref
        case status
        case scopeCategory
        case scopePosition
        case location
        case notes
        case costVariance
        case postedAt
        case voidedAt
        case createdAt
        case count = "_count"
        case lines
    }
}

struct ContainerLine: Codable, Identifiable, Equatable {
    struct Sku: Codable, Identifiable, Equatable {
        let id: String
        let sku: String
        let brand: String
        let model: String
        let size: String
        let category: String
        let position: String
    }

    let id: String
    let skuId: String
    let qty: Int
    let unitCost: String
    let fetPerUnit: String
    let landedUnitCost: String?
    let landedTotal: String?
    let prevPriceCost: String?
    let sku: Sku
}

struct ContainerCost: Codable, Identifiable, Equatable {
    let id: String
    let containerId: String
    let category: String
    let status: String
    let description: String?
    let amount: String
    let amountPaid: String
    let vendor: String?
    let reference: String?
    let createdAt: String
}

struct Container: Codable, Identifiable, Equatable {
    struct SupplierInfo: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let country: String?
    }

    struct Counts: Codable, Equatable {
        let lines: Int
        let costs: Int
    }

    let id: String
    let ref: String?
    let reference: String?
    let bolNumber: String?
    let supplier: SupplierInfo
    let status: ContainerStatus
    let isDDP: Bool
    let costSpread: String
    let etaAt: String?
    let arrivedAt: String?
    let receivedAt: String?
    let notes: String?
    let lines: [ContainerLine]
    let costs: [ContainerCost]
    let createdAt: String
    let count: Counts?

    enum CodingKeys: String, CodingKey {
        case id
        case ref
        case reference
        case bolNumber
        case supplier
        case status
        case isDDP
        case costSpread
        case etaAt
        case arrivedAt
        case receivedAt
        case notes
        case lines
        case costs
        case createdAt
        case count = "_count"
    }
}

struct Account: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let name: String
    let type: AccountType
    let balance: Double
}

struct JournalLine: Codable, Identifiable, Equatable {
    struct AccountInfo: Codable, Equatable {
        let code: String
        let name: String
    }

    let id: String
    let debit: String
    let credit: String
    let account: AccountInfo
}

struct JournalEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let memo: String?
    let refType: String?
    let refId: String?
    let lines: [JournalLine]
}

struct Pnl: Codable, Equatable {
    struct Line: Codable, Equatable {
        let code: String
        let name: String
        let total: Double
    }

    let from: String
    let to: String
    let revenue: [Line]
    let revenueTotal: Double
    let expenses: [Line]
    let expensesTotal: Double
    let netIncome: Double
}

struct CashAccount: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let name: String
    let type: String
    let balance: Double
}

struct ExpenseAccount: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let name: String
}

struct CashTransfer: Codable, Identifiable, Equatable {
    let id: String
    let fromAccount: JournalLine.AccountInfo
    let toAccount: JournalLine.AccountInfo
    let amount: String
    let fee: String
    let note: String?
    let createdAt: String
}

struct PaymentMethod: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let feeRate: String?
    let isActive: Bool
    let processor: String?
    let account: JournalLine.AccountInfo
}

struct FetQuarter: Codable, Equatable {
    let key: String
    let label: String
    let year: Int
    let quarter: Int
    let periodStart: String
    let periodEnd: String
    let formDueDate: String
    let fetDue: Double
    let depositRequired: Bool
}

struct FetStatus: Codable, Equatable {
    struct Payment: Codable, Identifiable, Equatable {
        let id: String
        let refId: String
        let date: String
        let memo: String?
        let amount: Double
    }

    let payable: Double
    let quarters: [FetQuarter]
    let payments: [Payment]
    let paidPerQuarter: [String: Double]
}

struct EodReport: Codable, Equatable {
    struct Sales: Codable, Equatable {
        struct Item: Codable, Equatable {
            let saleRef: String?
            let customer: String
            let soldBy: String
            let status: String
            let subtotal: Double
            let tax: Double
            let total: Double
            let at: String
        }

        struct Summary: Codable, Equatable {
            let count: Int
            let subtotal: Double
            let tax: Double
            let total: Double
        }

        let items: [Item]
        let summary: Summary
    }

    struct Payments: Codable, Equatable {
        struct Item: Codable, Equatable {
            let method: String
            let amount: Double
            let surcharge: Double
            let reference: String?
            let at: String
        }

        struct MethodTotal: Codable, Equatable {
            let method: String
            let count: Int
            let amount: Double
        }

        struct Summary: Codable, Equatable {
            let count: Int
            let total: Double
        }

        let items: [Item]
        let byMethod: [MethodTotal]
        let summary: Summary
    }

    struct Expenses: Codable, Equatable {
        struct Item: Codable, Equatable {
            let memo: String?
            let amount: Double
            let at: String
        }

        let items: [Item]
        let total: Double
    }

    struct CashMovement: Codable, Equatable {
        let code: String
        let name: String
        let incoming: Double
        let out: Double
        let net: Double

        enum CodingKeys: String, CodingKey {
            case code
            case name
            case incoming = "in"
            case out
            case net
        }
    }

    struct ReportPnl: Codable, Equatable {
        let revenue: [Pnl.Line]
        let revenueTotal: Double
        let expenses: [Pnl.Line]
        let expensesTotal: Double
        let netIncome: Double
    }

    let date: String
    let sales: Sales
    let payments: Payments
    let expenses: Expenses
    let pnl: ReportPnl
    let cashMovement: [CashMovement]
}

struct AuditLog: Codable, Identifiable, Equatable {
    struct UserInfo: Codable, Identifiable, Equatable {
        let id: String
        let fullName: String
        let email: String
    }

    let id: String
    let action: String
    let entity: String
    let entityId: String?
    let data: [String: JSONValue]?
    let createdAt: String
    let user: UserInfo?
}

struct ApprovalSale: Codable, Equatable {
    struct Customer: Codable, Equatable {
        let name: String
        let company: String?
        let phone: String?
    }

    struct Line: Codable, Equatable {
        let description: String
        let itemType: String
        let qty: Int
        let unitPrice: Double
        let lineTotal: Double
    }

    struct Payment: Codable, Equatable {
        let amount: Double
        let method: String?
        let reference: String?
        let createdAt: String
    }

    let ref: String?
    let status: String
    let createdAt: String
    let customer: Customer?
    let lines: [Line]
    let subtotal: Double
    let taxAmount: Double
    let total: Double
    let paid: Double
    let payments: [Payment]
}

struct ApprovalRequest: Codable, Identifiable, Equatable {
    let id: String
    let action: String
    let entityType: String?
    let entityId: String?
    let payload: JSONValue?
    let status: ApprovalStatus
    let note: String?
    let requestedById: String
    let requestedBy: AuditLog.UserInfo
    let requestedAt: String
    let decidedById: String?
    let decidedBy: AuditLog.UserInfo?
    let decidedAt: String?
    let decisionNote: String?
    let executedAt: String?
    let executionError: String?
    let context: JSONValue?
}

struct UserAccount: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let fullName: String
    let roleId: String
    let roleName: String
    let active: Bool
    let mfaMethod: String?
    let createdAt: String
}

struct Role: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let permissions: [String]
    let approvalPermissions: [String]
    let isSystem: Bool
    let isAdmin: Bool?
    let userCount: Int
    let createdAt: String
}

struct PermissionGroup: Codable, Equatable {
    struct Permission: Codable, Equatable {
        let key: String
        let label: String
        let approvable: Bool?
    }

    let group: String
    let permissions: [Permission]
}

struct ApiKey: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let scopes: [String]
    let lastUsedAt: String?
    let revokedAt: String?
    let revoked: Bool
    let createdAt: String
}

struct ApiKeyCreated: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let scopes: [String]
    let lastUsedAt: String?
    let revokedAt: String?
    let revoked: Bool
    let createdAt: String
    let plaintext: String
}

struct AiScopeGroup: Codable, Equatable {
    struct Scope: Codable, Equatable {
        let key: String
        let label: String
    }

    let group: String
    let scopes: [Scope]
}

struct GeneralSettings: Codable, Equatable {
    let timezone: String
    let defaultTaxRate: Double
}

struct BrandingSettings: Codable, Equatable {
    let shopName: String?
    let shopAddress: String?
    let shopPhone: String?
    let shopEmail: String?
    let logoUrl: String?
}

struct MailConfig: Codable, Equatable {
    let host: String
    let port: Int
    let secure: Bool
    let user: String
    let from: String
    let fromName: String
    let hasPassword: Bool
}

struct OkResponse: Codable, Equatable {
    let ok: Bool?
    let deleted: Bool?
}

struct CountResponse: Codable, Equatable {
    let count: Int
}

struct CreditBalance: Codable, Equatable {
    let balance: Double
}

struct ConnectionToken: Codable, Equatable {
    let secret: String
    let locationId: String?
}

struct InvoiceEmailResult: Codable, Equatable {
    let ok: Bool
    let to: String
    let messageId: String?
}

// MARK: - Notifications

struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let entityType: String?
    let entityId: String?
    let readAt: String?
    let createdAt: String
}

struct NotificationsPage: Codable, Equatable {
    let items: [AppNotification]
    let total: Int
    let page: Int
    let pageSize: Int
    let unread: Int
}

// MARK: - Web Orders

typealias OrderStatus = String
typealias OrderFulfillment = String

struct OrderCustomerRef: Codable, Equatable {
    let id: String
    let name: String
    let company: String?
}

struct OrderUserRef: Codable, Equatable {
    let id: String
    let email: String
}

struct OrderLine: Codable, Identifiable, Equatable {
    let id: String
    let skuId: String
    let description: String
    let qty: Int
    let unitPrice: String
    let lineTotal: String
}

struct OrderSaleRef: Codable, Equatable {
    let id: String
    let ref: String?
}

struct Order: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let customerId: String
    let customer: OrderCustomerRef
    let customerUser: OrderUserRef?
    let status: OrderStatus
    let fulfillment: OrderFulfillment
    let deliveryAddress: String?
    let notes: String?
    let subtotal: String
    let total: String
    let saleId: String?
    let sale: OrderSaleRef?
    let createdAt: String
    let lines: [OrderLine]
}

// MARK: - Brand Info

struct BrandInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let key: String
    let introEn: String
    let introZh: String
    let country: String?
    let foundedYear: Int?
    let website: String?
    let active: Bool
    let usageCount: Int
}

// MARK: - Monthly Sales report

struct MonthlySalesRow: Codable, Identifiable, Equatable {
    let date: String
    let itemCode: String
    let productCode: String
    let invoiceNo: String
    let brand: String
    let pattern: String
    let size: String
    let pr: String
    let loadIndex: String
    let salesPrice: Double
    let qty: Double
    let amount: Double
    let taxRate: Double
    let salesTax: Double
    let unitCost: Double
    let totalCost: Double
    let paymentMethod: String
    let unitFet: Double
    let totalFet: Double

    var id: String { "\(invoiceNo)-\(itemCode)-\(date)" }
}

struct MonthlySalesSummary: Codable, Equatable {
    let lineCount: Int
    let qty: Double
    let amount: Double
    let salesTax: Double
    let totalCost: Double
    let totalFet: Double
}

struct MonthlySalesReport: Codable, Equatable {
    let from: String
    let to: String
    let rows: [MonthlySalesRow]
    let summary: MonthlySalesSummary
}

// MARK: - Employees & commissions

struct EmployeeUserRef: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let active: Bool?
}

struct EmployeeCommissionSummary: Codable, Equatable {
    let accrued: Double
    let paid: Double
    let total: Double
}

struct Employee: Codable, Identifiable, Equatable {
    let id: String
    let employeeNo: String?
    let userId: String?
    let user: EmployeeUserRef?
    let fullName: String
    let phone: String?
    let email: String?
    let address: String?
    let position: String?
    let department: String?
    let status: EmployeeStatus
    let hireDate: String?
    let endDate: String?
    let payType: PayType
    let payRate: Double
    let commissionRate: Double
    let commissionBasis: CommissionBasis
    let notes: String?
    let commissions: EmployeeCommissionSummary?
    let createdAt: String
    let updatedAt: String
}

struct CommissionEmployeeRef: Codable, Identifiable, Equatable {
    let id: String
    let fullName: String
}

struct CommissionSaleRef: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let total: Double
}

struct CommissionEntry: Codable, Identifiable, Equatable {
    let id: String
    let employeeId: String
    let saleId: String?
    let basis: CommissionBasis
    let basisAmount: Double
    let rate: Double
    let amount: Double
    let status: CommissionStatus
    let note: String?
    let payoutId: String?
    let paidAt: String?
    let createdAt: String
    let employee: CommissionEmployeeRef?
    let sale: CommissionSaleRef?
}

struct CommissionPayout: Codable, Identifiable, Equatable {
    let id: String
    let amount: Double
    let entryCount: Int
    let createdAt: String
}
