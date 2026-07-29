import SwiftUI

private enum StockAdjustEntryMode: String, CaseIterable, Identifiable {
    case delta
    case counted

    var id: String { rawValue }
}

private struct StockAdjustDraftLine: Identifiable {
    var sku: TireSku
    var value = ""
    var note = ""

    var id: String { sku.id }

    func onHand(at location: String) -> Int {
        sku.inventory.first { $0.location == location }?.qtyOnHand ?? 0
    }

    func delta(mode: StockAdjustEntryMode, location: String) -> Int {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        switch mode {
        case .delta:
            return number
        case .counted:
            return number - onHand(at: location)
        }
    }
}

struct StockAdjustBatchNativeView: View {
    @EnvironmentObject private var i18n: I18nStore

    let initialSkuIDs: [String]
    let initialLocation: String?

    @State private var warehouses: [Warehouse] = []
    @State private var location: String
    @State private var reason: StockAdjustReason = "ADJUSTMENT"
    @State private var mode: StockAdjustEntryMode = .delta
    @State private var batchNote = ""
    @State private var lines: [StockAdjustDraftLine] = []
    @State private var q = ""
    @State private var searchResults: [TireSku] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var loading = true
    @State private var searching = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var posted: StockAdjustBatchResult?
    @State private var submittedForApproval = false

    init(initialSkuIDs: [String] = [], initialLocation: String? = nil) {
        self.initialSkuIDs = initialSkuIDs
        self.initialLocation = initialLocation
        _location = State(initialValue: initialLocation ?? "")
    }

    private var changedLines: [(line: StockAdjustDraftLine, delta: Int)] {
        lines.compactMap { line in
            let delta = line.delta(mode: mode, location: location)
            return delta == 0 ? nil : (line, delta)
        }
    }

    private var totalDelta: Int {
        changedLines.reduce(0) { $0 + $1.delta }
    }

    private var shortLine: StockAdjustDraftLine? {
        changedLines.first {
            $0.line.onHand(at: location) + $0.delta < 0
        }?.line
    }

