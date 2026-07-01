import SwiftUI
import UIKit

// MARK: - Users

private struct UserEditTarget: Identifiable {
    let user: UserAccount?
    var id: String { user?.id ?? "new" }
}

struct UsersNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var users: [UserAccount] = []
    @State private var roles: [Role] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var editing: UserEditTarget?
    @State private var resetTarget: UserAccount?
    @State private var mfaTarget: UserAccount?
    @State private var actionError: String?

    private var canManage: Bool { auth.has("users.manage") }

    private var filtered: [UserAccount] {
        guard let needle = search.nilIfBlank?.lowercased() else { return users }
        return users.filter {
            $0.fullName.lowercased().contains(needle)
                || $0.email.lowercased().contains(needle)
                || $0.roleName.lowercased().contains(needle)
        }
    }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, users.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if filtered.isEmpty {
                EmptyStateView(text: search.nilIfBlank == nil ? "No users yet." : "No users match \"\(search)\".")
            } else {
                List(filtered) { user in
                    UserRow(user: user)
                        .contentShape(Rectangle())
                        .onTapGesture { if canManage { editing = UserEditTarget(user: user) } }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canManage { rowActions(user) }
                        }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search name, email, role")
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = UserEditTarget(user: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New user")
                }
            }
        }
        .sheet(item: $editing) { target in
            UserEditorView(user: target.user, roles: roles) {
                editing = nil
                Task { await load() }
            }
        }
        .sheet(item: $resetTarget) { user in
            ResetPasswordView(user: user) { resetTarget = nil }
        }
        .alert("Reset two-step verification?", isPresented: Binding(get: { mfaTarget != nil }, set: { if !$0 { mfaTarget = nil } })) {
            Button("Cancel", role: .cancel) { mfaTarget = nil }
            Button("Reset", role: .destructive) {
                if let user = mfaTarget { Task { await resetMfa(user) } }
                mfaTarget = nil
            }
        } message: {
            Text("\(mfaTarget?.fullName ?? "This user") will be prompted to set up two-step verification again at next sign-in.")
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { if !loaded { await load() } }
    }

    @ViewBuilder
    private func rowActions(_ user: UserAccount) -> some View {
        Button {
            Task { await setActive(user, active: !user.active) }
        } label: {
            Label(user.active ? "Deactivate" : "Activate", systemImage: user.active ? "person.slash" : "person.fill.checkmark")
        }
        .tint(user.active ? Theme.danger : Theme.success)

        Button { resetTarget = user } label: {
            Label("Password", systemImage: "key")
        }
        .tint(Theme.primary)

        Button { mfaTarget = user } label: {
            Label("MFA", systemImage: "lock.rotation")
        }
        .tint(.orange)
    }

    @MainActor
    private func load() async {
        do {
            async let usersTask = UsersAPI().list()
            async let rolesTask = RolesAPI().list()
            users = try await usersTask
            roles = try await rolesTask
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load users."
        }
        loaded = true
    }

    @MainActor
    private func setActive(_ user: UserAccount, active: Bool) async {
        do {
            _ = try await UsersAPI().update(id: user.id, body: UserPatchInput(fullName: nil, roleId: nil, active: active))
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not update the user."
        }
    }

    @MainActor
    private func resetMfa(_ user: UserAccount) async {
        do {
            _ = try await UsersAPI().resetMfa(id: user.id)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not reset two-step verification."
        }
    }
}

