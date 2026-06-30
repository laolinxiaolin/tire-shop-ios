import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    enum SignInResult: Equatable {
        case ok
        case mfa(method: String, challengeToken: String)
    }

    private let userKey = "ts_user"
    private let api: APIClient

    @Published var ready = false
    @Published var user: SessionUser?

    init(api: APIClient = .shared) {
        self.api = api
        self.api.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.user = nil
                UserDefaults.standard.removeObject(forKey: self?.userKey ?? "ts_user")
            }
        }
    }

    func restore() {
        api.token = KeychainStore.loadToken()

        if
            api.token != nil,
            let data = UserDefaults.standard.data(forKey: userKey),
            let cached = try? JSONDecoder().decode(SessionUser.self, from: data)
        {
            user = cached
        }

        ready = true
    }

    func signIn(email: String, password: String) async throws -> SignInResult {
        let result = try await api.login(email: email, password: password)
        switch result {
        case .mfa(let challenge):
            return .mfa(method: challenge.method, challengeToken: challenge.challengeToken)
        case .session(let session):
            persist(token: session.accessToken, user: session.user)
            return .ok
        }
    }

    func completeMFA(challengeToken: String, code: String) async throws -> LoginSession {
        let session = try await api.verifyMFA(challengeToken: challengeToken, code: code)
        persist(token: session.accessToken, user: session.user)
        return session
    }

    func signOut() {
        api.token = nil
        KeychainStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: userKey)
        user = nil
    }

    func updateUser(_ patch: (inout SessionUser) -> Void) {
        guard var current = user else { return }
        patch(&current)
        user = current

        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    func has(_ permission: String) -> Bool {
        guard let user else { return false }
        return user.isAdmin || user.permissions.contains(permission)
    }

    func canActOrRequest(_ permission: String) -> Bool {
        guard let user else { return false }
        return user.isAdmin
            || user.permissions.contains(permission)
            || (user.approvalPermissions ?? []).contains(permission)
    }

    private func persist(token: String, user: SessionUser) {
        api.token = token
        KeychainStore.saveToken(token)
        self.user = user

        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }
}
