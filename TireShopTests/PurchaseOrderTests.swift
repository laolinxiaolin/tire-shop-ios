import XCTest
@testable import TireShop

final class PurchaseOrderTests: XCTestCase {
    func testHistoricalPaymentAllowsUnknownMethod() throws {
        let json = """
        {"id":"payment","ref":"sp-1","method":null,"paidAt":"2026-10-06T12:00:00Z",
         "poAllocatedAmount":100,"allocations":[]}
        """
        let payment = try JSONDecoder().decode(PurchaseOrderPayment.self, from: Data(json.utf8))
        XCTAssertNil(payment.method)
        XCTAssertEqual(payment.poAllocatedAmount, 100)
    }

    func testSummaryKeepsAgreementCashAndPayablesSeparate() throws {
        let order = try PurchaseOrderFixtures.order()
        XCTAssertEqual(order.agreedGoodsAmount, 1000)
        XCTAssertEqual(order.summary.goodsRemaining, 700)
        XCTAssertEqual(order.summary.supplierPaid, 400)
        XCTAssertEqual(order.summary.activeSupplierPaid, 300)
        XCTAssertEqual(order.summary.cancelledSupplierPaid, 100)
        XCTAssertEqual(order.summary.openPayable, 120)
        XCTAssertEqual(order.summary.dueNow, 20)
        XCTAssertEqual(order.auditHistory?.first?.user?.fullName, "Buyer")
    }

    func testUnknownGoodsBalanceRemainsUnavailable() throws {
        let json = PurchaseOrderFixtures.json.replacingOccurrences(of: "\"goodsAmount\":1000", with: "\"goodsAmount\":null")
            .replacingOccurrences(of: "\"goodsRemaining\":700", with: "\"goodsRemaining\":null")
            .replacingOccurrences(of: "\"goodsAmountSource\":\"AGREEMENT\"", with: "\"goodsAmountSource\":\"INCOMPLETE\"")
        let order = try JSONDecoder().decode(PurchaseOrder.self, from: Data(json.utf8))
        XCTAssertNil(order.summary.goodsAmount)
        XCTAssertNil(order.summary.goodsRemaining)
        XCTAssertEqual(order.summary.goodsAmountSource, "INCOMPLETE")
    }

    func testMembershipReviewEncodesUnlinkedParentAsExplicitNull() throws {
        let input = PurchaseOrderMoveContainerInput(
            purchaseOrderId: "po-target", expectedPurchaseOrderId: nil, expectedVersion: 4, reason: "  Consolidate shipments  "
        )
        let json = try object(input)
        XCTAssertTrue(json["expectedPurchaseOrderId"] is NSNull)
        XCTAssertEqual(json["expectedVersion"] as? Int, 4)
        XCTAssertNil(json["expectedSourceVersion"])
        XCTAssertEqual(json["reason"] as? String, "Consolidate shipments")

        let linked = PurchaseOrderMoveContainerInput(
            purchaseOrderId: "po-target", expectedPurchaseOrderId: "po-source", expectedVersion: 4,
            expectedSourceVersion: 9, plannedContainerCount: 3, reason: "Consolidate shipments"
        )
        let linkedJSON = try object(linked)
        XCTAssertEqual(linkedJSON["expectedPurchaseOrderId"] as? String, "po-source")
        XCTAssertEqual(linkedJSON["expectedSourceVersion"] as? Int, 9)
        XCTAssertEqual(linkedJSON["plannedContainerCount"] as? Int, 3)
    }

    func testHeaderUpdatesCanClearNullableFields() throws {
        let json = try object(PurchaseOrderUpdateInput(
            expectedVersion: 5, supplierReference: nil, plannedContainerCount: 2,
            agreedGoodsAmount: nil, paymentTerms: nil, notes: nil
        ))
        for key in ["supplierReference", "agreedGoodsAmount", "paymentTerms", "notes"] {
            XCTAssertTrue(json[key] is NSNull, key)
        }
    }

    func testSparseParentReferencesAndOlderContainersRemainCompatible() throws {
        let incoming = try JSONDecoder().decode(PurchaseOrderReference.self, from: Data("{\"id\":\"po\",\"ref\":\"po-1\"}".utf8))
        XCTAssertNil(incoming.version)
        let legacy = """
        {"id":"cg","supplier":{"id":"supplier","name":"Factory"},"status":"DRAFT",
         "isDDP":false,"location":"MAIN","costSpread":"BY_QTY","costs":[],"createdAt":"2026-10-06T12:00:00Z"}
        """
        let container = try JSONDecoder().decode(ContainerListItem.self, from: Data(legacy.utf8))
        XCTAssertNil(container.purchaseOrderId)
        XCTAssertNil(container.purchaseOrder)
    }

    func testFrozenPaymentLineUsesDocumentParentReference() throws {
        let json = """
        {"id":"line","containerCostId":"bill","amount":100,"paidAmount":0,"billAmount":100,
         "category":"BALANCE_PAYMENT","companyRef":"cg-original","poReference":"supplier-contract",
         "purchaseOrderRef":"po-original","cost":{"amount":100,"amountPaid":0,"status":"DUE",
         "container":{"id":"cg","ref":"cg-original","purchaseOrder":{"id":"other","ref":"po-new"}}}}
        """
        let line = try JSONDecoder().decode(PaymentApplicationLine.self, from: Data(json.utf8))
        XCTAssertEqual(line.purchaseOrderRef, "po-original")
        XCTAssertEqual(line.companyRef, "cg-original")
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}

enum PurchaseOrderFixtures {
    static func order(id: String = "po", version: Int = 4) throws -> PurchaseOrder {
        try JSONDecoder().decode(PurchaseOrder.self, from: Data(json(id: id, version: version).utf8))
    }

    static var json: String { json(id: "po", version: 4) }

    static func json(id: String, version: Int) -> String {
        """
        {"id":"\(id)","ref":"po-261006001","supplierId":"supplier",
         "supplier":{"id":"supplier","name":"Factory","currency":"USD"},
         "supplierReference":"contract","plannedContainerCount":2,"agreedGoodsAmount":"1000.00",
         "version":\(version),"createdAt":"2026-10-06T12:00:00Z","updatedAt":"2026-10-06T12:00:00Z",
         "summary":{"status":"PARTIALLY_RECEIVED","plannedCount":2,"containerCount":2,"activeCount":1,
          "cancelledCount":1,"receivedCount":1,"unassignedCount":0,"totalQty":50,"receivedQty":50,
          "manifestedGoodsAmount":900,"goodsAmount":1000,"goodsAmountSource":"AGREEMENT","manifestComplete":true,
          "supplierPaid":400,"legacySupplierPaid":0,"activeSupplierPaid":300,"cancelledSupplierPaid":100,
          "goodsRemaining":700,"openPayable":120,"dueNow":20,"missingEtaCount":0,"lateCount":0},
         "containers":[],"attachments":[],"auditHistory":[{"id":"audit","action":"purchaseOrder.create",
          "entity":"PurchaseOrder","entityId":"\(id)","data":{"plannedContainerCount":2},
          "createdAt":"2026-10-06T12:00:00Z","user":{"id":"buyer","fullName":"Buyer"}}]}
        """
    }
}
