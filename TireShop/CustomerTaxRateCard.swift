import SwiftUI

struct CustomerTaxRateCard: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    let customer: Customer
    let onChange: (Customer) -> Void

    @State private var lookup: CustomerTaxDetails?
    @State private var loading = false
    @State private var saving = false
    @State private var reviewing = false
    @State private var loadGeneration = UUID()
    @State private var errorMessage: String?
    @State private var mode: CustomerTaxMode = .automatic
    @State private var percent = ""
    @State private var reason = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var reviewSourceURL = ""
    @State private var reviewNotes = ""
    @State private var reviewConfirmed = false
    @State private var customerReloadPending = false

    private var canManage: Bool { auth.user?.isAdmin == true }
    private var busy: Bool { loading || saving || reviewing }
    private var canSave: Bool {
        canManage && lookup != nil && !customerReloadPending && reason.nilIfBlank != nil && reason.count <= 500
            && (mode != .manual || CustomerTaxValidation.rate(fromPercent: percent) != nil)
    }
    private var canReview: Bool {
        canManage && lookup?.resolution?.problemCode == "SPECIAL_DISTRICT_COVERAGE_UNKNOWN"
            && CustomerTaxValidation.evidenceURL(reviewSourceURL) != nil
            && reviewSourceURL.count <= 2000 && reviewNotes.nilIfBlank != nil
            && reviewNotes.count <= 1000 && reviewConfirmed
    }

    var body: some View {
        Section {
            Text(i18n.t("customers.taxRateVerifiedHint"))
                .font(.caption)
                .foregroundStyle(Theme.muted)

            if loading {
                ProgressView(i18n.t("common.loading"))
            } else if let lookup {
                resolutionSummary(lookup)
            }

            if let lookup, lookup.source == "EXEMPT" {
                Text(i18n.t("customers.taxRateExempt"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.success)
            }

            if let current = lookup?.override {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("\(i18n.t(current.usesShopDefault ? "customers.taxRateShopDefault" : "customers.taxRateManual")): \(percentage(current.rate))")
                    Text("\(i18n.t("customers.taxOverrideAuthorized")): \(current.reason)")
                    if let end = current.expiresAt, let day = CustomerTaxValidation.expiryDay(end) {
                        Text("\(i18n.t("customers.taxOverrideExpires")) \(CustomerTaxValidation.dateKey(day))")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            }

            if canManage {
                overrideFields
            } else {
                Text(i18n.t("customers.taxOverrideAdminOnly"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            }

            if canManage {
                Button {
                    Task { await saveOverride() }
                } label: {
                    Label(i18n.t(saving ? "common.saving" : "customers.saveTaxRate"), systemImage: "checkmark.seal")
                }
                .disabled(busy || !canSave)
            }

            Button {
                Task { await refresh() }
            } label: {
                Label(i18n.t("customers.refreshTaxRate"), systemImage: "arrow.clockwise")
            }
            .disabled(busy)
        } header: {
            Text(i18n.t("customers.salesTaxRate"))
        }
        .task(id: customer) { await load(resetReview: true) }

        if canManage, lookup?.resolution?.problemCode == "SPECIAL_DISTRICT_COVERAGE_UNKNOWN" {
            addressReviewSection
        }
    }

    private func resolutionSummary(_ details: CustomerTaxDetails) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(i18n.t("customers.taxResolutionStatus.\(details.resolutionStatus)"))
                .font(.subheadline.weight(.semibold))
            if let code = details.resolution?.problemCode {
                Text(i18n.t("customers.taxResolutionProblem.\(code)"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            if let address = details.resolution?.addressLabel, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            if let reviewedAt = details.resolution?.reviewedAt {
                Text("\(i18n.t("customers.addressReviewedAt")) \(AppFormat.dateTime(reviewedAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                if let source = details.resolution?.reviewSourceUrl,
                   let url = CustomerTaxValidation.evidenceURL(source) {
                    Link(i18n.t("customers.addressReviewEvidence"), destination: url)
                        .font(.caption)
                }
            }
            if let rate = details.automaticRate {
                LabeledContent(i18n.t("customers.taxRateAutomatic"), value: percentage(rate))
                    .font(.subheadline)
            }
            if details.automatic?.status == "RESOLVED", let source = details.automatic?.source {
                Text(([source.label] + source.dorCodes.compactMap { $0 }).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var overrideFields: some View {
        Group {
            Picker(i18n.t("customers.salesTaxRate"), selection: $mode) {
                Text(i18n.t("customers.taxRateAutomatic")).tag(CustomerTaxMode.automatic)
                Text("\(i18n.t("customers.taxRateShopDefault")) (\(percentage(lookup?.shopDefaultRate ?? 0)))")
                    .tag(CustomerTaxMode.shopDefault)
                Text(i18n.t("customers.taxRateManual")).tag(CustomerTaxMode.manual)
            }
            .pickerStyle(.inline)
            .onChange(of: mode) { _, next in
                if next == .manual, percent.isEmpty, let rate = lookup?.automaticRate {
                    percent = String(format: "%.2f", rate * 100)
                }
            }

            if mode == .manual {
                TextField(i18n.t("customers.taxRatePercent"), text: $percent)
                    .keyboardType(.decimalPad)
                if CustomerTaxValidation.rate(fromPercent: percent) == nil {
                    Text(i18n.t("customers.taxRateInvalid"))
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }

            TextField(i18n.t("customers.taxOverrideReason"), text: $reason, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: reason) { _, value in
                    if value.count > 500 { reason = String(value.prefix(500)) }
                }

            if mode == .manual {
                Toggle(i18n.t("customers.taxOverrideExpiry"), isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker(i18n.t("customers.taxOverrideExpiry"), selection: $expiry, displayedComponents: .date)
                        .environment(\.timeZone, CustomerTaxValidation.expiryTimeZone)
                }
            }
        }
        .disabled(busy || lookup == nil)
    }

    private var addressReviewSection: some View {
        Section {
            Text(i18n.t("customers.addressReviewDescription"))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            TextField(i18n.t("customers.addressReviewSource"), text: $reviewSourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: reviewSourceURL) { _, value in
                    reviewConfirmed = false
                    if value.count > 2000 { reviewSourceURL = String(value.prefix(2000)) }
                }
            TextField(i18n.t("customers.addressReviewNotes"), text: $reviewNotes, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: reviewNotes) { _, value in
                    reviewConfirmed = false
                    if value.count > 1000 { reviewNotes = String(value.prefix(1000)) }
                }
            Toggle(i18n.t("customers.addressReviewConfirmation"), isOn: $reviewConfirmed)
            Button {
                Task { await reviewAddress() }
            } label: {
                Label(i18n.t(reviewing ? "common.saving" : "customers.addressReviewApprove"), systemImage: "checkmark.shield")
            }
            .disabled(!canReview)
        } header: {
            Text(i18n.t("customers.addressReviewTitle"))
        }
        .disabled(busy)
    }

    private func percentage(_ rate: Double) -> String {
        String(format: "%.2f%%", rate * 100)
    }

    @MainActor
    private func load(resetReview: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation
        loading = true
        lookup = nil
        errorMessage = nil
        if resetReview {
            reviewSourceURL = ""
            reviewNotes = ""
            reviewConfirmed = false
        }
        defer { if generation == loadGeneration { loading = false } }
        do {
            let result = try await CustomerTaxAPI().details(customerId: customer.id)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            lookup = result
            if let current = result.override {
                mode = current.usesShopDefault ? .shopDefault : .manual
                percent = String(format: "%.2f", current.rate * 100)
                let day = current.expiresAt.flatMap(CustomerTaxValidation.expiryDay)
                hasExpiry = day != nil
                if let day { expiry = day }
            } else {
                mode = .automatic
                percent = ""
                hasExpiry = false
            }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refresh() async {
        guard !busy else { return }
        if customerReloadPending {
            loading = true
            do {
                let updated = try await CustomerTaxAPI().reloadCustomer(customerId: customer.id)
                customerReloadPending = false
                onChange(updated)
            } catch {
                loading = false
                errorMessage = i18n.t("customers.taxRateSavedReloadFailed")
                return
            }
            loading = false
        }
        await load()
    }

    @MainActor
    private func saveOverride() async {
        guard canSave, !busy else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let result = try await CustomerTaxAPI().saveOverride(
                customerId: customer.id,
                body: CustomerTaxOverrideInput(
                    taxRateOverride: mode == .manual ? CustomerTaxValidation.rate(fromPercent: percent) : nil,
                    useShopDefault: mode == .shopDefault,
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                    expiresAt: mode == .manual && hasExpiry ? CustomerTaxValidation.dateKey(expiry) : nil
                )
            )
            reason = ""
            switch result {
            case .reloaded(let updated):
                onChange(updated)
            case .needsCustomerReload:
                customerReloadPending = true
            }
            await load()
            if customerReloadPending { errorMessage = i18n.t("customers.taxRateSavedReloadFailed") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reviewAddress() async {
        guard canReview, !busy else { return }
        reviewing = true
        errorMessage = nil
        defer { reviewing = false }
        do {
            try await CustomerTaxAPI().reviewAddress(
                customerId: customer.id,
                body: CustomerAddressReviewInput(
                    sourceUrl: reviewSourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: reviewNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                    confirmedNoUncoveredSpecialDistrict: reviewConfirmed
                )
            )
            await load(resetReview: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
