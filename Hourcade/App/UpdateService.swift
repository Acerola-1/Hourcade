import Combine
import Foundation
import Sparkle

/// Sparkle 自更新的封装。Hourcade 只通过 GitHub 直接分发，更新完全由 Sparkle 负责。
///
/// `SPUStandardUpdaterController` 驱动整套流程：检查 → 展示更新日志 → 下载（EdDSA
/// 签名校验）→ 替换 .app → 重启。整套 UI 由 Sparkle 原生提供，这里只把「能否检查」
/// 状态与「检查更新」入口暴露给设置页。
@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    /// 当前版本号，用于设置页展示。
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// 是否可发起检查（下载/安装进行中时 Sparkle 会置为 false），用于禁用按钮避免重复触发。
    @Published private(set) var canCheckForUpdates = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        // startingUpdater: true → 随 App 启动即按 Sparkle 默认周期后台检查；
        // 把 canCheckForUpdates 桥接给 SwiftUI，供按钮响应式禁用。
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 手动检查更新。有新版本时 Sparkle 弹出带更新日志的窗口引导下载安装；
    /// 已是最新时提示「已是最新版本」。
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
