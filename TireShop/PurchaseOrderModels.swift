import Foundation

typealias PurchaseOrderStatus = String
typealias PurchaseOrderListItem = PurchaseOrder

/// Parent references are intentionally sparse on incoming inventory and old servers.
struct PurchaseOrderReference: Codable, Identifiable, Equatable {
    struct Counts: Codable, Equatable {
        let containers: Int
    }

    let id: String
    let ref: String
    var version: Int? = nil
    var supplierReference: String? = nil
    var plannedContainerCount: Int? = nil
    var count: Counts? = nil

    enum CodingKeys: String, CodingKey {
        case id, ref, version, supplierReference, plannedContainerCount
        case count = "_count"
    }
}

/// These balances are computed by the API from surviving settlement evidence.
/// A bill or an approved payment application is not supplier cash paid.
struct PurchaseOrderSummary: Codable, Equatable {
    let status: PurchaseOrderStatus
    let plannedCount: Int
    let containerCount: Int
    let activeCount: Int
    let cancelledCount: Int
    let receivedCount: Int
    let unassignedCount: Int
    let totalQty: Int
    let receivedQty: Int
    let manifestedGoodsAmount: Double
    let goodsAmount: Double?
    let goodsAmountSource: String
    let manifestComplete: Bool
    let supplierPaid: Double
    let legacySupplierPaid: Double
    var activeSupplierPaid: Double? = nil
    var cancelledSupplierPaid: Double? = nil
    var paidDiscrepancyCount: Int? = nil
    var openSupplierPayable: Double? = nil
    var dueSupplierNow: Double? = nil
    var futureDue: Double? = nil
    var undatedPayable: Double? = nil
    var excludedOpenPayable: Double? = nil
    let goodsRemaining: Double?
    let openPayable: Double
    let dueNow: Double
    let nextEtaAt: String?
    let missingEtaCount: Int
    let lateCount: Int
    var orderedQty: Int? = nil
    var inTransitQty: Int? = nil
    var arrivedQty: Int? = nil
    var supplierBills: Double? = nil
    var otherBills: Double? = nil
    var otherPaid: Double? = nil
    var receivedLandedAmount: Double? = nil
    var agreementDifference: Double? = nil
}

struct PurchaseOrderContainer: Codable, Identifiable, Equatable {
    let id: String
    let ref: String?
    let reference: String?
    let status: ContainerStatus
    let bolNumber: String?
    let etaAt: String?
    let arrivedAt: String?
    let receivedAt: String?
    let orderedAt: String?
    let isDDP: Bool
    let location: String
    let totalQty: Int
    let goodsAmount: Double
    var canRemove: Bool? = nil
    var purchaseOrder: PurchaseOrderReference? = nil
}

struct PurchaseOrderAttachment: Codable, Identifiable, Equatable {
    let id: String
    let purchaseOrderId: String
    let kind: ContainerAttachmentKind
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let uploadedById: String?
    let note: String?
    let createdAt: String
}

/// The detail endpoint returns audit users without their email address.
struct PurchaseOrderAuditEntry: Codable, Identifiable, Equatable {
    struct User: Codable, Identifiable, Equatable {
        let id: String
        let fullName: String
    }

    let id: String
    let action: String
    let entity: String
    let entityId: String?
    let data: [String: JSONValue]?
    let createdAt: String
    let user: User?
}

struct PurchaseOrder: Codable, Identifiable, Equatable {
    struct Supplier: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let currency: String?
    }

    let id: String
    let ref: String
    let supplierId: String
    let supplier: Supplier
    let supplierReference: String?
    let plannedContainerCount: Int
    let agreedGoodsAmount: Double?
    let paymentTerms: String?
    let notes: String?
    let orderedAt: String?
    let version: Int
    let createdAt: String
    let updatedAt: String
    let summary: PurchaseOrderSummary
    let containers: [PurchaseOrderContainer]
    let attachments: [PurchaseOrderAttachment]?
    let auditHistory: [PurchaseOrderAuditEntry]?

    enum CodingKeys: String, CodingKey {
        case id, ref, supplierId, supplier, supplierReference, plannedContainerCount
        case agreedGoodsAmount, paymentTerms, notes, orderedAt, version, createdAt, updatedAt
        case summary, containers, attachments, auditHistory
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        ref = try values.decode(String.self, forKey: .ref)
        supplierId = try values.decode(String.self, forKey: .supplierId)
        supplier = try values.decode(Supplier.self, forKey: .supplier)
        supplierReference = try values.decodeIfPresent(String.self, forKey: .supplierReference)
        plannedContainerCount = try values.decode(Int.self, forKey: .plannedContainerCount)
        if let string = try? values.decode(String.self, forKey: .agreedGoodsAmount) {
            guard let amount = Double(string), amount.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .agreedGoodsAmount, in: values, debugDescription: "Invalid agreed goods amount")
            }
            agreedGoodsAmount = amount
        } else {
            agreedGoodsAmount = try values.decodeIfPresent(Double.self, forKey: .agreedGoodsAmount)
        }
        paymentTerms = try values.decodeIfPresent(String.self, forKey: .paymentTerms)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        orderedAt = try values.decodeIfPresent(String.self, forKey: .orderedAt)
        version = try values.decode(Int.self, forKey: .version)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        summary = try values.decode(PurchaseOrderSummary.self, forKey: .summary)
        containers = try values.decode([PurchaseOrderContainer].self, forKey: .containers)
        attachments = try values.decodeIfPresent([PurchaseOrderAttachment].self, forKey: .attachments)
        auditHistory = try values.decodeIfPresent([PurchaseOrderAuditEntry].self, forKey: .auditHistory)
    }
}

