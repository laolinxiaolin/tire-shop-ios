import SwiftUI
import UniformTypeIdentifiers

struct TaxDataNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TaxDataStore()
    @State private var choosingRateFile = false
    @State private var choosingBoundaryFile = false

    private var isAdmin: Bool { auth.user?.isAdmin == true }
    private var disabled: Bool { store.busy != nil || store.loading }

    var body: some View {
        Group {
            if isAdmin {
                List {
                    summarySection
                    if let error = store.errorMessage {
                        Section {
                            Text(i18n.t(error)).foregroundStyle(Theme.danger)
                            Button(i18n.t("common.retry")) { Task { await store.refresh() } }
                                .disabled(disabled)
                        }
                    }
                    rateImportSection
                    boundaryImportSection
                    if !store.jobs.isEmpty || store.progressError != nil { jobsSection }
                    datasetsSection
                }
                .listStyle(.insetGrouped)
                .refreshable { await store.refresh() }
                .overlay {
                    if store.loading && store.datasets.isEmpty { ProgressView() }
                }
            } else {
                EmptyStateView(text: i18n.t("taxData.adminOnly"))
            }
        }
        .navigationTitle(i18n.t("taxData.title"))
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(disabled)
                }
            }
        }
        .task(id: isAdmin && scenePhase == .active) {
            guard isAdmin, scenePhase == .active else { return }
            store.bindSession(auth)
            await store.refresh()
            await store.pollActiveJobs()
        }
        .fileImporter(isPresented: $choosingRateFile, allowedContentTypes: [.pdf, .json], allowsMultipleSelection: false) { result in
            guard isAdmin else { return }
            Task { await store.selectFile(result, kind: .rate) }
        }
        .fileImporter(isPresented: $choosingBoundaryFile, allowedContentTypes: [.zip, .commaSeparatedText], allowsMultipleSelection: false) { result in
            guard isAdmin else { return }
            Task { await store.selectFile(result, kind: .boundary) }
        }
        .sheet(item: $store.preview) { dataset in
            TaxDatasetPreviewView(dataset: dataset, store: store)
        }
    }

    private var summarySection: some View {
        Section {
            Text(i18n.t("taxData.description"))
                .font(.subheadline).foregroundStyle(Theme.muted)
            LabeledContent(i18n.t("taxData.current"), value: store.currentDataset?.label ?? i18n.t("taxData.none"))
            LabeledContent(i18n.t("taxData.upcoming"), value: store.upcomingDataset?.label ?? i18n.t("taxData.none"))
            LabeledContent(i18n.t("taxData.lastCheck"), value: store.lastCheck.map(AppFormat.dateTime) ?? i18n.t("taxData.never"))
        }
    }

    private var rateImportSection: some View {
        Section(i18n.t("taxData.import")) {
            Text(i18n.t("taxData.reviewNotice")).font(.footnote).foregroundStyle(Theme.muted)
            Button {
                Task { await store.check() }
            } label: {
                Label(i18n.t(store.busy == "check" ? "taxData.checking" : "taxData.check"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(disabled)
            Button { choosingRateFile = true } label: {
                Label(i18n.t("taxData.file"), systemImage: "folder")
            }
            .disabled(disabled)
            Text(i18n.t("taxData.fileLimit")).font(.footnote).foregroundStyle(Theme.muted)
            if let file = store.rateFile {
                selectedFile(file)
                Button(i18n.t(store.busy == "rateUpload" ? "taxData.uploading" : "taxData.upload")) {
                    Task { await store.uploadRate() }
                }
                .disabled(disabled)
            }
        }
    }

    private var boundaryImportSection: some View {
        Section(i18n.t("taxData.sst.title")) {
            Text(i18n.t("taxData.sst.description")).font(.footnote).foregroundStyle(Theme.muted)
            if let url = URL(string: "https://www.streamlinedsalestax.org/ratesandboundry/Boundary/") {
                Link(i18n.t("taxData.sst.download"), destination: url)
            }
            Button { choosingBoundaryFile = true } label: {
                Label(i18n.t("taxData.sst.file"), systemImage: "folder")
            }
            .disabled(disabled)
            Text(i18n.t("taxData.sst.fileLimit")).font(.footnote).foregroundStyle(Theme.muted)
            if let file = store.boundaryFile { selectedFile(file) }
            TextField(i18n.t("taxData.sst.version"), text: $store.sourceVersion)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .disabled(disabled)
            if !store.sourceVersion.isEmpty && !TaxImportPeriod.isValidSourceVersion(store.sourceVersion) {
                Text(i18n.t("taxData.sst.versionInvalid")).font(.footnote).foregroundStyle(Theme.danger)
            }
            Stepper(value: $store.year, in: 2000...2100) {
                LabeledContent(i18n.t("taxData.sst.year"), value: String(store.year))
            }
            .disabled(disabled)
            Picker(i18n.t("taxData.sst.quarter"), selection: $store.quarter) {
                ForEach(1...4, id: \.self) { quarter in
                    Text(i18n.t("taxData.sst.q\(quarter)")).tag(quarter)
                }
            }
            .disabled(disabled)
            Text(i18n.t("taxData.sst.periodHelp")).font(.footnote).foregroundStyle(Theme.muted)
            Text("\(store.period.effectiveFrom) – \(store.period.effectiveTo)")
                .font(.caption).monospacedDigit()
            Button(i18n.t(store.busy == "boundaryUpload" ? "taxData.uploading" : "taxData.sst.import")) {
                Task { await store.uploadBoundary() }
            }
            .disabled(disabled || !store.canUploadBoundary)
            if store.busy == "boundaryUpload" {
                HStack {
                    ProgressView()
                    Text(i18n.t("taxData.sst.uploadHelp")).font(.footnote)
                }
            }
        }
    }

    private var jobsSection: some View {
        Section(i18n.t("taxData.sst.title")) {
            if let error = store.progressError {
                Text("\(i18n.t("taxData.sst.progressError")): \(i18n.t(error))")
                    .foregroundStyle(Theme.danger)
                Button(i18n.t("common.retry")) { Task { await store.refresh() } }
                    .disabled(disabled)
            }
            ForEach(store.jobs) { job in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(job.filename).font(.headline)
                    Text(i18n.t("taxData.sst.\(job.status)"))
                        .foregroundStyle(job.status == "FAILED" ? Theme.danger : Theme.muted)
                    Text("\(job.sourceVersion) · \(job.effectiveFrom) – \(job.effectiveTo)").font(.caption)
                    Text(i18n.t("taxData.sst.ranges", ["count": job.imported.formatted()])).font(.caption)
                    if let error = job.error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                    if job.isActive {
                        HStack {
                            ProgressView()
                            Text(i18n.t("taxData.sst.background")).font(.footnote)
                        }
                    }
                    if job.status == "FAILED" {
                        Button(i18n.t("taxData.sst.retry")) { Task { await store.retry(job) } }
                            .disabled(disabled || store.jobs.filter(\.isActive).count >= 3)
                    }
                    if job.status == "COMPLETE", let id = job.datasetId {
                        Button(i18n.t("taxData.preview")) { Task { await store.openPreview(id: id) } }
                            .disabled(disabled)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }

    private var datasetsSection: some View {
        Section(i18n.t("taxData.history")) {
            if store.datasets.isEmpty { Text(i18n.t("taxData.empty")).foregroundStyle(Theme.muted) }
            ForEach(store.datasets) { dataset in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(dataset.label).font(.headline)
                    TaxDatasetSummary(dataset: dataset)
                    Button(i18n.t("taxData.preview")) { Task { await store.openPreview(id: dataset.id) } }
                        .disabled(disabled)
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }

    private func selectedFile(_ file: TaxImportFile) -> some View {
        LabeledContent(file.filename, value: ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))
            .font(.subheadline)
    }
}

private struct TaxDatasetSummary: View {
    @EnvironmentObject private var i18n: I18nStore
    let dataset: TaxDataset

    var body: some View {
        LabeledContent(i18n.t("taxData.status"), value: dataset.status)
        LabeledContent(i18n.t("taxData.window"), value: "\(AppFormat.shortDate(dataset.effectiveFrom)) – \(AppFormat.shortDate(dataset.effectiveTo))")
        if dataset.kind == "BOUNDARY" {
            Text(i18n.t("taxData.sst.ranges", ["count": (dataset.coverage?.imported ?? 0).formatted()]))
        } else if let count = dataset.counts?.rates {
            LabeledContent(i18n.t("taxData.coverage"), value: "\(count) / \(dataset.coverage?.expectedGeneralJurisdictions.map(String.init) ?? "?")")
        }
        LabeledContent(i18n.t("taxData.issues"), value: "\(dataset.findings.filter { $0.severity == "ERROR" }.count) / \(dataset.findings.filter { $0.severity == "WARNING" }.count)")
    }
}

private struct TaxDatasetPreviewView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore
    let dataset: TaxDataset
    @ObservedObject var store: TaxDataStore

    var body: some View {
        NavigationStack {
            List {
                Section(dataset.label) {
                    TaxDatasetSummary(dataset: dataset)
                    if let filename = dataset.artifact?.filename { Text(filename).font(.caption) }
                    if let source = dataset.artifact?.sourceUrl, let url = URL(string: source), url.scheme == "https" {
                        Link(source, destination: url).font(.caption)
                    }
                    if let hash = dataset.artifact?.sha256 {
                        Text(hash).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                if let error = store.errorMessage {
                    Section { Text(i18n.t(error)).foregroundStyle(Theme.danger) }
                }
                if !dataset.findings.isEmpty {
                    Section(i18n.t("taxData.issues")) {
                        ForEach(dataset.findings) { finding in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(finding.code).font(.caption.monospaced())
                                Text(finding.message)
                            }
                            .foregroundStyle(finding.severity == "ERROR" ? Theme.danger : .orange)
                        }
                    }
                }
                if dataset.kind == "BOUNDARY" {
                    Section(i18n.t("taxData.coverage")) {
                        Text(i18n.t("taxData.sst.skipped", ["count": (dataset.coverage?.skippedOutsidePeriod ?? 0).formatted()]))
                        Text(i18n.t("taxData.sst.reviewHelp")).font(.footnote).foregroundStyle(Theme.muted)
                    }
                } else if let differences = dataset.diff {
                    Section(i18n.t("taxData.change")) {
                        ForEach(Array(differences.enumerated()), id: \.offset) { _, difference in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(difference.jurisdiction).font(.headline)
                                Text([difference.code, difference.change].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                LabeledContent(i18n.t("taxData.oldRate"), value: rate(difference.oldRate))
                                LabeledContent(i18n.t("taxData.newRate"), value: rate(difference.newRate))
                            }
                        }
                    }
                }
                if dataset.canPublish {
                    Section {
                        Text(i18n.t("taxData.reviewNotice")).font(.footnote).foregroundStyle(Theme.muted)
                        Button(i18n.t("taxData.publish")) { Task { await store.publishPreview() } }
                            .disabled(store.busy != nil || auth.user?.isAdmin != true)
                    }
                }
            }
            .navigationTitle(i18n.t("taxData.preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.close")) { store.preview = nil }.disabled(store.busy != nil)
                }
            }
            .interactiveDismissDisabled(store.busy != nil)
        }
    }

    private func rate(_ value: Double?) -> String {
        value.map { "\(SaleTaxPercentage.text(SaleTaxPercentage.fromFraction($0)))%" } ?? "—"
    }
}
