import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en
    case zh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: return "English"
        case .zh: return "简体中文"
        }
    }

    var shortLabel: String {
        switch self {
        case .en: return "EN"
        case .zh: return "中"
        }
    }
}

@MainActor
final class I18nStore: ObservableObject {
    private let storageKey = "ts_lang"

    @Published private(set) var language: AppLanguage = .en

    init() {
        if
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let saved = AppLanguage(rawValue: raw)
        {
            language = saved
        }
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }

    func t(_ key: String, _ params: [String: CustomStringConvertible] = [:]) -> String {
        var value = Self.messages[language]?[key] ?? Self.messages[.en]?[key] ?? key
        for (name, replacement) in params {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement.description)
        }
        return value
    }
}
