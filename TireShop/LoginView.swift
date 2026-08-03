import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var i18n: I18nStore

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: Challenge?
    @State private var busy = false
    @State private var alert: AlertState?
    @State private var serverURL = Server.baseURLString
    @FocusState private var focusedField: LoginField?

    private static let serverFieldID = "serverConfig"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    HStack {
                        Spacer()
                        LanguageMenuButton()
                    }

                    VStack(spacing: Theme.Space.xs) {
                        Text(i18n.t("app.name"))
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(Theme.text)

                        Text(i18n.t("login.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, Theme.Space.md)

                    if let challenge {
                        mfaForm(challenge)
                    } else {
                        credentialsForm
                        serverConfigSection
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, field in
                guard field == .server else { return }
                // The ScrollView's automatic keyboard avoidance handles most
                // cases; this makes sure the bottom-most field is fully
                // visible once the keyboard has animated in.
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation {
                        proxy.scrollTo(Self.serverFieldID, anchor: .bottom)
                    }
                }
            }
        }
        .background(Theme.background)
        .alert(item: $alert) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text(i18n.t("common.ok")))
            )
        }
    }

    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            AppTextField(
                label: i18n.t("login.serverField"),
                text: $serverURL,
                placeholder: Server.defaultBaseURLString,
                keyboardType: .URL,
                disabled: busy
            )
            .focused($focusedField, equals: .server)

            Text(i18n.t("login.serverNote", ["url": Server.defaultBaseURLString]))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, Theme.Space.lg)
        .id(Self.serverFieldID)
    }

    private var credentialsForm: some View {
        VStack(spacing: Theme.Space.md) {
            AppTextField(
                label: i18n.t("login.email"),
                text: $email,
                placeholder: "you@tireshop.local",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                disabled: busy
            )
            .focused($focusedField, equals: .email)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .password
            }

            AppTextField(
                label: i18n.t("login.password"),
                text: $password,
                placeholder: i18n.t("login.password"),
                textContentType: .password,
                secure: true,
                disabled: busy
            )
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit(submitCredentials)

            PrimaryButton(
                title: i18n.t("login.signIn"),
                loading: busy,
                disabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty,
                action: submitCredentials
            )
        }
    }

    private func mfaForm(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(mfaInstructions(for: challenge))
            .font(.subheadline)
            .foregroundStyle(Theme.muted)

            AppTextField(
                label: i18n.t("login.code"),
                text: $code,
                placeholder: "123456",
                keyboardType: .numberPad,
                textContentType: .oneTimeCode,
                disabled: busy
            )
            .focused($focusedField, equals: .code)

            PrimaryButton(
                title: i18n.t("login.verify"),
                loading: busy,
                disabled: code.trimmingCharacters(in: .whitespacesAndNewlines).count < 6,
                action: submitCode
            )

            SecondaryButton(title: i18n.t("common.back"), disabled: busy) {
                self.challenge = nil
                self.code = ""
            }
        }
    }

    private func submitCredentials() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }

        guard Server.setBaseURL(serverURL) else {
            alert = AlertState(
                title: i18n.t("login.invalidServerTitle"),
                message: i18n.t("login.invalidServerBody", ["url": Server.defaultBaseURLString])
            )
            return
        }
        serverURL = Server.baseURLString

        focusedField = nil
        busy = true
        Task {
            defer { busy = false }

            do {
                let result = try await auth.signIn(email: trimmedEmail, password: password)
                if case .mfa(let method, let challengeToken) = result {
                    challenge = Challenge(method: method, token: challengeToken)
                    code = ""
                }
            } catch {
                showFailure(error)
            }
        }
    }

    private func submitCode() {
        guard let challenge else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count >= 6 else { return }

        focusedField = nil
        busy = true
        Task {
            defer { busy = false }

            do {
                let result = try await auth.completeMFA(challengeToken: challenge.token, code: trimmedCode)
                if result.usedBackupCode == true {
                    alert = AlertState(
                        title: i18n.t("login.backupUsedTitle"),
                        message: i18n.t("login.backupUsedBody", [
                            "count": result.backupCodesRemaining ?? 0
                        ])
                    )
                }
            } catch {
                showFailure(error)
            }
        }
    }

    private func showFailure(_ error: Error) {
        alert = AlertState(
            title: i18n.t("login.failedTitle"),
            message: (error as? LocalizedError)?.errorDescription ?? i18n.t("login.failedBody")
        )
    }

    private func mfaInstructions(for challenge: Challenge) -> String {
        let methodKey = challenge.method == "EMAIL" ? "login.mfaEmailHint" : "login.mfaTotpHint"
        return "\(i18n.t(methodKey)) \(i18n.t("login.mfaBackupHint"))"
    }

    private struct Challenge: Equatable {
        let method: String
        let token: String
    }

    private enum LoginField: Hashable {
        case email
        case password
        case code
        case server
    }

    private struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}
