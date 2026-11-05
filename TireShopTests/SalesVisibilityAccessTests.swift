import XCTest
@testable import TireShop

@MainActor
final class SalesVisibilityAccessTests: XCTestCase {
    private let globalModules = [
        "orders", "checks", "fet", "eod",
        "monthlySales", "commissions", "activity"
    ]
    private let accountingModules = ["accounting", "cashAccounts"]
    private let modulePermissions = [
        "orders.manage", "accounting.view", "payments.collect", "employees.view", "activity.view"
    ]

    func testGlobalModulesRequireAllSalesAccessAsWellAsModulePermission() {
        let scoped = makeAuth(permissions: modulePermissions)
        let allSales = makeAuth(permissions: modulePermissions + ["sales.viewAll"])
        let visibilityOnly = makeAuth(permissions: ["sales.viewAll"])

        for key in globalModules {
            XCTAssertFalse(DestinationRegistry.isVisible(key, auth: scoped), key)
            XCTAssertTrue(DestinationRegistry.isVisible(key, auth: allSales), key)
            XCTAssertFalse(DestinationRegistry.isVisible(key, auth: visibilityOnly), key)
        }
    }

    func testChecksRetainCollectionAlternativeWithMandatoryAllSalesAccess() {
        XCTAssertTrue(DestinationRegistry.isVisible("checks", auth: makeAuth(
            permissions: ["payments.collect", "sales.viewAll"]
        )))
        XCTAssertFalse(DestinationRegistry.isVisible("checks", auth: makeAuth(
            permissions: ["payments.collect"]
        )))
    }

    func testAccountingModulesRemainAvailableWithoutAllSalesAccess() {
        let auth = makeAuth(permissions: ["accounting.view"])
        for key in accountingModules {
            XCTAssertTrue(DestinationRegistry.isVisible(key, auth: auth), key)
        }
    }

    func testAccountingModulesStillRequireAccountingPermission() {
        for permissions in [[], ["sales.viewAll"], [
            "orders.manage", "payments.collect", "employees.view", "activity.view", "sales.view"
        ]] {
            let auth = makeAuth(permissions: permissions)
            for key in accountingModules {
                XCTAssertFalse(DestinationRegistry.isVisible(key, auth: auth), key)
            }
        }
    }

    func testAccountingNavigationSurvivesSanitizingWithoutAllSalesAccess() {
        let auth = makeAuth(permissions: ["accounting.view"])
        let visible = Set(DestinationRegistry.visibleDestinations(auth: auth).map(\.key))

        for key in accountingModules {
            let navigation = AppNavigationModel()
            navigation.selectDestination(key)
            navigation.sanitize(visibleDestinationKeys: visible)

            XCTAssertEqual(navigation.selectedDestinationKey, key)
            XCTAssertEqual(navigation.path(for: AppNavigationModel.moreKey).wrappedValue, [.module(key)])
        }
    }

    func testAccountingTabsExcludeSalesReportsWithoutAllSalesAccess() {
        XCTAssertEqual(AccountingNativeView.Tab.available(canReadSales: false), [.accounts])
        XCTAssertEqual(AccountingNativeView.Tab.available(canReadSales: true), AccountingNativeView.Tab.allCases)
    }

    func testCashAccountTabsExcludeTransfersWithoutAllSalesAccess() {
        XCTAssertEqual(CashAccountsNativeView.Tab.available(canReadSales: false), [.expenses, .methods])
        XCTAssertEqual(CashAccountsNativeView.Tab.available(canReadSales: true), CashAccountsNativeView.Tab.allCases)
    }

    func testFinanceScopeChangesWhenSameUsersSalesOrManagementPermissionsAreRevoked() {
        let auth = makeAuth(permissions: ["accounting.view", "accounting.manage", "sales.viewAll"])
        let original = FinanceReadScope(auth)
        XCTAssertTrue(original.canReadSales)
        XCTAssertTrue(original.canManage)

        auth.user = makeAuth(permissions: ["accounting.view", "accounting.manage"]).user
        let salesRevoked = FinanceReadScope(auth)
        XCTAssertEqual(salesRevoked.session, original.session)
        XCTAssertFalse(salesRevoked.canReadSales)
        XCTAssertTrue(salesRevoked.canManage)
        XCTAssertNotEqual(salesRevoked, original)

        auth.user = makeAuth(permissions: ["accounting.view"]).user
        let managementRevoked = FinanceReadScope(auth)
        XCTAssertEqual(managementRevoked.session, original.session)
        XCTAssertFalse(managementRevoked.canReadSales)
        XCTAssertFalse(managementRevoked.canManage)
        XCTAssertNotEqual(managementRevoked, salesRevoked)

        let replacementSession = FinanceReadScope(makeAuth(permissions: ["accounting.view"]))
        XCTAssertNotEqual(replacementSession.session, managementRevoked.session)
        XCTAssertNotEqual(replacementSession, managementRevoked)
    }

    func testCashSnapshotSkipsTransferRequestWithoutAllSalesAccess() async throws {
        let (api, requestID) = makeCashAccountsAPI()
        defer { CashAccountsSnapshotProtocol.clear(requestID) }

        let snapshot = await CashAccountsSnapshot.load(canReadSales: false, api: api)

        XCTAssertEqual(CashAccountsSnapshotProtocol.paths(for: requestID).sorted(), [
            "/api/accounting/cash-accounts", "/api/accounting/expenses", "/api/accounting/payment-methods"
        ])
        XCTAssertNil(snapshot.transfers)
        XCTAssertTrue(try snapshot.accounts.get().isEmpty)
        XCTAssertTrue(try snapshot.expenses.get().items.isEmpty)
        XCTAssertTrue(try snapshot.methods.get().items.isEmpty)
    }

