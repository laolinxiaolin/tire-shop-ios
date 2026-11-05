import XCTest
@testable import TireShop

final class SaleSalespersonPolicyTests: XCTestCase {
    func testOnlyConfirmedSaleStatusesAllowReassignment() {
        for status in ["INVOICED", "PAID"] {
            XCTAssertTrue(SaleSalespersonPolicy.allowsAssignment(status: status), status)
        }
        for status in ["DRAFT", "QUOTE", "CANCELLED", "VOID", "UNKNOWN"] {
            XCTAssertFalse(SaleSalespersonPolicy.allowsAssignment(status: status), status)
        }
    }

    func testNewChoicesIncludeOnlyActiveStaffAndAreSortedWithoutDuplicates() {
        let active = person("active", "Jamie", "ACTIVE")
        let another = person("another", "Alex", "ACTIVE")
        let options = SaleSalespersonPolicy.options(
            staff: [active, person("inactive", "Inactive", "INACTIVE"),
                    person("terminated", "Terminated", "TERMINATED"),
                    person("unknown", "Unknown", nil), another, active],
            currentID: nil, current: nil
        )
        XCTAssertEqual(options, [another, active])
    }

    func testCurrentInactiveOrTerminatedEmployeeRemainsVisibleWithoutBecomingAssignable() {
        let active = person("active", "Alex", "ACTIVE")
        for status in ["INACTIVE", "TERMINATED"] {
            let current = person("current", "Jamie", status)
            let options = SaleSalespersonPolicy.options(
                staff: [active], currentID: current.id, current: current
            )
            XCTAssertEqual(options, [active, current])
            XCTAssertFalse(SaleSalespersonPolicy.canSave(
                status: "INVOICED", selectedID: current.id,
                currentID: active.id, options: options
            ))
        }
    }

    func testCurrentIDPreservesEmployeeWhenNestedSalespersonIsAbsent() {
        let current = person("current", "Jamie", "INACTIVE")
        XCTAssertEqual(SaleSalespersonPolicy.options(
            staff: [current], currentID: current.id, current: nil
        ), [current])
    }

    func testFreshStaffStatusOverridesStaleActiveSaleSnapshot() {
        let stale = person("current", "Jamie", "ACTIVE")
        let fresh = person("current", "Jamie", "INACTIVE")
        let options = SaleSalespersonPolicy.options(
            staff: [fresh], currentID: fresh.id, current: stale
        )
        XCTAssertEqual(options, [fresh])
        XCTAssertFalse(SaleSalespersonPolicy.canSave(
            status: "PAID", selectedID: fresh.id, currentID: nil, options: options
        ))
    }

    func testMissingCurrentEmployeeDetailsPreserveSelectionWithoutOfferingNewAssignment() {
        let options = SaleSalespersonPolicy.options(staff: [], currentID: "current", current: nil)
        XCTAssertEqual(options.map(\.id), ["current"])
        XCTAssertNil(options.first?.status)
        XCTAssertFalse(SaleSalespersonPolicy.canSave(
            status: "PAID", selectedID: "current", currentID: nil, options: options
        ))
    }

    func testSaveRequiresActualChangeToNoneOrAnActiveChoiceOnConfirmedSale() {
        let active = person("active", "Alex", "ACTIVE")
        let inactive = person("inactive", "Jamie", "INACTIVE")
        let options = [active, inactive]
        for status in ["INVOICED", "PAID"] {
            XCTAssertTrue(SaleSalespersonPolicy.canSave(
                status: status, selectedID: active.id, currentID: inactive.id, options: options
            ))
            XCTAssertTrue(SaleSalespersonPolicy.canSave(
                status: status, selectedID: nil, currentID: inactive.id, options: options
            ))
            XCTAssertFalse(SaleSalespersonPolicy.canSave(
                status: status, selectedID: active.id, currentID: active.id, options: options
            ))
            XCTAssertFalse(SaleSalespersonPolicy.canSave(
                status: status, selectedID: nil, currentID: nil, options: options
            ))
            for invalid in [inactive.id, "missing", ""] {
                XCTAssertFalse(SaleSalespersonPolicy.canSave(
                    status: status, selectedID: invalid, currentID: nil, options: options
                ), invalid)
            }
        }
        for status in ["DRAFT", "QUOTE", "CANCELLED"] {
            XCTAssertFalse(SaleSalespersonPolicy.canSave(
                status: status, selectedID: active.id, currentID: inactive.id, options: options
            ))
            XCTAssertFalse(SaleSalespersonPolicy.canSave(
                status: status, selectedID: nil, currentID: inactive.id, options: options
            ))
        }
    }

    private func person(_ id: String, _ name: String, _ status: EmployeeStatus?) -> CustomerSalesperson {
        CustomerSalesperson(id: id, fullName: name, status: status)
    }
}
