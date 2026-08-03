import SwiftUI
import UIKit
import QuickLook
import UniformTypeIdentifiers

/// A file reference suitable for driving a `.sheet(item:)` QuickLook preview.
final class PreviewFile: Identifiable {
    let id = UUID()
    let url: URL

    init(url: URL) {
        self.url = url
    }

    deinit {
        TemporaryDownloadStore.remove(url)
    }
}

struct PreparedCameraUpload: Sendable {
    let url: URL
    let filename: String
    let mimeType: String
}

struct CameraUploadPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let temporaryPrefix: String
    let fallbackFilenamePrefix: String
    let onPrepared: (Result<PreparedCameraUpload, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private struct SendableImage: @unchecked Sendable {
            let value: UIImage
        }

        private let parent: CameraUploadPicker

        init(parent: CameraUploadPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let sourceURL = info[.imageURL] as? URL {
                prepare(sourceURL)
                return
            }

            guard let image = info[.originalImage] as? UIImage else {
                finish(.failure(APIError(status: 0, message: "Could not read the captured photo.")))
                return
            }

            let sendableImage = SendableImage(value: image)
            let filename = "\(parent.fallbackFilenamePrefix) \(Int(Date().timeIntervalSince1970)).jpg"
            let temporaryPrefix = parent.temporaryPrefix

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result: Result<PreparedCameraUpload, Error>
                do {
                    guard let data = sendableImage.value.jpegData(compressionQuality: 0.92) else {
                        throw APIError(status: 0, message: "Could not encode the captured photo.")
                    }
                    let url = try UploadFilePreparation.writeTemporaryDataSynchronously(
                        data,
                        filename: filename,
                        prefix: temporaryPrefix
                    )
                    result = .success(PreparedCameraUpload(
                        url: url,
                        filename: filename,
                        mimeType: "image/jpeg"
                    ))
                } catch {
                    result = .failure(error)
                }

                DispatchQueue.main.async {
                    self?.finish(result)
                }
            }
        }

        private func prepare(_ sourceURL: URL) {
            let temporaryPrefix = parent.temporaryPrefix
            Task { [weak self] in
                let result: Result<PreparedCameraUpload, Error>
                do {
                    let copied = try await UploadFilePreparation.copySecurityScopedFile(
                        sourceURL,
                        prefix: temporaryPrefix
                    )
                    let type = UTType(filenameExtension: sourceURL.pathExtension)
                    result = .success(PreparedCameraUpload(
                        url: copied,
                        filename: sourceURL.lastPathComponent,
                        mimeType: type?.preferredMIMEType ?? "application/octet-stream"
                    ))
                } catch {
                    result = .failure(error)
                }
                self?.finish(result)
            }
        }

        private func finish(_ result: Result<PreparedCameraUpload, Error>) {
            parent.onPrepared(result)
            parent.dismiss()
        }
    }
}

/// Presents the system AirPrint sheet for a printable file (e.g. a PDF at a local URL).
enum DocumentPrinter {
    static func print(url: URL, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true) { _, _, _ in
            TemporaryDownloadStore.remove(url)
        }
    }
}

/// Shared QuickLook preview for local file URLs (PDFs, images, documents).
struct QuickLookSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url) {
            dismiss()
        }
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = QLPreviewController()
        previewController.dataSource = context.coordinator
        previewController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismissPreview)
        )
        return UINavigationController(rootViewController: previewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        private let onDismiss: () -> Void

        init(url: URL, onDismiss: @escaping () -> Void) {
            self.url = url
            self.onDismiss = onDismiss
        }

        @objc func dismissPreview() {
            onDismiss()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct LoadingView: View {
    let label: String

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView()
            Text(LocalizedStringKey(label))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct PrimaryButton: View {
    let title: String
    var loading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if loading {
                    ProgressView()
                        .tint(Theme.primaryText)
                }

                Text(LocalizedStringKey(title))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(disabled ? Theme.border : Theme.primary)
            .foregroundStyle(disabled ? Theme.muted : Theme.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .disabled(disabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.card)
                .foregroundStyle(Theme.text)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.border)
                )
        }
        .disabled(disabled)
    }
}

struct LanguageMenuButton: View {
    @EnvironmentObject private var i18n: I18nStore

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    i18n.setLanguage(language)
                } label: {
                    HStack {
                        Text(language.label)
                        if language == i18n.language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "globe")
                Text(i18n.language.shortLabel)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 38)
            .background(Theme.card)
            .overlay {
                Capsule().stroke(Theme.border)
            }
            .clipShape(Capsule())
        }
        .accessibilityLabel(i18n.t("profile.language"))
        .accessibilityValue(i18n.language.label)
    }
}

struct AppTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var secure = false
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(LocalizedStringKey(label))
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)

            if secure {
                SecureField(LocalizedStringKey(placeholder), text: $text)
                    .textContentType(textContentType)
                    .disabled(disabled)
                    .textFieldStyle(.plain)
                    .fieldChrome()
            } else {
                TextField(LocalizedStringKey(placeholder), text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(disabled)
                    .textFieldStyle(.plain)
                    .fieldChrome()
            }
        }
    }
}

