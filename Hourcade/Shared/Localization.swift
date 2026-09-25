import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: Self { self }
}

/// Kept beside the language preference because both live in the shared store and
/// both are applied by the app scene.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
}

enum L10n {
    static let languageKey = "preferredLanguage"
    static let themeKey = "preferredTheme"
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HourcadeAppGroup") as? String,
              let defaults = UserDefaults(suiteName: group) else {
            fatalError("Missing Hourcade App Group configuration")
        }
        return defaults
    }()

    static var language: AppLanguage {
        let selected = AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "system") ?? .system
        if selected != .system { return selected }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .simplifiedChinese : .english
    }

    /// The stored preference, without resolving `.system` against the current look.
    static var theme: AppTheme {
        AppTheme(rawValue: defaults.string(forKey: themeKey) ?? "system") ?? .system
    }

    static var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static var locale: Locale { Locale(identifier: language.rawValue) }

    static func tr(_ key: String, table: String = "App") -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: table)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: arguments)
    }

    static func widget(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key, table: "Widgets"), locale: locale, arguments: arguments)
    }
}
