import SwiftUI
import Security
import WidgetKit

private enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, steam, nintendo, playStation, studio, general
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: L10n.tr("总览")
        case .steam: "Steam"
        case .nintendo: "Nintendo Switch"
        case .playStation: "PlayStation"
        case .studio: L10n.tr("组件预览")
        case .general: L10n.tr("常规设置")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gamecontroller.circle"
        case .steam: "gamecontroller.fill"
        case .nintendo: "switch.2"
        case .playStation: "playstation.logo"
        case .studio: "square.grid.2x2"
        case .general: "gearshape"
        }
    }
}

/// Sidebar rows all share one geometry — a 27×27 mark column followed by the
/// title — so platform logos and plain SF symbols line up on the same edges.
private struct SidebarMark: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 27, height: 27)
    }
}

struct AccountPlatformMark: View {
    let platform: GamePlatform
    var size: CGFloat = 34

    private var asset: String {
        switch platform {
        case .steam: "SteamLogo"
        case .nintendo: "NintendoSwitchLogo"
        case .playStation: "PlayStationLogo"
        }
    }

    private var color: Color {
        switch platform {
        case .steam: Color(red: 0.10, green: 0.24, blue: 0.36)
        case .nintendo: Color(red: 0.89, green: 0.09, blue: 0.12)
        case .playStation: Color(red: 0.02, green: 0.28, blue: 0.73)
        }
    }

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.57, height: size * 0.57)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

enum DisplayFormat {
    static func syncDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return formatter.string(from: date)
    }
}

// Keep messages as data so switching languages also updates existing sync results.
private enum AccountMessage {
    case text(String)
    case widgetWriteFailure(Error)
    case failure(Error)
    case synced(Date)

