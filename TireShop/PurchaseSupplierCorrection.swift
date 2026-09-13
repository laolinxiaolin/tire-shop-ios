import SwiftUI

/// Mirrors the server's supplier-owed cost categories. Freight and landed-cost
/// extras never determine whether the supplier's purchase invoice is paid.
enum PurchasePaymentStatus: String {
    case unpaid, partial, paid

    static let supplierCategories = ["DOWN_PAYMENT", "BALANCE_PAYMENT", "SUPPLIER_OTHER"]

    static func from(costs: [PurchasePaymentCost]) -> Self {
        let supplierCosts = costs.filter {
            $0.status != "VOID" && supplierCategories.contains($0.category)
        }
        guard !supplierCosts.isEmpty else { return .unpaid }
        let total = supplierCosts.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amount) ?? 0) }
        let paid = supplierCosts.reduce(Decimal.zero) { $0 + (Decimal(string: $1.amountPaid) ?? 0) }
        if paid >= total - Decimal(1) / 100 { return .paid }
        return paid > 0 ? .partial : .unpaid
    }

    static func from(costs: [ContainerCost]) -> Self {
        from(costs: costs.map {
            PurchasePaymentCost(category: $0.category, status: $0.status, amount: $0.amount, amountPaid: $0.amountPaid)
        })
    }

    @MainActor
    func label(using i18n: I18nStore) -> String {
        i18n.t("purchasing.paymentStatus.\(rawValue)")
    }

    var color: Color {
        switch self {
        case .unpaid: return Theme.danger
        case .partial: return Color(lightHex: 0x9a6700, darkHex: 0xe3b341)
        case .paid: return Theme.success
        }
    }
}

struct PurchasePaymentCost: Codable, Equatable {
    let category: String
    let status: String
    let amount: String
    let amountPaid: String

    init(category: String, status: String, amount: String, amountPaid: String) {
        self.category = category
        self.status = status
        self.amount = amount
        self.amountPaid = amountPaid
    }

    private enum CodingKeys: String, CodingKey {
        case category, status, amount, amountPaid
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        category = try values.decode(String.self, forKey: .category)
        status = try values.decode(String.self, forKey: .status)
        amount = try Self.money(values, key: .amount)
        amountPaid = try Self.money(values, key: .amountPaid)
    }

    private static func money(_ values: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> String {
        if let value = try? values.decode(String.self, forKey: key) { return value }
        return try values.decode(Decimal.self, forKey: key).description
    }
}

struct ContainerSupplierChoice: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let payeeVendorId: String?
    let payeeVendorName: String
}

struct ContainerSupplierChangePreview: Decodable, Equatable {
    struct Supplier: Decodable, Equatable {
        let id: String
        let name: String
    }

    struct Bill: Decodable, Identifiable, Equatable {
        let id: String
        let category: String
        let description: String?
        let reference: String?
        let amount: Double
        let amountPaid: Double
        let status: String
        let vendorId: String?
        let vendor: String?
    }

    let previewToken: String
    let containerId: String
    let containerRef: String?
    let status: String
    let oldSupplier: Supplier
    let newSupplier: ContainerSupplierChoice?
    let suppliers: [ContainerSupplierChoice]
    let affectedBills: [Bill]
    let affectedTotal: Double

    func submission(containerId: String, supplierId: String, reason: String) -> ContainerSupplierChangeInput? {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.containerId == containerId, status != "CANCELLED",
              !supplierId.isEmpty, newSupplier?.id == supplierId, oldSupplier.id != supplierId,
              !previewToken.isEmpty, !trimmedReason.isEmpty, trimmedReason.utf16.count <= 1000 else { return nil }
        return ContainerSupplierChangeInput(
            supplierId: supplierId,
            expectedSupplierId: oldSupplier.id,
            previewToken: previewToken,
            reason: trimmedReason
        )
    }
}

struct ContainerSupplierChangeInput: Encodable, Equatable {
    let supplierId: String
    let expectedSupplierId: String
    let previewToken: String
    let reason: String
}

extension ContainersAPI {
    func previewSupplierChange(id: String, supplierId: String?) async throws -> ContainerSupplierChangePreview {
        var components = URLComponents()
        components.queryItems = supplierId.map { [URLQueryItem(name: "supplierId", value: $0)] }
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await client.request("/containers/\(id)/supplier-change\(suffix)")
    }

    func changeSupplier(id: String, body: ContainerSupplierChangeInput) async throws -> Container {
        try await client.request("/containers/\(id)/supplier-change", method: "POST", body: body)
    }
}

