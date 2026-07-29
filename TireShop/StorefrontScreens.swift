import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum StorefrontVisibilityFilter: String, CaseIterable, Identifiable {
    case all
    case shown
    case hidden

    var id: String { rawValue }

    var apiValue: Bool? {
        switch self {
        case .all: return nil
        case .shown: return true
        case .hidden: return false
        }
    }
}

struct StorefrontManagementNativeView: View {
    @EnvironmentObject private var i18n: I18nStore

    @State private var q = ""
    @State private var visibility: StorefrontVisibilityFilter = .all
    @State private var items: [StorefrontSku] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var bulkSaving = false
    @State private var checkingLinks = false
    @State private var linkReport: SkuImageLinkReport?
    @State private var showingLinkReport = false

    var body: some View {
        VStack(spacing: 0) {
            controls

            Group {
                if loading && !loaded {
                    LoadingView(label: i18n.t("common.loading"))
                } else if let errorMessage, !loaded {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if loaded && items.isEmpty {
                    EmptyStateView(text: i18n.t("inventory.empty"))
                } else {
                    list
                }
            }
        }
        .background(Theme.background)
        .task {
            if !loaded { await load() }
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await checkLinks() }
                } label: {
                    if checkingLinks {
                        ProgressView()
                    } else {
                        Label(i18n.t("storefrontMgmt.checkLinks"), systemImage: "link.badge.plus")
                    }
                }
                .disabled(checkingLinks)

                Button(selecting ? i18n.t("common.done") : i18n.t("common.select")) {
                    selecting.toggle()
                    if !selecting {
                        selectedIDs.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar
            }
        }
        .sheet(isPresented: $showingLinkReport) {
            StorefrontLinkReportSheet(report: linkReport)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(i18n.t("storefrontMgmt.blurb"))
                .font(.caption)
                .foregroundStyle(Theme.muted)

            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField(i18n.t("inventory.search"), text: $q)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: q) { _, _ in scheduleSearch() }

                if !q.isEmpty {
                    Button {
                        q = ""
                        searchTask?.cancel()
                        Task { await load() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 42)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border)
            )

            Picker(i18n.t("storefrontMgmt.visible"), selection: $visibility) {
                Text(i18n.t("storefrontMgmt.filterAll")).tag(StorefrontVisibilityFilter.all)
                Text(i18n.t("storefrontMgmt.filterVisible")).tag(StorefrontVisibilityFilter.shown)
                Text(i18n.t("storefrontMgmt.filterHidden")).tag(StorefrontVisibilityFilter.hidden)
            }
            .pickerStyle(.segmented)
            .onChange(of: visibility) { _, _ in
                Task { await load() }
            }

            Text(i18n.t("storefrontMgmt.total", ["n": total]))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)
    }

    private var list: some View {
        List(items) { sku in
            if selecting {
                Button {
                    toggleSelection(sku.id)
                } label: {
                    HStack(spacing: Theme.Space.md) {
                        Image(systemName: selectedIDs.contains(sku.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedIDs.contains(sku.id) ? Theme.primary : Theme.muted)
                        StorefrontSkuRow(sku: sku)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    StorefrontSkuEditorNativeView(sku: sku) {
                        Task { await load() }
                    }
                } label: {
                    StorefrontSkuRow(sku: sku)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
    }

    private var selectionBar: some View {
        HStack(spacing: Theme.Space.sm) {
            Text(i18n.t("selection.nSelected", ["n": selectedIDs.count]))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: Theme.Space.xs)

            Button(i18n.t("storefrontMgmt.bulkShow")) {
                Task { await setVisibility(true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIDs.isEmpty || bulkSaving)

            Button(i18n.t("storefrontMgmt.bulkHide")) {
                Task { await setVisibility(false) }
            }
            .buttonStyle(.bordered)
            .disabled(selectedIDs.isEmpty || bulkSaving)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .background(.bar)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
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
    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let page = try await InventoryAPI().listStorefrontSkus(
                q: q.nilIfBlank,
                storefrontVisible: visibility.apiValue,
                page: 1,
                pageSize: 1000
            )
            items = page.items
            total = page.total
            selectedIDs.formIntersection(Set(page.items.map(\.id)))
            loaded = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load storefront products."
            loaded = !items.isEmpty
        }
    }

    @MainActor
    private func setVisibility(_ visible: Bool) async {
        guard !selectedIDs.isEmpty else { return }
        bulkSaving = true
        errorMessage = nil
        defer { bulkSaving = false }

        do {
            _ = try await InventoryAPI().setStorefrontVisibility(
                ids: selectedIDs.sorted(),
                visible: visible
            )
            selectedIDs.removeAll()
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not update storefront visibility."
        }
    }

    @MainActor
    private func checkLinks() async {
        checkingLinks = true
        errorMessage = nil
        defer { checkingLinks = false }

        do {
            linkReport = try await InventoryAPI().checkSkuImageLinks()
            showingLinkReport = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not check image links."
        }
    }
}

private struct StorefrontSkuRow: View {
    @EnvironmentObject private var i18n: I18nStore
    let sku: StorefrontSku

    private var description: String? {
        sku.descriptionEn?.nilIfBlank ?? sku.descriptionZh?.nilIfBlank
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sku.brand) \(sku.model)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                Text(AppFormat.money(sku.priceRetail))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            Text("\(sku.size) · \(sku.sku)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            HStack {
                Label(
                    sku.storefrontVisible
                        ? i18n.t("storefrontMgmt.shown")
                        : i18n.t("storefrontMgmt.hidden"),
                    systemImage: sku.storefrontVisible ? "eye.fill" : "eye.slash.fill"
                )
                .foregroundStyle(sku.storefrontVisible ? Theme.success : Theme.muted)

                Spacer()

                Text("\(sku.qtyOnHand) \(i18n.t("inventory.onHand"))")
                Text("·")
                Text("\(sku.imageCount.images) \(i18n.t("skuImages.action").lowercased())")
            }
            .font(.caption)

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .opacity(sku.storefrontVisible ? 1 : 0.65)
    }
}

private struct StorefrontSkuEditorNativeView: View {
    @EnvironmentObject private var i18n: I18nStore

    @State private var sku: StorefrontSku
    @State private var savingVisibility = false
    @State private var errorMessage: String?
    @State private var editingDescription = false
    @State private var editingImages = false

    let onChanged: () -> Void

    init(sku: StorefrontSku, onChanged: @escaping () -> Void) {
        _sku = State(initialValue: sku)
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            Section {
                RowLine(
                    title: "\(sku.brand) \(sku.model)",
                    subtitle: "\(sku.size) · \(sku.sku)",
                    trailing: AppFormat.money(sku.priceRetail)
                )
                RowLine(
                    title: i18n.t("storefrontMgmt.stock"),
                    trailing: sku.qtyOnHand.formatted()
                )
            }

            Section(i18n.t("storefrontMgmt.visible")) {
                Toggle(
                    sku.storefrontVisible
                        ? i18n.t("storefrontMgmt.shown")
                        : i18n.t("storefrontMgmt.hidden"),
                    isOn: Binding(
                        get: { sku.storefrontVisible },
                        set: { next in Task { await setVisibility(next) } }
                    )
                )
                .disabled(savingVisibility)
            }

            Section(i18n.t("storefrontMgmt.description")) {
                Text(sku.descriptionEn?.nilIfBlank ?? i18n.t("storefrontMgmt.noDescriptionEn"))
                    .foregroundStyle(sku.descriptionEn?.nilIfBlank == nil ? Theme.muted : Theme.text)
                Text(sku.descriptionZh?.nilIfBlank ?? i18n.t("storefrontMgmt.noDescriptionZh"))
                    .foregroundStyle(sku.descriptionZh?.nilIfBlank == nil ? Theme.muted : Theme.text)

                Button(i18n.t("storefrontMgmt.editDescription")) {
                    editingDescription = true
                }
            }

            Section {
                Button {
                    editingImages = true
                } label: {
                    Label(
                        "\(i18n.t("skuImages.action")) (\(sku.imageCount.images))",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle(i18n.t("storefrontMgmt.title"))
        .sheet(isPresented: $editingDescription) {
            StorefrontDescriptionSheet(sku: sku) { result in
                sku = StorefrontSku(
                    id: sku.id,
                    sku: sku.sku,
                    brand: sku.brand,
                    model: sku.model,
                    size: sku.size,
                    priceRetail: sku.priceRetail,
                    storefrontVisible: result.storefrontVisible,
                    descriptionEn: result.descriptionEn,
                    descriptionZh: result.descriptionZh,
                    inventory: sku.inventory,
                    imageCount: sku.imageCount
                )
                onChanged()
            }
        }
        .sheet(isPresented: $editingImages, onDismiss: onChanged) {
            SkuImagesManagementSheet(
                skuId: sku.id,
                skuLabel: "\(sku.brand) \(sku.model) · \(sku.size) · \(sku.sku)"
            )
        }
    }

    @MainActor
    private func setVisibility(_ visible: Bool) async {
        savingVisibility = true
        errorMessage = nil
        defer { savingVisibility = false }

        do {
            let result = try await InventoryAPI().updateStorefront(
                id: sku.id,
                body: StorefrontSkuPatchInput(storefrontVisible: visible)
            )
            sku = StorefrontSku(
                id: sku.id,
                sku: sku.sku,
                brand: sku.brand,
                model: sku.model,
                size: sku.size,
                priceRetail: sku.priceRetail,
                storefrontVisible: result.storefrontVisible,
                descriptionEn: result.descriptionEn,
                descriptionZh: result.descriptionZh,
                inventory: sku.inventory,
                imageCount: sku.imageCount
            )
            onChanged()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not update storefront visibility."
        }
    }
}

private struct StorefrontDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore

    let sku: StorefrontSku
    let onSaved: (StorefrontSkuPatchResult) -> Void

    @State private var descriptionEn: String
    @State private var descriptionZh: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(sku: StorefrontSku, onSaved: @escaping (StorefrontSkuPatchResult) -> Void) {
        self.sku = sku
        self.onSaved = onSaved
        _descriptionEn = State(initialValue: sku.descriptionEn ?? "")
        _descriptionZh = State(initialValue: sku.descriptionZh ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(i18n.t("storefrontMgmt.descriptionEn")) {
                    TextEditor(text: $descriptionEn)
                        .frame(minHeight: 120)
                }

                Section(i18n.t("storefrontMgmt.descriptionZh")) {
                    TextEditor(text: $descriptionZh)
                        .frame(minHeight: 120)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(i18n.t("storefrontMgmt.clearDescription"), role: .destructive) {
                        descriptionEn = ""
                        descriptionZh = ""
                        Task { await save() }
                    }
                    .disabled(saving || (sku.descriptionEn == nil && sku.descriptionZh == nil))
                }
            }
            .navigationTitle(i18n.t("storefrontMgmt.descriptionTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? i18n.t("common.saving") : i18n.t("common.save")) {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            let result = try await InventoryAPI().updateStorefront(
                id: sku.id,
                body: StorefrontSkuPatchInput(
                    descriptionEn: descriptionEn.nilIfBlank,
                    descriptionZh: descriptionZh.nilIfBlank
                )
            )
            onSaved(result)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not save the description."
        }
    }
}

private struct SkuImagesManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore

    let skuId: String
    let skuLabel: String

    @State private var images: [SkuImage] = []
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var linkURL = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var editingLink: SkuImage?
    @State private var deletingImage: SkuImage?

    var body: some View {
        let photoPickerTitle = busy
            ? i18n.t("skuImages.uploading")
            : i18n.t("skuImages.add")

        return NavigationStack {
            List {
                Section {
                    Text(skuLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if loading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if images.isEmpty {
                    Section {
                        Text(i18n.t("skuImages.none"))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Section(i18n.t("skuImages.title")) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            SkuImageManagementRow(
                                image: image,
                                isCover: index == 0,
                                canMoveEarlier: index > 0,
                                canMoveLater: index < images.count - 1,
                                busy: busy,
                                onMoveEarlier: { Task { await move(index: index, offset: -1) } },
                                onMoveLater: { Task { await move(index: index, offset: 1) } },
                                onEdit: { editingLink = image },
                                onDelete: { deletingImage = image }
                            )
                        }
                    }
                }

                Section {
                    TextField("https://…", text: $linkURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button(i18n.t("skuImages.addLink")) {
                        Task { await addLink() }
                    }
                    .disabled(linkURL.nilIfBlank == nil || busy)
                } footer: {
                    Text(i18n.t("skuImages.linkHint"))
                }

                Section {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label(
                            photoPickerTitle,
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .disabled(busy)
                } footer: {
                    Text(i18n.t("skuImages.uploadResizeHint"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle(i18n.t("skuImages.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t("common.close")) { dismiss() }
                }
            }
            .task {
                await load()
            }
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
            .sheet(item: $editingLink) { image in
                SkuImageLinkEditorSheet(image: image) {
                    await load()
                }
            }
            .alert(i18n.t("skuImages.deleteConfirm"), isPresented: Binding(
                get: { deletingImage != nil },
                set: { if !$0 { deletingImage = nil } }
            )) {
                Button(i18n.t("common.cancel"), role: .cancel) {
                    deletingImage = nil
                }
                Button(i18n.t("common.delete"), role: .destructive) {
                    guard let image = deletingImage else { return }
                    deletingImage = nil
                    Task { await remove(image) }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            images = try await InventoryAPI().listSkuImages(skuId: skuId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load product photos."
        }
    }

    @MainActor
    private func addLink() async {
        guard let url = linkURL.nilIfBlank else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            _ = try await InventoryAPI().addSkuImageLink(skuId: skuId, url: url)
            linkURL = ""
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? i18n.t("skuImages.linkError")
        }
    }

    @MainActor
    private func move(index: Int, offset: Int) async {
        let destination = index + offset
        guard images.indices.contains(index), images.indices.contains(destination) else { return }

        busy = true
        errorMessage = nil
        defer { busy = false }

        var reordered = images
        reordered.swapAt(index, destination)

        do {
            images = try await InventoryAPI().reorderSkuImages(
                skuId: skuId,
                ids: reordered.map(\.id)
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not reorder product photos."
            await load()
        }
    }

    @MainActor
    private func remove(_ image: SkuImage) async {
        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            _ = try await InventoryAPI().deleteSkuImage(imageId: image.id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? i18n.t("skuImages.deleteError")
        }
    }

    @MainActor
    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        errorMessage = nil
        defer {
            busy = false
            photoSelection = nil
        }

        do {
            guard let source = try await item.loadTransferable(type: Data.self) else {
                throw APIError(status: 0, message: "Could not read the selected image.")
            }
            let upload = try Self.prepareUpload(
                source,
                contentType: item.supportedContentTypes.first
            )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sku-\(UUID().uuidString).\(upload.fileExtension)")
            try upload.data.write(to: fileURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            _ = try await InventoryAPI().uploadSkuImage(
                skuId: skuId,
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                mimeType: upload.mimeType
            )
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? i18n.t("skuImages.uploadError")
        }
    }

    private struct PreparedUpload {
        let data: Data
        let fileExtension: String
        let mimeType: String
    }

    private static func prepareUpload(_ source: Data, contentType: UTType?) throws -> PreparedUpload {
        guard let image = UIImage(data: source) else {
            throw APIError(status: 0, message: "The selected file is not an image.")
        }

        let originalType = supportedType(contentType)
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 1600 else {
            if let originalType {
                return PreparedUpload(
                    data: source,
                    fileExtension: originalType.ext,
                    mimeType: originalType.mime
                )
            }
            guard let jpeg = image.jpegData(compressionQuality: 0.88) else {
                throw APIError(status: 0, message: "Could not prepare the selected image.")
            }
            return PreparedUpload(data: jpeg, fileExtension: "jpg", mimeType: "image/jpeg")
        }

        let scale = 1600 / longestSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.88) else {
            throw APIError(status: 0, message: "Could not resize the selected image.")
        }

        if jpeg.count < source.count {
            return PreparedUpload(data: jpeg, fileExtension: "jpg", mimeType: "image/jpeg")
        }
        if let originalType {
            return PreparedUpload(
                data: source,
                fileExtension: originalType.ext,
                mimeType: originalType.mime
            )
        }
        return PreparedUpload(data: jpeg, fileExtension: "jpg", mimeType: "image/jpeg")
    }

    private static func supportedType(_ type: UTType?) -> (ext: String, mime: String)? {
        guard let type else { return nil }
        if type.conforms(to: .jpeg) { return ("jpg", "image/jpeg") }
        if type.conforms(to: .png) { return ("png", "image/png") }
        if type.identifier == "org.webmproject.webp" { return ("webp", "image/webp") }
        if type.conforms(to: .heic) { return ("heic", "image/heic") }
        if type.identifier == "public.heif" { return ("heif", "image/heif") }
        return nil
    }
}

private struct SkuImageManagementRow: View {
    @EnvironmentObject private var i18n: I18nStore

    let image: SkuImage
    let isCover: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let busy: Bool
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            AsyncImage(url: image.displayURL) { phase in
                switch phase {
                case .success(let loaded):
                    loaded
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(Theme.muted)
                default:
                    ProgressView()
                }
            }
            .frame(width: 72, height: 72)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if isCover {
                    Label(i18n.t("skuImages.cover"), systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
                Text(
                    image.externalUrl == nil
                        ? i18n.t("skuImages.uploaded")
                        : i18n.t("skuImages.linkBadge")
                )
                    .font(.subheadline)
                if let externalUrl = image.externalUrl {
                    Text(externalUrl)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

            Spacer()

            Menu {
                Button(i18n.t("skuImages.moveEarlier"), action: onMoveEarlier)
                    .disabled(!canMoveEarlier || busy)
                Button(i18n.t("skuImages.moveLater"), action: onMoveLater)
                    .disabled(!canMoveLater || busy)
                if image.externalUrl != nil {
                    Button(i18n.t("skuImages.editLink"), action: onEdit)
                        .disabled(busy)
                }
                Button(i18n.t("common.delete"), role: .destructive, action: onDelete)
                    .disabled(busy)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
    }
}

private struct SkuImageLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore

    let image: SkuImage
    let onSaved: () async -> Void

    @State private var url: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(image: SkuImage, onSaved: @escaping () async -> Void) {
        self.image = image
        self.onSaved = onSaved
        _url = State(initialValue: image.externalUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://…", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(i18n.t("skuImages.editLinkTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.t("common.cancel")) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? i18n.t("common.saving") : i18n.t("common.save")) {
                        Task { await save() }
                    }
                    .disabled(url.nilIfBlank == nil || saving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let url = url.nilIfBlank else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }

        do {
            _ = try await InventoryAPI().updateSkuImageLink(imageId: image.id, url: url)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? i18n.t("skuImages.linkError")
        }
    }
}

private struct StorefrontLinkReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var i18n: I18nStore
    let report: SkuImageLinkReport?

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    if report.broken.isEmpty {
                        Section {
                            Label(
                                i18n.t("storefrontMgmt.linksAllOk", ["n": report.checked]),
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(Theme.success)
                        }
                    } else {
                        Section {
                            Text(i18n.t("storefrontMgmt.linksBroken", [
                                "broken": report.broken.count,
                                "n": report.checked
                            ]))
                            .foregroundStyle(Theme.danger)
                        }

                        Section {
                            ForEach(report.broken) { link in
                                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                    Text("\(link.sku.brand) \(link.sku.model) · \(link.sku.size)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(link.sku.sku)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.muted)
                                    Text(link.url)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.muted)
                                    Text(link.reason)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.danger)
                                }
                                .padding(.vertical, Theme.Space.xs)
                            }
                        }
                    }
                }
            }
            .navigationTitle(i18n.t("storefrontMgmt.checkLinks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(i18n.t("common.close")) { dismiss() }
                }
            }
        }
    }
}

private extension SkuImage {
    var displayURL: URL? {
        if let externalUrl {
            return URL(string: externalUrl)
        }
        var components = URLComponents(url: Server.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/sku-images/\(id)"
        components?.query = nil
        return components?.url
    }
}