    var text: String {
        switch self {
        case .text(let key): L10n.tr(key)
        case .widgetWriteFailure(let error): L10n.format("桌面小组件数据写入失败：%@", error.localizedDescription)
        case .failure(let error): (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        case .synced(let date):
            L10n.format("同步成功 · %@", date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
        }
    }
}

struct ContentView: View {
    @Environment(\.locale) private var locale
    @State private var selection: DashboardPage? = .overview
    @State private var steamSnapshot: SteamSnapshot? = LocalSnapshotStore.load("steam")
    @State private var nintendoSnapshot: NintendoSnapshot? = LocalSnapshotStore.load("nintendo")
    @State private var psnSnapshot: PSNSnapshot? = LocalSnapshotStore.load("psn")
    @State private var steamSyncing = false
    @State private var steamError: AccountMessage?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = locale
        NavigationSplitView {
            List(selection: $selection) {
                sidebarRow(.overview)
                sidebarRow(.general)
                Section(L10n.tr("平台账号")) {
                    ForEach([DashboardPage.steam, .nintendo, .playStation]) { page in
                        sidebarRow(page)
                    }
                }
                Section(L10n.tr("设计")) {
                    sidebarRow(.studio)
                }
            }
            .navigationTitle("Hourcade")
            .navigationSplitViewColumnWidth(min: 210, ideal: 238)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(
                    steam: steamSnapshot,
                    nintendo: nintendoSnapshot,
                    playStation: psnSnapshot,
                    steamConfigured: KeychainSecret.read("steam.apiKey") != nil,
                    isRefreshing: steamSyncing,
                    refreshError: steamError?.text,
                    selectPlatform: { platform in
                        switch platform {
                        case .steam: selection = .steam
                        case .nintendo: selection = .nintendo
                        case .playStation: selection = .playStation
                        }
                    },
                    syncAll: { Task { await syncAll() } }
                )
            case .steam:
                SteamSettingsView(
                    snapshot: steamSnapshot,
                    isRefreshing: steamSyncing,
                    syncError: steamError?.text,
                    onSync: syncSteam
                )
            case .nintendo:
                NintendoSettingsView(snapshot: nintendoSnapshot) { newSnapshot in
                    try LocalSnapshotStore.save(newSnapshot, as: "nintendo")
                    nintendoSnapshot = newSnapshot
                    try saveWidgetSnapshots()
                }
            case .playStation:
                PSNSettingsView(snapshot: psnSnapshot) { library in
                    let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "psn")
                    psnSnapshot = newSnapshot
                    try saveWidgetSnapshots()
                    reloadWidgets()
                }
            case .studio:
                ContentUnavailableView {
                    Label(L10n.tr("组件设计稿"), systemImage: "square.grid.2x2")
                } description: {
                    Text(L10n.tr("A2、B、C、D 与早期探索稿都已保留。"))
                } actions: {
                    Button(L10n.tr("打开组件预览")) { openWindow(id: "widget-studio") }
                }
            case .general:
                GeneralSettingsView()
            }
        }
        .frame(minWidth: 820, minHeight: 610)
        .task {
            migrateNintendoSessionToken()
            do { try saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
            if let steamSnapshot {
                // Refresh the library without waiting for cached artwork downloads.
                async let publication: Void = publishSteamWidget(steamSnapshot)
                await autoRefreshSteam()
                await publication
            } else {
                await autoRefreshSteam()
            }
            // Every connected platform refreshes on launch so the overview never
            // shows week-old play data that only a manual sync would fix.
            await refreshNintendo()
            await refreshPlayStation()
            await cachePlatformArtwork()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ page: DashboardPage) -> some View {
        HStack(spacing: 10) {
            if let platform = page.platform {
                AccountPlatformMark(platform: platform, size: 27)
            } else {
                SidebarMark(symbol: page.symbol)
            }
            Text(page.title)
        }
        .tag(page)
    }

    @MainActor
    private func publishSteamWidget(_ snapshot: SteamSnapshot) async {
        do {
            try SteamWidgetStore.save(snapshot)
            try saveWidgetSnapshots()
        } catch {
            steamError = .widgetWriteFailure(error)
            return
        }
        await SteamAPI.cacheArtwork(for: snapshot)
        reloadWidgets()
    }

    /// One-time migration: if the Keychain has no Nintendo session token but a
    /// local JSON file does (left over from development), move it into the
    /// Keychain under the app's own ACL so reading it never triggers a prompt.
    @MainActor
    private func migrateNintendoSessionToken() {
        guard KeychainSecret.read("nintendo.sessionToken") == nil else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "Hourcade/nintendo-session.json")
        guard let url, let data = try? Data(contentsOf: url),
              let migrated = try? JSONDecoder().decode([String: String].self, from: data),
              let token = migrated["session_token"], !token.isEmpty
        else { return }
        try? KeychainSecret.save(token, for: "nintendo.sessionToken")
    }

    /// Downloads the cover art for each connected platform's most-played game so
    /// `GameArtwork` can render real images in the widget instead of gradients.
    /// Steam already has its own richer pipeline (`SteamAPI.cacheArtwork`); this
    /// covers the Nintendo and PlayStation CDNs, whose images are direct URLs.
    @MainActor
    private func cachePlatformArtwork() async {
        // Nintendo: upgrade to 1024 for better quality when available.
        if let nintendo = nintendoSnapshot,
           let top = nintendo.games.max(by: { $0.totalPlayTime < $1.totalPlayTime }),
           !top.imageUri.isEmpty,
           var remote = URL(string: top.imageUri) {
            if remote.absoluteString.hasSuffix("_512"),
               let hd = URL(string: remote.absoluteString.replacingOccurrences(of: "_512", with: "_1024")) {
                remote = hd
            }
            let name = "nintendo-\(top.titleId ?? top.name)"
            await downloadAndCache(remote, named: name)
        }
        // PlayStation: the gamelist API gives a direct image URL.
        if let psn = psnSnapshot,
           let top = psn.library.games.max(by: { $0.lifetimeMinutes < $1.lifetimeMinutes }),
           let remote = top.imageURL {
            await downloadAndCache(remote, named: "psn-\(top.id)")
        }
    }

