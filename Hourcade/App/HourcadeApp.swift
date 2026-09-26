import SwiftUI
import WidgetKit

@main
struct HourcadeApp: App {
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language: AppLanguage = .system
    @AppStorage(L10n.themeKey, store: L10n.defaults) private var theme: AppTheme = .system

    var body: some Scene {
        // Observe the shared preferences without recreating windows or connection state.
        let _ = (language, theme)

        WindowGroup {
            ContentView()
                .environment(\.locale, L10n.locale)
                .preferredColorScheme(L10n.colorScheme)
        }
        .defaultSize(width: 1040, height: 760)
    }
}
