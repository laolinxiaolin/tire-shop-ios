import SwiftUI

struct AddCashAccountSheet: View {
    let onCreated: (CashAccount) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @State private var name = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(i18n.t("accounting.cash.addAccountHelp"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    AppTextField(
                        label: i18n.t("accounting.cash.accountName"),
                        text: $name,
                        placeholder: i18n.t("accounting.cash.accountNamePlaceholder")
                    )
                }
                .disabled(saving)
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle(i18n.t("accounting.cash.addAccount"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t(saving ? "accounting.cash.adding" : "accounting.cash.addAccount")) {
                        Task { await save() }
                    }
                    .disabled(saving || name.nilIfBlank == nil || name.count > 100 || !auth.has("accounting.manage"))
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @MainActor
    private func save() async {
        guard !saving, auth.has("accounting.manage"), let name = name.nilIfBlank, name.count <= 100 else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let account = try await CashAccountsAPI().createAccount(name: name)
            onCreated(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
