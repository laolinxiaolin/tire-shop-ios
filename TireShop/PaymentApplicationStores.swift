import Foundation
import SwiftUI

struct PaymentApplicationListFilter: Equatable {
    let view: String
    let query: String?
    let status: String?
}

@MainActor
final class PaymentApplicationsListStore: ObservableObject {
    typealias Loader = (PaymentApplicationListFilter, Int, Int) async throws -> Paged<PaymentApplicationRow>

    @Published private(set) var data: Paged<PaymentApplicationRow>?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    private var filter: PaymentApplicationListFilter?
    private var requestID = 0
    private var retryPage = 1
    private let pageSize: Int
    private let loader: Loader

    var page: Int { data?.page ?? 1 }

    init(pageSize: Int = 30, loader: @escaping Loader = { filter, page, size in
        try await PaymentApplicationsAPI().list(view: filter.view, q: filter.query,
            status: filter.status, page: page, pageSize: size)
    }) {
        self.pageSize = pageSize
        self.loader = loader
    }

    func load(filter: PaymentApplicationListFilter, page requestedPage: Int) async {
        requestID += 1
        let request = requestID
        if self.filter != filter { data = nil }
        self.filter = filter
        retryPage = max(1, requestedPage)
        let page = retryPage
        loading = true
        errorMessage = nil
        defer { if request == requestID { loading = false } }
        do {
            let result = try await loader(filter, page, pageSize)
            try Task.checkCancellation()
            guard request == requestID else { return }
            // The displayed page changes only when its rows have arrived.
            data = result
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        guard !loading, let filter else { return }
        await load(filter: filter, page: retryPage)
    }

    func invalidate() {
        requestID += 1
        loading = false
    }
}

/// Bills belong to a payee; bank options belong to a payee and a currency.
/// Invalidate those contexts synchronously before starting their requests so
/// the form can never submit selections from a previous payee or currency.
@MainActor
final class PaymentApplicationResourcesStore: ObservableObject {
    struct BillsRequest: Equatable {
        let id = UUID()
        let vendorId: String
    }

    struct BanksRequest: Equatable {
        let id = UUID()
        let vendorId: String
        let currency: String
    }

    struct Request {
        let bills: BillsRequest?
        let banks: BanksRequest?
    }

    typealias BillsLoader = (String) async throws -> [PaymentApplicationOpenBill]
    typealias BanksLoader = (String, String) async throws -> [PaymentApplicationBankOption]

    @Published private(set) var bills: [PaymentApplicationOpenBill] = []
    @Published private(set) var bankOptions: [PaymentApplicationBankOption] = []
    @Published var bankAccountId = ""
    @Published private(set) var selectedBillIDs = Set<String>()
    @Published var amounts: [String: String] = [:]
    @Published var lineNotes: [String: String] = [:]
    @Published private(set) var billsLoading = false
    @Published private(set) var banksLoading = false
    @Published private(set) var billsError: String?
    @Published private(set) var banksError: String?

    private var vendorId = ""
    private var currency = ""
    private var billsLoaded = false
    private var banksLoaded = false
    private var billsRequest: BillsRequest?
    private var banksRequest: BanksRequest?
    private let billsLoader: BillsLoader
    private let banksLoader: BanksLoader

    var errorMessage: String? { billsError ?? banksError }

    init(billsLoader: @escaping BillsLoader = { try await PaymentApplicationsAPI().openBills(vendorId: $0) },
         banksLoader: @escaping BanksLoader = { try await PaymentApplicationsAPI().bankOptions(vendorId: $0, currency: $1) }) {
        self.billsLoader = billsLoader
        self.banksLoader = banksLoader
    }

    func prepare(vendorId: String, currency: String) -> Request {
        let currency = currency.uppercased()
        let vendorChanged = self.vendorId != vendorId
        let bankContextChanged = vendorChanged || self.currency != currency
        self.vendorId = vendorId
        self.currency = currency

        if vendorChanged || vendorId.isEmpty {
            billsRequest = nil
            bills = []
            billsLoaded = false
            billsLoading = false
            billsError = nil
            selectedBillIDs = []
            amounts = [:]
            lineNotes = [:]
        }
        if bankContextChanged || vendorId.isEmpty {
            banksRequest = nil
            bankOptions = []
            bankAccountId = ""
            banksLoaded = false
            banksLoading = false
            banksError = nil
        }
        guard !vendorId.isEmpty else { return Request(bills: nil, banks: nil) }

        var nextBills: BillsRequest?
        if !billsLoaded && billsRequest == nil {
            nextBills = BillsRequest(vendorId: vendorId)
            billsRequest = nextBills
            billsLoading = true
            billsError = nil
        }
        var nextBanks: BanksRequest?
        if !banksLoaded && banksRequest == nil {
            nextBanks = BanksRequest(vendorId: vendorId, currency: currency)
            banksRequest = nextBanks
            banksLoading = true
            banksError = nil
        }
        return Request(bills: nextBills, banks: nextBanks)
    }

