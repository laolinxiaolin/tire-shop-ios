import Foundation
import SwiftUI

protocol TaxDataServing {
    func datasets() async throws -> [TaxDataset]
    func jobs() async throws -> [TaxBoundaryImportJob]
    func preview(id: String) async throws -> TaxDataset
    func check() async throws
    func publish(id: String) async throws
    func uploadRate(_ file: TaxImportFile) async throws
    func uploadBoundary(_ file: TaxImportFile, period: TaxImportPeriod, version: String) async throws -> TaxBoundaryImportJob
    func retry(id: String) async throws -> TaxBoundaryImportJob
}

extension TaxDataAPI: TaxDataServing {}

@MainActor
final class TaxDataStore: ObservableObject {
    @Published private(set) var datasets: [TaxDataset] = []
    @Published private(set) var jobs: [TaxBoundaryImportJob] = []
    @Published var preview: TaxDataset?
    @Published private(set) var loading = false
    @Published private(set) var busy: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var progressError: String?
    @Published private(set) var rateFile: TaxImportFile?
    @Published private(set) var boundaryFile: TaxImportFile?
    @Published var sourceVersion = ""
    @Published var year: Int
    @Published var quarter: Int

    private let api: any TaxDataServing
    private var generation = 0
    private var sessionIsCurrent: @MainActor () -> Bool
    private var sessionBound = false

    init(api: any TaxDataServing = TaxDataAPI(), sessionIsCurrent: @escaping @MainActor () -> Bool = { true }) {
        self.api = api
        self.sessionIsCurrent = sessionIsCurrent
        let components = ShopClock.calendar.dateComponents([.year, .month], from: Date())
        year = components.year ?? 2026
        quarter = ((components.month ?? 1) - 1) / 3 + 1
    }

    func bindSession(_ auth: AuthStore) {
        guard !sessionBound else { return }
        sessionBound = true
        let identity = AppSessionIdentity(auth)
        sessionIsCurrent = { [weak auth] in
            guard let auth else { return false }
            return auth.user?.isAdmin == true && identity.isCurrent(auth)
        }
    }

    var hasActiveJobs: Bool { jobs.contains(where: \.isActive) }
    var period: TaxImportPeriod { TaxImportPeriod(year: year, quarter: quarter) }
    var canUploadBoundary: Bool {
        sessionIsCurrent() && busy == nil && boundaryFile != nil && period.isValid
            && TaxImportPeriod.isValidSourceVersion(sourceVersion)
            && jobs.filter(\.isActive).count < 3
    }

    var currentDataset: TaxDataset? { datasets.first { $0.isCurrent(at: Date()) } }
    var upcomingDataset: TaxDataset? {
        datasets.filter {
            $0.kind == "RATE" && $0.status == "PUBLISHED"
                && (AppFormat.date($0.effectiveFrom) ?? .distantPast) > Date()
        }.min { $0.effectiveFrom < $1.effectiveFrom }
    }

    var lastCheck: String? {
        datasets.filter { $0.artifact?.type == "WEBSITE" }
            .compactMap { $0.artifact?.fetchedAt ?? $0.artifact?.createdAt }
            .max { (AppFormat.date($0) ?? .distantPast) < (AppFormat.date($1) ?? .distantPast) }
    }

