import XCTest
@testable import TireShop

final class CheckAPITests: XCTestCase {
    func testCollectionInputsSendDateOnlyWhenProvided() throws {
        let payment = PaymentRecordInput(paymentMethodId: "check", amount: 125, reference: "1234", note: nil, plannedDepositDate: "2026-09-14")
        XCTAssertEqual(try object(payment)["plannedDepositDate"] as? String, "2026-09-14")
        let cash = PaymentRecordInput(paymentMethodId: "cash", amount: 125, reference: nil, note: nil)
        XCTAssertNil(try object(cash)["plannedDepositDate"])

        let receipt = ReceivablesPayInput(customerId: "customer", paymentMethodId: "check", applications: [
            ReceivableApplication(invoiceId: "invoice-1", amount: 50),
            ReceivableApplication(invoiceId: "invoice-2", amount: 75)
        ], reference: "1234", note: nil, plannedDepositDate: "2026-09-14")
        XCTAssertEqual(try object(receipt)["plannedDepositDate"] as? String, "2026-09-14")
        let exchange = PostReturnInput.NetPayment(paymentMethodId: "check", amount: 25, reference: "1235", note: nil, plannedDepositDate: "2026-09-15")
        XCTAssertEqual(try object(exchange)["plannedDepositDate"] as? String, "2026-09-15")
    }

    func testHistoricalReportRetainsIdentityAfterPaymentDeletion() throws {
        let report = try JSONDecoder().decode(UndepositedCheckReport.self, from: Data(CheckStubProtocol.reportJSON.utf8))
        let check = try XCTUnwrap(report.items.first)
        XCTAssertEqual(check.id, "permanent-check-1")
        XCTAssertNil(check.paymentId)
        XCTAssertNil(check.customerName)
        XCTAssertNil(check.methodName)
        XCTAssertNil(check.plannedDepositDate)
        XCTAssertEqual(check.receiptRef, "RC-001")
        XCTAssertEqual(report.asOf, "2026-09-11")
        XCTAssertEqual(report.timezone, "America/New_York")
        XCTAssertEqual(report.totalAmount, 125.5)
    }

    func testCurrentChecksAcceptLegacyMissingScheduleAndNormalizePaymentIdentity() throws {
        let response = try JSONDecoder().decode(UndepositedChecks.self, from: Data("""
        {"accountCode":"1030","items":[{"id":"payment-1","amount":50,"reference":"C-1",
         "note":null,"createdAt":"2026-09-12T03:30:00Z","methodName":"Check",
         "invoiceRef":"INV-1","customerName":"Customer"}]}
        """.utf8))
        let current = try XCTUnwrap(response.items.first)
        XCTAssertNil(current.plannedDepositDate)
        XCTAssertNil(current.receiptRef)
        let register = CheckRegisterItem(current)
        XCTAssertEqual(register.paymentId, current.id)
        XCTAssertEqual(register.amount, current.amount)
    }

    func testPaymentAndReceiptDetailsDecodeTheirSchedules() throws {
        let payment = try JSONDecoder().decode(InvoicePayment.self, from: Data("""
        {"id":"payment-1","amount":"125.50","status":"SETTLED","plannedDepositDate":"2026-09-14"}
        """.utf8))
        XCTAssertEqual(payment.plannedDepositDate, "2026-09-14")
        let line = try JSONDecoder().decode(CustomerReceiptDetail.Line.self, from: Data("""
        {"id":"payment-1","invoiceId":"invoice-1","amount":125.5,"surchargeAmount":0,"plannedDepositDate":"2026-09-14"}
        """.utf8))
        XCTAssertEqual(line.plannedDepositDate, "2026-09-14")
    }

    func testCheckDatesRejectRolloverAndTimestampValues() {
        for valid in ["2026-09-14", "2024-02-29", "2000-02-29", "0001-01-01"] {
            XCTAssertTrue(CheckDates.isValid(valid), valid)
        }
        for invalid in ["", "2026-2-01", "2026-02-29", "1900-02-29", "2026-04-31", "2026-13-01", "0000-01-01", "2026-09-14T00:00:00Z", " 2026-09-14", "２０２６-09-14"] {
            XCTAssertFalse(CheckDates.isValid(invalid), invalid)
        }
    }

    func testCheckDatesUseShopDayAcrossUTCMidnightAndDaylightSaving() throws {
        let timezone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let received = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-12T03:30:00Z"))
        XCTAssertEqual(CheckDates.string(received, in: timezone), "2026-09-11")
        for day in ["2026-03-08", "2026-11-01"] {
            let date = try XCTUnwrap(CheckDates.date(day, in: timezone))
            XCTAssertEqual(CheckDates.string(date, in: timezone), day)
        }
        XCTAssertEqual(CheckDates.status(plannedDepositDate: "2026-09-10", asOf: "2026-09-11"), .overdue)
        XCTAssertEqual(CheckDates.status(plannedDepositDate: "2026-09-11", asOf: "2026-09-11"), .dueToday)
        XCTAssertEqual(CheckDates.status(plannedDepositDate: "2026-09-12", asOf: "2026-09-11"), .future)
        XCTAssertEqual(CheckDates.status(plannedDepositDate: nil, asOf: "2026-09-11"), .unscheduled)
    }