struct PurchaseSupplierCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore

    let container: Container
    let onSaved: (Container) -> Void

    @State private var supplierId = ""
    @State private var reason = ""
    @State private var suppliers: [ContainerSupplierChoice] = []
    @State private var preview: ContainerSupplierChangePreview?
    @State private var loading = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var requestID = 0

    private var submission: ContainerSupplierChangeInput? {
        guard !loading else { return nil }
        return preview?.submission(containerId: container.id, supplierId: supplierId, reason: reason)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(i18n.t("purchasing.supplierChange.originalSupplier"), value: preview?.oldSupplier.name ?? container.supplier.name)
                    Picker(i18n.t("purchasing.supplierChange.newSupplier"), selection: Binding(
                        get: { supplierId },
                        set: {
                            preview = nil
                            supplierId = $0
                        }
                    )) {
                        Text(i18n.t("purchasing.pickSupplier")).tag("")
                        ForEach(suppliers.filter { $0.id != (preview?.oldSupplier.id ?? container.supplier.id) }) { supplier in
                            Text(supplier.name).tag(supplier.id)
                        }
                    }
                    .disabled(saving || suppliers.isEmpty)
                }

                if loading {
                    ProgressView(i18n.t("purchasing.supplierChange.loadingReview"))
                }

                if let preview {
                    Section(i18n.t("purchasing.supplierChange.affectedBills")) {
                        if preview.affectedBills.isEmpty {
                            Text(i18n.t("purchasing.supplierChange.noBills"))
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(preview.affectedBills) { bill in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                LabeledContent(i18n.t("purchasing.costCategory.\(bill.category)"), value: AppFormat.money(bill.amount))
                                if let details = [bill.reference, bill.description].compactMap({ $0?.nilIfBlank }).joined(separator: " · ").nilIfBlank {
                                    Text(details).font(.caption).foregroundStyle(Theme.muted)
                                }
                                LabeledContent(i18n.t("purchasing.supplierChange.currentPayee"), value: bill.vendor ?? "—")
                                    .font(.caption)
                            }
                        }
                        Text(i18n.t("purchasing.supplierChange.affectedTotal", [
                            "count": preview.affectedBills.count,
                            "amount": String(format: "%.2f", preview.affectedTotal)
                        ]))
                        .fontWeight(.semibold)
                        if let supplier = preview.newSupplier {
                            Text("\(preview.oldSupplier.name) → \(supplier.name)")
                            Text(i18n.t("purchasing.supplierChange.newPayee", ["name": supplier.payeeVendorName]))
                                .font(.subheadline)
                        }
                    }
                }

                Section(i18n.t("purchasing.supplierChange.reason")) {
                    TextField(i18n.t("purchasing.supplierChange.reason"), text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(saving)
                    Text("\(reason.utf16.count) / 1000")
                        .font(.caption)
                        .foregroundStyle(reason.utf16.count > 1000 ? Theme.danger : Theme.muted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                        Button(i18n.t("purchasing.supplierChange.retryReview")) {
                            Task { await loadPreview() }
                        }
                        .disabled(loading || saving)
                    }
                }

                Section {
                    PrimaryButton(title: i18n.t("purchasing.supplierChange.confirm"), loading: saving, disabled: submission == nil || saving) {
                        Task { await save() }
                    }
                }
            }
            .navigationTitle(i18n.t("purchasing.supplierChange.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
            .task(id: supplierId) { await loadPreview() }
            .onDisappear { requestID += 1 }
        }
    }

    @MainActor
    private func loadPreview() async {
        requestID += 1
        let request = requestID
        let selectedSupplier = supplierId
        loading = true
        preview = nil
        errorMessage = nil
        do {
            let result = try await ContainersAPI().previewSupplierChange(id: container.id, supplierId: selectedSupplier.nilIfBlank)
            guard request == requestID, supplierId == selectedSupplier, !Task.isCancelled else { return }
            preview = result
            suppliers = result.suppliers
        } catch {
            guard request == requestID, supplierId == selectedSupplier, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func save() async {
        guard !saving, let body = submission else { return }
        saving = true
        errorMessage = nil
        do {
            let updated = try await ContainersAPI().changeSupplier(id: container.id, body: body)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            // A changed payment, bill, or supplier invalidates the reviewed
            // snapshot. Require another server preview before the next write.
            preview = nil
        }
        saving = false
    }
}
