import PhotosUI
import SwiftUI
import UIKit

private let settingsTimezones: [(value: String, label: String)] = [
    ("America/Los_Angeles", "Pacific - Los Angeles"),
    ("America/Denver", "Mountain - Denver"),
    ("America/Phoenix", "Mountain (no DST) - Phoenix"),
    ("America/Chicago", "Central - Chicago"),
    ("America/New_York", "Eastern - New York"),
    ("America/Anchorage", "Alaska - Anchorage"),
    ("Pacific/Honolulu", "Hawaii - Honolulu"),
    ("UTC", "UTC")
]

struct ShopSettingsNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    @State private var general: GeneralSettings?
    @State private var branding: BrandingSettings?
    @State private var mail: MailConfig?
    @State private var invoiceTemplate: InvoiceEmailTemplate?

    @State private var shopName = ""
    @State private var shopAddress = ""
    @State private var shopPhone = ""
    @State private var shopEmail = ""

    @State private var timezone = ""
    @State private var taxRatePercent = ""

    @State private var mailProvider = "smtp"
    @State private var mailHost = ""
    @State private var mailPort = "587"
    @State private var mailSecure = false
    @State private var mailUser = ""
    @State private var mailPassword = ""
    @State private var mailFrom = ""
    @State private var resendApiKey = ""
    @State private var testTo = ""

    @State private var invoiceSubject = ""
    @State private var invoiceBody = ""

    @State private var logoImage: UIImage?
    @State private var logoSelection: PhotosPickerItem?
    @State private var removeLogoPending = false

    @State private var savingBranding = false
    @State private var savingGeneral = false
    @State private var savingMail = false
    @State private var testingMail = false
    @State private var savingTemplate = false
    @State private var savingLogo = false

    private var canManage: Bool { auth.has("settings.manage") }

    var body: some View {
        Group {
            if loading && !loaded {
                LoadingView(label: "Loading...")
            } else if !loaded, let errorMessage {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                Form {
                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                    }

                    if let statusMessage {
                        Section {
                            Label(statusMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                                .font(.subheadline)
                        }
                    }

                    shopInfoSection
                    generalSection
                    mailSection
                    invoiceTemplateSection
                    logoSection
                }
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
        .onChange(of: logoSelection) { _, item in
            guard let item else { return }
            Task { await uploadLogo(item) }
        }
        .alert("Remove logo?", isPresented: $removeLogoPending) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await deleteLogo() }
            }
        } message: {
            Text("Invoices will use the shop name instead.")
        }
    }

    private var shopInfoSection: some View {
        Section("Shop Info") {
            TextField("Shop name", text: $shopName)
                .disabled(!canManage || savingBranding)
            TextField("Address", text: $shopAddress, axis: .vertical)
                .lineLimit(1...3)
                .disabled(!canManage || savingBranding)
            TextField("Phone", text: $shopPhone)
                .keyboardType(.phonePad)
                .disabled(!canManage || savingBranding)
            TextField("Email", text: $shopEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!canManage || savingBranding)

            Button {
                Task { await saveBranding() }
            } label: {
                Label(savingBranding ? "Saving..." : "Save shop info", systemImage: "building.2")
            }
            .disabled(!canManage || savingBranding)
        }
    }

    private var generalSection: some View {
        Section {
            Picker("Timezone", selection: $timezone) {
                if !timezone.isEmpty, !settingsTimezones.contains(where: { $0.value == timezone }) {
                    Text(timezone).tag(timezone)
                }
                ForEach(settingsTimezones, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .disabled(!canManage || savingGeneral)

            HStack {
                TextField("Default tax rate", text: $taxRatePercent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .disabled(!canManage || savingGeneral)
                Text("%").foregroundStyle(Theme.muted)
            }

            Button {
                Task { await saveGeneral() }
            } label: {
                Label(savingGeneral ? "Saving..." : "Save general settings", systemImage: "gearshape")
            }
            .disabled(!canManage || savingGeneral)
        } header: {
            Text("General")
        } footer: {
            Text("Tax is stored as a fraction on the server and pre-fills new sales.")
        }
    }

    private var mailSection: some View {
        Section {
            Picker("Provider", selection: $mailProvider) {
                Text("SMTP").tag("smtp")
                Text("Resend").tag("resend")
            }
            .pickerStyle(.segmented)
            .disabled(!canManage || savingMail)

            if mailProvider == "smtp" {
                TextField("SMTP host", text: $mailHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!canManage || savingMail)
                TextField("Port", text: $mailPort)
                    .keyboardType(.numberPad)
                    .disabled(!canManage || savingMail)
                Toggle("TLS/SSL", isOn: $mailSecure)
                    .disabled(!canManage || savingMail)
                TextField("Username", text: $mailUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!canManage || savingMail)
                SecureField(mail?.hasPassword == true ? "Password saved" : "Password", text: $mailPassword)
                    .textContentType(.newPassword)
                    .disabled(!canManage || savingMail)
            } else {
                SecureField(mail?.hasResendKey == true ? "Resend key saved" : "Resend API key", text: $resendApiKey)
                    .textContentType(.newPassword)
                    .disabled(!canManage || savingMail)
            }

            TextField("From address", text: $mailFrom)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!canManage || savingMail)

            if let fromName = mail?.fromName.nilIfBlank {
                LabeledContent("Display name", value: fromName)
            }

            Button {
                Task { await saveMail() }
            } label: {
                Label(savingMail ? "Saving..." : "Save email server", systemImage: "envelope")
            }
            .disabled(!canManage || savingMail)

            HStack {
                TextField("Test recipient", text: $testTo)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!canManage || testingMail)
                Button {
                    Task { await sendTestMail() }
                } label: {
                    Label(testingMail ? "Sending..." : "Send", systemImage: "paperplane")
                }
                .disabled(!canManage || testingMail || testTo.nilIfBlank == nil)
            }
        } header: {
            Text("Email Server")
        } footer: {
            Text("Secrets are only replaced when you type a new value.")
        }
    }

    private var invoiceTemplateSection: some View {
        Section("Invoice Email Template") {
            TextField("Subject", text: $invoiceSubject)
                .disabled(!canManage || savingTemplate)
            TextEditor(text: $invoiceBody)
                .frame(minHeight: 150)
                .font(.system(.body, design: .monospaced))
                .disabled(!canManage || savingTemplate)

            if let placeholders = invoiceTemplate?.placeholders, !placeholders.isEmpty {
                Text("Placeholders: \(placeholders.map { "{{\($0)}}" }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Button {
                Task { await saveInvoiceTemplate() }
            } label: {
                Label(savingTemplate ? "Saving..." : "Save template", systemImage: "doc.text")
            }
            .disabled(!canManage || savingTemplate)
        }
    }

    private var logoSection: some View {
        Section {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 96)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.xs)
            } else if branding?.hasLogo == true {
                Label("Logo is set.", systemImage: "photo")
                    .foregroundStyle(Theme.muted)
            } else {
                Text("No logo uploaded.")
                    .foregroundStyle(Theme.muted)
            }

            if let size = branding?.logo?.size {
                LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }

            PhotosPicker(selection: $logoSelection, matching: .images) {
                Label(savingLogo ? "Uploading..." : (branding?.hasLogo == true ? "Replace logo" : "Upload logo"), systemImage: "photo.badge.plus")
            }
            .disabled(!canManage || savingLogo)

            if branding?.hasLogo == true {
                Button(role: .destructive) {
                    removeLogoPending = true
                } label: {
                    Label("Remove logo", systemImage: "trash")
                }
                .disabled(!canManage || savingLogo)
            }
        } header: {
            Text("Logo")
        } footer: {
            Text("PNG or JPEG under 2 MB. The app converts selected photos to JPEG before upload.")
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        statusMessage = nil

        do {
            async let generalTask = SettingsAPI().general()
            async let brandingTask = SettingsAPI().branding()
            async let mailTask = SettingsAPI().mail()
            async let templateTask = SettingsAPI().invoiceTemplate()

            let loadedGeneral = try await generalTask
            let loadedBranding = try await brandingTask
            let loadedMail = try await mailTask
            let loadedTemplate = try await templateTask

            apply(
                general: loadedGeneral,
                branding: loadedBranding,
                mail: loadedMail,
                template: loadedTemplate
            )

            if loadedBranding.hasLogo, let data = try? await SettingsAPI().logoData() {
                logoImage = UIImage(data: data)
            } else {
                logoImage = nil
            }

            loaded = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load shop settings."
        }

        loading = false
    }

    @MainActor
    private func apply(
        general: GeneralSettings,
        branding: BrandingSettings,
        mail: MailConfig,
        template: InvoiceEmailTemplate
    ) {
        self.general = general
        self.branding = branding
        self.mail = mail
        self.invoiceTemplate = template

        shopName = branding.shopName ?? ""
        shopAddress = branding.shopAddress ?? ""
        shopPhone = branding.shopPhone ?? ""
        shopEmail = branding.shopEmail ?? ""

        timezone = general.timezone
        taxRatePercent = Self.taxPercentText(general.defaultTaxRate)

        mailProvider = mail.provider ?? "smtp"
        mailHost = mail.host
        mailPort = "\(mail.port)"
        mailSecure = mail.secure
        mailUser = mail.user
        mailPassword = ""
        mailFrom = mail.from
        resendApiKey = ""

        invoiceSubject = template.subject
        invoiceBody = template.body
    }

    @MainActor
    private func saveBranding() async {
        savingBranding = true
        clearMessages()

        do {
            branding = try await SettingsAPI().updateBranding(BrandingPatchInput(
                shopName: shopName,
                shopAddress: shopAddress,
                shopPhone: shopPhone,
                shopEmail: shopEmail
            ))
            statusMessage = "Shop info saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save shop info."
        }

        savingBranding = false
    }

    @MainActor
    private func saveGeneral() async {
        savingGeneral = true
        clearMessages()

        do {
            guard timezone.nilIfBlank != nil else {
                throw APIError(status: 0, message: "Timezone is required.")
            }
            let cleaned = taxRatePercent.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let percent = Double(cleaned), percent >= 0, percent <= 100 else {
                throw APIError(status: 0, message: "Enter a tax rate between 0 and 100%.")
            }
            let fraction = ((percent / 100) * 10000).rounded() / 10000
            let updated = try await SettingsAPI().updateGeneral(GeneralPatchInput(
                timezone: timezone,
                defaultTaxRate: fraction
            ))
            general = updated
            timezone = updated.timezone
            taxRatePercent = Self.taxPercentText(updated.defaultTaxRate)
            statusMessage = "General settings saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save general settings."
        }

        savingGeneral = false
    }

    @MainActor
    private func saveMail() async {
        savingMail = true
        clearMessages()

        do {
            guard mailProvider == "smtp" || mailProvider == "resend" else {
                throw APIError(status: 0, message: "Choose a mail provider.")
            }
            let port: Int?
            if let value = mailPort.nilIfBlank {
                guard let parsed = Int(value), (1...65535).contains(parsed) else {
                    throw APIError(status: 0, message: "Port must be between 1 and 65535.")
                }
                port = parsed
            } else {
                port = mailProvider == "smtp" ? 587 : nil
            }

            mail = try await SettingsAPI().updateMail(MailPatchInput(
                provider: mailProvider,
                host: mailHost,
                port: port,
                secure: mailSecure,
                user: mailUser,
                password: mailProvider == "smtp" ? mailPassword.nilIfBlank : nil,
                from: mailFrom,
                resendApiKey: mailProvider == "resend" ? resendApiKey.nilIfBlank : nil
            ))
            if let mail {
                mailProvider = mail.provider ?? mailProvider
                mailHost = mail.host
                mailPort = "\(mail.port)"
                mailSecure = mail.secure
                mailUser = mail.user
                mailFrom = mail.from
            }
            mailPassword = ""
            resendApiKey = ""
            statusMessage = "Email server saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save email server."
        }

        savingMail = false
    }

    @MainActor
    private func sendTestMail() async {
        testingMail = true
        clearMessages()

        do {
            guard let recipient = testTo.nilIfBlank else {
                throw APIError(status: 0, message: "Enter a test recipient.")
            }
            _ = try await SettingsAPI().testMail(to: recipient)
            statusMessage = "Test email sent to \(recipient)."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not send the test email."
        }

        testingMail = false
    }

    @MainActor
    private func saveInvoiceTemplate() async {
        savingTemplate = true
        clearMessages()

        do {
            invoiceTemplate = try await SettingsAPI().updateInvoiceTemplate(InvoiceTemplatePatchInput(
                subject: invoiceSubject,
                body: invoiceBody
            ))
            if let invoiceTemplate {
                invoiceSubject = invoiceTemplate.subject
                invoiceBody = invoiceTemplate.body
            }
            statusMessage = "Invoice template saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the invoice template."
        }

        savingTemplate = false
    }

    @MainActor
    private func uploadLogo(_ item: PhotosPickerItem) async {
        savingLogo = true
        clearMessages()

        var tempURL: URL?
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw APIError(status: 0, message: "Could not read the selected image.")
            }
            let url = try Self.logoUploadFile(from: data)
            tempURL = url
            _ = try await SettingsAPI().uploadLogo(fileURL: url, fileName: url.lastPathComponent, mimeType: "image/jpeg")
            branding = try await SettingsAPI().branding()
            if let data = try? await SettingsAPI().logoData() {
                logoImage = UIImage(data: data)
            }
            statusMessage = "Logo uploaded."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not upload the logo."
        }

        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        logoSelection = nil
        savingLogo = false
    }

    @MainActor
    private func deleteLogo() async {
        savingLogo = true
        clearMessages()

        do {
            _ = try await SettingsAPI().deleteLogo()
            branding = try await SettingsAPI().branding()
            logoImage = nil
            statusMessage = "Logo removed."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not remove the logo."
        }

        savingLogo = false
    }

    private func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private static func taxPercentText(_ fraction: Double) -> String {
        let text = String(format: "%.4f", fraction * 100)
        return text
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func logoUploadFile(from source: Data) throws -> URL {
        guard let image = UIImage(data: source) else {
            throw APIError(status: 0, message: "Logo must be an image.")
        }

        var quality: CGFloat = 0.9
        var payload = image.jpegData(compressionQuality: quality)
        while let current = payload, current.count > 1_950_000, quality > 0.3 {
            quality -= 0.15
            payload = image.jpegData(compressionQuality: quality)
        }

        guard let payload else {
            throw APIError(status: 0, message: "Could not prepare the logo image.")
        }
        guard payload.count <= 2_000_000 else {
            throw APIError(status: 0, message: "Logo exceeds 2 MB.")
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-logo-\(UUID().uuidString).jpg")
        try payload.write(to: url)
        return url
    }
}