struct AddressLookupFields: View {
    @Binding var postalCode: String
    @Binding var state: String
    @Binding var city: String
    @Binding var county: String

    @State private var lookupStatus: String?
    @State private var candidates: [ZipCandidate] = []
    @State private var pickingCounty = false

    var body: some View {
        Group {
            HStack {
                TextField("ZIP", text: $postalCode)
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                    .onChange(of: postalCode) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(5))
                        if digits != value {
                            postalCode = digits
                        }
                    }

                TextField("State", text: $state)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: state) { _, value in
                        state = String(value.uppercased().prefix(2))
                    }

                Button("Lookup") {
                    Task { await lookupZip() }
                }
                .disabled(postalCode.count != 5)
            }

            TextField("City", text: $city)
                .textInputAutocapitalization(.words)
            TextField("County", text: $county)
                .textInputAutocapitalization(.words)

            if let lookupStatus {
                Text(lookupStatus)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .confirmationDialog("Choose county", isPresented: $pickingCounty, titleVisibility: .visible) {
            ForEach(candidates) { candidate in
                Button("\(candidate.county) - \(candidate.city) (\(String(format: "%.1f", candidate.sharePct))%)") {
                    apply(candidate)
                }
            }
        } message: {
            Text("This ZIP crosses county lines. Pick the customer location.")
        }
    }

    @MainActor
    private func lookupZip() async {
        lookupStatus = "Looking up ZIP..."
        do {
            let result = try await ZipLocationsAPI().lookup(
                postalCode: postalCode,
                state: state.nilIfBlank ?? "GA"
            )
            candidates = result.candidates
            guard let first = result.candidates.first else {
                lookupStatus = "No match found. You can enter city and county manually."
                return
            }

            apply(first)
            lookupStatus = result.candidates.count > 1
                ? "ZIP has multiple county matches. Confirm the county."
                : "City and county filled from ZIP."
            if result.candidates.count > 1 {
                pickingCounty = true
            }
        } catch {
            lookupStatus = (error as? LocalizedError)?.errorDescription ?? "Could not look up ZIP."
        }
    }

    private func apply(_ candidate: ZipCandidate) {
        postalCode = candidate.postalCode
        state = candidate.state
        city = candidate.city
        county = candidate.county
    }
}

private extension View {
    func fieldChrome() -> some View {
        self
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 46)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

struct AvatarButton: View {
    let name: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(initials)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 30, height: 30)
                .background(Theme.primary)
                .foregroundStyle(Theme.primaryText)
                .clipShape(Circle())
        }
        .accessibilityLabel("Profile")
    }

    private var initials: String {
        guard let first = name?.first else { return "?" }
        return String(first).uppercased()
    }
}

struct PlaceholderScreen: View {
    let title: String
    var blurb: String?

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "iphone")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)

            Text(LocalizedStringKey(title))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Theme.text)

            Text(LocalizedStringKey(blurb ?? "Coming soon to mobile. This module is available on the web app today."))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct ModuleScreen: View {
    @EnvironmentObject private var i18n: I18nStore

    let destination: Destination

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Label(destination.localizedTitle(using: i18n), systemImage: destination.systemImage)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.text)

            Text("Native screen scaffold")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("This SwiftUI screen replaces the React Native route for \(destination.title). Connect its list, form, and detail API calls as each module is migrated.")
                .foregroundStyle(Theme.muted)
                .lineSpacing(3)

            Spacer()
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}

struct AsyncContentView<Value, Content: View>: View {
    let load: () async throws -> Value
    let content: (Value) -> Content

    @State private var value: Value?
    @State private var errorMessage: String?
    @State private var loading = false

    init(load: @escaping () async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if loading {
                LoadingView(label: "Loading...")
            } else if let errorMessage {
                VStack(spacing: Theme.Space.md) {
                    Text(errorMessage)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)

                    PrimaryButton(title: "Retry") {
                        Task { await refresh() }
                    }
                    .frame(maxWidth: 220)
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            } else {
                LoadingView(label: "Loading...")
            }
        }
        .task {
            if value == nil && !loading {
                await refresh()
            }
        }
        .refreshable {
            await refresh()
        }
    }

    @MainActor
    private func refresh() async {
        loading = true
        errorMessage = nil

        do {
            value = try await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }

        loading = false
    }
}

struct StatGrid: View {
    let stats: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: Theme.Space.md)], spacing: Theme.Space.md) {
            ForEach(stats, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(LocalizedStringKey(title))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.md)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.border)
                )
            }
        }
    }
}

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.headline)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowLine: View {
    let title: String
    let subtitle: String?
    let trailing: String?

    init(title: String, subtitle: String? = nil, trailing: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(LocalizedStringKey(title))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let trailing, !trailing.isEmpty {
                Text(LocalizedStringKey(trailing))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
