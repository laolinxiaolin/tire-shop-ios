import SwiftUI
import UIKit

struct LoadingView: View {
    let label: String

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView()
            Text(label)
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

                Text(title)
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
            Text(title)
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
            Text(label)
                .font(.footnote)
                .fontWeight(.600)
                .foregroundStyle(Theme.text)

            if secure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
                    .disabled(disabled)
                    .textFieldStyle(.plain)
                    .fieldChrome()
            } else {
                TextField(placeholder, text: $text)
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

            Text(title)
                .font(.title3)
                .fontWeight(.700)
                .foregroundStyle(Theme.text)

            Text(blurb ?? "Coming soon to mobile. This module is available on the web app today.")
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
    let destination: Destination

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.title2)
                .fontWeight(.700)
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
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(value)
                        .font(.title3)
                        .fontWeight(.700)
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
        Text(title)
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
                Text(title)
                    .font(.body)
                    .fontWeight(.600)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.subheadline)
                    .fontWeight(.600)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
