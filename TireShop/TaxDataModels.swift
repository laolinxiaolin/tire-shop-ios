import Foundation

struct TaxDataset: Decodable, Identifiable, Equatable {
    struct Coverage: Decodable, Equatable {
        let expectedGeneralJurisdictions: Int?
        let stagedGeneralJurisdictions: Int?
        let imported: Int?
        let skippedUnsupportedAddresses: Int?
        let skippedOutsidePeriod: Int?
        let unmapped: Int?
    }

    struct Artifact: Decodable, Equatable {
        let type: String?
        let filename: String?
        let sourceUrl: String?
        let sha256: String
        let fetchedAt: String?
        let createdAt: String?
    }

    struct Finding: Decodable, Identifiable, Equatable {
        let id: String
        let severity: String
        let code: String
        let message: String
    }

    struct Counts: Decodable, Equatable {
        let rates: Int?
        let boundaries: Int?
    }

    struct RateDifference: Decodable, Equatable {
        let code: String?
        let jurisdiction: String
        let oldRate: Double?
        let newRate: Double?
        let change: String
        let sourceRow: String?
    }

    let id: String
    let kind: String
    let label: String
    let status: String
    let effectiveFrom: String
    let effectiveTo: String
    let coverage: Coverage?
    let artifact: Artifact?
    let findings: [Finding]
    let counts: Counts?
    let diff: [RateDifference]?

    enum CodingKeys: String, CodingKey {
        case id, kind, label, status, effectiveFrom, effectiveTo, coverage, artifact, findings, diff
        case counts = "_count"
    }

    var canPublish: Bool {
        status == "VALIDATED" && !findings.contains { $0.severity == "ERROR" }
    }

    func isCurrent(at date: Date) -> Bool {
        guard kind == "RATE", status == "PUBLISHED",
              let from = AppFormat.date(effectiveFrom), let to = AppFormat.date(effectiveTo) else { return false }
        return from <= date && date < to
    }
}

struct TaxBoundaryImportJob: Decodable, Identifiable, Equatable {
    let id: String
    let status: String
    let filename: String
    let sourceVersion: String
    let effectiveFrom: String
    let effectiveTo: String
    let datasetId: String?
    let imported: Int
    let error: String?

    var isActive: Bool { status == "QUEUED" || status == "RUNNING" }
}

struct TaxImportPeriod: Equatable {
    let year: Int
    let quarter: Int

    var isValid: Bool { (2000...2100).contains(year) && (1...4).contains(quarter) }

    var effectiveFrom: String {
        String(format: "%04d-%02d-01", year, (quarter - 1) * 3 + 1)
    }

    var effectiveTo: String {
        quarter == 4 ? String(format: "%04d-01-01", year + 1)
            : String(format: "%04d-%02d-01", year, quarter * 3 + 1)
    }

    func fields(sourceVersion: String) throws -> [String: String] {
        guard isValid else { throw TaxDataValidationError(key: "taxData.sst.periodInvalid") }
        guard Self.isValidSourceVersion(sourceVersion) else {
            throw TaxDataValidationError(key: "taxData.sst.versionInvalid")
        }
        return ["sourceVersion": sourceVersion, "effectiveFrom": effectiveFrom, "effectiveTo": effectiveTo]
    }

    static func isValidSourceVersion(_ value: String) -> Bool {
        guard let match = value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$"#, options: .regularExpression) else { return false }
        return match == value.startIndex..<value.endIndex
    }
}

struct TaxDataValidationError: Error {
    let key: String
}

enum TaxImportKind {
    case rate
    case boundary

    func maximumBytes(filename: String) -> Int {
        if self == .rate { return 20 * 1_024 * 1_024 }
        return (URL(fileURLWithPath: filename).pathExtension.lowercased() == "zip" ? 64 : 512) * 1_024 * 1_024
    }

    func validate(filename: String, byteCount: Int) throws {
        guard byteCount > 0 else { throw TaxDataValidationError(key: "taxData.fileUnavailable") }
        let extensions = self == .rate ? ["pdf", "json"] : ["zip", "csv"]
        guard extensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased()),
              byteCount <= maximumBytes(filename: filename) else {
            throw TaxDataValidationError(key: self == .rate ? "taxData.fileLimit" : "taxData.sst.fileLimit")
        }
    }
}

final class TaxImportFile {
    let url: URL
    let filename: String
    let byteCount: Int

    init(url: URL, filename: String, byteCount: Int) {
        self.url = url
        self.filename = filename
        self.byteCount = byteCount
    }

    deinit { remove() }

    var mimeType: String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "zip": return "application/zip"
        default: return "text/csv"
        }
    }

    static func prepare(_ source: URL, kind: TaxImportKind) async throws -> TaxImportFile {
        let task = Task.detached(priority: .utility) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize else {
                throw TaxDataValidationError(key: "taxData.fileUnavailable")
            }
            let filename = source.lastPathComponent
            try kind.validate(filename: filename, byteCount: size)
            try Task.checkCancellation()
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("tax-import-\(UUID().uuidString).\(source.pathExtension)")
            do {
                // Large CSV files stay on disk through copying and multipart upload.
                try FileManager.default.copyItem(at: source, to: destination)
                try Task.checkCancellation()
                let copiedSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try kind.validate(filename: filename, byteCount: copiedSize)
                return TaxImportFile(url: destination, filename: filename, byteCount: copiedSize)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

struct TaxDataAPI {
    var client = APIClient.shared

    func datasets() async throws -> [TaxDataset] { try await client.request("/tax-data") }
    func jobs() async throws -> [TaxBoundaryImportJob] { try await client.request("/tax-data/boundary-imports") }
    func preview(id: String) async throws -> TaxDataset { try await client.request("/tax-data/\(id)/preview") }

    func check() async throws {
        let _: EmptyResponse = try await client.request("/tax-data/check", method: "POST", body: [String: String]())
    }

    func publish(id: String) async throws {
        let _: EmptyResponse = try await client.request("/tax-data/\(id)/publish", method: "POST", body: [String: String]())
    }

    func uploadRate(_ file: TaxImportFile) async throws {
        try TaxImportKind.rate.validate(filename: file.filename, byteCount: file.byteCount)
        let _: EmptyResponse = try await client.uploadMultipart(
            "/tax-data/upload", fileURL: file.url, fileName: file.filename, mimeType: file.mimeType,
            maximumFileBytes: TaxImportKind.rate.maximumBytes(filename: file.filename)
        )
    }

    func uploadBoundary(_ file: TaxImportFile, period: TaxImportPeriod, version: String) async throws -> TaxBoundaryImportJob {
        try TaxImportKind.boundary.validate(filename: file.filename, byteCount: file.byteCount)
        return try await client.uploadMultipart(
            "/tax-data/boundary-imports", fileURL: file.url, fileName: file.filename, mimeType: file.mimeType,
            fields: period.fields(sourceVersion: version),
            maximumFileBytes: TaxImportKind.boundary.maximumBytes(filename: file.filename)
        )
    }

    func retry(id: String) async throws -> TaxBoundaryImportJob {
        try await client.request("/tax-data/boundary-imports/\(id)/retry", method: "POST", body: [String: String]())
    }
}