    func load(_ request: Request) async {
        async let bills: Void = loadBills(request.bills)
        async let banks: Void = loadBanks(request.banks)
        _ = await (bills, banks)
    }

    func seed(vendorId: String, currency: String, bills: [PaymentApplicationOpenBill],
              bankOptions: [PaymentApplicationBankOption], preferredBankId: String?,
              selectedBillIDs: Set<String>, amounts: [String: String], lineNotes: [String: String]) {
        invalidate()
        self.vendorId = vendorId
        self.currency = currency.uppercased()
        self.bills = bills.filter { belongsToVendor($0, vendorId: vendorId) }
        self.bankOptions = bankOptions.filter { $0.currency.uppercased() == self.currency }
        billsLoaded = true
        banksLoaded = true
        billsError = nil
        banksError = nil
        self.selectedBillIDs = selectedBillIDs.intersection(Set(self.bills.map(\.id)))
        self.amounts = amounts
        self.lineNotes = lineNotes
        bankAccountId = self.bankOptions.first(where: { $0.id == preferredBankId })?.id
            ?? self.bankOptions.first(where: \.isDefault)?.id ?? self.bankOptions.first?.id ?? ""
    }

    func canSelectBills(vendorId: String) -> Bool {
        !vendorId.isEmpty && self.vendorId == vendorId && billsLoaded && !billsLoading
    }

    func canSelectBank(vendorId: String, currency: String) -> Bool {
        !vendorId.isEmpty && self.vendorId == vendorId && self.currency == currency.uppercased()
            && banksLoaded && !banksLoading
    }

    func ownsSelections(vendorId: String, currency: String) -> Bool {
        canSelectBills(vendorId: vendorId) && canSelectBank(vendorId: vendorId, currency: currency)
            && bankOptions.contains(where: { $0.id == bankAccountId })
            && !selectedBillIDs.isEmpty
            && selectedBillIDs.allSatisfy { id in
                bills.contains { $0.id == id && belongsToVendor($0, vendorId: vendorId) }
            }
    }

    func toggle(_ bill: PaymentApplicationOpenBill, selected: Bool) {
        guard canSelectBills(vendorId: vendorId),
              bills.contains(where: { $0.id == bill.id && belongsToVendor($0, vendorId: vendorId) }) else { return }
        if selected {
            selectedBillIDs.insert(bill.id)
            if amounts[bill.id]?.nilIfBlank == nil {
                amounts[bill.id] = String(format: "%.2f", bill.applicable)
            }
        } else {
            selectedBillIDs.remove(bill.id)
        }
    }

    func invalidate() {
        billsRequest = nil
        banksRequest = nil
        billsLoading = false
        banksLoading = false
        billsLoaded = false
        banksLoaded = false
    }

    private func belongsToVendor(_ bill: PaymentApplicationOpenBill, vendorId: String) -> Bool {
        bill.vendorId == nil || bill.vendorId == vendorId
    }

    private func loadBills(_ request: BillsRequest?) async {
        guard let request, request == billsRequest else { return }
        defer {
            if request == billsRequest { billsLoading = false; billsRequest = nil }
        }
        do {
            let result = try await billsLoader(request.vendorId)
            try Task.checkCancellation()
            guard request == billsRequest else { return }
            bills = result.filter { belongsToVendor($0, vendorId: request.vendorId) }
            billsLoaded = true
        } catch {
            guard request == billsRequest, !Task.isCancelled else { return }
            billsError = error.localizedDescription
        }
    }

    private func loadBanks(_ request: BanksRequest?) async {
        guard let request, request == banksRequest else { return }
        defer {
            if request == banksRequest { banksLoading = false; banksRequest = nil }
        }
        do {
            let result = try await banksLoader(request.vendorId, request.currency)
            try Task.checkCancellation()
            guard request == banksRequest else { return }
            bankOptions = result.filter { $0.currency.uppercased() == request.currency }
            bankAccountId = bankOptions.first(where: \.isDefault)?.id ?? bankOptions.first?.id ?? ""
            banksLoaded = true
        } catch {
            guard request == banksRequest, !Task.isCancelled else { return }
            banksError = error.localizedDescription
        }
    }
}
