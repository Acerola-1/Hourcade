import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct HourcadeApp: App {
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language: AppLanguage = .system
    @AppStorage(L10n.themeKey, store: L10n.defaults) private var theme: AppTheme = .system

    init() {
        // 启动 Sparkle：startingUpdater 已开启，这里只需让单例活起来。
        _ = UpdateService.shared
        // 匿名心跳：启动时检查一次，并挂上周期计时器（覆盖长期驻留菜单栏的情况）。
        UsageReporter.shared.reportIfNeeded(trigger: .launch)
        UsageReporter.shared.start()
        Task { @MainActor in BackgroundSyncScheduler.runLaunchSequenceOnce() }
    }

    var body: some Scene {
        // Observe the shared preferences without recreating windows or connection state.
        let _ = (language, theme)

        // A single Window (not WindowGroup): openWindow focuses the existing
        // window instead of stacking a new one on every menu-bar click.
        Window("Hourcade", id: "main") {
            ContentView()
                .environment(\.locale, L10n.locale)
                .preferredColorScheme(L10n.colorScheme)
        }
        .defaultSize(width: 1040, height: 760)
        .restorationBehavior(.disabled)

        MenuBarExtra("Hourcade", systemImage: "gamecontroller.fill") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The whole app keeps running with the window closed (macOS default), so the
/// menu bar stays available and the background scheduler keeps refreshing data.
private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.tr("打开主界面")) {
            // An accessory app (LSUIElement) never activates itself, so the
            // window would open behind everything; bring the app forward too.
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(L10n.tr("立即同步")) {
            Task { await SyncCoordinator.shared.syncAll() }
        }
        Divider()
        Button(L10n.tr("退出 Hourcade")) {
            NSApp.terminate(nil)
        }
    }
}

/// Hourly data refresh while the app is running (menu bar or window).
/// NSBackgroundActivityScheduler cooperates with App Nap and sleep; each tick
/// checks whether connected data is stale. The app process owns this schedule,
/// independent of whether its window is open.
@MainActor
enum BackgroundSyncScheduler {
    private static var activity: NSBackgroundActivityScheduler?
    private static var wakeObserver: NSObjectProtocol?
    private static var activationObserver: NSObjectProtocol?

    static func start() {
        guard activity == nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "dev.acerola.Hourcade.sync")
        scheduler.repeats = true
        scheduler.interval = 3_600
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await SyncCoordinator.shared.refreshIfStale()
                completion(.finished)
            }
        }
        activity = scheduler
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await SyncCoordinator.shared.refreshIfStale() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await SyncCoordinator.shared.refreshIfStale() }
        }
    }

    static func runLaunchSequenceOnce() {
        guard !launchSequenceRan else { return }
        launchSequenceRan = true
        start()
        Task { @MainActor in
            await SyncCoordinator.shared.runLaunchSequence()
        }
    }

    private static var launchSequenceRan = false
}
