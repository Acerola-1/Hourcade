import SwiftUI
import WidgetKit
import ServiceManagement

/// Login-item registration for silent launch-and-stay-in-menu-bar operation.
/// Must be toggled by a user action (System Settings shows the entry either way).
enum LaunchAtLogin {
    @MainActor
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @MainActor
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Cover art cached in the App Group for the overview and the widgets. Every
/// file in the directory is re-downloadable, so deleting it is always safe.
enum ArtworkCache {
    static func usage() async -> (bytes: Int64, files: Int) {
        // App Group artwork (widget pipeline) plus the in-app cover disk cache.
        async let widget = measure(directory: SteamWidgetStore.artworkDirectory)
        async let covers = measure(directory: CoverStore.coversDirectory)
        let (widgetUsage, coverUsage) = await (widget, covers)
        return (widgetUsage.bytes + coverUsage.bytes, widgetUsage.files + coverUsage.files)
    }

    static func clear() async {
        guard let directory = SteamWidgetStore.artworkDirectory else { return }
        await Task.detached(priority: .utility) { @Sendable in
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
            for name in names where name.hasSuffix(".jpg") {
                try? fm.removeItem(at: directory.appending(path: name))
            }
        }.value
        await CoverStore.shared.clear()
    }

    private static func measure(directory: URL?) async -> (bytes: Int64, files: Int) {
        guard let directory else { return (0, 0) }
        return await Task.detached(priority: .utility) { @Sendable in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { return (0, 0) }
            var bytes: Int64 = 0
            var count = 0
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                bytes += Int64(values.fileSize ?? 0)
                count += 1
            }
            return (bytes, count)
        }.value
    }
}

/// General preferences, shown inline as a sidebar page rather than in a separate
/// settings window. Both choices write to the shared store so the app and the
/// widgets agree.
struct GeneralSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language: AppLanguage = .system
    @AppStorage(L10n.themeKey, store: L10n.defaults) private var theme: AppTheme = .system
    @ObservedObject private var updater = UpdateService.shared
    @State private var cacheBytes: Int64?
    @State private var cacheFiles = 0
    @State private var isClearing = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        let _ = locale
        PageShell(title: L10n.tr("常规设置"), eyebrow: L10n.tr("偏好设置"), subtitle: L10n.tr("这些选项同时应用于 Hourcade 和桌面小组件。")) {
            SettingsPanel(title: L10n.tr("登录时启动")) {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("开机后在菜单栏静默运行"))
                            .font(.subheadline.weight(.medium))
                        Text(L10n.tr("Hourcade 驻留菜单栏并定时同步组件数据，不占用 Dock；随时可从菜单栏退出。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLogin = LaunchAtLogin.isEnabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            SettingsPanel(title: L10n.tr("语言")) {
                Picker(L10n.tr("语言"), selection: $language) {
                    Text(L10n.tr("跟随系统")).tag(AppLanguage.system)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(L10n.tr("语言设置同时应用于 Hourcade 和桌面小组件。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsPanel(title: L10n.tr("主题")) {
                Picker(L10n.tr("主题"), selection: $theme) {
                    Text(L10n.tr("跟随系统")).tag(AppTheme.system)
                    Text(L10n.tr("浅色")).tag(AppTheme.light)
                    Text(L10n.tr("深色")).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(L10n.tr("主题只影响 Hourcade 窗口；桌面小组件跟随系统外观。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsPanel(title: L10n.tr("更新")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.format("当前版本 %@", UpdateService.appVersion))
                            .font(.subheadline.weight(.medium))
                        Text(L10n.tr("有新版本时，Hourcade 会从 GitHub 下载并校验签名后安装。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.tr("检查更新")) {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
            SettingsPanel(title: L10n.tr("缓存")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("封面图片"))
                            .font(.subheadline.weight(.medium))
                        Text(sizeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isClearing = true
                        Task {
                            await ArtworkCache.clear()
                            cacheBytes = 0
                            cacheFiles = 0
                            WidgetCenter.shared.reloadAllTimelines()
                            isClearing = false
                        }
                    } label: {
                        if isClearing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.tr("清除"))
                        }
                    }
                    .disabled(isClearing || cacheBytes == 0)
                }
                Text(L10n.tr("清除后，封面会在下次同步或启动时重新下载。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsPanel(title: L10n.tr("隐私")) {
                Toggle(isOn: Binding(
                    get: { UsageReporter.shared.isEnabled },
                    set: { UsageReporter.shared.isEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("匿名使用数据"))
                            .font(.subheadline.weight(.medium))
                        Text(L10n.tr("仅上报匿名心跳（安装 UUID、版本、系统与芯片型号、语言），不含账号信息与游玩内容；关闭后立即停止。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: language) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .task {
            let usage = await ArtworkCache.usage()
            cacheBytes = usage.bytes
            cacheFiles = usage.files
        }
    }

    private var sizeSummary: String {
        guard let cacheBytes else { return L10n.tr("计算中…") }
        let size = ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
        return L10n.format("%1$@ · %2$lld 张图片", size, cacheFiles)
    }
}
