import Foundation
import SwiftUI

enum QuotePricingError: Error, LocalizedError {
    case pickCustomer, reviewRequired, invalidPrice, invalidPreview, staleReview, unconfirmedCreation

    var localizationKey: String {
        switch self {
        case .pickCustomer: return "pricing.pickCustomer"
        case .reviewRequired: return "pricing.reviewRequired"
        case .invalidPrice: return "pricing.invalidPrice"
        case .invalidPreview: return "pricing.invalidPreview"
        case .staleReview: return "pricing.staleReview"
        case .unconfirmedCreation: return "pricing.unconfirmedCreation"
        }
    }

    var errorDescription: String? {
        switch self {
        case .pickCustomer: return "Pick a customer before adding a tire."
        case .reviewRequired: return "Refresh and review customer prices before saving."
        case .invalidPrice: return "Prices and adjustments must be valid amounts with at most two decimal places."
        case .invalidPreview: return "Customer pricing is incomplete. Retry the price preview."
        case .staleReview: return "The sale changed while prices were being reviewed. Refresh the preview."
        case .unconfirmedCreation: return "Sale creation was not confirmed. Check Sales for a saved draft before starting another sale."
        }
    }
}

struct QuotePricingProposal: Identifiable {
    let id = UUID()
    let customer: QuoteCustomer
    let originalCustomerId: String?
    let originalLines: [QuoteLine]
    let proposedLines: [QuoteLine]
    let priceLevel: PriceLevel
    let contextGeneration: Int
}

struct FleetPricingReviewView: View {
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.dismiss) private var dismiss
    let proposal: QuotePricingProposal
    let onAccept: () -> Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RowLine(title: proposal.customer.company ?? proposal.customer.name,
                            trailing: i18n.t(proposal.priceLevel.localizationKey))
                    Text(i18n.t("pricing.reviewDescription"))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(proposal.proposedLines.filter { $0.itemType == "SKU" }) { line in
                    Section(line.description) {
                        if let old = proposal.originalLines.first(where: { $0.id == line.id }) {
                            RowLine(title: i18n.t("pricing.previousActual"), trailing: AppFormat.money(old.unitPrice))
                        }
                        RowLine(title: i18n.t("pricing.standard"), trailing: line.standardUnitPrice.map(AppFormat.money) ?? "—")
                        RowLine(title: i18n.t("pricing.actual"), trailing: AppFormat.money(line.unitPrice))
                        RowLine(title: i18n.t("pricing.source"), trailing: i18n.t("pricing.source.\(line.priceSource ?? "STANDARD")"))
                        RowLine(title: i18n.t("pricing.lineAmount"), trailing: AppFormat.money(line.lineTotal))
                    }
                }
            }
            .navigationTitle(i18n.t("pricing.reviewTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t("pricing.accept")) {
                        if onAccept() { dismiss() }
                    }
                }
            }
        }
    }
}
