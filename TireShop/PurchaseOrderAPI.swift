import Foundation

struct PurchaseOrdersAPI {
    var client = APIClient.shared

    func list(
        q: String? = nil,
        supplierId: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> Paged<PurchaseOrder> {
        try await client.request("/purchase-orders\(Self.query(q: q, supplierId: supplierId, sortBy: sortBy, sortOrder: sortOrder, page: page, pageSize: pageSize))")
    }

    func get(id: String) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders/\(id)")
    }

    func create(body: PurchaseOrderCreateInput) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders", method: "POST", body: body)
    }

    func create(_ body: PurchaseOrderCreateInput) async throws -> PurchaseOrder {
        try await create(body: body)
    }

    func update(id: String, body: PurchaseOrderUpdateInput) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders/\(id)", method: "PATCH", body: body)
    }

    func issue(id: String, expectedVersion: Int) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders/\(id)/issue", method: "POST", body: PurchaseOrderVersionInput(expectedVersion: expectedVersion))
    }

    func addContainers(id: String, body: PurchaseOrderAddContainersInput) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders/\(id)/containers", method: "POST", body: body)
    }

    func removeContainer(id: String, containerId: String, expectedVersion: Int) async throws -> PurchaseOrder {
        try await client.request("/purchase-orders/\(id)/containers/\(containerId)", method: "DELETE", body: PurchaseOrderVersionInput(expectedVersion: expectedVersion))
    }

    func moveContainer(containerId: String, body: PurchaseOrderMoveContainerInput) async throws -> PurchaseOrder {
        try await client.request("/containers/\(containerId)/purchase-order", method: "POST", body: body)
    }

    func candidates(supplierId: String, excludingOrderId: String, q: String? = nil) async throws -> [ContainerListItem] {
        let page: Paged<ContainerListItem> = try await client.request("/containers\(Self.query(q: q, supplierId: supplierId, pageSize: 100))")
        return page.items.filter {
            $0.supplier.id == supplierId && ($0.purchaseOrderId ?? $0.purchaseOrder?.id) != excludingOrderId
        }
    }

    func payments(id: String) async throws -> [PurchaseOrderPayment] {
        let result: PurchaseOrderPaymentsResponse = try await client.request("/purchase-orders/\(id)/payments")
        return result.items
    }

    func attachments(id: String) async throws -> [PurchaseOrderAttachment] {
        try await client.request("/purchase-orders/\(id)/attachments")
    }

    func uploadAttachment(
        id: String,
        fileURL: URL,
        fileName: String,
        mimeType: String,
        kind: ContainerAttachmentKind,
        note: String? = nil
    ) async throws -> PurchaseOrderAttachment {
        var fields = ["kind": kind]
        if let note { fields["note"] = note }
        return try await client.uploadMultipart(
            "/purchase-orders/\(id)/attachments",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType,
            fields: fields,
            maximumFileBytes: 20 * 1_024 * 1_024
        )
    }

    func downloadAttachment(id: String, attachment: PurchaseOrderAttachment) async throws -> URL {
        try await client.download("/purchase-orders/\(id)/attachments/\(attachment.id)/download", fileName: attachment.filename)
    }

    func deleteAttachment(id: String, attachmentId: String) async throws -> OkResponse {
        try await client.request("/purchase-orders/\(id)/attachments/\(attachmentId)", method: "DELETE")
    }

    func export(q: String? = nil, supplierId: String? = nil, ids: [String]? = nil) async throws -> URL {
        try await client.download("/purchase-orders/export\(Self.query(q: q, supplierId: supplierId, ids: ids))", fileName: "purchase-orders.xlsx")
    }

    private static func query(
        q: String? = nil,
        supplierId: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        ids: [String]? = nil
    ) -> String {
        let parameters: [(String, String?)] = [
            ("q", q), ("supplierId", supplierId), ("sortBy", sortBy), ("sortOrder", sortOrder),
            ("page", page.map(String.init)), ("pageSize", pageSize.map(String.init)),
            ("ids", ids.map { $0.joined(separator: ",") })
        ]
        var components = URLComponents()
        components.queryItems = parameters.compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        // Nest's form-style query parser treats a literal plus as a space.
        return components.percentEncodedQuery.map { "?\($0.replacingOccurrences(of: "+", with: "%2B"))" } ?? ""
    }
}

private struct PurchaseOrderPaymentsResponse: Decodable {
    let items: [PurchaseOrderPayment]
}

extension PaymentApplicationsAPI {
    func relatedAttachments(id: String) async throws -> [PaymentApplicationRelatedAttachment] {
        try await client.request("/payment-applications/\(id)/related-attachments")
    }

    /// Importing copies the bytes; source removal cannot erase approval evidence.
    func importAttachment(id: String, body: PaymentApplicationImportAttachmentInput) async throws -> PaymentApplicationAttachment {
        try await client.request("/payment-applications/\(id)/attachments/import", method: "POST", body: body)
    }
}
