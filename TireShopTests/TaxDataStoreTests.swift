import XCTest
@testable import TireShop

@MainActor
final class TaxDataStoreTests: XCTestCase {
    func testSessionChangeDuringMutationStopsFollowUpReadsAndFutureWrites() async throws {
        let api = TaxDataStoreMock()
        var current = true
        let store = TaxDataStore(api: api, sessionIsCurrent: { current })
        await store.refresh()
        let readsBeforeMutation = api.datasetRequests
        let started = expectation(description: "Original admin mutation started")
        var completion: CheckedContinuation<Void, Never>?
        api.checkAction = {
            await withCheckedContinuation { continuation in
                completion = continuation
                started.fulfill()
            }
        }
        let mutation = Task { await store.check() }
        await fulfillment(of: [started], timeout: 1)
        current = false
        completion?.resume()
        await mutation.value
        XCTAssertEqual(api.datasetRequests, readsBeforeMutation, "An old mutation must not fetch datasets with the replacement account")
        XCTAssertNil(store.errorMessage)
        await store.check()
        XCTAssertEqual(api.checkRequests, 1, "Queued writes from an obsolete admin screen must stop")
    }

    func testDatasetReadFromPreviousSessionIsDiscardedWithoutFetchingJobs() async throws {
        let api = TaxDataStoreMock()
        var current = true
        let store = TaxDataStore(api: api, sessionIsCurrent: { current })
        let started = expectation(description: "Original dataset read started")
        var completion: CheckedContinuation<[TaxDataset], Never>?
        api.datasetLoader = {
            await withCheckedContinuation { continuation in
                completion = continuation
                started.fulfill()
            }
        }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 1)
        current = false
        completion?.resume(returning: [try dataset(status: "PUBLISHED")])
        await refresh.value
        XCTAssertTrue(store.datasets.isEmpty)
        XCTAssertEqual(api.jobRequests, 0)
        XCTAssertNil(store.errorMessage)
    }

    func testPollingDoesNotStartWhileMutationIsRunning() async throws {
        let api = TaxDataStoreMock()
        api.datasetValues = [try dataset(status: "VALIDATED")]
        api.jobValues = [try job(status: "RUNNING")]
        let store = TaxDataStore(api: api)
        await store.refresh()

        let started = expectation(description: "Check started")
        var completion: CheckedContinuation<Void, Never>?
        api.checkAction = {
            await withCheckedContinuation { continuation in
                completion = continuation
                started.fulfill()
            }
        }
        let mutation = Task { await store.check() }
        await fulfillment(of: [started], timeout: 1)
        let previousJobRequests = api.jobRequests
        await store.pollJobsOnce()
        XCTAssertEqual(api.jobRequests, previousJobRequests, "Polling must not fetch a pre-mutation snapshot")
        api.datasetValues = [try dataset(status: "PUBLISHED")]
        completion?.resume()
        await mutation.value
        XCTAssertEqual(store.datasets.first?.status, "PUBLISHED")
    }

    func testPollStartedBeforeMutationCannotReplaceFreshData() async throws {
        let api = TaxDataStoreMock()
        api.datasetValues = [try dataset(status: "VALIDATED")]
        api.jobValues = [try job(status: "RUNNING")]
        let store = TaxDataStore(api: api)
        await store.refresh()

        let started = expectation(description: "Old poll started")
        var completion: CheckedContinuation<[TaxBoundaryImportJob], Never>?
        api.jobLoader = {
            await withCheckedContinuation { continuation in
                completion = continuation
                started.fulfill()
            }
        }
        let oldPoll = Task { await store.pollJobsOnce() }
        await fulfillment(of: [started], timeout: 1)
        api.datasetValues = [try dataset(status: "PUBLISHED")]
        await store.check()
        let requestsAfterMutation = api.datasetRequests
        api.datasetValues = [try dataset(status: "VALIDATED")]
        completion?.resume(returning: [try job(status: "COMPLETE")])
        await oldPoll.value

        XCTAssertEqual(api.datasetRequests, requestsAfterMutation, "An obsolete completion must not trigger a stale dataset fetch")
        XCTAssertEqual(store.datasets.first?.status, "PUBLISHED")
        XCTAssertEqual(store.jobs.first?.status, "RUNNING")
    }

    private func dataset(status: String) throws -> TaxDataset {
        try JSONDecoder().decode(TaxDataset.self, from: Data("""
        {"id":"dataset","kind":"RATE","label":"Q4","status":"\(status)",
         "effectiveFrom":"2026-10-01T04:00:00Z","effectiveTo":"2027-01-01T05:00:00Z","findings":[]}
        """.utf8))
    }

    private func job(status: String) throws -> TaxBoundaryImportJob {
        try JSONDecoder().decode(TaxBoundaryImportJob.self, from: Data("""
        {"id":"job","status":"\(status)","filename":"GAB.zip","sourceVersion":"GAB",
         "effectiveFrom":"2026-10-01","effectiveTo":"2027-01-01","datasetId":"dataset","imported":100,"error":null}
        """.utf8))
    }
}

@MainActor
private final class TaxDataStoreMock: TaxDataServing {
    var datasetValues: [TaxDataset] = []
    var jobValues: [TaxBoundaryImportJob] = []
    var datasetRequests = 0
    var jobRequests = 0
    var checkRequests = 0
    var checkAction: () async throws -> Void = {}
    var datasetLoader: (() async -> [TaxDataset])?
    var jobLoader: (() async -> [TaxBoundaryImportJob])?

    func datasets() async throws -> [TaxDataset] {
        datasetRequests += 1
        if let datasetLoader { return await datasetLoader() }
        return datasetValues
    }

    func jobs() async throws -> [TaxBoundaryImportJob] {
        jobRequests += 1
        if let jobLoader { return await jobLoader() }
        return jobValues
    }

    func check() async throws {
        checkRequests += 1
        try await checkAction()
    }
    func preview(id: String) async throws -> TaxDataset { throw URLError(.unsupportedURL) }
    func publish(id: String) async throws { throw URLError(.unsupportedURL) }
    func uploadRate(_ file: TaxImportFile) async throws { throw URLError(.unsupportedURL) }
    func uploadBoundary(_ file: TaxImportFile, period: TaxImportPeriod, version: String) async throws -> TaxBoundaryImportJob {
        throw URLError(.unsupportedURL)
    }
    func retry(id: String) async throws -> TaxBoundaryImportJob { throw URLError(.unsupportedURL) }
}
