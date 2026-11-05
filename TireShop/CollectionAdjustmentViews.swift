import SwiftUI

/// Secondary controls shared by invoice and multi-invoice collection. The
/// amount being collected remains in the parent payment form.
struct CollectionAdjustmentEditor: View {
    let originalBalance: Double
    @Binding var draft: CollectionAdjustmentDraft
    var invoiceRef: String? = nil
    var isEnabled = true
    var onRemove: (() -> Void)? = nil

    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @FocusState private var amountFocused: Bool

    private var adjustment: InvoiceCollectionAdjustment? {
        try? draft.adjustment(invoiceId: "preview", originalBalance: originalBalance)
    }

    private var validationError: String? { draft.validationError(originalBalance: originalBalance) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { expanded.toggle() }
                    amountFocused = expanded
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text(i18n.t("payment.adjustInvoiceTotal"))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                    .padding(.vertical, Theme.Space.xs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
                .disabled(!isEnabled)
                .accessibilityLabel(invoiceRef.map { i18n.t("payment.adjustInvoiceTotalFor", ["ref": $0]) }
                    ?? i18n.t("payment.adjustInvoiceTotal"))
                .accessibilityValue(i18n.t(expanded ? "payment.adjustmentExpanded" : "payment.adjustmentCollapsed"))

                Spacer(minLength: 0)
                if let adjustment {
                    Text(signedAmount(adjustment.amount))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                } else if draft.isEmpty {
                    Text(i18n.t("payment.adjustmentOptional"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Picker(i18n.t("payment.adjustmentDirection"), selection: $draft.direction) {
                        ForEach(CollectionAdjustmentDirection.allCases) { direction in
                            Text(i18n.t(direction.localizationKey)).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isEnabled)

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(i18n.t("payment.adjustmentAmount"))
                            .font(.caption).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                            Text("$").foregroundStyle(Theme.muted)
                            TextField("0.00", text: $draft.amountText)
                                .font(.body).monospacedDigit()
                                .keyboardType(.decimalPad)
                                .focused($amountFocused)
                                .accessibilityLabel(i18n.t("payment.adjustmentAmount"))
                                .disabled(!isEnabled)
                            Button(i18n.t("payment.removeAdjustment")) { remove() }
                                .font(.subheadline)
                                .disabled(!isEnabled)
                        }
                    }

                    Text(i18n.t("payment.invoiceAdjustmentHint"))
                        .font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, Theme.Space.md)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.border).frame(width: 2)
                }
            }

            if let adjustment, let revised = try? draft.adjustedBalance(originalBalance: originalBalance) {
                calculation(adjustment: adjustment, revised: revised)
            }
            if let validationError {
                Text(i18n.t(validationError))
                    .font(.caption).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !draft.isEmpty { expanded = true } }
        .onChange(of: isEnabled) { _, enabled in if !enabled { amountFocused = false } }
        .toolbar {
            if amountFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(i18n.t("common.done")) { amountFocused = false }
                }
            }
        }
    }

    @ViewBuilder
    private func calculation(adjustment: InvoiceCollectionAdjustment, revised: Double) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                LabeledContent(i18n.t("payment.balanceBeforeAdjustment"), value: AppFormat.money(originalBalance))
                LabeledContent(i18n.t("payment.invoiceAdjustment"), value: signedAmount(adjustment.amount))
                LabeledContent(i18n.t("payment.balanceAfterAdjustment"), value: AppFormat.money(revised))
                    .fontWeight(.semibold)
            }
            .font(.caption).monospacedDigit()
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(i18n.t("payment.balanceAfterAdjustment"))
                    .font(.caption).foregroundStyle(Theme.muted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.xs) {
                        Text(AppFormat.money(originalBalance))
                        Text(adjustment.amount < 0 ? "−" : "+")
                        Text(AppFormat.money(abs(adjustment.amount)))
                        Text("=")
                        Text(AppFormat.money(revised)).fontWeight(.semibold)
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        LabeledContent(i18n.t("payment.balanceBeforeAdjustment"), value: AppFormat.money(originalBalance))
                        LabeledContent(i18n.t("payment.invoiceAdjustment"), value: signedAmount(adjustment.amount))
                        LabeledContent(i18n.t("payment.balanceAfterAdjustment"), value: AppFormat.money(revised))
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                }
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(Theme.text)
            }
        }
    }

    private func signedAmount(_ amount: Double) -> String {
        (amount < 0 ? "−" : "+") + AppFormat.money(abs(amount))
    }

    private func remove() {
        amountFocused = false
        draft = CollectionAdjustmentDraft()
        expanded = false
        onRemove?()
    }
}