    func refresh() async {
        guard sessionIsCurrent(), !Task.isCancelled, !loading, busy == nil else { return }
        generation += 1
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let next = try await api.datasets()
            try requireCurrentSession()
            datasets = next
        } catch { if !Task.isCancelled, sessionIsCurrent() { errorMessage = message(for: error) } }
        guard sessionIsCurrent(), !Task.isCancelled else { return }
        await refreshJobs()
    }

    func pollActiveJobs() async {
        while !Task.isCancelled && sessionIsCurrent() {
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            await pollJobsOnce()
        }
    }

    func pollJobsOnce() async {
        guard hasActiveJobs, busy == nil, !loading else { return }
        await refreshJobs()
    }

    func selectFile(_ result: Result<[URL], Error>, kind: TaxImportKind) async {
        guard sessionIsCurrent(), !Task.isCancelled, busy == nil else { return }
        busy = "prepare"
        errorMessage = nil
        defer { busy = nil }
        do {
            guard let url = try result.get().first else { return }
            let file = try await TaxImportFile.prepare(url, kind: kind)
            try requireCurrentSession()
            if kind == .rate {
                rateFile?.remove()
                rateFile = file
            } else {
                boundaryFile?.remove()
                boundaryFile = file
                sourceVersion = URL(fileURLWithPath: file.filename).deletingPathExtension().lastPathComponent
            }
        } catch {
            if !Task.isCancelled, sessionIsCurrent() { errorMessage = message(for: error) }
        }
    }

    func check() async {
        await run("check") { try await self.api.check() }
    }

    func uploadRate() async {
        guard let file = rateFile else { return }
        await run("rateUpload") {
            try await self.api.uploadRate(file)
            try self.requireCurrentSession()
            self.rateFile?.remove()
            self.rateFile = nil
        }
    }

    func uploadBoundary() async {
        guard canUploadBoundary, let file = boundaryFile else { return }
        let period = period
        let version = sourceVersion
        await run("boundaryUpload") {
            let job = try await self.api.uploadBoundary(file, period: period, version: version)
            try self.requireCurrentSession()
            self.merge(job)
            self.boundaryFile?.remove()
            self.boundaryFile = nil
        }
    }

    func openPreview(id: String) async {
        guard sessionIsCurrent(), !Task.isCancelled, busy == nil else { return }
        busy = id
        errorMessage = nil
        defer { busy = nil }
        do {
            let loaded = try await api.preview(id: id)
            try requireCurrentSession()
            preview = loaded
        } catch { if !Task.isCancelled, sessionIsCurrent() { errorMessage = message(for: error) } }
    }

    func publishPreview() async {
        guard let preview, preview.canPublish else { return }
        await run("publish") {
            try await self.api.publish(id: preview.id)
            try self.requireCurrentSession()
            // Dismiss a published preview immediately; a failed reload must
            // not present its former validated state as ready to publish.
            self.preview = nil
        }
    }

    func retry(_ job: TaxBoundaryImportJob) async {
        guard job.status == "FAILED", jobs.filter(\.isActive).count < 3 else { return }
        await run(job.id) {
            let retried = try await self.api.retry(id: job.id)
            try self.requireCurrentSession()
            self.merge(retried)
        }
    }

    private func run(_ key: String, action: () async throws -> Void) async {
        guard sessionIsCurrent(), !Task.isCancelled, busy == nil, !loading else { return }
        generation += 1
        busy = key
        errorMessage = nil
        defer { busy = nil }
        do {
            try await action()
            try requireCurrentSession()
            let next = try await api.datasets()
            try requireCurrentSession()
            datasets = next
        } catch {
            if !Task.isCancelled, sessionIsCurrent() { errorMessage = message(for: error) }
        }
    }

    private func merge(_ job: TaxBoundaryImportJob) {
        jobs = [job] + jobs.filter { $0.id != job.id }
    }

    private func refreshJobs() async {
        guard sessionIsCurrent(), !Task.isCancelled, busy == nil else { return }
        let generation = generation
        do {
            let next = try await api.jobs()
            guard sessionIsCurrent(), !Task.isCancelled, generation == self.generation else { return }
            let previouslyComplete = Set(jobs.filter { $0.status == "COMPLETE" }.map(\.id))
            let completed = next.contains { $0.status == "COMPLETE" && !previouslyComplete.contains($0.id) }
            jobs = next
            progressError = nil
            if completed {
                let updated = try await api.datasets()
                guard sessionIsCurrent(), !Task.isCancelled, generation == self.generation else { return }
                datasets = updated
            }
        } catch {
            if sessionIsCurrent(), !Task.isCancelled, generation == self.generation { progressError = message(for: error) }
        }
    }

    private func requireCurrentSession() throws {
        try Task.checkCancellation()
        guard sessionIsCurrent() else { throw CancellationError() }
    }

    private func message(for error: Error) -> String {
        (error as? TaxDataValidationError)?.key ?? error.localizedDescription
    }
}
