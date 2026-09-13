import XCTest
@testable import TireShop

final class SupplierCorrectionTests: XCTestCase {
    func testSupplierPaymentStatusIgnoresVoidedBillsAndFreight() {
        let costs = [
            PurchasePaymentCost(category: "BALANCE_PAYMENT", status: "PAID", amount: "100.00", amountPaid: "100.00"),
            PurchasePaymentCost(category: "DOWN_PAYMENT", status: "VOID", amount: "200.00", amountPaid: "0.00"),
            PurchasePaymentCost(category: "FREIGHT", status: "DUE", amount: "500.00", amountPaid: "0.00"),
        ]
        XCTAssertEqual(PurchasePaymentStatus.from(costs: costs), .paid)
        XCTAssertEqual(PurchasePaymentStatus.supplierCategories, ["DOWN_PAYMENT", "BALANCE_PAYMENT", "SUPPLIER_OTHER"])
    }

    func testSupplierPaymentStatusHandlesPartialAndCentTolerance() {
        XCTAssertEqual(PurchasePaymentStatus.from(costs: [
            PurchasePaymentCost(category: "SUPPLIER_OTHER", status: "DUE", amount: "10", amountPaid: "9.98"),
        ]), .partial)
        XCTAssertEqual(PurchasePaymentStatus.from(costs: [
            PurchasePaymentCost(category: "BALANCE_PAYMENT", status: "DUE", amount: "10", amountPaid: "9.99"),
        ]), .paid)
        XCTAssertEqual(PurchasePaymentStatus.from(costs: [PurchasePaymentCost]()), .unpaid)
    }

    func testSupplierContainerDecodesPaymentCostsFromNumericAndDecimalAmounts() throws {
        let json = """
        {"id":"po-1","ref":"PO-0001","status":"RECEIVED","location":"MAIN","isDDP":false,
         "createdAt":"2026-09-10T12:00:00Z","tireQty":100,"_count":{"lines":2,"costs":2},
         "costs":[{"category":"DOWN_PAYMENT","status":"PAID","amount":100.5,"amountPaid":100.5},
                  {"category":"BALANCE_PAYMENT","status":"DUE","amount":"200.50","amountPaid":"0"}]}
        """
        let row = try JSONDecoder().decode(SupplierContainerRow.self, from: Data(json.utf8))
        XCTAssertEqual(row.count?.lines, 2)
        XCTAssertEqual(row.costs?.first?.amount, "100.5")
        XCTAssertEqual(PurchasePaymentStatus.from(costs: try XCTUnwrap(row.costs)), .partial)
    }

    func testSupplierContainerWithoutCostsDoesNotClaimUnpaid() throws {
        let json = """
        {"id":"po-1","status":"ORDERED","location":"MAIN","isDDP":true,
         "createdAt":"2026-09-10T12:00:00Z","tireQty":10}
        """
        let row = try JSONDecoder().decode(SupplierContainerRow.self, from: Data(json.utf8))
        XCTAssertNil(row.costs)
    }

    func testCorrectionSubmissionCarriesReviewedIdentitiesAndToken() throws {
        let preview = try decodePreview()
        let body = try XCTUnwrap(preview.submission(containerId: "po-1", supplierId: "supplier-new", reason: "  Correct contract heading\n"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String]
        XCTAssertEqual(encoded, [
            "supplierId": "supplier-new",
            "expectedSupplierId": "supplier-old",
            "previewToken": "review-snapshot",
            "reason": "Correct contract heading",
        ])
        XCTAssertEqual(preview.affectedBills.first?.vendor, "Old payee")
        XCTAssertEqual(preview.newSupplier?.payeeVendorName, "New payee")
        XCTAssertEqual(preview.affectedTotal, 100.5)
    }

    func testCorrectionCannotSubmitAStaleSelectionOrInvalidReason() throws {
        let preview = try decodePreview()
        XCTAssertNil(preview.submission(containerId: "another-po", supplierId: "supplier-new", reason: "Correction"))
        XCTAssertNil(preview.submission(containerId: "po-1", supplierId: "another-supplier", reason: "Correction"))
        XCTAssertNil(preview.submission(containerId: "po-1", supplierId: "supplier-new", reason: " \n "))
        XCTAssertNil(preview.submission(containerId: "po-1", supplierId: "supplier-new", reason: String(repeating: "a", count: 1001)))
    }

    func testSupplierVendorCostsDecodeBillAndContainerReferences() throws {
        let json = """
        {"id":"cost-1","category":"BALANCE_PAYMENT","status":"DUE","amount":100,"amountPaid":0,
         "reference":null,"container":{"id":"po-1","ref":"PO-0001","reference":"SUPPLIER-INVOICE-42"},
         "createdAt":"2026-09-10T12:00:00Z"}
        """
        let cost = try JSONDecoder().decode(VendorRecentCost.self, from: Data(json.utf8))
        XCTAssertNil(cost.reference)
        XCTAssertEqual(cost.container?.reference, "SUPPLIER-INVOICE-42")
    }

    private func decodePreview() throws -> ContainerSupplierChangePreview {
        let json = """
        {"previewToken":"review-snapshot","containerId":"po-1","containerRef":"PO-0001","status":"RECEIVED",
         "oldSupplier":{"id":"supplier-old","name":"Old supplier"},
         "newSupplier":{"id":"supplier-new","name":"New supplier","payeeVendorId":"payee-new","payeeVendorName":"New payee"},
         "suppliers":[{"id":"supplier-new","name":"New supplier","payeeVendorId":"payee-new","payeeVendorName":"New payee"}],
         "affectedBills":[{"id":"cost-1","category":"BALANCE_PAYMENT","reference":"INV-1","description":null,
                           "amount":100.5,"amountPaid":0,"status":"DUE","vendorId":"payee-old","vendor":"Old payee"}],
         "affectedTotal":100.5}
        """
        return try JSONDecoder().decode(ContainerSupplierChangePreview.self, from: Data(json.utf8))
    }
}
