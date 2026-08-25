import XCTest
@testable import TireShop

/// Pins the client to the backend response contracts added after the last
/// parity point:
/// - #403: Best Sellers accepts a warehouse scope and echoes it back as
///   `warehouse` (null for the combined all-warehouse view).
/// - #406: `GET /sales` supports `summary=false` light mode, where the server
///   returns `total: null` and omits the financial `summary` entirely.
/// - #420: containers carry `balanceDueAt`, and a bill's due date is reschedulable
///   on its own after receipt.
/// - #421: commission payouts are numbered documents with a DRAFT/PAID/VOID
///   lifecycle, replacing the one-shot payout.
/// - #422: payment-application approval moved to the shared approvals queue, and
///   `GET /approvals/pending-count` now breaks its total down per queue.
final class BackendParityTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: XCTUnwrap(json.data(using: .utf8)))
    }

    private func encodeJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Manual payment overpayment

    func testCustomerManualPaymentCanCreateStoreCredit() {
        XCTAssertTrue(ManualPaymentOverpaymentPolicy.allowsOverpayment(
            customerId: "customer_1",
            storeCreditApplied: 0
        ))
        XCTAssertTrue(ManualPaymentOverpaymentPolicy.isOverpayment(
            totalApplied: 125,
            balance: 100
        ))
        XCTAssertEqual(ManualPaymentOverpaymentPolicy.amount(
            totalApplied: 125,
            balance: 100
        ), 25)
        XCTAssertEqual(ManualPaymentOverpaymentPolicy.appliedToInvoice(
            totalApplied: 125,
            balance: 100
        ), 100)
    }

    func testManualPaymentRejectsOverpaymentWithoutCustomer() {
        XCTAssertFalse(ManualPaymentOverpaymentPolicy.allowsOverpayment(
            customerId: nil,
            storeCreditApplied: 0
        ))
        XCTAssertFalse(ManualPaymentOverpaymentPolicy.allowsOverpayment(
            customerId: "  ",
            storeCreditApplied: 0
        ))
    }

    func testStoreCreditCannotFundAnOverpayment() {
        XCTAssertFalse(ManualPaymentOverpaymentPolicy.allowsOverpayment(
            customerId: "customer_1",
            storeCreditApplied: 10
        ))
    }

    func testReceivableQuickSplitCarriesExcessIntoReceiptSubmission() {
        let visibleApplications = [
            ReceivableApplication(invoiceId: "invoice_1", amount: 4_032),
            ReceivableApplication(invoiceId: "invoice_2", amount: 5_040),
        ]

        let excess = ReceivableOverpaymentPolicy.excess(
            received: 10_000,
            openBalance: 9_072
        )
        let submittedApplications = ReceivableOverpaymentPolicy.applicationsForSubmission(
            visibleApplications,
            excess: excess
        )

        XCTAssertEqual(excess, 928)
        XCTAssertEqual(submittedApplications, [
            ReceivableApplication(invoiceId: "invoice_1", amount: 4_032),
            ReceivableApplication(invoiceId: "invoice_2", amount: 5_968),
        ])
        XCTAssertEqual(submittedApplications.reduce(0) { $0 + $1.amount }, 10_000)
    }

    func testReceivableStoreCreditTenderCannotCreateStoreCredit() {
        XCTAssertFalse(ReceivableOverpaymentPolicy.allowsStoreCredit(
            excess: 928,
            paymentMethodAccountCode: "2400"
        ))
        XCTAssertTrue(ReceivableOverpaymentPolicy.allowsStoreCredit(
            excess: 928,
            paymentMethodAccountCode: "1010"
        ))
    }

    func testOverpaymentSafeguardsHaveEnglishAndChineseMessages() {
        let keys = [
            "payment.confirmOverpayment",
            "payment.confirmCustomerOverpayment",
            "payment.confirmSingleOverpayment",
            "payment.feeAppliesSummary",
            "payment.verifyCustomerOverpayment",
            "payment.verifyManualOverpayment",
            "payment.warningOverpayment",
        ]

        for key in keys {
            let english = I18nStore.messages[.en]?[key]
            let chinese = I18nStore.messages[.zh]?[key]
            XCTAssertNotNil(english, "Missing English localization for \(key)")
            XCTAssertNotNil(chinese, "Missing Chinese localization for \(key)")
            XCTAssertNotEqual(english, chinese, "Chinese localization should not fall back for \(key)")
        }

        XCTAssertEqual(
            I18nStore.messages[.zh]?["payment.storeCredit"],
            "客户预存余额"
        )
        XCTAssertFalse(
            I18nStore.messages[.zh]?.values.contains { $0.contains("店内信用") } == true,
            "Chinese copy should use the clearer customer prepaid-balance term"
        )
    }

    // MARK: - Sales list light mode (#406)

    func testSalesListDecodesFullMode() throws {
        let response: SalesListResponse = try decode(
            SalesListResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"count":0,"tireQty":0,"taxAmount":"0.00","grossProfit":"0.00","total":"0.00"}}
            """
        )
        XCTAssertEqual(response.total, 0)
        XCTAssertEqual(response.summary?.count, 0)
    }

    func testSalesListDecodesLightMode() throws {
        // summary=false: the server skips the whole-set count and the
        // financial aggregates, so total is null and summary is absent.
        let response: SalesListResponse = try decode(
            SalesListResponse.self,
            """
            {"items":[],"total":null,"page":1,"pageSize":50}
            """
        )
        XCTAssertNil(response.total)
        XCTAssertNil(response.summary)
    }

    // MARK: - Best Sellers warehouse scope (#403)

    func testBestSellersDecodesWarehouseScope() throws {
        let response: BestSellersResponse = try decode(
            BestSellersResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"skuCount":0,"qty":0,"saleCount":0,"revenue":"0.00","grossProfit":"0.00"},
             "period":{"months":3,"from":"2026-05-08","to":"2026-08-07","timezone":"America/New_York"},
             "warehouse":{"code":"MAIN","name":"Main Warehouse"}}
            """
        )
        XCTAssertEqual(response.warehouse?.code, "MAIN")
        XCTAssertEqual(response.warehouse?.name, "Main Warehouse")
    }

    func testBestSellersDecodesCombinedView() throws {
        // Omitted location → warehouse: null. An older server omits the key
        // entirely, which must decode the same way.
        let response: BestSellersResponse = try decode(
            BestSellersResponse.self,
            """
            {"items":[],"total":0,"page":1,"pageSize":50,
             "summary":{"skuCount":0,"qty":0,"saleCount":0,"revenue":"0.00","grossProfit":"0.00"},
             "period":{"months":null,"from":null,"to":"2026-08-07","timezone":"America/New_York"},
             "warehouse":null}
            """
        )
        XCTAssertNil(response.warehouse)
    }

    // MARK: - Sales list continuation paging (#406, review P1/P2)

    func testDefaultOrderContinuationUsesCursor() {
        let cursor = SalesCursor(before: "2026-08-07T12:00:00Z", beforeId: "sale-9")
        let request = SalesContinuationRequest(
            sortBy: nil,
            sortOrder: nil,
            page: 3,
            cursor: cursor
        )
        // Keyset mode: the cursor rides alongside the offset page (the
        // compatibility contract), and no sort is sent (the server's cursor
        // ordering is fixed at createdAt desc, id desc).
        XCTAssertEqual(request.page, 3)
        XCTAssertEqual(request.before, cursor.before)
        XCTAssertEqual(request.beforeId, cursor.beforeId)
        XCTAssertNil(request.sortBy)
        XCTAssertNil(request.sortOrder)
    }

    func testCustomSortContinuationPagesByOffset() {
        let cursor = SalesCursor(before: "2026-08-07T12:00:00Z", beforeId: "sale-9")
        let request = SalesContinuationRequest(
            sortBy: "total",
            sortOrder: "desc",
            page: 2,
            cursor: cursor
        )
        // A keyset continuation would be reordered to (createdAt desc, id
        // desc), silently dropping the sort — so custom sorts must page by
        // offset with no cursor.
        XCTAssertEqual(request.page, 2)
        XCTAssertNil(request.before)
        XCTAssertNil(request.beforeId)
        XCTAssertEqual(request.sortBy, "total")
        XCTAssertEqual(request.sortOrder, "desc")
    }

    func testDefaultOrderWithoutCursorPagesByOffset() {
        // Defensive path: no cursor available but hasMore said there is more;
        // the request must still advance by page rather than stall.
        let request = SalesContinuationRequest(
            sortBy: nil,
            sortOrder: nil,
            page: 4,
            cursor: nil
        )
        XCTAssertEqual(request.page, 4)
        XCTAssertNil(request.before)
        XCTAssertNil(request.beforeId)
        XCTAssertNil(request.sortBy)
    }

    // MARK: - Supplier profiles & vendor pagination (#407)

    func testVendorDetailDecodesWithoutRecentLists() throws {
        // #407 removed the recentCosts/recentExpenses/recentRefunds arrays
        // from GET /api/vendors/:id — the client must decode the summary-only
        // response (the old non-optional fields would have crashed decode).
        let detail: VendorDetail = try decode(
            VendorDetail.self,
            """
            {"id":"v_1","name":"Trucking Co","category":"TRUCKING","contactName":null,
             "phone":null,"email":null,"address":null,"notes":null,"active":true,
             "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
             "summary":{"openAP":100,"paidOut":500,"refunds":50,"netSpend":450}}
            """
        )
        XCTAssertEqual(detail.summary.openAP, 100)
        XCTAssertEqual(detail.summary.netSpend, 450)
    }

    func testSupplierDetailDecodesSummary() throws {
        let detail: SupplierDetail = try decode(
            SupplierDetail.self,
            """
            {"id":"sup_1","name":"Linglong","contactName":null,"phone":null,"email":null,
             "country":"China","address":null,"currency":"USD","defaultDDP":true,"notes":null,
             "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
             "summary":{"supplierOpenAP":1000,"supplierBilled":5000,"supplierPaid":4000,
              "otherOpenAP":200,"otherBilled":800,"otherPaid":600,"landedValue":12000,
              "tiresReceived":400,"containerCount":3,"openContainerCount":1,
              "receivedContainerCount":2,"firstOrderAt":"2025-06-01T00:00:00.000Z",
              "lastOrderAt":"2026-07-01T00:00:00.000Z"}}
            """
        )
        XCTAssertEqual(detail.summary.supplierOpenAP, 1000)
        XCTAssertEqual(detail.summary.receivedContainerCount, 2)
        XCTAssertEqual(detail.summary.firstOrderAt, "2025-06-01T00:00:00.000Z")
        XCTAssertEqual(detail.defaultDDP, true)
    }

    func testSupplierContainerRowDecodes() throws {
        let row: SupplierContainerRow = try decode(
            SupplierContainerRow.self,
            """
            {"id":"c_1","ref":"CN-2026-001","reference":"PO-100","status":"RECEIVED",
             "bolNumber":"BOL-1","location":"MAIN","isDDP":true,
             "orderedAt":"2026-01-01T00:00:00.000Z","etaAt":null,"arrivedAt":null,
             "receivedAt":"2026-02-01T00:00:00.000Z","createdAt":"2026-01-01T00:00:00.000Z",
             "tireQty":120,"_count":{"lines":3,"costs":2}}
            """
        )
        XCTAssertEqual(row.status, "RECEIVED")
        XCTAssertEqual(row.tireQty, 120)
        XCTAssertEqual(row.count?.lines, 3)
        XCTAssertEqual(row.count?.costs, 2)
    }

    func testSupplierCostRowDecodes() throws {
        let row: SupplierCostRow = try decode(
            SupplierCostRow.self,
            """
            {"id":"cost_1","category":"BALANCE_PAYMENT","status":"DUE",
             "description":"Balance","amount":5000,"amountPaid":1000,
             "vendor":null,"vendorId":null,"dueAt":"2026-03-01T00:00:00.000Z",
             "paidAt":null,"reference":"REF-1","createdAt":"2026-01-01T00:00:00.000Z",
             "container":{"id":"c_1","ref":"CN-2026-001"}}
            """
        )
        XCTAssertEqual(row.amount, 5000)
        XCTAssertEqual(row.amountPaid, 1000)
        XCTAssertEqual(row.container?.ref, "CN-2026-001")
    }

    func testSupplierCostRowDecodesWithoutContainer() throws {
        // Transfer-freight bills are ContainerCosts with transferId set, so
        // the supplier-scoped list can still surface them with container null.
        let row: SupplierCostRow = try decode(
            SupplierCostRow.self,
            """
            {"id":"cost_2","category":"FREIGHT","status":"PAID",
             "description":null,"amount":300,"amountPaid":300,
             "vendor":"Trucking Co","vendorId":"v_1","dueAt":null,
             "paidAt":"2026-01-15T00:00:00.000Z","reference":null,
             "createdAt":"2026-01-01T00:00:00.000Z","container":null}
            """
        )
        XCTAssertNil(row.container)
        XCTAssertEqual(row.vendor, "Trucking Co")
    }

    func testSupplierPaymentRowDecodes() throws {
        let row: SupplierPaymentRow = try decode(
            SupplierPaymentRow.self,
            """
            {"id":"pmt_1","ref":"pmt-2026-0001","vendor":"Linglong","total":5000,
             "appliedToSupplier":3000,"status":"POSTED","reference":null,"paidBy":"Alice",
             "paidAt":"2026-03-01T00:00:00.000Z",
             "fundingAccount":{"code":"1020","name":"Bank Account"},
             "lines":[{"id":"l_1","amount":3000,"containerCost":{"id":"cost_1",
               "category":"BALANCE_PAYMENT","container":{"id":"c_1","ref":"CN-2026-001"}}}]}
            """
        )
        XCTAssertEqual(row.appliedToSupplier, 3000)
        XCTAssertEqual(row.fundingAccount?.code, "1020")
        XCTAssertEqual(row.lines.first?.containerCost.category, "BALANCE_PAYMENT")
        XCTAssertEqual(row.lines.first?.containerCost.container?.ref, "CN-2026-001")
    }

    func testSupplierReturnRowDecodes() throws {
        let row: SupplierReturnRow = try decode(
            SupplierReturnRow.self,
            """
            {"id":"ret_1","ref":"rt-2026-0001","type":"WARRANTY","status":"POSTED",
             "refundTotal":250,"warrantyDisposition":"SUPPLIER_CLAIM",
             "createdAt":"2026-04-01T00:00:00.000Z","postedAt":"2026-04-02T00:00:00.000Z",
             "sale":{"id":"s_1","ref":"s-2026-0100"},"_count":{"lines":2}}
            """
        )
        XCTAssertEqual(row.refundTotal, 250)
        XCTAssertEqual(row.sale.ref, "s-2026-0100")
        XCTAssertEqual(row.count?.lines, 2)
    }

    func testSupplierCostsPageDecodesPagedEnvelope() throws {
        let page: Paged<SupplierCostRow> = try decode(
            Paged<SupplierCostRow>.self,
            """
            {"items":[{"id":"cost_1","category":"BALANCE_PAYMENT","status":"DUE",
               "description":null,"amount":5000,"amountPaid":1000,"vendor":null,
               "vendorId":null,"dueAt":null,"paidAt":null,"reference":null,
               "createdAt":"2026-01-01T00:00:00.000Z","container":null}],
             "total":1,"page":1,"pageSize":25}
            """
        )
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.pageSize, 25)
        XCTAssertEqual(page.items.count, 1)
    }

    // MARK: - Payment applications and bank details (#409–#412, #418)

    func testCashTransferDecodesReferenceAndDepositUsage() throws {
        let transfer: CashTransfer = try decode(
            CashTransfer.self,
            """
            {"id":"tr_1","ref":"tf-2026-0001",
             "fromAccount":{"code":"1020","name":"Operating Bank"},
             "toAccount":{"code":"1010","name":"Cash on Hand"},
             "amount":"1000.00","fee":"5.00","note":null,"reference":"WIRE-88",
             "reversedAt":null,"createdAt":"2026-08-15T12:00:00.000Z",
             "_count":{"depositChecks":2}}
            """
        )
        XCTAssertEqual(transfer.ref, "tf-2026-0001")
        XCTAssertEqual(transfer.reference, "WIRE-88")
        XCTAssertEqual(transfer.counts.depositChecks, 2)
    }

    func testPaymentApplicationUpdateEncodesExplicitClears() throws {
        let body = PaymentApplicationUpdateInput(
            bankAccountId: "bank_1",
            currency: "USD",
            purpose: "GOODS",
            requestedAt: "2026-08-15",
            plannedPayAt: nil,
            note: nil,
            lines: [PaymentApplicationLineInput(containerCostId: "cost_1", amount: 250, note: nil)]
        )
        let json = try encodeJSONObject(body)
        XCTAssertTrue(json["plannedPayAt"] is NSNull)
        XCTAssertTrue(json["note"] is NSNull)
    }

    func testVendorBankPatchClearsOptionalFieldsWithoutReplacingAccountNumber() throws {
        let body = VendorBankAccountPatchInput(
            label: nil,
            beneficiaryName: "Road Tire Supply",
            bankName: "Example Bank",
            accountNumber: nil,
            bankCountry: "US",
            currency: "USD",
            routingNumber: nil,
            swift: nil,
            bankAddress: nil,
            intermediaryBankName: nil,
            intermediarySwift: nil,
            intermediaryAccount: nil,
            financeContactName: nil,
            financeContactEmail: nil,
            isDefault: true,
            note: nil
        )
        let json = try encodeJSONObject(body)
        XCTAssertTrue(json["label"] is NSNull)
        XCTAssertTrue(json["routingNumber"] is NSNull)
        XCTAssertTrue(json["note"] is NSNull)
        XCTAssertFalse(json.keys.contains("accountNumber"))
        XCTAssertFalse(json.keys.contains("intermediaryAccount"))
    }

    func testPaymentApplicationDetailDecodesRollingDeploymentOptionals() throws {
        let application: PaymentApplicationDetail = try decode(
            PaymentApplicationDetail.self,
            """
            {"id":"app_1","ref":"pa-260819001","status":"APPROVED",
             "vendor":{"id":"v_1","name":"Road Tire","email":null},
             "vendorKey":"road tire","payerName":"Tire Force","currency":"USD","purpose":"GOODS",
             "requestedAt":"2026-08-19T04:00:00.000Z","plannedPayAt":null,"note":null,
             "totalAmount":250,"paidAmount":0,"remaining":250,
             "requestedBy":{"id":"u_1","fullName":"Alex Chen"},
             "submittedAt":"2026-08-19T12:00:00.000Z","approvedBy":null,"decidedAt":null,
             "decisionNote":null,"remainingCancelledAt":null,"remainingCancelledBy":null,
             "voidedAt":null,"voidedBy":null,
             "bank":{"accountId":"bank_1","snapshotAt":"2026-08-19T12:00:00.000Z",
                     "beneficiaryName":"Road Tire","bankName":"Example Bank",
                     "accountLast4":"7403","accountMasked":"****7403","bankCountry":"US",
                     "routingNumber":null,"swift":null,"bankAddress":null,"intermediary":null,
                     "intermediaryAccountLast4":null,"intermediaryAccountMasked":null,
                     "financeEmail":null},
             "lines":[],"approvals":[],
             "attachments":[{"id":"att_1","kind":"BILL","filename":"bill.pdf",
                             "mimeType":"application/pdf","sizeBytes":42,"note":null,
                             "supplierPaymentId":null,"createdAt":"2026-08-19T12:00:00.000Z"}],
             "emails":[]}
            """
        )
        XCTAssertEqual(application.bank.accountMasked, "****7403")
        XCTAssertNil(application.bank.accountNumber)
        XCTAssertNil(application.attachments.first?.sourceContainerAttachmentId)
        XCTAssertNil(application.supplierPayments)
    }

    func testPaymentApplicationSubmissionIdentitySurvivesRecreationUntilExplicitlyCleared() throws {
        let suiteName = "PaymentApplicationSubmissionIdentityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = PaymentApplicationSubmissionIdentity(
            kind: "payment",
            applicationID: "app_1",
            userID: "user_1",
            defaults: defaults
        )
        let original = PaymentApplicationLineInput(containerCostId: "cost_1", amount: 25, note: nil)
        let originalKey = try first.key(for: original)

        let recreated = PaymentApplicationSubmissionIdentity(
            kind: "payment",
            applicationID: "app_1",
            userID: "user_1",
            defaults: defaults
        )
        XCTAssertEqual(try recreated.key(for: original), originalKey)

        let changed = PaymentApplicationLineInput(containerCostId: "cost_1", amount: 30, note: nil)
        let changedKey = try recreated.key(for: changed)
        XCTAssertEqual(changedKey, originalKey)

        recreated.clear()
        XCTAssertNotEqual(try recreated.key(for: changed), changedKey)
    }

    // MARK: - Purchasing bill due dates (#420)

    func testContainerDecodesBalanceDueDate() throws {
        let container: Container = try decode(
            Container.self,
            """
            {"id":"ct_1","ref":"c-2026-0001","reference":"PO-9","bolNumber":null,
             "supplierId":"sp_1","supplier":{"id":"sp_1","name":"Road Tire","country":"US"},
             "status":"RECEIVED","isDDP":false,"location":"MAIN","costSpread":"VALUE",
             "orderedAt":null,"etaAt":null,"arrivedAt":null,
             "balanceDueAt":"2026-09-30T00:00:00.000Z","receivedAt":"2026-08-15T10:00:00.000Z",
             "notes":null,"lines":[],"costs":[],"attachments":[],
             "createdAt":"2026-08-01T10:00:00.000Z","updatedAt":null}
            """
        )
        XCTAssertEqual(container.balanceDueAt, "2026-09-30T00:00:00.000Z")
    }

    func testContainerCostDueDatePatchSendsOnlyDueDate() throws {
        let json = try encodeJSONObject(ContainerCostDueDateInput(dueAt: "2026-09-30"))
        XCTAssertEqual(json.keys.sorted(), ["dueAt"])
        XCTAssertEqual(json["dueAt"] as? String, "2026-09-30")
    }

    func testContainerCostDueDatePatchClearsWithExplicitNull() throws {
        let json = try encodeJSONObject(ContainerCostDueDateInput(dueAt: nil))
        XCTAssertEqual(json.keys.sorted(), ["dueAt"])
        XCTAssertTrue(json["dueAt"] is NSNull)
    }

    // MARK: - Numbered commission payouts (#421)

    func testCommissionPayoutListRowDecodes() throws {
        let payout: CommissionPayout = try decode(
            CommissionPayout.self,
            """
            {"id":"cp_1","ref":"cp-260818001","status":"DRAFT","amount":1250.5,
             "entryCount":4,"periodFrom":"2026-08-01T00:00:00.000Z",
             "periodTo":"2026-08-15T00:00:00.000Z",
             "paymentMethod":{"id":"pm_1","name":"Cash"},
             "paidAt":null,"voidedAt":null,"voidReason":null,
             "createdAt":"2026-08-18T09:00:00.000Z","updatedAt":"2026-08-18T09:00:00.000Z"}
            """
        )
        XCTAssertEqual(payout.ref, "cp-260818001")
        XCTAssertEqual(payout.status, "DRAFT")
        XCTAssertEqual(payout.entryCount, 4)
        // The list endpoint carries neither of these; only the document does.
        XCTAssertNil(payout.entries)
        XCTAssertNil(payout.fundingAccount)
    }

    func testCommissionPayoutDetailDecodesLinesAndFundingAccount() throws {
        let payout: CommissionPayout = try decode(
            CommissionPayout.self,
            """
            {"id":"cp_1","ref":"cp-260818001","status":"PAID","amount":100,
             "entryCount":1,"periodFrom":null,"periodTo":null,
             "paymentMethod":{"id":"pm_1","name":"Cash"},
             "fundingAccount":{"id":"ac_1","code":"1010","name":"Cash on Hand"},
             "employee":{"id":"em_1","fullName":"Sam Rivera"},
             "entries":[{"id":"ce_1","employeeId":"em_1","saleId":"sl_1","basis":"PROFIT",
                         "basisAmount":400,"rate":0.25,"amount":100,"status":"PAID",
                         "note":null,"payoutId":"cp_1","paidAt":"2026-08-18T09:05:00.000Z",
                         "createdAt":"2026-08-10T12:00:00.000Z",
                         "sale":{"id":"sl_1","ref":"s-2026-0007","total":900}}],
             "paidAt":"2026-08-18T09:05:00.000Z","voidedAt":null,"voidReason":null,
             "createdAt":"2026-08-18T09:00:00.000Z","updatedAt":"2026-08-18T09:05:00.000Z"}
            """
        )
        XCTAssertEqual(payout.fundingAccount?.code, "1010")
        XCTAssertEqual(payout.entries?.count, 1)
        XCTAssertEqual(payout.entries?.first?.sale?.ref, "s-2026-0007")
    }

    func testCommissionPayoutPreviewDecodesSalesAndRollovers() throws {
        let preview: CommissionPayoutPreview = try decode(
            CommissionPayoutPreview.self,
            """
            {"sales":[{"id":"ce_1","employeeId":"em_1","saleId":"sl_1","basis":"PROFIT",
                       "basisAmount":400,"rate":0.25,"amount":100,"status":"ACCRUED",
                       "note":null,"payoutId":null,"paidAt":null,
                       "createdAt":"2026-08-10T12:00:00.000Z","sale":null}],
             "rollovers":[{"id":"ce_2","employeeId":"em_1","saleId":null,"basis":"PROFIT",
                           "basisAmount":0,"rate":0,"amount":-25,"status":"ACCRUED",
                           "note":"Rollover","payoutId":null,"paidAt":null,
                           "createdAt":"2026-08-01T12:00:00.000Z","sale":null}],
             "rolloverTotal":-25}
            """
        )
        XCTAssertEqual(preview.sales.count, 1)
        XCTAssertEqual(preview.rolloverTotal, -25)
        // A rollover has no sale, which is what keeps it out of the selectable list.
        XCTAssertNil(preview.rollovers.first?.saleId)
    }

    func testCommissionPayoutCreateSendsTheServersFieldNames() throws {
        let json = try encodeJSONObject(
            CommissionPayoutCreateInput(
                entryIds: ["ce_1", "ce_2"],
                paymentMethodId: "pm_1",
                expectedAmount: 75,
                from: "2026-08-01",
                to: "2026-08-15"
            )
        )
        XCTAssertEqual(
            json.keys.sorted(),
            ["entryIds", "expectedAmount", "from", "paymentMethodId", "to"]
        )
        XCTAssertEqual(json["expectedAmount"] as? Double, 75)
    }

    func testVoidedPayoutDecodesAsImmediateAndApprovalAlike() throws {
        let immediate: ImmediateOrApproval<CommissionPayout> = try decode(
            ImmediateOrApproval<CommissionPayout>.self,
            """
            {"id":"cp_1","ref":"cp-260818001","status":"VOID","amount":100,"entryCount":1,
             "periodFrom":null,"periodTo":null,"paymentMethod":null,
             "paidAt":null,"voidedAt":"2026-08-18T10:00:00.000Z","voidReason":"Wrong period",
             "createdAt":"2026-08-18T09:00:00.000Z","updatedAt":"2026-08-18T10:00:00.000Z"}
            """
        )
        guard case .immediate(let payout) = immediate else {
            return XCTFail("Expected the payout document")
        }
        XCTAssertEqual(payout.voidReason, "Wrong period")

        let queued: ImmediateOrApproval<CommissionPayout> = try decode(
            ImmediateOrApproval<CommissionPayout>.self,
            """
            {"approvalRequest":{"id":"ar_1"}}
            """
        )
        guard case .approval(let request) = queued else {
            return XCTFail("Expected an approval request")
        }
        XCTAssertEqual(request.id, "ar_1")
    }

    // MARK: - Approval queue counts (#422)

    func testPendingCountBreaksTheTotalDownPerQueue() throws {
        let counts: ApprovalPendingCount = try decode(
            ApprovalPendingCount.self,
            """
            {"count":7,"requests":5,"paymentApplications":2}
            """
        )
        // `count` sums every queue, so a screen rendering only one of them has
        // to badge off that queue's own field.
        XCTAssertEqual(counts.count, 7)
        XCTAssertEqual(counts.requests, 5)
        XCTAssertEqual(counts.paymentApplications, 2)
    }
}