    private func downloadAndCache(_ remote: URL, named name: String) async {
        guard let destination = SteamWidgetStore.artworkURL(named: name),
              !FileManager.default.fileExists(atPath: destination.path)
        else { return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, _) = try await session.data(from: remote)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        } catch {
            // Best effort; the widget falls back to a gradient.
        }
    }

    @MainActor
    private func saveWidgetSnapshots() throws {
        try WidgetSnapshotStore.save(WidgetSnapshots(steam: steamSnapshot, nintendo: nintendoSnapshot, playStation: psnSnapshot))
        reloadWidgets()
    }

    @MainActor
    private func reloadWidgets() {
        for style in AggregateStyle.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: style.liveWidgetKind)
        }
        NotificationCenter.default.post(name: SteamWidgetStore.didChange, object: nil)
    }

    @MainActor
    private func autoRefreshSteam() async {
        guard let account = UserDefaults.standard.string(forKey: "steam.account"),
              !account.isEmpty, let key = KeychainSecret.read("steam.apiKey")
        else { return }
        _ = await syncSteam(account, key)
    }

    /// Refreshes every platform the user has already connected, in place, without
    /// sending them to each platform page. Platforms without stored credentials are
    /// left alone so the button never turns into an unexpected login prompt.
    @MainActor
    private func syncAll() async {
        guard !steamSyncing else { return }
        steamSyncing = true
        defer { steamSyncing = false }

        await autoRefreshSteam()
        await refreshNintendo()
        await refreshPlayStation()
        await cachePlatformArtwork()
        do { try saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
    }

    @MainActor
    private func refreshNintendo() async {
        guard let token = KeychainSecret.read("nintendo.sessionToken") else { return }
        do {
            let result = try await NintendoAPI.load(savedSessionToken: token, login: nil)
            let newSnapshot = NintendoSnapshot(
                games: result.games,
                syncedAt: .now,
                accountName: result.accountName ?? nintendoSnapshot?.accountName
            )
            try LocalSnapshotStore.save(newSnapshot, as: "nintendo")
            nintendoSnapshot = newSnapshot
        } catch {
            // A failed platform must not discard the others' fresh data.
        }
    }

    @MainActor
    private func refreshPlayStation() async {
        guard let refresh = KeychainSecret.read("psn.refreshToken") else { return }
        do {
            let (library, rotated) = try await PSNAPI.load(
                savedRefreshToken: refresh,
                accessCode: nil
            )
            if let rotated { try KeychainSecret.save(rotated, for: "psn.refreshToken") }
            let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
            try LocalSnapshotStore.save(newSnapshot, as: "psn")
            psnSnapshot = newSnapshot
        } catch {
            // Keep the previous PlayStation snapshot on failure.
        }
    }

    @MainActor
    private func syncSteam(_ account: String, _ enteredKey: String) async -> Bool {
        guard !steamSyncing else { return false }
        steamSyncing = true
        steamError = nil
        defer { steamSyncing = false }
        let key = enteredKey.isEmpty ? KeychainSecret.read("steam.apiKey") : enteredKey
        guard let key, !key.isEmpty else {
            steamError = .text("请输入 Web API Key")
            return false
        }
        do {
            var library = try await SteamAPI.load(account: account, key: key)
            if library.player == nil,
               UserDefaults.standard.string(forKey: "steam.account") == account.trimmingCharacters(in: .whitespacesAndNewlines) {
                library.player = steamSnapshot?.library.player
            }
            let newSnapshot = SteamSnapshot(library: library, syncedAt: .now)
            if !enteredKey.isEmpty { try KeychainSecret.save(enteredKey, for: "steam.apiKey") }
            try LocalSnapshotStore.save(newSnapshot, as: "steam")
            UserDefaults.standard.set(account.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "steam.account")
            steamSnapshot = newSnapshot
            await publishSteamWidget(newSnapshot)
            if library.games.isEmpty {
                steamError = .text("Steam 没有返回游戏。请检查个人资料的“游戏详情”隐私设置；改为公开会让其他人也能查看相关游戏信息")
            }
            return true
        } catch {
            steamError = .failure(error)
            return false
        }
    }
}

