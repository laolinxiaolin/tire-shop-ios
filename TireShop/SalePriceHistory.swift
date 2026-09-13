import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let customerSalePricesChanged = Notification.Name("customerSalePricesChanged")
}

struct SalePriceRequest: Hashable {
    let customerId: String?
    let skuIds: [String]

    init(customerId: String?, skuIds: [String]) {
        self.customerId = customerId?.nilIfBlank
        self.skuIds = Array(Set(skuIds.filter { !$0.isEmpty })).sorted()
    }
}

/// Prices belong to one customer and candidate set. Clear them before every
/// refresh, and ignore responses from superseded or cancelled requests.
@MainActor
final class SalePriceHistoryStore: ObservableObject {
    typealias Loader = (String, [String]) async throws -> [CustomerLastSalePrice]

    @Published private(set) var request = SalePriceRequest(customerId: nil, skuIds: [])
    @Published private(set) var isLoading = false
    @Published private(set) var hasError = false
    @Published private(set) var bySku: [String: CustomerLastSalePrice] = [:]

    private let loader: Loader
    private var generation = 0
    private var changeObserver: AnyCancellable?

    init(loader: @escaping Loader = { customerId, skuIds in
        try await CustomersAPI().lastSalePrices(customerId: customerId, skuIds: skuIds)
    }) {
        self.loader = loader
        changeObserver = NotificationCenter.default.publisher(for: .customerSalePricesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Hide the previous result immediately, including while the
                // refresh task waits for the main actor.
                self.generation += 1
                self.bySku = [:]
                let request = self.request
                let generation = self.generation
                self.isLoading = request.customerId != nil && !request.skuIds.isEmpty
                Task {
                    guard self.generation == generation else { return }
                    await self.load(request)
                }
            }
    }

    func price(for skuId: String, request: SalePriceRequest) -> CustomerLastSalePrice? {
        guard self.request == request, !isLoading, !hasError else { return nil }
        return bySku[skuId]
    }

    func load(_ request: SalePriceRequest) async {
        generation += 1
        let generation = generation
        self.request = request
        bySku = [:]
        hasError = false
        isLoading = false
        guard let customerId = request.customerId, !request.skuIds.isEmpty else { return }

        isLoading = true
        defer {
            if generation == self.generation { isLoading = false }
        }

        do {
            var prices: [String: CustomerLastSalePrice] = [:]
            // Bounded requests prevent oversized URLs when a catalog spans
            // many pages. Deduplication and ordering happen in the request.
            for offset in stride(from: 0, to: request.skuIds.count, by: 100) {
                try Task.checkCancellation()
                let ids = Array(request.skuIds[offset..<min(offset + 100, request.skuIds.count)])
                let batch = try await loader(customerId, ids)
                guard generation == self.generation else { return }
                for price in batch where ids.contains(price.skuId) {
                    guard let value = Double(price.effectiveUnitPrice), value.isFinite, value >= 0 else { continue }
                    prices[price.skuId] = price
                }
            }
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            bySku = prices
        } catch {
            guard generation == self.generation else { return }
            bySku = [:]
            hasError = !Task.isCancelled && !(error is CancellationError)
        }
    }
}

struct SalePriceHistoryStatusView: View {
    @EnvironmentObject private var i18n: I18nStore
    @ObservedObject var history: SalePriceHistoryStore
    let request: SalePriceRequest

    var body: some View {
        Group {
            if request.customerId == nil {
                Text(i18n.t("salePrice.pickCustomer"))
                    .foregroundStyle(Theme.muted)
            } else if !request.skuIds.isEmpty {
                if history.request == request && history.hasError {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(i18n.t("salePrice.error"))
                            .foregroundStyle(Theme.danger)
                        Button(i18n.t("common.retry")) {
                            Task { await history.load(request) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if history.request != request || history.isLoading {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView()
                        Text(i18n.t("salePrice.loading"))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .font(.caption)
    }
}

struct LastSalePriceChoice: View {
    @EnvironmentObject private var i18n: I18nStore
    let price: CustomerLastSalePrice
    var apply = false
    var disabled = false
    let onSelect: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button(i18n.t(apply ? "salePrice.useLast" : "salePrice.lastSold", [
                "price": AppFormat.money(price.effectiveUnitPrice)
            ])) {
                if let value = Double(price.effectiveUnitPrice), value.isFinite, value >= 0 {
                    onSelect(value)
                }
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
            Text(i18n.t("salePrice.historySource", [
                "ref": price.saleRef ?? price.saleId,
                "date": AppFormat.shortDate(price.soldAt)
            ]))
            .foregroundStyle(Theme.muted)
            if (Double(price.discount) ?? 0) > 0 {
                Text(i18n.t("salePrice.discounted"))
                    .foregroundStyle(Theme.muted)
            }
        }
        .font(.caption)
    }
}

struct SkuSalePriceChoices: View {
    @EnvironmentObject private var i18n: I18nStore
    let sku: TireSku
    @ObservedObject var history: SalePriceHistoryStore
    let request: SalePriceRequest
    var disabled = false
    let onSelect: (Double) -> Void

    private var retail: Double? { validPrice(sku.priceRetail) }
    private var wholesale: Double? { validPrice(sku.priceWholesale) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.sm) { catalogChoices }
                VStack(alignment: .leading, spacing: Theme.Space.sm) { catalogChoices }
            }
            if let previous = history.price(for: sku.id, request: request) {
                LastSalePriceChoice(price: previous, disabled: disabled, onSelect: onSelect)
            } else if request.customerId != nil, history.request == request,
                      !history.isLoading, !history.hasError {
                Text(i18n.t("salePrice.noHistory"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var catalogChoices: some View {
        Group {
            Button("\(i18n.t("sku.retail")) \(AppFormat.money(sku.priceRetail))") {
                if let retail { onSelect(retail) }
            }
            .disabled(disabled || retail == nil)

            Button(sku.priceWholesale.map { "\(i18n.t("sku.wholesale")) \(AppFormat.money($0))" }
                   ?? i18n.t("salePrice.wholesaleUnset")) {
                if let wholesale { onSelect(wholesale) }
            }
            .disabled(disabled || wholesale == nil)
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    private func validPrice(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
