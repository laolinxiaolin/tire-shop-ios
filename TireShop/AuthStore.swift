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
    @Published var user: SessionUser? {
        didSet {
            permissionSet = Set(user?.permissions ?? [])
            approvalPermissionSet = Set(user?.approvalPermissions ?? [])
        }
    }

    private var permissionSet: Set<String> = []
    private var approvalPermissionSet: Set<String> = []

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
        // The API currently has no read-only endpoint that returns the signed-in
        // user with freshly evaluated role permissions. Reusing the cached user
        // here would make old permissions an authorization source indefinitely.
        // Keep sessions in memory, but require fresh credentials after a cold
        // launch until the server provides a session-refresh contract.
        api.token = nil
        KeychainStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: userKey)
        user = nil
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
    }

    func has(_ permission: String) -> Bool {
        guard let user else { return false }
        return user.isAdmin || permissionSet.contains(permission)
    }

    func canActOrRequest(_ permission: String) -> Bool {
        guard let user else { return false }
        return user.isAdmin
            || permissionSet.contains(permission)
            || approvalPermissionSet.contains(permission)
    }

    private func persist(token: String, user: SessionUser) {
        api.token = token
        self.user = user
    }
}