private struct UserRow: View {
    let user: UserAccount

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(user.fullName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.sm) {
                    Text(user.roleName)
                    if user.mfaMethod != nil {
                        Label("MFA", systemImage: "lock.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }

            Spacer()

            StatusPill(text: user.active ? "Active" : "Inactive", color: user.active ? Theme.success : Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct UserEditorView: View {
    let user: UserAccount?
    let roles: [Role]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var roleId = ""
    @State private var active = true
    @State private var saving = false
    @State private var errorMessage: String?

    private var isNew: Bool { user == nil }

    private var canSave: Bool {
        guard fullName.nilIfBlank != nil, roleId.nilIfBlank != nil else { return false }
        if isNew {
            return email.nilIfBlank != nil && password.count >= 8
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                    if isNew {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        LabeledContent("Email", value: email)
                    }
                }

                if isNew {
                    Section {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                    } header: {
                        Text("Password")
                    } footer: {
                        Text("At least 8 characters. The user can change it after signing in.")
                    }
                }

                Section("Role") {
                    Picker("Role", selection: $roleId) {
                        Text("Select a role").tag("")
                        ForEach(roles) { role in
                            Text(role.name).tag(role.id)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Toggle("Active", isOn: $active)
                    } footer: {
                        Text("Inactive users cannot sign in.")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle(isNew ? "New User" : "Edit User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || !canSave)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func seed() {
        guard let user else {
            roleId = roles.first?.id ?? ""
            return
        }
        fullName = user.fullName
        email = user.email
        roleId = user.roleId
        active = user.active
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        do {
            if let user {
                _ = try await UsersAPI().update(
                    id: user.id,
                    body: UserPatchInput(fullName: fullName.nilIfBlank, roleId: roleId.nilIfBlank, active: active)
                )
            } else {
                guard let email = email.nilIfBlank, let name = fullName.nilIfBlank else {
                    saving = false
                    return
                }
                _ = try await UsersAPI().create(
                    UserCreateInput(email: email, password: password, fullName: name, roleId: roleId)
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the user."
        }
        saving = false
    }
}

private struct ResetPasswordView: View {
    let user: UserAccount
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var canSave: Bool { password.count >= 8 && password == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirm)
                        .textContentType(.newPassword)
                } header: {
                    Text("Reset password for \(user.fullName)")
                } footer: {
                    Text("At least 8 characters.")
                }

                if password.count > 0, password != confirm {
                    Text("Passwords do not match.").foregroundStyle(.red).font(.subheadline)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDone(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || !canSave)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        do {
            _ = try await UsersAPI().resetPassword(id: user.id, password: password)
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reset the password."
        }
        saving = false
    }
}

// MARK: - Roles

private enum PermState: String, CaseIterable, Identifiable {
    case off
    case approval
    case granted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .approval: return "Approval"
        case .granted: return "Granted"
        }
    }
}

private struct RoleEditTarget: Identifiable {
    let role: Role?
    var id: String { role?.id ?? "new" }
}

struct RolesNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var roles: [Role] = []
    @State private var catalog: [PermissionGroup] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var editing: RoleEditTarget?
    @State private var actionError: String?

    private var canManage: Bool { auth.has("users.manage") }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, roles.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else {
                List {
                    ForEach(roles) { role in
                        RoleRow(role: role)
                            .contentShape(Rectangle())
                            .onTapGesture { if canManage { editing = RoleEditTarget(role: role) } }
                            .swipeActions(edge: .trailing) {
                                if canManage, !role.isSystem {
                                    Button(role: .destructive) {
                                        Task { await remove(role) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = RoleEditTarget(role: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New role")
                }
            }
        }
        .sheet(item: $editing) { target in
            RoleEditorView(role: target.role, catalog: catalog) {
                editing = nil
                Task { await load() }
            }
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { if !loaded { await load() } }
    }

    @MainActor
    private func load() async {
        do {
            async let rolesTask = RolesAPI().list()
            async let catalogTask = RolesAPI().catalog()
            roles = try await rolesTask
            catalog = try await catalogTask
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load roles."
        }
        loaded = true
    }

    @MainActor
    private func remove(_ role: Role) async {
        do {
            _ = try await RolesAPI().remove(id: role.id)
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not delete the role."
        }
    }
}

private struct RoleRow: View {
    let role: Role

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.sm) {
                    Text(role.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)
                    if role.isSystem {
                        StatusPill(text: "System", color: Theme.muted)
                    }
                }
                if let description = role.description?.nilIfBlank {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Text("\(role.permissions.count) granted · \(role.approvalPermissions.count) approval")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Text("\(role.userCount) users")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct RoleEditorView: View {
    let role: Role?
    let catalog: [PermissionGroup]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var states: [String: PermState] = [:]
    @State private var saving = false
    @State private var errorMessage: String?

    private var isNew: Bool { role == nil }
    private var isSystem: Bool { role?.isSystem ?? false }
    private var isAdmin: Bool { role?.isAdmin == true || (isSystem && role?.name == "Admin") }
    private var nameLocked: Bool { !isNew && isSystem }
    private var permissionsLocked: Bool { !isNew && isAdmin }
    private var saveDisabled: Bool { saving || (!nameLocked && name.nilIfBlank == nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Name", text: $name).disabled(nameLocked)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(1...4)
                }

                if nameLocked {
                    Text("Built-in role names cannot be changed.")
                        .foregroundStyle(Theme.muted)
                        .font(.subheadline)
                }
                if permissionsLocked {
                    Label("The Admin role always holds every permission.", systemImage: "lock.fill")
                        .foregroundStyle(Theme.muted)
                        .font(.subheadline)
                }

                ForEach(catalog, id: \.group) { group in
                    Section(group.group.capitalized) {
                        ForEach(group.permissions, id: \.key) { permission in
                            permissionRow(permission)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle(isNew ? "New Role" : (isSystem ? "Role" : "Edit Role"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saveDisabled)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func permissionRow(_ permission: PermissionGroup.Permission) -> some View {
        let binding = Binding<PermState>(
            get: { permissionsLocked ? .granted : (states[permission.key] ?? .off) },
            set: { if !permissionsLocked { states[permission.key] = $0 } }
        )
        let approvable = permission.approvable ?? false
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(permission.label)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
            Text(permission.key)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            Picker("State", selection: binding) {
                ForEach(PermState.allCases) { state in
                    if state != .approval || approvable {
                        Text(state.label).tag(state)
                    }
                }
            }
            .pickerStyle(.segmented)
            .disabled(permissionsLocked)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func seed() {
        if let role {
            name = role.name
            description = role.description ?? ""
        }
        var next: [String: PermState] = [:]
        for group in catalog {
            for permission in group.permissions {
                if role?.permissions.contains(permission.key) == true {
                    next[permission.key] = .granted
                } else if role?.approvalPermissions.contains(permission.key) == true {
                    next[permission.key] = .approval
                } else {
                    next[permission.key] = .off
                }
            }
        }
        states = next
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        let granted = states.filter { $0.value == .granted }.map(\.key).sorted()
        let approval = states.filter { $0.value == .approval }.map(\.key).sorted()
        do {
            if let role {
                let cleanDescription = description.nilIfBlank
                _ = try await RolesAPI().update(
                    id: role.id,
                    body: RolePatchInput(
                        name: nameLocked ? nil : name.nilIfBlank,
                        description: cleanDescription,
                        permissions: permissionsLocked ? nil : granted,
                        approvalPermissions: permissionsLocked ? nil : approval,
                        clearsDescription: cleanDescription == nil
                    )
                )
            } else {
                guard let cleanName = name.nilIfBlank else {
                    saving = false
                    return
                }
                _ = try await RolesAPI().create(
                    RoleCreateInput(name: cleanName, description: description.nilIfBlank, permissions: granted, approvalPermissions: approval)
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not save the role."
        }
        saving = false
    }
}

// MARK: - API Keys

struct ApiKeysNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var keys: [ApiKey] = []
    @State private var scopes: [AiScopeGroup] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var creating = false
    @State private var created: ApiKeyCreated?
    @State private var revokeTarget: ApiKey?
    @State private var actionError: String?

    private var canManage: Bool { auth.has("apikeys.manage") }

    var body: some View {
        Group {
            if !loaded {
                LoadingView(label: "Loading...")
            } else if let errorMessage, keys.isEmpty {
                RetryView(message: errorMessage) { Task { await load() } }
            } else if keys.isEmpty {
                EmptyStateView(text: "No API keys yet. Create one with +.")
            } else {
                List {
                    ForEach(keys) { key in
                        ApiKeyRow(key: key)
                            .swipeActions(edge: .trailing) {
                                if canManage, !key.revoked {
                                    Button(role: .destructive) { revokeTarget = key } label: {
                                        Label("Revoke", systemImage: "xmark.circle")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New API key")
                }
            }
        }
        .sheet(isPresented: $creating) {
            ApiKeyEditorView(scopes: scopes) { result in
                creating = false
                created = result
                Task { await load() }
            }
        }
        .sheet(item: $created) { result in
            ApiKeyRevealView(created: result) { created = nil }
        }
        .alert("Revoke API key?", isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } })) {
            Button("Cancel", role: .cancel) { revokeTarget = nil }
            Button("Revoke", role: .destructive) {
                if let key = revokeTarget { Task { await revoke(key) } }
                revokeTarget = nil
            }
        } message: {
            Text("\(revokeTarget?.name ?? "This key") will stop working immediately. This cannot be undone.")
        }
        .alert("Action failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { if !loaded { await load() } }
    }

    @MainActor
    private func load() async {
        do {
            async let keysTask = ApiKeysAPI().list()
            async let scopesTask = ApiKeysAPI().scopes()
            keys = try await keysTask
            scopes = try await scopesTask
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load API keys."
        }
        loaded = true
    }

    @MainActor
    private func revoke(_ key: ApiKey) async {
        do {
            _ = try await ApiKeysAPI().revoke(id: key.id)
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Could not revoke the key."
        }
    }
}

private struct ApiKeyRow: View {
    let key: ApiKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(key.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(key.scopes.count) scope\(key.scopes.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(key.lastUsedAt == nil ? "Never used" : "Last used \(AppFormat.shortDate(key.lastUsedAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            StatusPill(text: key.revoked ? "Revoked" : "Active", color: key.revoked ? Theme.danger : Theme.success)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ApiKeyEditorView: View {
    let scopes: [AiScopeGroup]
    let onCreated: (ApiKeyCreated) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var saving = false
    @State private var errorMessage: String?

    private var canSave: Bool { name.nilIfBlank != nil && !selected.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("Name", text: $name)
                }

                ForEach(scopes, id: \.group) { group in
                    Section(group.group.capitalized) {
                        ForEach(group.scopes, id: \.key) { scope in
                            Button {
                                toggle(scope.key)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scope.label).foregroundStyle(Theme.text)
                                        Text(scope.key).font(.caption2).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if selected.contains(scope.key) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                }
            }
            .navigationTitle("New API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(saving || !canSave)
                }
            }
        }
    }

    private func toggle(_ key: String) {
        if selected.contains(key) {
            selected.remove(key)
        } else {
            selected.insert(key)
        }
    }

    @MainActor
    private func save() async {
        saving = true
        errorMessage = nil
        guard let cleanName = name.nilIfBlank else { saving = false; return }
        do {
            let result = try await ApiKeysAPI().create(ApiKeyCreateInput(name: cleanName, scopes: Array(selected).sorted()))
            onCreated(result)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not create the key."
        }
        saving = false
    }
}

private struct ApiKeyRevealView: View {
    let created: ApiKeyCreated
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(created.plaintext)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Secret for \(created.name)")
                } footer: {
                    Text("Copy this key now — it will not be shown again.")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = created.plaintext
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy key", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .navigationTitle("API Key Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Approvals

private enum ApprovalTab: String, CaseIterable, Identifiable {
    case pending
    case mine
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .mine: return "Mine"
        case .history: return "History"
        }
    }
}

struct ApprovalsNativeView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var tab: ApprovalTab = .pending
    @State private var items: [ApprovalRequest] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selected: ApprovalRequest?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(ApprovalTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Space.lg)
            .background(Theme.background)

            Divider()

            Group {
                if loading && items.isEmpty {
                    LoadingView(label: "Loading...")
                } else if let errorMessage, items.isEmpty {
                    RetryView(message: errorMessage) { Task { await load() } }
                } else if items.isEmpty {
                    EmptyStateView(text: emptyText)
                } else {
                    List(items) { request in
                        ApprovalRow(request: request)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = request }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .background(Theme.background)
        .sheet(item: $selected) { request in
            ApprovalDetailView(request: request, currentUserId: auth.user?.id) {
                selected = nil
                Task { await load() }
            }
        }
        .task(id: tab) { await load() }
    }

    private var emptyText: String {
        switch tab {
        case .pending: return "No pending approvals."
        case .mine: return "You have not requested any approvals."
        case .history: return "No decided approvals yet."
        }
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            let page: Paged<ApprovalRequest>
            switch tab {
            case .pending:
                page = try await ApprovalsAPI().list(status: "PENDING", pageSize: 50)
                items = page.items
            case .mine:
                page = try await ApprovalsAPI().list(mine: true, pageSize: 50)
                items = page.items
            case .history:
                page = try await ApprovalsAPI().list(pageSize: 50)
                items = page.items.filter { $0.status != "PENDING" }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load approvals."
        }
        loading = false
    }
}

private struct ApprovalRow: View {
    let request: ApprovalRequest

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(ApprovalFormat.action(request.action))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(request.requestedBy.fullName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text(AppFormat.dateTime(request.requestedAt))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            StatusPill(text: ApprovalFormat.status(request.status), color: ApprovalFormat.color(request.status))
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ApprovalDetailView: View {
    let request: ApprovalRequest
    let currentUserId: String?
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ApprovalRequest?
    @State private var note = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var detailError: String?

    private var current: ApprovalRequest { detail ?? request }
    private var isPending: Bool { current.status == "PENDING" }
    private var isMine: Bool { current.requestedById == currentUserId }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Action", value: ApprovalFormat.action(current.action))
                    LabeledContent("Status", value: ApprovalFormat.status(current.status))
                    if let entity = current.entityType?.nilIfBlank {
                        LabeledContent("Entity", value: [entity, current.entityId].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                    }
                    LabeledContent("Requested by", value: current.requestedBy.fullName)
                    LabeledContent("Requested", value: AppFormat.dateTime(current.requestedAt))
                }

                if detail == nil, detailError == nil {
                    Section {
                        Label("Loading details...", systemImage: "arrow.clockwise")
                            .foregroundStyle(Theme.muted)
                            .font(.subheadline)
                    }
                }

                if let detailError {
                    Text(detailError).foregroundStyle(.red).font(.subheadline)
                }

                if let payload = current.payload, case let rows = ApprovalFormat.rows(payload), !rows.isEmpty {
                    Section("Details") {
                        ForEach(rows, id: \.0) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }

                if let context = current.context, case let rows = ApprovalFormat.rows(context), !rows.isEmpty {
                    Section("Context") {
                        ForEach(rows, id: \.0) { key, value in
                            LabeledContent(key, value: value)
                        }
                    }
                }

                if let note = current.note?.nilIfBlank {
                    Section("Reason") {
                        Text(note).foregroundStyle(Theme.text)
                    }
                }

                if let decidedBy = current.decidedBy {
                    Section("Decision") {
                        LabeledContent("Decided by", value: decidedBy.fullName)
                        if let decidedAt = current.decidedAt {
                            LabeledContent("Decided", value: AppFormat.dateTime(decidedAt))
                        }
                        if let decisionNote = current.decisionNote?.nilIfBlank {
                            LabeledContent("Note", value: decisionNote)
                        }
                    }
                }

                if let error = current.executionError?.nilIfBlank {
                    Section("Execution error") {
                        Text(error).foregroundStyle(Theme.danger).font(.subheadline)
                    }
                }

                if isPending {
                    Section("Add a note (optional)") {
                        TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }

                    Section {
                        if isMine {
                            Button(role: .destructive) {
                                Task { await act { try await ApprovalsAPI().cancel(id: current.id) } }
                            } label: {
                                Label("Cancel request", systemImage: "xmark.circle")
                            }
                            .disabled(working)
                        } else {
                            Button {
                                Task { await act { try await ApprovalsAPI().approve(id: current.id, note: note.nilIfBlank) } }
                            } label: {
                                Label("Approve", systemImage: "checkmark.circle")
                                    .foregroundStyle(Theme.success)
                            }
                            .disabled(working)

                            Button(role: .destructive) {
                                Task { await act { try await ApprovalsAPI().deny(id: current.id, note: note.nilIfBlank) } }
                            } label: {
                                Label("Deny", systemImage: "nosign")
                            }
                            .disabled(working)
                        }
                    }
                }
            }
            .navigationTitle("Approval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadDetail() }
    }

    @MainActor
    private func loadDetail() async {
        do {
            detail = try await ApprovalsAPI().get(id: request.id)
            detailError = nil
        } catch {
            detailError = (error as? LocalizedError)?.errorDescription ?? "Could not load full approval details."
        }
    }

    @MainActor
    private func act(_ operation: @escaping () async throws -> ApprovalRequest) async {
        working = true
        errorMessage = nil
        do {
            _ = try await operation()
            onChanged()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not complete the action."
        }
        working = false
    }
}

private enum ApprovalFormat {
    static func action(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ").capitalized
    }

    static func status(_ value: ApprovalStatus) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func color(_ value: ApprovalStatus) -> Color {
        switch value {
        case "APPROVED": return Theme.success
        case "DENIED", "CANCELLED": return Theme.danger
        case "PENDING": return .orange
        default: return Theme.muted
        }
    }

    static func rows(_ value: JSONValue) -> [(String, String)] {
        guard case let .object(object) = value else { return [] }
        return object
            .sorted { $0.key < $1.key }
            .map { ($0.key, scalar($0.value)) }
    }

    private static func scalar(_ value: JSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number):
            if number == number.rounded() { return String(Int(number)) }
            return String(number)
        case .bool(let bool): return bool ? "Yes" : "No"
        case .null: return "—"
        case .array(let array): return "\(array.count) item\(array.count == 1 ? "" : "s")"
        case .object: return "…"
        }
    }
}

// MARK: - Shared

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
