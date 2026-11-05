import Combine
import Foundation

enum ContractReceiptDisposition: String, CaseIterable, Identifiable {
    case saleable = "SALEABLE"
    case qc = "QC"
    case damaged = "DAMAGED"

    var id: String { rawValue }
}

struct ContractReceiptShipment: Identifiable, Equatable {
    let id: String
    let contractLineID: String
    let containerLineID: String
    let label: String
    let remainingQty: Int
    let businessDate: String
    let currentBusinessDate: String
}

struct ContractReceiptRequest: Encodable, Equatable {
    let expectedVersion: Int
    let kind = "RECEIVE"
    let qty: Int
    let sourceEventId: String
    let shipmentId: String
    let containerLineId: String
    let businessDate: String
    let disposition: ContractReceiptDisposition
}

extension ContractReceiptDisposition: Codable {}

struct ContractReceiptPendingRequest: Equatable {
    let orderID: String
    let contractLineID: String
    let body: ContractReceiptRequest
}

struct ContractReceiptLedger: Decodable {
    let version: Int
    let lines: [Line]

    struct Line: Decodable {
        let id: String
        let purchaseOrderId: String?
        let skuLabel: String?
        let currentBusinessDate: String?
        let legacyMappingArchivedAt: String?
        let events: [ContractReceiptEvent]
    }
}

struct ContractReceiptEvent: Decodable {
    struct SourceDocument: Decodable {
        let type: String
        let id: String
    }

    let id: String
    let kind: String
    let qty: Int
    let sourceEventId: String?
    let shipmentId: String?
    let originalEventId: String?
    let containerLineId: String?
    let businessDate: String?
    let currentBusinessDate: String?
    let disposition: ContractReceiptDisposition?
    let reversedAt: String?
    let legacyMappingArchivedAt: String?
    let remainingProtectableQty: Double?
    let sourceDocument: SourceDocument?

    func matches(_ request: ContractReceiptRequest) -> Bool {
        kind == request.kind && sourceEventId == request.sourceEventId && qty == request.qty
            && shipmentId == request.shipmentId && containerLineId == request.containerLineId
            && businessDate == request.businessDate && disposition == request.disposition
    }
}

struct ContractReceivingAPI {
    let loadLedger: (String) async throws -> ContractReceiptLedger
    let recordReceipt: (String, String, ContractReceiptRequest) async throws -> ContractReceiptEvent

    init(client: APIClient = .shared) {
        loadLedger = { orderID in
            try await client.request("/purchase-orders/\(orderID)/quantity-ledger")
        }
        recordReceipt = { orderID, lineID, body in
            try await client.request("/purchase-orders/\(orderID)/contract-lines/\(lineID)/receipts", method: "POST", body: body)
        }
    }

    init(
        loadLedger: @escaping (String) async throws -> ContractReceiptLedger,
        recordReceipt: @escaping (String, String, ContractReceiptRequest) async throws -> ContractReceiptEvent
    ) {
        self.loadLedger = loadLedger
        self.recordReceipt = recordReceipt
    }
}

/// A receipt's request identity survives an uncertain write and subsequent reads.
/// The backend checks that identity before checking the captured parent version.
@MainActor
final class ContractReceivingStore: ObservableObject {
    @Published private(set) var shipments: [ContractReceiptShipment] = []
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var saved = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingRequest: ContractReceiptPendingRequest?
    @Published private(set) var requiresRefresh = true

    private let container: Container
    private let api: ContractReceivingAPI
    private var version: Int?

    init(container: Container, api: ContractReceivingAPI = .init()) {
        self.container = container
        self.api = api
    }

    func load() async {
        guard !loading, !saving, !saved else { return }
        guard let orderID = container.purchaseOrderId ?? container.purchaseOrder?.id else {
            errorMessage = "purchasing.receipt.missingOrder"
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let ledger = try await api.loadLedger(orderID)
            try Task.checkCancellation()
            guard ledger.version > 0 else {
                throw APIError(status: 400, message: "purchasing.receipt.refreshRequired")
            }
            if let pendingRequest,
               ledger.lines.contains(where: { line in
                   line.id == pendingRequest.contractLineID && line.purchaseOrderId == orderID
                       && line.events.contains(where: { $0.matches(pendingRequest.body) })
               }) {
                saved = true
                self.pendingRequest = nil
                requiresRefresh = false
                return
            }
            shipments = Self.shipments(from: ledger, for: container, orderID: orderID)
            version = ledger.version
            requiresRefresh = false
        } catch {
            errorMessage = error.localizedDescription
            requiresRefresh = true
        }
    }