    func testCheckEndpointsUseReportDateAndServerFilteredHistoryPagination() async throws {
        let api = AccountingAPI(client: client())
        let report = try await api.undepositedCheckReport(asOf: "2026-09-11")
        XCTAssertEqual(report.count, 1)
        let reminders = try await api.checkReminders()
        XCTAssertEqual(reminders.unscheduledCount, 1)
        XCTAssertEqual(reminders.totalAmount, 0)
        XCTAssertEqual(reminders.items.first?.status, .unscheduled)

        let cash = CashAccountsAPI(client: client())
        let history = try await cash.checkDeposits(page: 2, pageSize: 20)
        XCTAssertEqual(history.total, 21)
        XCTAssertEqual(history.page, 2)
        let transfer = try XCTUnwrap(history.items.first)
        XCTAssertNotNil(transfer.reversedAt)
        XCTAssertEqual(transfer.netAmount, 123)
        XCTAssertEqual(transfer.checks.map(\.id), ["membership-1", "membership-2"])
        XCTAssertEqual(transfer.checks.map(\.invoiceRef), ["INV-1", "INV-2"])
        XCTAssertEqual(Set(transfer.checks.compactMap(\.receiptRef)), ["RC-001"])
        XCTAssertNil(transfer.createdByName)
        let detail = try await cash.transfer(id: "transfer-1")
        XCTAssertEqual(detail, transfer)
    }

    func testReschedulingUsesPatchAndPublishesRefreshAfterSuccess() async throws {
        let changed = expectation(forNotification: .checkRegisterDidChange, object: nil)
        let api = AccountingAPI(client: client())
        let result = try await api.updatePlannedDepositDate(paymentId: "payment-1", plannedDepositDate: "2026-09-14")
        XCTAssertEqual(result.id, "payment-1")
        XCTAssertEqual(result.plannedDepositDate, "2026-09-14")
        await fulfillment(of: [changed], timeout: 1)
    }

    func testDetachedReschedulingDeliversRefreshOnMainThread() async throws {
        let changed = expectation(description: "Check refresh delivered on main thread")
        let observer = NotificationCenter.default.addObserver(
            forName: .checkRegisterDidChange, object: nil, queue: nil
        ) { _ in
            XCTAssertTrue(Thread.isMainThread)
            changed.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let api = AccountingAPI(client: client())

        let result = try await Task.detached {
            try await api.updatePlannedDepositDate(paymentId: "payment-1", plannedDepositDate: "2026-09-14")
        }.value

        XCTAssertEqual(result.plannedDepositDate, "2026-09-14")
        await fulfillment(of: [changed], timeout: 1)
    }

    func testFailedReschedulingDoesNotPublishRefresh() async throws {
        let changed = expectation(forNotification: .checkRegisterDidChange, object: nil)
        changed.isInverted = true
        let api = AccountingAPI(client: client())

        do {
            _ = try await api.updatePlannedDepositDate(paymentId: "missing-payment", plannedDepositDate: "2026-09-14")
            XCTFail("The unsupported payment should fail")
        } catch {}

        await fulfillment(of: [changed], timeout: 0.1)
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CheckStubProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }
}

private final class CheckStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
            let responseBody: String
            switch (request.httpMethod, url.path) {
            case ("GET", "/api/accounting/reports/undeposited-checks") where query == ["asOf": "2026-09-11"]:
                responseBody = Self.reportJSON
            case ("GET", "/api/accounting/check-reminders"):
                responseBody = """
                {"asOf":"2026-09-12","timezone":"America/New_York","dueTodayCount":0,"overdueCount":0,
                 "unscheduledCount":1,"totalAmount":0,"items":[
                  {"id":"entry-1","paymentId":"payment-1","amount":125.5,"createdAt":"2026-09-11T12:00:00Z",
                   "plannedDepositDate":null,"status":"unscheduled"}]}
                """
            case ("GET", "/api/accounting/check-deposits") where query == ["page": "2", "pageSize": "20"]:
                responseBody = "{\"items\":[\(Self.transferJSON)],\"total\":21,\"page\":2,\"pageSize\":20}"
            case ("GET", "/api/accounting/transfers/transfer-1"):
                responseBody = Self.transferJSON
            case ("PATCH", "/api/accounting/checks/payment-1/planned-deposit-date"):
                let body = try JSONDecoder().decode([String: String].self, from: bodyData())
                guard body == ["plannedDepositDate": "2026-09-14"] else { throw URLError(.badServerResponse) }
                responseBody = "{\"id\":\"payment-1\",\"plannedDepositDate\":\"2026-09-14\"}"
            default:
                throw URLError(.unsupportedURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData() throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    static let reportJSON = """
    {"asOf":"2026-09-11","timezone":"America/New_York","count":1,"totalAmount":125.5,"items":[
      {"id":"permanent-check-1","paymentId":null,"amount":125.5,"reference":"C-123","note":null,
       "createdAt":"2026-09-11T12:00:00Z","plannedDepositDate":null,"receiptRef":"RC-001",
       "invoiceRef":"INV-001","customerName":null,"methodName":null}]}
    """

    private static let transferJSON = """
    {"id":"transfer-1","ref":"TR-001","reference":"BANK-123","note":null,"amount":125.5,"fee":2.5,
     "netAmount":123,"reversedAt":"2026-09-12T17:00:00Z","createdAt":"2026-09-12T15:00:00Z",
     "fromAccount":{"code":"1030","name":"Undeposited Checks"},"toAccount":{"code":"1010","name":"Bank"},
     "createdByName":null,"checkCount":2,"checks":[
       {"id":"membership-1","amount":50,"checkNumber":"C-123","receiptRef":"RC-001","invoiceRef":"INV-1",
        "customerName":null,"methodName":null,"note":null},
       {"id":"membership-2","amount":75.5,"checkNumber":"C-123","receiptRef":"RC-001","invoiceRef":"INV-2",
        "customerName":"Historical Customer","methodName":"Check","note":"Second allocation"}]}
    """
}