    var body: some View {
        Group {
            if loading {
                LoadingView(label: i18n.t("common.loading"))
            } else if let posted {
                postedView(posted)
            } else if submittedForApproval {
                approvalView
            } else {
                editor
            }
        }
        .navigationTitle(i18n.t("stockAdjust.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSetup()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StockAdjustmentsLogNativeView()
                } label: {
                    Label(i18n.t("stockAdjust.viewLog"), systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private var editor: some View {
        List {
            Section {
                Text(i18n.t("stockAdjust.description"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Section(i18n.t("stockAdjust.batch")) {
                if warehouses.isEmpty {
                    Text(i18n.t("stockAdjust.noWarehouses"))
                        .foregroundStyle(Theme.danger)
                } else {
                    Picker(i18n.t("inventory.warehouse"), selection: $location) {
                        ForEach(warehouses) { warehouse in
                            Text("\(warehouse.code) — \(warehouse.name)")
                                .tag(warehouse.code)
                        }
                    }
                }

                Picker(i18n.t("inventory.reason"), selection: $reason) {
                    Text(i18n.t("adjust.reason.ADJUSTMENT")).tag("ADJUSTMENT")
                    Text(i18n.t("adjust.reason.PURCHASE")).tag("PURCHASE")
                    Text(i18n.t("adjust.reason.RETURN")).tag("RETURN")
                }

                Picker(i18n.t("stockAdjust.entryMode"), selection: $mode) {
                    Text(i18n.t("stockAdjust.modeDelta")).tag(StockAdjustEntryMode.delta)
                    Text(i18n.t("stockAdjust.modeCount")).tag(StockAdjustEntryMode.counted)
                }
                .pickerStyle(.segmented)

                Text(
                    mode == .delta
                        ? i18n.t("stockAdjust.modeDeltaHint")
                        : i18n.t("stockAdjust.modeCountHint")
                )
                .font(.caption)
                .foregroundStyle(Theme.muted)

                TextField(
                    i18n.t("stockAdjust.batchNotePlaceholder"),
                    text: $batchNote,
                    axis: .vertical
                )
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.muted)
                    TextField(i18n.t("stockAdjust.addSku"), text: $q)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: q) { _, _ in scheduleSearch() }
                    if searching {
                        ProgressView()
                    }
                }

                ForEach(searchResults) { sku in
                    Button {
                        add(sku)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("\(sku.brand) \(sku.model) · \(sku.size)")
                                    .foregroundStyle(Theme.text)
                                Text(sku.sku)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(i18n.t("stockAdjust.atWarehouse", [
                                "n": onHand(sku, at: location),
                                "wh": location
                            ]))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .disabled(lines.contains { $0.id == sku.id })
                }
            } header: {
                Text(i18n.t("stockAdjust.addTires"))
            }

            Section {
                if lines.isEmpty {
                    Text(i18n.t("stockAdjust.noLines"))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach($lines) { $line in
                        StockAdjustDraftLineEditor(
                            line: $line,
                            mode: mode,
                            location: location,
                            onRemove: {
                                lines.removeAll { $0.id == line.id }
                            }
                        )
                    }
                }
            } header: {
                Text(i18n.t("stockAdjust.totals", ["n": changedLines.count]))
            } footer: {
                if let shortLine {
                    Text(i18n.t("stockAdjust.short", [
                        "sku": shortLine.sku.sku,
                        "wh": location
                    ]))
                    .foregroundStyle(Theme.danger)
                } else if !lines.isEmpty {
                    Text(i18n.t("stockAdjust.netChange", ["n": signed(totalDelta)]))
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if saving {
                            ProgressView()
                        } else {
                            Label(
                                i18n.t("stockAdjust.post", ["n": changedLines.count]),
                                systemImage: "checkmark.circle.fill"
                            )
                        }
                        Spacer()
                    }
                }
                .disabled(
                    saving
                        || changedLines.isEmpty
                        || shortLine != nil
                        || !warehouses.contains(where: { $0.code == location })
                )
            }
        }
    }

    private func postedView(_ result: StockAdjustBatchResult) -> some View {
        List {
            Section {
                Label(
                    i18n.t("stockAdjust.posted", [
                        "ref": result.ref,
                        "n": result.skus,
                        "wh": result.location
                    ]),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(Theme.success)
            }

            Section(result.ref) {
                ForEach(result.lines, id: \.skuId) { line in
                    RowLine(
                        title: line.sku ?? line.skuId,
                        subtitle: line.note,
                        trailing: "\(line.qtyBefore) → \(line.qtyAfter)"
                    )
                }
            }

            Section {
                Button(i18n.t("stockAdjust.another")) {
                    reset()
                }

                NavigationLink {
                    StockAdjustmentsLogNativeView()
                } label: {
                    Label(i18n.t("stockAdjust.viewLog"), systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private var approvalView: some View {
        List {
            Section {
                Label(
                    i18n.t("adjust.submittedForApproval"),
                    systemImage: "hourglass.circle.fill"
                )
                .foregroundStyle(Theme.primary)
                Text(i18n.t("adjust.approvalBody"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Section {
                Button(i18n.t("stockAdjust.another")) {
                    reset()
                }
            }
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func onHand(_ sku: TireSku, at location: String) -> Int {
        sku.inventory.first { $0.location == location }?.qtyOnHand ?? 0
    }

    private func add(_ sku: TireSku) {
        guard !lines.contains(where: { $0.id == sku.id }) else { return }
        lines.append(StockAdjustDraftLine(sku: sku))
        q = ""
        searchResults = []
        searchTask?.cancel()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard q.nilIfBlank != nil else {
            searchResults = []
            searching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    @MainActor
    private func loadSetup() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            warehouses = try await WarehousesAPI().list(activeOnly: true)
            location = initialLocation.flatMap { preferred in
                warehouses.first { $0.code == preferred }?.code
            } ?? warehouses.first(where: \.isDefault)?.code
                ?? warehouses.first?.code
                ?? ""

            if !initialSkuIDs.isEmpty {
                let page = try await InventoryAPI().listSkus(
                    ids: initialSkuIDs,
                    page: 1,
                    pageSize: 1000
                )
                lines = page.items.map { StockAdjustDraftLine(sku: $0) }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not prepare the stock adjustment."
        }
    }

    @MainActor
    private func search() async {
        guard let query = q.nilIfBlank else {
            searchResults = []
            return
        }
        searching = true
        defer { searching = false }

        do {
            let page = try await InventoryAPI().listSkus(q: query, page: 1, pageSize: 30)
            guard !Task.isCancelled else { return }
            searchResults = page.items
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    @MainActor
    private func submit() async {
        guard !changedLines.isEmpty, shortLine == nil else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let outcome = try await InventoryAPI().adjustBatch(StockAdjustBatchInput(
                lines: changedLines.map {
                    StockAdjustBatchLineInput(
                        skuId: $0.line.sku.id,
                        delta: $0.delta,
                        note: $0.line.note.nilIfBlank
                    )
                },
                reason: reason,
                location: location.nilIfBlank,
                note: batchNote.nilIfBlank
            ))

            switch outcome {
            case .immediate(let result):
                posted = result
            case .approval:
                submittedForApproval = true
            }
            lines = []
            batchNote = ""
            q = ""
            searchResults = []
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not post the stock adjustment."
        }
    }

    private func reset() {
        posted = nil
        submittedForApproval = false
        errorMessage = nil
        lines = []
        batchNote = ""
    }
}

private struct StockAdjustDraftLineEditor: View {
    @EnvironmentObject private var i18n: I18nStore
    @Binding var line: StockAdjustDraftLine
    let mode: StockAdjustEntryMode
    let location: String
    let onRemove: () -> Void

    private var onHand: Int {
        line.onHand(at: location)
    }

    private var delta: Int {
        line.delta(mode: mode, location: location)
    }

    private var resulting: Int {
        onHand + delta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("\(line.sku.brand) \(line.sku.model) · \(line.sku.size)")
                        .font(.subheadline.weight(.semibold))
                    Text(line.sku.sku)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                LabeledContent(i18n.t("stockAdjust.onHand"), value: onHand.formatted())

                TextField(
                    mode == .delta
                        ? i18n.t("stockAdjust.change")
                        : i18n.t("stockAdjust.counted"),
                    text: $line.value
                )
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
            }

            HStack {
                Text(i18n.t("stockAdjust.newQty"))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(line.value.nilIfBlank == nil ? "—" : "\(resulting) (\(signed(delta)))")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(resulting < 0 ? Theme.danger : Theme.text)
            }

            TextField(
                i18n.t("stockAdjust.lineNotePlaceholder"),
                text: $line.note,
                axis: .vertical
            )
            .font(.subheadline)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

struct SkuHistoryNativeView: View {
    @EnvironmentObject private var i18n: I18nStore
    let skuId: String

    var body: some View {
        AsyncContentView(load: load) { history in
            List {
                Section {
                    RowLine(
                        title: "\(history.sku.brand) \(history.sku.model)",
                        subtitle: "\(history.sku.size) · \(history.sku.sku)",
                        trailing: "\(history.onHand) \(i18n.t("inventory.onHand"))"
                    )
                }

                if history.items.isEmpty {
                    Section {
                        Text(i18n.t("inventory.history.none"))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Section(i18n.t("inventory.history.movements")) {
                        ForEach(history.items) { movement in
                            movementRow(movement)
                        }
                    }
                }
            }
            .navigationTitle(i18n.t("inventory.history.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func movementRow(_ movement: SkuMovement) -> some View {
        if movement.refType == "stock-adjust-batch" {
            NavigationLink {
                StockAdjustmentsLogNativeView()
            } label: {
                SkuMovementRow(movement: movement, reason: reason(movement))
            }
        } else if let route = referenceRoute(movement) {
            NavigationLink(value: route) {
                SkuMovementRow(movement: movement, reason: reason(movement))
            }
        } else {
            SkuMovementRow(movement: movement, reason: reason(movement))
        }
    }

    private func load() async throws -> SkuHistory {
        try await InventoryAPI().skuHistory(id: skuId, page: 1, pageSize: 1000)
    }

    private func reason(_ movement: SkuMovement) -> String {
        let normalizedType = movement.refType?.replacingOccurrences(of: "reversal:", with: "") ?? ""
        if movement.reason == "RETURN", normalizedType == "sale-void" || normalizedType == "sale-reverse" {
            return i18n.t("adjust.reason.SALE_REVERSAL")
        }
        switch movement.reason {
        case "PURCHASE": return i18n.t("adjust.reason.PURCHASE")
        case "ADJUSTMENT": return i18n.t("adjust.reason.ADJUSTMENT")
        case "RETURN": return i18n.t("adjust.reason.RETURN")
        case "SALE": return i18n.t("adjust.reason.SALE")
        default: return movement.reason.capitalized
        }
    }

    private func referenceRoute(_ movement: SkuMovement) -> AppRoute? {
        guard
            let refType = movement.refType?.replacingOccurrences(of: "reversal:", with: ""),
            let rawId = movement.refId?.nilIfBlank
        else { return nil }

        let id = String(rawId.split(separator: ":").first ?? Substring(rawId))
        if refType.hasPrefix("sale") { return .saleDetail(id) }
        if refType == "Container" || refType.hasPrefix("container") { return .containerDetail(id) }
        if refType.hasPrefix("return") { return .returnDetail(id) }
        if refType == "inventory-count" { return .inventoryCountDetail(id) }
        return nil
    }
}

private struct SkuMovementRow: View {
    let movement: SkuMovement
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(reason)
                        .font(.subheadline.weight(.semibold))
                    if let reference = movement.refLabel?.nilIfBlank {
                        Text("· \(reference)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.primary)
                    }
                }

                Text(AppFormat.dateTime(movement.date))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if let note = movement.note?.nilIfBlank {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                if let user = movement.user?.nilIfBlank {
                    Text(user)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()
            DeltaText(value: movement.delta)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

struct StockAdjustmentsLogNativeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    @State private var q = ""
    @State private var location = ""
    @State private var warehouses: [Warehouse] = []
    @State private var items: [StockAdjustBatch] = []
    @State private var total = 0
    @State private var expandedRefs: Set<String> = []
    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if loading && !loaded {
                LoadingView(label: i18n.t("common.loading"))
            } else if let errorMessage, !loaded {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                list
            }
        }
        .navigationTitle(i18n.t("adjustLog.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loaded { await loadSetup() }
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .toolbar {
            if auth.canActOrRequest("inventory.adjust") {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        StockAdjustBatchNativeView()
                    } label: {
                        Label(i18n.t("inventory.stockAdjust"), systemImage: "plus.forwardslash.minus")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Text(i18n.t("adjustLog.description"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.muted)
                    TextField(i18n.t("adjustLog.search"), text: $q)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: q) { _, _ in scheduleSearch() }
                }

                if warehouses.count > 1 {
                    Picker(i18n.t("inventory.warehouse"), selection: $location) {
                        Text(i18n.t("inventory.allWarehouses")).tag("")
                        ForEach(warehouses) { warehouse in
                            Text("\(warehouse.code) — \(warehouse.name)")
                                .tag(warehouse.code)
                        }
                    }
                    .onChange(of: location) { _, _ in
                        Task { await load() }
                    }
                }

                Text(i18n.t("stockAdjust.batchCount", ["n": total]))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }

            if items.isEmpty && loaded {
                Section {
                    Text(i18n.t("adjustLog.empty"))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                ForEach(items) { batch in
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedRefs.contains(batch.ref) },
                                set: { expanded in
                                    if expanded {
                                        expandedRefs.insert(batch.ref)
                                    } else {
                                        expandedRefs.remove(batch.ref)
                                    }
                                }
                            )
                        ) {
                            ForEach(batch.lines) { line in
                                NavigationLink {
                                    SkuHistoryNativeView(skuId: line.skuId)
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                            Text("\(line.brand) \(line.model) · \(line.size)")
                                                .font(.subheadline.weight(.semibold))
                                            Text(line.sku)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(Theme.muted)
                                            if let note = line.note?.nilIfBlank {
                                                Text(note)
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.muted)
                                            }
                                        }
                                        Spacer()
                                        DeltaText(value: line.delta)
                                    }
                                }
                            }
                        } label: {
                            StockAdjustBatchSummary(batch: batch)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .refreshable { await load() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    @MainActor
    private func loadSetup() async {
        warehouses = (try? await WarehousesAPI().list(activeOnly: true)) ?? []
        await load()
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let page = try await InventoryAPI().listAdjustmentBatches(
                q: q.nilIfBlank,
                location: location.nilIfBlank,
                page: 1,
                pageSize: 1000
            )
            items = page.items
            total = page.total
            expandedRefs.formIntersection(Set(page.items.map(\.ref)))
            loaded = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load stock adjustments."
            loaded = !items.isEmpty
        }
    }
}

private struct StockAdjustBatchSummary: View {
    @EnvironmentObject private var i18n: I18nStore
    let batch: StockAdjustBatch

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(batch.ref)
                    .font(.subheadline.monospaced().weight(.semibold))
                Spacer()
                DeltaText(value: batch.totalDelta)
            }

            Text(AppFormat.dateTime(batch.at))
                .font(.caption)
                .foregroundStyle(Theme.muted)

            HStack {
                Text(batch.user ?? "—")
                Text("·")
                Text(batch.location ?? "—")
                Text("·")
                Text(reasonLabel(batch.reason))
                Spacer()
                Text(i18n.t("stockAdjust.tireCount", ["n": batch.skus]))
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func reasonLabel(_ reason: String?) -> String {
        guard let reason else { return "—" }
        return i18n.t("adjust.reason.\(reason)")
    }
}

private struct DeltaText: View {
    let value: Int

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(value > 0 ? Theme.success : value < 0 ? Theme.danger : Theme.muted)
    }
}