    func testCashSnapshotIncludesTransferRequestWithAllSalesAccess() async throws {
        let (api, requestID) = makeCashAccountsAPI()
        defer { CashAccountsSnapshotProtocol.clear(requestID) }

        let snapshot = await CashAccountsSnapshot.load(canReadSales: true, api: api)

        XCTAssertEqual(CashAccountsSnapshotProtocol.paths(for: requestID).sorted(), [
            "/api/accounting/cash-accounts", "/api/accounting/expenses",
            "/api/accounting/payment-methods", "/api/accounting/transfers"
        ])
        XCTAssertTrue(try snapshot.accounts.get().isEmpty)
        XCTAssertTrue(try snapshot.expenses.get().items.isEmpty)
        XCTAssertTrue(try snapshot.methods.get().items.isEmpty)
        let transfers = try XCTUnwrap(snapshot.transfers)
        XCTAssertTrue(try transfers.get().items.isEmpty)
    }

    func testDeniedTransferRequestDoesNotDiscardPermittedCashPanels() async throws {
        let (api, requestID) = makeCashAccountsAPI(transferStatus: 403)
        defer { CashAccountsSnapshotProtocol.clear(requestID) }

        let snapshot = await CashAccountsSnapshot.load(canReadSales: true, api: api)

        XCTAssertEqual(CashAccountsSnapshotProtocol.paths(for: requestID).sorted(), [
            "/api/accounting/cash-accounts", "/api/accounting/expenses",
            "/api/accounting/payment-methods", "/api/accounting/transfers"
        ])
        XCTAssertTrue(try snapshot.accounts.get().isEmpty)
        XCTAssertTrue(try snapshot.expenses.get().items.isEmpty)
        XCTAssertTrue(try snapshot.methods.get().items.isEmpty)
        let transfers = try XCTUnwrap(snapshot.transfers)
        XCTAssertThrowsError(try transfers.get()) { error in
            XCTAssertEqual((error as? APIError)?.status, 403)
        }
    }

    func testOwnSalesHRAndAnalyticsRemainAvailableAndKeepTheirNavigationPaths() {
        let auth = makeAuth(permissions: modulePermissions + [
            "sales.view", "sales.manage", "customers.analytics.view", "receivables.view"
        ])
        let visible = Set(DestinationRegistry.visibleDestinations(auth: auth).map(\.key))
        XCTAssertTrue(Set(["sales", "newQuote", "employees", "customerAnalytics", "money"]).isSubset(of: visible))

        let navigation = AppNavigationModel(selectedDestinationKey: "sales")
        navigation.append(.saleDetail("own-sale"), to: "sales")
        navigation.append(.employeeDetail("employee"), to: "employees")
        navigation.append(.orderDetail("global-order"), to: "orders")
        navigation.sanitize(visibleDestinationKeys: visible)

        XCTAssertEqual(navigation.selectedDestinationKey, "sales")
        XCTAssertEqual(navigation.path(for: "sales").wrappedValue, [.saleDetail("own-sale")])
        XCTAssertEqual(navigation.path(for: "employees").wrappedValue, [.employeeDetail("employee")])
        XCTAssertTrue(navigation.path(for: "orders").wrappedValue.isEmpty)
    }

    func testAdminWildcardCanStillOpenGlobalModules() {
        let auth = makeAuth(permissions: [], isAdmin: true)
        XCTAssertTrue((globalModules + accountingModules).allSatisfy {
            DestinationRegistry.isVisible($0, auth: auth)
        })
    }

    private func makeCashAccountsAPI(transferStatus: Int = 200) -> (CashAccountsAPI, String) {
        let requestID = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CashAccountsSnapshotProtocol.self]
        configuration.httpAdditionalHeaders = [
            "X-Cash-Snapshot-Test": requestID,
            "X-Transfer-Status": String(transferStatus)
        ]
        let client = APIClient(session: URLSession(configuration: configuration))
        return (CashAccountsAPI(client: client), requestID)
    }

    private func makeAuth(permissions: [String], isAdmin: Bool = false) -> AuthStore {
        let auth = AuthStore(api: APIClient(session: URLSession(configuration: .ephemeral)))
        auth.user = SessionUser(
            id: "staff", email: "staff@example.invalid", fullName: "Staff",
            roleId: "role", roleName: "Staff", homeWarehouse: nil, isAdmin: isAdmin,
            permissions: permissions, approvalPermissions: [], mfaMethod: nil
        )
        auth.ready = true
        return auth
    }
}

private final class CashAccountsSnapshotProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recordedPaths: [String: [String]] = [:]

    static func paths(for requestID: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths[requestID] ?? []
    }

    static func clear(_ requestID: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedPaths.removeValue(forKey: requestID)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let requestID = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Cash-Snapshot-Test"))
            Self.lock.lock()
            Self.recordedPaths[requestID, default: []].append(url.path)
            Self.lock.unlock()

            XCTAssertEqual(request.httpMethod, "GET")
            let status: Int
            let body: String
            switch url.path {
            case "/api/accounting/cash-accounts":
                status = 200
                body = "[]"
            case "/api/accounting/transfers", "/api/accounting/expenses", "/api/accounting/payment-methods":
                status = url.path == "/api/accounting/transfers"
                    ? Int(request.value(forHTTPHeaderField: "X-Transfer-Status") ?? "200") ?? 200
                    : 200
                body = status == 200
                    ? #"{"items":[],"total":0,"page":1,"pageSize":30}"#
                    : #"{"message":"Global sales access required"}"#
            default:
                status = 404
                body = #"{"message":"Unexpected cash snapshot request"}"#
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