    func submit(shipment: ContractReceiptShipment, quantity: String, businessDate: String, disposition: ContractReceiptDisposition) async {
        guard !saving, !loading, !saved, pendingRequest == nil else { return }
        guard !requiresRefresh, let version,
              let orderID = container.purchaseOrderId ?? container.purchaseOrder?.id else {
            errorMessage = "purchasing.receipt.refreshRequired"
            return
        }
        guard shipments.contains(shipment) else {
            errorMessage = "purchasing.receipt.unavailableShipment"
            return
        }
        let text = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let qty = Int(text), qty > 0, qty <= Int32.max, qty <= shipment.remainingQty else {
            errorMessage = "purchasing.receipt.invalidQuantity"
            return
        }
        guard CheckDates.isValid(businessDate), CheckDates.isValid(shipment.businessDate),
              CheckDates.isValid(shipment.currentBusinessDate) else {
            errorMessage = "purchasing.receipt.invalidDate"
            return
        }
        guard businessDate >= shipment.businessDate else {
            errorMessage = "purchasing.receipt.beforeShipment"
            return
        }
        guard businessDate <= shipment.currentBusinessDate else {
            errorMessage = "purchasing.receipt.futureDate"
            return
        }
        pendingRequest = ContractReceiptPendingRequest(orderID: orderID, contractLineID: shipment.contractLineID,
            body: ContractReceiptRequest(expectedVersion: version, qty: qty, sourceEventId: UUID().uuidString,
                shipmentId: shipment.id, containerLineId: shipment.containerLineID,
                businessDate: businessDate, disposition: disposition))
        await retry()
    }

    func retry() async {
        guard !saving, !loading, !saved, let pendingRequest else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let event = try await api.recordReceipt(pendingRequest.orderID, pendingRequest.contractLineID, pendingRequest.body)
            guard event.matches(pendingRequest.body) else {
                errorMessage = "purchasing.receipt.uncertain"
                return
            }
            // A later parent-screen refresh cannot make this write repeatable.
            saved = true
            self.pendingRequest = nil
            requiresRefresh = false
        } catch {
            if let status = (error as? APIError)?.status,
               (400..<500).contains(status), ![408, 429].contains(status) {
                self.pendingRequest = nil
                requiresRefresh = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private static func shipments(from ledger: ContractReceiptLedger, for container: Container, orderID: String) -> [ContractReceiptShipment] {
        let nativeLines = Dictionary(uniqueKeysWithValues: container.lines.map { ($0.id, $0) })
        return ledger.lines.flatMap { line -> [ContractReceiptShipment] in
            guard line.purchaseOrderId == orderID, line.legacyMappingArchivedAt == nil else { return [] }
            let reversed = Set(line.events.filter {
                $0.kind == "REVERSE" && $0.reversedAt == nil && $0.legacyMappingArchivedAt == nil
            }.compactMap(\.originalEventId))
            return line.events.compactMap { event in
                guard event.kind == "SHIP", event.reversedAt == nil, event.legacyMappingArchivedAt == nil,
                      !reversed.contains(event.id), let nativeID = event.containerLineId,
                      let native = nativeLines[nativeID], native.contractLineId == line.id,
                      event.sourceDocument?.type == "CONTAINER", event.sourceDocument?.id == container.id,
                      let remaining = event.remainingProtectableQty, remaining.isFinite, remaining > 0,
                      remaining.rounded() == remaining, remaining <= Double(Int32.max),
                      let day = event.businessDate, CheckDates.isValid(day),
                      let today = event.currentBusinessDate ?? line.currentBusinessDate, CheckDates.isValid(today),
                      day <= today else { return nil }
                return ContractReceiptShipment(id: event.id, contractLineID: line.id, containerLineID: nativeID,
                    label: line.skuLabel ?? native.sku.sku, remainingQty: Int(remaining),
                    businessDate: day, currentBusinessDate: today)
            }
        }
    }
}
