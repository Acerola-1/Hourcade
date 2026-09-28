import SwiftUI

struct SteamSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var account = UserDefaults.standard.string(forKey: "steam.account") ?? ""
    @State private var apiKey = ""
    @State private var isEditing = KeychainSecret.read("steam.apiKey") == nil
    @State private var priceValue: String?

    let snapshot: SteamSnapshot?
    let isRefreshing: Bool
    let syncError: String?
    let onSync: (String, String) async -> Bool

    private var hasConnection: Bool {
        !account.isEmpty && KeychainSecret.read("steam.apiKey") != nil
    }

    var body: some View {
        let _ = locale
        PageShell(title: "Steam", showsHeading: false) {
            if let snapshot, hasConnection, !isEditing {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        PlatformAvatarView(url: snapshot.library.player?.avatarURL, platform: .steam)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.library.player?.name ?? account)
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.format("最近同步 %@", DisplayFormat.syncDate(snapshot.syncedAt)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                Task { _ = await onSync(account, "") }
                            } label: {
                                Label(L10n.tr("立即同步"), systemImage: "arrow.clockwise")
                            }
                            .disabled(isRefreshing)
                            Menu {
                                Button(L10n.tr("更换账号或密钥")) { isEditing = true }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            if isRefreshing { ProgressView().controlSize(.small) }
                        }
                    }
                    if let syncError {
                        Label(syncError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    StatsRow(stats: [
                        .init(value: snapshot.library.player?.level.map { L10n.format("Lv.%lld", $0) } ?? "—", label: L10n.tr("等级")),
                        .init(value: DisplayFormat.totalHours(snapshot.library.totalMinutes), label: L10n.tr("总时长")),
                        .init(value: "\(snapshot.library.games.count)", label: L10n.tr("游戏数量")),
                        .init(value: priceValue ?? "—", label: L10n.tr("参考价值")),
                    ])
                    SteamGameList(games: snapshot.library.games, steamID: snapshot.library.player?.steamID, key: KeychainSecret.read("steam.apiKey") ?? "")
                    DisclosureGroup(L10n.tr("查看连接说明")) { connectionGuide }
                        .padding(.horizontal, 4)
                }
                .task { priceValue = await PriceValue.steamText(snapshot: snapshot) }
                .onReceive(NotificationCenter.default.publisher(for: .pricesDidChange)) { _ in
                    Task { priceValue = await PriceValue.steamText(snapshot: snapshot) }
                }
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

struct NintendoSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var status: AccountMessage?
    @State private var isLoading = false
    @State private var priceValue: String?
    let snapshot: NintendoSnapshot?
    let onSynced: (NintendoSnapshot) async throws -> Void

    private var hasSavedSession: Bool { KeychainSecret.read("nintendo.sessionToken") != nil }
    private var accountName: String {
        snapshot?.accountName ?? "Nintendo Switch"
    }

    var body: some View {
        let _ = locale
        PageShell(title: "Nintendo Switch", showsHeading: false) {
            if let snapshot, hasSavedSession {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        PlatformAvatarView(url: snapshot.avatarURL, platform: .nintendo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.format("最近同步 %@", DisplayFormat.syncDate(snapshot.syncedAt)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                Task { await connect(useBrowser: false) }
                            } label: {
                                Label(L10n.tr("立即同步"), systemImage: "arrow.clockwise")
                            }
                            .disabled(isLoading)
                            Menu {
                                Button(L10n.tr("重新登录")) { Task { await connect(useBrowser: true) } }
                                    .disabled(isLoading)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            if isLoading { ProgressView().controlSize(.small) }
                        }
                    }
                    if let status {
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                    }
                    StatsRow(stats: [
                        .init(value: DisplayFormat.totalHours(snapshot.totalMinutes), label: L10n.tr("总时长")),
                        .init(value: "\(snapshot.games.count)", label: L10n.tr("游戏数量")),
                        .init(value: priceValue ?? "—", label: L10n.tr("参考价值")),
                    ])
                    NintendoGameList(games: snapshot.games)
                }
                .task { priceValue = await PriceValue.nintendoText(snapshot: snapshot) }
                .onReceive(NotificationCenter.default.publisher(for: .pricesDidChange)) { _ in
                    Task { priceValue = await PriceValue.nintendoText(snapshot: snapshot) }
                }
            } else {
                SettingsPanel(title: L10n.tr("连接账号")) {
                    HStack(spacing: 13) {
                        AccountPlatformMark(platform: .nintendo, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName)
                                .font(.subheadline.weight(.semibold))
                            Text(L10n.tr("需要登录 Nintendo 账号"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Button(isLoading ? L10n.tr("连接中…") : L10n.tr("使用 Nintendo 账号登录")) {
                            Task { await connect(useBrowser: true) }
                        }
                        .disabled(isLoading)
                        if isLoading { ProgressView().controlSize(.small) }
                    }
                    if let status {
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                    }
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
                accountName: result.accountName,
                avatarURL: result.avatarURL
            ))
            status = .synced(.now)
        } catch {
            status = .failure(error)
        }
    }
}

struct PSNSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var status: AccountMessage?
    @State private var isLoading = false
    @State private var priceValue: String?
    let snapshot: PSNSnapshot?
    let onSynced: (PSNLibrary) async throws -> Void

    private var hasSavedSession: Bool { KeychainSecret.read("psn.refreshToken") != nil }
    // The Online ID is discovered from the signed-in account, never typed by the user.
    private var accountName: String {
        snapshot?.library.onlineID ?? "PlayStation Network"
    }

    var body: some View {
        let _ = locale
        PageShell(title: "PlayStation", showsHeading: false) {
            if let snapshot, hasSavedSession {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        PlatformAvatarView(url: snapshot.library.avatarURL, platform: .playStation)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.format("最近同步 %@", DisplayFormat.syncDate(snapshot.syncedAt)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                Task { await connect(useBrowser: false) }
                            } label: {
                                Label(L10n.tr("立即同步"), systemImage: "arrow.clockwise")
                            }
                            .disabled(isLoading)
                            Menu {
                                Button(L10n.tr("重新登录")) { Task { await connect(useBrowser: true) } }
                                    .disabled(isLoading)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            if isLoading { ProgressView().controlSize(.small) }
                        }
                    }
                    if let status {
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                    }
                    StatsRow(stats: [
                        .init(value: snapshot.library.trophies?.level.map { L10n.format("Lv.%lld", $0) } ?? "—", label: L10n.tr("等级")),
                        .init(value: DisplayFormat.totalHours(snapshot.library.totalMinutes), label: L10n.tr("总时长")),
                        .init(value: "\(snapshot.library.games.count)", label: L10n.tr("游戏数量")),
                        .init(value: completionRate, label: L10n.tr("完成率")),
                        .init(value: priceValue ?? "—", label: L10n.tr("参考价值")),
                    ])
                    if let counts = snapshot.library.trophies?.earned {
                        TrophyCountRow(counts: counts)
                    }
                    PSNGameList(games: snapshot.library.games)
                }
                .task { priceValue = await PriceValue.psnText(snapshot: snapshot) }
                .onReceive(NotificationCenter.default.publisher(for: .pricesDidChange)) { _ in
                    Task { priceValue = await PriceValue.psnText(snapshot: snapshot) }
                }
            } else {
                SettingsPanel(title: L10n.tr("连接账号")) {
                    HStack(spacing: 13) {
                        AccountPlatformMark(platform: .playStation, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName)
                                .font(.subheadline.weight(.semibold))
                            Text(L10n.tr("需要登录 PlayStation 账号"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Button(isLoading ? L10n.tr("连接中…") : L10n.tr("使用 PlayStation 账号登录")) {
                            Task { await connect(useBrowser: true) }
                        }
                        .disabled(isLoading)
                        if isLoading { ProgressView().controlSize(.small) }
                    }
                    if let status {
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.tr("登录窗口由系统打开，Hourcade 不接收你的密码。此连接仍在测试，服务变更可能导致失败。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var completionRate: String {
        guard let trophies = snapshot?.library.trophies,
              let earned = trophies.earnedTotal, let defined = trophies.definedTotal, defined > 0
        else { return "—" }
        return L10n.format("%.1f%%", Double(earned) / Double(defined) * 100)
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
