import SwiftUI

struct PaymentApplicationRelatedDocumentsSheet: View {
    let applicationId: String
    let onImported: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    @EnvironmentObject private var auth: AuthStore
    @State private var documents: [PaymentApplicationRelatedAttachment] = []
    @State private var loading = true
    @State private var importing: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(i18n.t("pa.copyEvidenceNote")).font(.footnote).foregroundStyle(Theme.muted)
                }
                if loading { ProgressView() }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                        Button(i18n.t("common.retry")) { Task { await load() } }.disabled(importing != nil)
                    }
                }
                if !loading, documents.isEmpty, errorMessage == nil {
                    Text(i18n.t("pa.noRelatedDocuments")).foregroundStyle(Theme.muted)
                }
                ForEach(documents) { document in
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(document.filename).font(.headline)
                            Text(document.sourceType == "PURCHASE_ORDER"
                                 ? document.purchaseOrderRef ?? document.containerRef
                                 : document.containerRef)
                                .font(.caption).foregroundStyle(Theme.muted)
                            Text("\(i18n.t("purchasing.po.kind.\(document.kind)")) · \(document.sizeBytes / 1024) KB")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if document.alreadyAttached {
                            Label(i18n.t("pa.alreadyAttached"), systemImage: "checkmark").font(.caption)
                        } else if importing == document.id {
                            ProgressView()
                        } else {
                            Button(i18n.t("pa.attachCopy")) { Task { await attach(document) } }
                                .buttonStyle(.bordered)
                                .disabled(importing != nil || !auth.has("paymentapps.manage"))
                        }
                    }
                }
            }
            .navigationTitle(i18n.t("pa.fromPurchasing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.done")) { dismiss() }.disabled(importing != nil)
                }
            }
            .task { await load() }
            .interactiveDismissDisabled(importing != nil)
        }
    }

    @MainActor
    private func load() async {
        guard auth.has("paymentapps.manage") else { loading = false; return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let result = try await PaymentApplicationsAPI().relatedAttachments(id: applicationId)
            guard !Task.isCancelled else { return }
            documents = result
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }

    @MainActor
    private func attach(_ document: PaymentApplicationRelatedAttachment) async {
        guard importing == nil, !document.alreadyAttached, auth.has("paymentapps.manage") else { return }
        importing = document.id
        errorMessage = nil
        defer { importing = nil }
        do {
            _ = try await PaymentApplicationsAPI().importAttachment(id: applicationId, body: .init(
                sourceAttachmentId: document.id, sourceType: document.sourceType,
                kind: document.suggestedKind, note: document.note))
            await onImported()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}
