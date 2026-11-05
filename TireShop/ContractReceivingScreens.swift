import SwiftUI

extension Container {
    var hasContractLines: Bool { lines.contains { $0.contractLineId != nil } }
}

struct ContractReceivingSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    @StateObject private var store: ContractReceivingStore
    @State private var selectedShipmentID = ""
    @State private var quantity = ""
    @State private var businessDate = ""
    @State private var disposition: ContractReceiptDisposition = .saleable

    init(container: Container, store: ContractReceivingStore? = nil, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        _store = StateObject(wrappedValue: store ?? ContractReceivingStore(container: container))
    }

    private var selectedShipment: ContractReceiptShipment? {
        store.shipments.first { $0.id == selectedShipmentID }
    }

    private var locked: Bool {
        store.loading || store.saving || store.pendingRequest != nil || store.saved || store.requiresRefresh
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(i18n.t("purchasing.receipt.help"))
                        .foregroundStyle(Theme.muted)
                    if store.loading {
                        ProgressView(i18n.t("common.loading"))
                    } else if store.saving {
                        ProgressView(i18n.t("common.saving"))
                    }
                }

                if !store.shipments.isEmpty {
                    receiptFields
                } else if !store.loading && store.pendingRequest == nil && !store.saved {
                    Section {
                        Text(i18n.t("purchasing.receipt.noShipments"))
                            .foregroundStyle(Theme.muted)
                    }
                }

                if let error = store.errorMessage {
                    Section {
                        Text(i18n.t(error)).foregroundStyle(Theme.danger)
                    }
                }

                if store.pendingRequest != nil && !store.saving {
                    Section {
                        Text(i18n.t("purchasing.receipt.uncertain"))
                            .foregroundStyle(Theme.muted)
                        Button(i18n.t("purchasing.receipt.retry")) {
                            Task { await store.retry() }
                        }
                        .disabled(store.saving || store.loading || store.saved)
                    }
                }

                Section {
                    Button(i18n.t("common.refresh")) { Task { await store.load() } }
                        .disabled(store.saving || store.loading || store.saved)
                }
            }
            .navigationTitle(i18n.t("purchasing.receipt.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }
                        .disabled(store.saving || store.pendingRequest != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t("common.save")) {
                        guard let shipment = selectedShipment else { return }
                        Task {
                            await store.submit(shipment: shipment, quantity: quantity,
                                               businessDate: businessDate, disposition: disposition)
                        }
                    }
                    .disabled(locked || selectedShipment == nil || quantity.isEmpty || businessDate.isEmpty)
                }
            }
            .interactiveDismissDisabled(store.saving || store.pendingRequest != nil)
            .task {
                await store.load()
                selectAvailableShipment()
            }
            .onChange(of: selectedShipmentID) { _, _ in seedSelection() }
            .onChange(of: store.shipments) { _, shipments in
                if !shipments.contains(where: { $0.id == selectedShipmentID }) {
                    selectedShipmentID = shipments.first?.id ?? ""
                }
                seedSelection()
            }
            .onChange(of: store.loading) { _, loading in
                if !loading { selectAvailableShipment() }
            }
            .onChange(of: store.saved) { _, saved in
                if saved { onSaved(); dismiss() }
            }
        }
    }

    private var receiptFields: some View {
        Section {
            Picker(i18n.t("purchasing.receipt.shipment"), selection: $selectedShipmentID) {
                ForEach(store.shipments) { shipment in
                    Text(shipment.label).tag(shipment.id)
                }
            }
            if let shipment = selectedShipment {
                LabeledContent(i18n.t("purchasing.receipt.remaining"), value: String(shipment.remainingQty))
                LabeledContent(i18n.t("purchasing.receipt.shippedDate"), value: shipment.businessDate)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(i18n.t("purchasing.receipt.quantity"))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                TextField("0", text: $quantity)
                    .keyboardType(.numberPad)
                    .accessibilityLabel(i18n.t("purchasing.receipt.quantity"))
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(i18n.t("purchasing.receipt.date"))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                TextField("YYYY-MM-DD", text: $businessDate)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(i18n.t("purchasing.receipt.date"))
            }
            Picker(i18n.t("purchasing.receipt.disposition"), selection: $disposition) {
                ForEach(ContractReceiptDisposition.allCases) { option in
                    Text(i18n.t("purchasing.receipt.disposition.\(option.rawValue)")).tag(option)
                }
            }
        }
        .disabled(locked)
    }

    private func seedSelection() {
        guard !locked, let shipment = selectedShipment else { return }
        quantity = String(shipment.remainingQty)
        businessDate = shipment.currentBusinessDate
    }

    private func selectAvailableShipment() {
        if selectedShipment == nil { selectedShipmentID = store.shipments.first?.id ?? "" }
        seedSelection()
    }
}
