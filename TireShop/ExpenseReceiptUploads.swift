import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The creation endpoint returns the new expense, without the receipt count
/// included by the history endpoint. Keep its ID for subsequent attachments.
struct ExpenseCreateResponse: Decodable {
    let id: String
}

/// Owns the copied upload until it is uploaded, removed, or its form closes.
final class DocumentUploadDraft: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let mimeType: String

    init(url: URL, filename: String, mimeType: String) {
        self.url = url
        self.filename = filename
        self.mimeType = mimeType
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A receipt upload can fail after the expense has already posted. Preserve
/// that expense ID and only the remaining receipts for a safe retry.
@MainActor
final class ExpenseReceiptSubmission: ObservableObject {
    @Published var pendingReceipts: [DocumentUploadDraft] = []
    @Published private(set) var createdExpenseId: String?
    @Published private(set) var saving = false

    func submit(
        create: () async throws -> ExpenseCreateResponse,
        upload: (String, DocumentUploadDraft) async throws -> Void
    ) async throws {
        guard !saving else { return }
        saving = true
        defer { saving = false }

        if createdExpenseId == nil {
            createdExpenseId = try await create().id
        }
        guard let createdExpenseId else { return }
        while let receipt = pendingReceipts.first {
            try Task.checkCancellation()
            try await upload(createdExpenseId, receipt)
            pendingReceipts.removeAll { $0.id == receipt.id }
        }
    }
}

/// Shared by expense receipts and payment-application documents and proof.
/// PhotosPicker grants access only to the selected photo, without requesting
/// permission to read the user's entire photo library.
struct DocumentUploadSourcePicker: View {
    let disabled: Bool
    @Binding var preparing: Bool
    let onPrepared: (DocumentUploadDraft) -> Void
    let onError: (String) -> Void
    var titleKey = "expenseReceipt.add"
    var filenamePrefix = "Expense receipt"
    var allowedContentTypes: [UTType] = [.pdf, .jpeg, .png, .webP, .heic, .heif]

    @EnvironmentObject private var i18n: I18nStore
    @Environment(\.openURL) private var openURL
    @State private var choosingSource = false
    @State private var importing = false
    @State private var selectingPhoto = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var capturingPhoto = false
    @State private var showingCameraPermission = false

    var body: some View {
        Button {
            choosingSource = true
        } label: {
            Label(
                i18n.t(preparing ? "documentUpload.preparing" : titleKey),
                systemImage: "paperclip"
            )
        }
        .disabled(disabled || preparing)
        .confirmationDialog(
            i18n.t(titleKey),
            isPresented: $choosingSource,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    Task { await openCamera() }
                } label: {
                    Label(i18n.t("expenseReceipt.camera"), systemImage: "camera")
                }
            }
            Button {
                selectingPhoto = true
            } label: {
                Label(i18n.t("expenseReceipt.photos"), systemImage: "photo.on.rectangle")
            }
            Button {
                importing = true
            } label: {
                Label(i18n.t("expenseReceipt.files"), systemImage: "folder")
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await prepareFile(result) }
        }
        .photosPicker(
            isPresented: $selectingPhoto,
            selection: $photoSelection,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await preparePhoto(item) }
        }
        .fullScreenCover(isPresented: $capturingPhoto) {
            CameraUploadPicker(
                temporaryPrefix: "document-camera",
                fallbackFilenamePrefix: filenamePrefix
            ) { result in
                switch result {
                case .success(let capture):
                    onPrepared(DocumentUploadDraft(
                        url: capture.url,
                        filename: capture.filename,
                        mimeType: capture.mimeType
                    ))
                case .failure(let error):
                    report(error)
                }
            }
            .ignoresSafeArea()
        }
        .alert(i18n.t("expenseReceipt.cameraPermissionTitle"), isPresented: $showingCameraPermission) {
            Button(i18n.t("common.cancel"), role: .cancel) {}
            Button(i18n.t("expenseReceipt.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } message: {
            Text(i18n.t("documentUpload.cameraPermissionMessage"))
        }
    }

    @MainActor
    private func openCamera() async {
        guard !disabled, !preparing else { return }
        preparing = true
        defer { preparing = false }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        if authorized {
            capturingPhoto = true
        } else {
            showingCameraPermission = true
        }
    }

    @MainActor
    private func prepareFile(_ result: Result<[URL], Error>) async {
        guard !disabled, !preparing else { return }
        preparing = true
        defer { preparing = false }
        do {
            guard let source = try result.get().first else { return }
            let copied = try await UploadFilePreparation.copySecurityScopedFile(
                source,
                prefix: "expense-receipt"
            )
            onPrepared(DocumentUploadDraft(
                url: copied,
                filename: source.lastPathComponent,
                mimeType: UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
            ))
        } catch {
            if (error as NSError).code != NSUserCancelledError { report(error) }
        }
    }

    @MainActor
    private func preparePhoto(_ item: PhotosPickerItem) async {
        guard !disabled, !preparing else { return }
        preparing = true
        defer {
            photoSelection = nil
            preparing = false
        }
        do {
            guard let photo = try await item.loadTransferable(type: UploadPhotoFile.self) else {
                throw APIError(status: 0, message: i18n.t("expenseReceipt.photoReadFailed"))
            }
            // Prefer the transferred file's type: the picker can advertise
            // several representations, including one it did not transfer.
            let type = UTType(filenameExtension: photo.url.pathExtension)
                ?? item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
                ?? .jpeg
            let filename = "\(filenamePrefix) \(Int(Date().timeIntervalSince1970)).\(type.preferredFilenameExtension ?? "jpg")"
            onPrepared(DocumentUploadDraft(
                url: photo.url,
                filename: filename,
                mimeType: type.preferredMIMEType ?? "application/octet-stream"
            ))
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        onError((error as? LocalizedError)?.errorDescription ?? i18n.t("documentUpload.prepareFailed"))
    }
}
