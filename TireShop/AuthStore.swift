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
    private let storage: SessionStorage
    private var sessionRevision = UUID()
    private var installedToken: String?
    private var restoring = false

    @Published var ready = false
    @Published private(set) var restoreError: String?
    @Published var user: SessionUser? {
        didSet {
            permissionSet = Set(user?.permissions ?? [])
            approvalPermissionSet = Set(user?.approvalPermissions ?? [])
        }
    }

    private var permissionSet: Set<String> = []
    private var approvalPermissionSet: Set<String> = []

    init(api: APIClient = .shared, storage: SessionStorage = KeychainSessionStorage()) {
        self.api = api
        self.storage = storage
        self.api.onUnauthorized = { [weak self] rejectedToken in
            Task { @MainActor in
                // A delayed response from an earlier login must not erase a
                // newer session or its saved credential.
                guard let self, self.api.token == nil, self.installedToken == rejectedToken else { return }
                self.signOut()
            }
        }
    }

    func restore() async {
        guard !ready, !restoring else { return }
        restoring = true
        defer { restoring = false }
        restoreError = nil
        clearLegacySession()
        let revision = sessionRevision

        let saved: SavedSession
        do {
            guard let session = try storage.load() else {
                ready = true
                return
            }
            // Never send a credential to a different server, or trust cached
            // user permissions. Only the token and its origin are persisted.
            guard session.serverURL == Server.baseURL.absoluteString, !session.token.isEmpty else {
                try storage.clear()
                ready = true
                return
            }
            saved = session
        } catch {
            restoreError = "login.savedSessionUnavailable"
            return
        }

        installedToken = saved.token
        api.token = saved.token
        do {
            let currentUser = try await api.currentSession()
            try Task.checkCancellation()
            guard sessionRevision == revision, api.token == saved.token else { return }
            guard Server.baseURL.absoluteString == saved.serverURL else {
                signOut()
                return
            }
            user = currentUser
            ready = true
        } catch {
            guard sessionRevision == revision else { return }
            api.token = nil
            installedToken = nil
            user = nil
            if let error = error as? APIError, error.status == 401 {
                signOut()
            } else {
                // Offline, server failures, and cancelled requests preserve the
                // credential for retry without granting access to cached data.
                restoreError = (error as? APIError)?.status == 404
                    ? "login.sessionServerUpdateRequired"
                    : "login.sessionCheckFailed"
            }
        }
    }

    func signIn(email: String, password: String) async throws -> SignInResult {
        let revision = sessionRevision
        let serverURL = Server.baseURL.absoluteString
        let result = try await api.login(email: email, password: password)
        guard sessionRevision == revision, Server.baseURL.absoluteString == serverURL else {
            throw CancellationError()
        }
        switch result {
        case .mfa(let challenge):
            return .mfa(method: challenge.method, challengeToken: challenge.challengeToken)
        case .session(let session):
            try persist(token: session.accessToken, user: session.user, serverURL: serverURL)
            return .ok
        }
    }

    func completeMFA(challengeToken: String, code: String) async throws -> LoginSession {
        let revision = sessionRevision
        let serverURL = Server.baseURL.absoluteString
        let session = try await api.verifyMFA(challengeToken: challengeToken, code: code)
        guard sessionRevision == revision, Server.baseURL.absoluteString == serverURL else {
            throw CancellationError()
        }
        try persist(token: session.accessToken, user: session.user, serverURL: serverURL)
        return session
    }

    func signOut() {
        sessionRevision = UUID()
        api.token = nil
        installedToken = nil
        user = nil
        clearLegacySession()
        do {
            try storage.clear()
            restoreError = nil
            ready = true
        } catch {
            // Do not claim sign-out completed while a saved credential remains.
            restoreError = "login.sessionRemovalFailed"
            ready = false
        }
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

    private func persist(token: String, user: SessionUser, serverURL: String) throws {
        try storage.save(SavedSession(token: token, serverURL: serverURL))
        sessionRevision = UUID()
        installedToken = token
        api.token = token
        self.user = user
        restoreError = nil
        ready = true
    }

    private func clearLegacySession() {
        KeychainStore.deleteToken()
        KeychainStore.deleteLegacySavedLogin()
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}
