import XCTest
@testable import TireShop

final class TaxDataTests: XCTestCase {
    func testCoverageQuartersUseExclusiveEndDatesAndRollAcrossYears() throws {
        let expected = [
            (1, "2026-01-01", "2026-04-01"),
            (2, "2026-04-01", "2026-07-01"),
            (3, "2026-07-01", "2026-10-01"),
            (4, "2026-10-01", "2027-01-01")
        ]
        for (quarter, start, end) in expected {
            let fields = try TaxImportPeriod(year: 2026, quarter: quarter).fields(sourceVersion: "GAB2026Q4AUG20")
            XCTAssertEqual(fields, ["sourceVersion": "GAB2026Q4AUG20", "effectiveFrom": start, "effectiveTo": end])
        }
        for (year, quarter) in [(1999, 1), (2101, 1), (2026, 0), (2026, 5)] {
            XCTAssertThrowsError(try TaxImportPeriod(year: year, quarter: quarter).fields(sourceVersion: "release"))
        }
        XCTAssertEqual(try TaxImportPeriod(year: 2100, quarter: 4).fields(sourceVersion: "release")["effectiveTo"], "2101-01-01")
    }

    func testSourceVersionsMatchServerLengthAndCharacterLimits() {
        for version in ["GAB2026Q4AUG20", "release_2.0-final", "1", String(repeating: "a", count: 100)] {
            XCTAssertTrue(TaxImportPeriod.isValidSourceVersion(version), version)
        }
        for version in ["", " release", "release ", "release/name", "release\n", ".release", "版本", String(repeating: "a", count: 101)] {
            XCTAssertFalse(TaxImportPeriod.isValidSourceVersion(version), version)
        }
    }

    func testFileLimitsMatchEachEndpointWithoutApplyingGeneralUploadLimit() throws {
        let cases: [(TaxImportKind, String, Int)] = [
            (.rate, "rates.PDF", 20), (.rate, "rates.json", 20),
            (.boundary, "GAB2026.ZIP", 64), (.boundary, "GAB2026.csv", 512)
        ]
        for (kind, name, megabytes) in cases {
            let limit = megabytes * 1_024 * 1_024
            XCTAssertNoThrow(try kind.validate(filename: name, byteCount: limit))
            XCTAssertThrowsError(try kind.validate(filename: name, byteCount: limit + 1))
            XCTAssertThrowsError(try kind.validate(filename: name, byteCount: 0))
        }
        XCTAssertThrowsError(try TaxImportKind.rate.validate(filename: "rates.csv", byteCount: 10))
        XCTAssertThrowsError(try TaxImportKind.boundary.validate(filename: "rates.pdf", byteCount: 10))
        XCTAssertThrowsError(try TaxImportKind.boundary.validate(filename: "rates.zip.exe", byteCount: 10))
    }

    func testPreviewDecodesActualSparseArtifactAndNullableDiffRates() throws {
        let preview = try decode(TaxDataset.self, """
        {"id":"rate-1","kind":"RATE","label":"Q4","status":"VALIDATED",
         "effectiveFrom":"2026-10-01T04:00:00Z","effectiveTo":"2027-01-01T05:00:00Z",
         "coverage":{"expectedGeneralJurisdictions":159},
         "artifact":{"filename":"q4.pdf","sourceUrl":null,"sha256":"abc123"},
         "findings":[],"diff":[
           {"code":"001","jurisdiction":"Added","oldRate":null,"newRate":0.089,"change":"ADDED","sourceRow":"1"},
           {"code":null,"jurisdiction":"Removed","oldRate":0.07,"newRate":null,"change":"REMOVED","sourceRow":null}]}
        """)
        XCTAssertTrue(preview.canPublish)
        XCTAssertNil(preview.counts)
        XCTAssertNil(preview.artifact?.type)
        XCTAssertNil(preview.artifact?.createdAt)
        XCTAssertEqual(preview.diff?.count, 2)
        XCTAssertNil(preview.diff?[0].oldRate)
        XCTAssertNil(preview.diff?[1].newRate)
        XCTAssertEqual(preview.diff?[0].newRate, 0.089)
    }

    func testPublicationRequiresValidatedStatusWithoutBlockingFindings() throws {
        for (status, severity, allowed) in [
            ("STAGED", "WARNING", false), ("REJECTED", "ERROR", false),
            ("VALIDATED", "ERROR", false), ("VALIDATED", "WARNING", true),
            ("PUBLISHED", "WARNING", false), ("SUPERSEDED", "WARNING", false)
        ] {
            let dataset = try decode(TaxDataset.self, """
            {"id":"boundary","kind":"BOUNDARY","label":"SST","status":"\(status)",
             "effectiveFrom":"2026-10-01","effectiveTo":"2027-01-01","coverage":{"imported":12345,"skippedOutsidePeriod":10},
             "findings":[{"id":"finding","severity":"\(severity)","code":"COVERAGE","message":"Review coverage"}],
             "_count":{"boundaries":1,"rates":0}}
            """)
            XCTAssertEqual(dataset.canPublish, allowed)
            XCTAssertEqual(dataset.coverage?.imported, 12345)
        }
    }

    func testCurrentPublishedScheduleExcludesItsEndInstant() throws {
        let dataset = try decode(TaxDataset.self, """
        {"id":"rate","kind":"RATE","label":"Q3","status":"PUBLISHED",
         "effectiveFrom":"2026-07-01T04:00:00Z","effectiveTo":"2026-10-01T04:00:00Z","findings":[]}
        """)
        let formatter = ISO8601DateFormatter()
        XCTAssertTrue(dataset.isCurrent(at: try XCTUnwrap(formatter.date(from: "2026-07-01T04:00:00Z"))))
        XCTAssertFalse(dataset.isCurrent(at: try XCTUnwrap(formatter.date(from: "2026-10-01T04:00:00Z"))))
    }

    func testImportJobDecodesProgressAndRecognizesOnlyActiveStates() throws {
        for status in ["QUEUED", "RUNNING", "COMPLETE", "FAILED"] {
            let job = try decode(TaxBoundaryImportJob.self, """
            {"id":"job","status":"\(status)","filename":"GAB2026Q4.zip","sourceVersion":"GAB2026Q4",
             "effectiveFrom":"2026-10-01","effectiveTo":"2027-01-01","datasetId":null,"imported":45000,"error":null}
            """)
            XCTAssertEqual(job.isActive, status == "QUEUED" || status == "RUNNING")
            XCTAssertEqual(job.imported, 45000)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
