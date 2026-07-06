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
    @FocusState private var serverFieldFocused: Bool

    private static let serverFieldID = "serverConfig"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
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
            .onChange(of: serverFieldFocused) { _, focused in
                guard focused else { return }
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
            Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("OK")))
        }
    }

    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            AppTextField(
                label: "Server",
                text: $serverURL,
                placeholder: Server.defaultBaseURLString,
                keyboardType: .URL,
                disabled: busy
            )
            .focused($serverFieldFocused)

            Text("Leave as \(Server.defaultBaseURLString) unless your shop runs its own server.")
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

            AppTextField(
                label: i18n.t("login.password"),
                text: $password,
                placeholder: "Password",
                textContentType: .password,
                secure: true,
                disabled: busy
            )

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
            Text(challenge.method == "EMAIL"
                ? "Enter the 6-digit code we emailed you. You can also use a backup code."
                : "Enter the 6-digit code from your authenticator app. You can also use a backup code."
            )
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

            PrimaryButton(
                title: i18n.t("login.verify"),
                loading: busy,
                disabled: code.trimmingCharacters(in: .whitespacesAndNewlines).count < 6,
                action: submitCode
            )

            SecondaryButton(title: "Back", disabled: busy) {
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
                title: "Invalid server",
                message: "Enter a server like \(Server.defaultBaseURLString), or leave it blank for the default."
            )
            return
        }
        serverURL = Server.baseURLString

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

        busy = true
        Task {
            defer { busy = false }

            do {
                let result = try await auth.completeMFA(challengeToken: challenge.token, code: trimmedCode)
                if result.usedBackupCode == true {
                    alert = AlertState(
                        title: "Backup code used",
                        message: "You have \(result.backupCodesRemaining ?? 0) backup codes left. Regenerate them in the web app soon."
                    )
                }
            } catch {
                showFailure(error)
            }
        }
    }

    private func showFailure(_ error: Error) {
        alert = AlertState(
            title: "Sign-in failed",
            message: (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        )
    }

    private struct Challenge: Equatable {
        let method: String
        let token: String
    }

    private struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
}