private extension DashboardPage {
    var platform: GamePlatform? {
        switch self {
        case .steam: .steam
        case .nintendo: .nintendo
        case .playStation: .playStation
        default: nil
        }
    }
}

private struct PageShell<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(34)
        }
        .navigationTitle(title)
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SteamSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var account = UserDefaults.standard.string(forKey: "steam.account") ?? ""
    @State private var apiKey = ""
    @State private var isEditing = KeychainSecret.read("steam.apiKey") == nil

    let snapshot: SteamSnapshot?
    let isRefreshing: Bool
    let syncError: String?
    let onSync: (String, String) async -> Bool

    private var hasConnection: Bool {
        !account.isEmpty && KeychainSecret.read("steam.apiKey") != nil
    }

    var body: some View {
        let _ = locale
        PageShell(eyebrow: L10n.tr("平台连接"), title: "Steam", subtitle: L10n.tr("连接你的 Steam 账号，游玩数据会显示在总览。")) {
            if hasConnection && !isEditing {
                SettingsPanel(title: L10n.tr("已连接的账号")) {
                    HStack(spacing: 14) {
                        AccountPlatformMark(platform: .steam, size: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(account).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Label(L10n.tr("API Key 已保存在本机钥匙串"), systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(L10n.tr("最近同步"))
                        Spacer()
                        Text(snapshot.map { DisplayFormat.syncDate($0.syncedAt) } ?? L10n.tr("尚未同步"))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    if let syncError {
                        Label(syncError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button(L10n.tr("立即同步")) { Task { _ = await onSync(account, "") } }
                            .disabled(isRefreshing)
                        if isRefreshing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button(L10n.tr("更换账号或密钥")) { isEditing = true }
                    }
                }
                DisclosureGroup(L10n.tr("查看连接说明")) { connectionGuide }
                    .padding(.horizontal, 4)
            } else {
                connectionGuide
                SettingsPanel(title: L10n.tr("连接你的账号")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("个人资料链接")).font(.subheadline.weight(.medium))
                        TextField(L10n.tr("粘贴你的 steamcommunity.com 个人主页地址"), text: $account)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.tr("例如 steamcommunity.com/id/你的名称；也支持 17 位 SteamID。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Web API Key")).font(.subheadline.weight(.medium))
                        SecureField(hasConnection ? L10n.tr("留空沿用已保存的密钥") : L10n.tr("粘贴从 Steam 官方页面取得的密钥"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.tr("只用于向 Steam 请求你的游戏记录，保存在本机钥匙串。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let syncError {
                        Label(syncError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button(isRefreshing ? L10n.tr("连接中…") : L10n.tr("连接并同步")) {
                            Task {
                                if await onSync(account.trimmingCharacters(in: .whitespacesAndNewlines), apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                    apiKey = ""
                                    isEditing = false
                                }
                            }
                        }
                        .disabled(isRefreshing || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isRefreshing { ProgressView().controlSize(.small) }
                        if hasConnection {
                            Button(L10n.tr("取消")) { apiKey = ""; isEditing = false }
                        }
                    }
                }
            }
        }
    }

    private var connectionGuide: some View {
        SettingsPanel(title: L10n.tr("首次连接 · 两步完成")) {
            HStack(alignment: .top, spacing: 12) {
                stepNumber("1")
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("复制个人资料地址")).font(.subheadline.weight(.semibold))
                    Text(L10n.tr("在 Steam 客户端打开自己的个人资料，复制页面地址。你也可以在浏览器打开 Steam 社区个人主页。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                stepNumber("2")
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("获取 Web API Key")).font(.subheadline.weight(.semibold))
                    Text(L10n.tr("Steam 客户端内没有密钥入口。请在浏览器登录 Steam 官方密钥页面，查看或申请密钥，再复制到下方。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Link(L10n.tr("打开 Steam 官方密钥页面 ↗"), destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                        .font(.subheadline)
                }
            }
            Text(L10n.tr("这是当前测试版的接入方式。Web API Key 属于开发者凭据，正式版还需改进授权流程。请勿把密钥发给他人。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stepNumber(_ value: String) -> some View {
        Text(value)
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.blue, in: Circle())
    }
}

private struct NintendoSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var status: AccountMessage?
    @State private var isLoading = false
    let snapshot: NintendoSnapshot?
    let onSynced: (NintendoSnapshot) async throws -> Void

    private var hasSavedSession: Bool { KeychainSecret.read("nintendo.sessionToken") != nil }
    private var accountName: String {
        snapshot?.accountName ?? "Nintendo Switch"
    }

    var body: some View {
        let _ = locale
        PageShell(eyebrow: L10n.tr("平台连接"), title: "Nintendo Switch", subtitle: L10n.tr("使用你的 Nintendo 账号连接游玩记录。")) {
            SettingsPanel(title: snapshot == nil ? L10n.tr("连接账号") : L10n.tr("已连接的账号")) {
                HStack(spacing: 13) {
                    AccountPlatformMark(platform: .nintendo, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountName)
                            .font(.subheadline.weight(.semibold))
                        Text(hasSavedSession ? L10n.tr("登录凭据已保存在本机钥匙串") : L10n.tr("需要登录 Nintendo 账号"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let snapshot, hasSavedSession {
                    HStack {
                        Text(L10n.tr("最近同步"))
                        Spacer()
                        Text(DisplayFormat.syncDate(snapshot.syncedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Divider()
                HStack(spacing: 10) {
                    Button(isLoading ? L10n.tr("连接中…") : hasSavedSession ? L10n.tr("立即同步") : L10n.tr("使用 Nintendo 账号登录")) {
                        Task { await connect(useBrowser: !hasSavedSession) }
                    }
                    .disabled(isLoading)
                    if hasSavedSession {
                        Button(L10n.tr("重新登录")) { Task { await connect(useBrowser: true) } }
                            .disabled(isLoading)
                    }
                    if isLoading { ProgressView().controlSize(.small) }
                }
                if let status {
                    Text(status.text).font(.caption).foregroundStyle(.secondary)
                }
                if !hasSavedSession {
                    Text(L10n.tr("登录窗口由系统打开，Hourcade 不接收你的密码。此连接仍在测试，服务变更可能导致失败。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func connect(useBrowser: Bool) async {
        isLoading = true
        defer { isLoading = false }
        status = nil
        do {
            let login = useBrowser ? try await NintendoWebLogin.shared.authorize() : nil
            let result = try await NintendoAPI.load(
                savedSessionToken: KeychainSecret.read("nintendo.sessionToken"),
                login: login
            )
            if login != nil { try KeychainSecret.save(result.sessionToken, for: "nintendo.sessionToken") }
            try await onSynced(NintendoSnapshot(
                games: result.games,
                syncedAt: .now,
                accountName: result.accountName
            ))
            status = .synced(.now)
        } catch {
            status = .failure(error)
        }
    }
}

private struct PSNSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var status: AccountMessage?
    @State private var isLoading = false
    let snapshot: PSNSnapshot?
    let onSynced: (PSNLibrary) async throws -> Void

    private var hasSavedSession: Bool { KeychainSecret.read("psn.refreshToken") != nil }
    // The Online ID is discovered from the signed-in account, never typed by the user.
    private var accountName: String {
        snapshot?.library.onlineID ?? "PlayStation Network"
    }

    var body: some View {
        let _ = locale
        PageShell(eyebrow: L10n.tr("平台连接"), title: "PlayStation", subtitle: L10n.tr("使用你的 PlayStation 账号连接游玩记录。")) {
            SettingsPanel(title: snapshot == nil ? L10n.tr("连接账号") : L10n.tr("已连接的账号")) {
                HStack(spacing: 13) {
                    AccountPlatformMark(platform: .playStation, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountName)
                            .font(.subheadline.weight(.semibold))
                        Text(hasSavedSession ? L10n.tr("登录凭据已保存在本机钥匙串") : L10n.tr("需要登录 PlayStation 账号"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let snapshot, hasSavedSession {
                    HStack {
                        Text(L10n.tr("最近同步"))
                        Spacer()
                        Text(DisplayFormat.syncDate(snapshot.syncedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Divider()
                HStack(spacing: 10) {
                    Button(isLoading ? L10n.tr("连接中…") : hasSavedSession ? L10n.tr("立即同步") : L10n.tr("使用 PlayStation 账号登录")) {
                        Task { await connect(useBrowser: !hasSavedSession) }
                    }
                    .disabled(isLoading)
                    if hasSavedSession {
                        Button(L10n.tr("重新登录")) { Task { await connect(useBrowser: true) } }
                            .disabled(isLoading)
                    }
                    if isLoading { ProgressView().controlSize(.small) }
                }
                if let status {
                    Text(status.text).font(.caption).foregroundStyle(.secondary)
                }
                if !hasSavedSession {
                    Text(L10n.tr("登录窗口由系统打开，Hourcade 不接收你的密码。此连接仍在测试，服务变更可能导致失败。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func connect(useBrowser: Bool) async {
        isLoading = true
        defer { isLoading = false }
        status = nil
        do {
            let code = useBrowser ? try await PSNWebLogin.shared.authorize() : nil
            let (result, refresh) = try await PSNAPI.load(
                savedRefreshToken: KeychainSecret.read("psn.refreshToken"),
                accessCode: code
            )
            if let refresh { try KeychainSecret.save(refresh, for: "psn.refreshToken") }
            try await onSynced(result)
            status = .synced(.now)
        } catch {
            status = .failure(error)
        }
    }
}

enum KeychainSecret {
    private static let service = "dev.acerola.Hourcade"

    private enum Failure: LocalizedError, CustomNSError {
        case update(OSStatus)
        case save(OSStatus)

        static var errorDomain: String { "Hourcade.Keychain" }
        var errorCode: Int {
            switch self {
            case .update(let status), .save(let status): Int(status)
            }
        }
        var errorDescription: String? {
            switch self {
            case .update: L10n.tr("无法更新钥匙串中的密钥")
            case .save: L10n.tr("无法将密钥保存到钥匙串")
            }
        }
        var errorUserInfo: [String: Any] {
            [NSLocalizedDescriptionKey: errorDescription ?? ""]
        }
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            guard updateStatus == errSecSuccess else {
                throw Failure.update(updateStatus)
            }
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.save(status)
        }
    }
}

/// General preferences, shown inline as a sidebar page rather than in a separate
/// settings window. Both choices write to the shared store so the app and the
/// widgets agree.
/// Cover art cached in the App Group for the overview and the widgets. Every
/// file in the directory is re-downloadable, so deleting it is always safe.
enum ArtworkCache {
    static func usage() async -> (bytes: Int64, files: Int) {
        await measure(directory: SteamWidgetStore.artworkDirectory)
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

struct GeneralSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language: AppLanguage = .system
    @AppStorage(L10n.themeKey, store: L10n.defaults) private var theme: AppTheme = .system
    @State private var cacheBytes: Int64?
    @State private var cacheFiles = 0
    @State private var isClearing = false

    var body: some View {
        let _ = locale
        PageShell(eyebrow: L10n.tr("偏好设置"), title: L10n.tr("常规设置"), subtitle: L10n.tr("这些选项同时应用于 Hourcade 和桌面小组件。")) {
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