struct PurchaseOrderPayment: Codable, Identifiable, Equatable {
    struct Allocation: Codable, Identifiable, Equatable {
        let id: String
        let containerCostId: String
        let containerId: String
        let containerRef: String?
        let category: ContainerCostCategory
        let amount: Double
        let surviving: Bool
    }

    let id: String
    let ref: String?
    let reference: String?
    let method: String?
    let paidAt: String
    var status: String? = nil
    var note: String? = nil
    let poAllocatedAmount: Double
    let allocations: [Allocation]
}

struct PurchaseOrderCreateInput: Encodable, Equatable {
    let supplierId: String
    var supplierReference: String? = nil
    let plannedContainerCount: Int
    var agreedGoodsAmount: Double? = nil
    var paymentTerms: String? = nil
    var notes: String? = nil
    var idempotencyKey: String? = nil
}

struct PurchaseOrderUpdateInput: Encodable, Equatable {
    let expectedVersion: Int
    let supplierReference: String?
    let plannedContainerCount: Int
    let agreedGoodsAmount: Double?
    let paymentTerms: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case expectedVersion, supplierReference, plannedContainerCount, agreedGoodsAmount, paymentTerms, notes
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(expectedVersion, forKey: .expectedVersion)
        try values.encode(supplierReference, forKey: .supplierReference)
        try values.encode(plannedContainerCount, forKey: .plannedContainerCount)
        try values.encode(agreedGoodsAmount, forKey: .agreedGoodsAmount)
        try values.encode(paymentTerms, forKey: .paymentTerms)
        try values.encode(notes, forKey: .notes)
    }
}

struct PurchaseOrderVersionInput: Encodable, Equatable {
    let expectedVersion: Int
}

struct PurchaseOrderAddContainersInput: Encodable, Equatable {
    let expectedVersion: Int
    let count: Int
    var copyFromContainerId: String? = nil
}

struct PurchaseOrderMoveContainerInput: Encodable, Equatable {
    let purchaseOrderId: String
    let expectedPurchaseOrderId: String?
    let expectedVersion: Int
    var expectedSourceVersion: Int? = nil
    var plannedContainerCount: Int? = nil
    let reason: String

    enum CodingKeys: String, CodingKey {
        case purchaseOrderId, expectedPurchaseOrderId, expectedVersion, expectedSourceVersion, plannedContainerCount, reason
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(purchaseOrderId, forKey: .purchaseOrderId)
        // Explicit null proves that the user reviewed an unlinked container.
        try values.encode(expectedPurchaseOrderId, forKey: .expectedPurchaseOrderId)
        try values.encode(expectedVersion, forKey: .expectedVersion)
        try values.encodeIfPresent(expectedSourceVersion, forKey: .expectedSourceVersion)
        try values.encodeIfPresent(plannedContainerCount, forKey: .plannedContainerCount)
        try values.encode(reason.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .reason)
    }
}

struct PaymentApplicationRelatedAttachment: Codable, Identifiable, Equatable {
    let id: String
    let containerId: String?
    let containerRef: String
    let sourceType: String?
    let purchaseOrderId: String?
    let purchaseOrderRef: String?
    let kind: ContainerAttachmentKind
    let suggestedKind: PaymentApplicationAttachmentKind
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let note: String?
    let createdAt: String
    let isBillAttachment: Bool
    let alreadyAttached: Bool
}

struct PaymentApplicationImportAttachmentInput: Encodable, Equatable {
    let sourceAttachmentId: String
    var sourceType: String? = nil
    var kind: PaymentApplicationAttachmentKind? = nil
    var note: String? = nil
}
