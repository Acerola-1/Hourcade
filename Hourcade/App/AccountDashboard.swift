import SwiftUI
import Security

private enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, steam, nintendo, playStation, studio
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "总览"
        case .steam: "Steam"
        case .nintendo: "Nintendo Switch"
        case .playStation: "PlayStation"
        case .studio: "组件预览"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .steam: "gamecontroller.fill"
        case .nintendo: "switch.2"
        case .playStation: "playstation.logo"
        case .studio: "square.grid.2x2"
        }
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
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

struct ContentView: View {
    @State private var selection: DashboardPage? = .overview
    @State private var steamSnapshot: SteamSnapshot? = LocalSnapshotStore.load("steam")
    @State private var nintendoSnapshot: NintendoSnapshot? = LocalSnapshotStore.load("nintendo")
    @State private var psnSnapshot: PSNSnapshot? = LocalSnapshotStore.load("psn")
    @State private var steamSyncing = false
    @State private var steamError: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(DashboardPage.overview.title, systemImage: DashboardPage.overview.symbol)
                    .tag(DashboardPage.overview)
                Section("平台账号") {
                    ForEach([DashboardPage.steam, .nintendo, .playStation]) { page in
                        HStack(spacing: 10) {
                            AccountPlatformMark(platform: page.platform!, size: 27)
                            Text(page.title)
                        }
                        .tag(page)
                    }
                }
                Section("设计") {
                    Label(DashboardPage.studio.title, systemImage: DashboardPage.studio.symbol)
                        .tag(DashboardPage.studio)
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
                    refreshError: steamError,
                    selectPlatform: { platform in
                        switch platform {
                        case .steam: selection = .steam
                        case .nintendo: selection = .nintendo
                        case .playStation: selection = .playStation
                        }
                    },
                    refreshSteam: { Task { await autoRefreshSteam() } }
                )
            case .steam:
                SteamSettingsView(
                    snapshot: steamSnapshot,
                    isRefreshing: steamSyncing,
                    syncError: steamError,
                    onSync: syncSteam
                )
            case .nintendo:
                NintendoSettingsView(snapshot: nintendoSnapshot) { games in
                    let newSnapshot = NintendoSnapshot(games: games, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "nintendo")
                    nintendoSnapshot = newSnapshot
                }
            case .playStation:
                PSNSettingsView(snapshot: psnSnapshot) { library in
                    let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "psn")
                    psnSnapshot = newSnapshot
                }
            case .studio:
                ContentUnavailableView {
                    Label("组件设计稿", systemImage: "square.grid.2x2")
                } description: {
                    Text("A、A2、B、C、D 与早期探索稿都已保留。")
                } actions: {
                    Button("打开组件预览") { openWindow(id: "widget-studio") }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 610)
        .task { await autoRefreshSteam() }
    }

    @MainActor
    private func autoRefreshSteam() async {
        guard let account = UserDefaults.standard.string(forKey: "steam.account"),
              !account.isEmpty, let key = KeychainSecret.read("steam.apiKey")
        else { return }
        _ = await syncSteam(account, key)
    }

    @MainActor
    private func syncSteam(_ account: String, _ enteredKey: String) async -> Bool {
        guard !steamSyncing else { return false }
        steamSyncing = true
        steamError = nil
        defer { steamSyncing = false }
        let key = enteredKey.isEmpty ? KeychainSecret.read("steam.apiKey") : enteredKey
        guard let key, !key.isEmpty else {
            steamError = "请输入 Web API Key"
            return false
        }
        do {
            let library = try await SteamAPI.load(account: account, key: key)
            let newSnapshot = SteamSnapshot(library: library, syncedAt: .now)
            if !enteredKey.isEmpty { try KeychainSecret.save(enteredKey, for: "steam.apiKey") }
            try LocalSnapshotStore.save(newSnapshot, as: "steam")
            UserDefaults.standard.set(account.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "steam.account")
            steamSnapshot = newSnapshot
            if library.games.isEmpty {
                steamError = "Steam 没有返回游戏。请检查个人资料的“游戏详情”隐私设置；改为公开会让其他人也能查看相关游戏信息"
            }
            return true
        } catch {
            steamError = error.localizedDescription
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
        PageShell(eyebrow: "平台连接", title: "Steam", subtitle: "连接你的 Steam 账号，游玩数据会显示在总览。") {
            if hasConnection && !isEditing {
                SettingsPanel(title: "已连接的账号") {
                    HStack(spacing: 14) {
                        AccountPlatformMark(platform: .steam, size: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(account).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Label("API Key 已保存在本机钥匙串", systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("最近同步")
                        Spacer()
                        Text(snapshot.map { DisplayFormat.syncDate($0.syncedAt) } ?? "尚未同步")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    if let syncError {
                        Label(syncError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("立即同步") { Task { _ = await onSync(account, "") } }
                            .disabled(isRefreshing)
                        if isRefreshing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("更换账号或密钥") { isEditing = true }
                    }
                }
                DisclosureGroup("查看连接说明") { connectionGuide }
                    .padding(.horizontal, 4)
            } else {
                connectionGuide
                SettingsPanel(title: "连接你的账号") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("个人资料链接").font(.subheadline.weight(.medium))
                        TextField("粘贴你的 steamcommunity.com 个人主页地址", text: $account)
                            .textFieldStyle(.roundedBorder)
                        Text("例如 steamcommunity.com/id/你的名称；也支持 17 位 SteamID。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Web API Key").font(.subheadline.weight(.medium))
                        SecureField(hasConnection ? "留空沿用已保存的密钥" : "粘贴从 Steam 官方页面取得的密钥", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("只用于向 Steam 请求你的游戏记录，保存在本机钥匙串。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let syncError {
                        Label(syncError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button(isRefreshing ? "连接中…" : "连接并同步") {
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
                            Button("取消") { apiKey = ""; isEditing = false }
                        }
                    }
                }
            }
        }
    }

    private var connectionGuide: some View {
        SettingsPanel(title: "首次连接 · 两步完成") {
            HStack(alignment: .top, spacing: 12) {
                stepNumber("1")
                VStack(alignment: .leading, spacing: 5) {
                    Text("复制个人资料地址").font(.subheadline.weight(.semibold))
                    Text("在 Steam 客户端打开自己的个人资料，复制页面地址。你也可以在浏览器打开 Steam 社区个人主页。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                stepNumber("2")
                VStack(alignment: .leading, spacing: 5) {
                    Text("获取 Web API Key").font(.subheadline.weight(.semibold))
                    Text("Steam 客户端内没有密钥入口。请在浏览器登录 Steam 官方密钥页面，查看或申请密钥，再复制到下方。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Link("打开 Steam 官方密钥页面 ↗", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                        .font(.subheadline)
                }
            }
            Text("这是当前测试版的接入方式。Web API Key 属于开发者凭据，正式版还需改进授权流程。请勿把密钥发给他人。")
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
    @State private var executablePath = UserDefaults.standard.string(forKey: "nintendo.nxapiPath") ?? ""
    @State private var status = "尚未同步"
    @State private var isLoading = false
    let snapshot: NintendoSnapshot?
    let onSynced: ([NintendoGame]) throws -> Void

    var body: some View {
        PageShell(eyebrow: "平台连接", title: "Nintendo Switch", subtitle: "Nintendo 账号接入正在开发。") {
            SettingsPanel(title: snapshot == nil ? "Nintendo 账号" : "已连接的账号") {
                HStack(spacing: 13) {
                    AccountPlatformMark(platform: .nintendo, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot == nil ? "尚未连接" : "Nintendo Switch")
                            .font(.subheadline.weight(.semibold))
                        Text(snapshot == nil ? "应用内登录尚在适配" : "游玩记录已保存到本机")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let snapshot {
                    Divider()
                    HStack {
                        Text("最近同步")
                        Spacer()
                        Text(DisplayFormat.syncDate(snapshot.syncedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            SettingsPanel(title: "连接进度") {
                Text("目前还不能直接在 Hourcade 内登录 Nintendo 账号。连接方式完成后，你的游玩记录会显示在总览。")
                    .foregroundStyle(.secondary)
                Text("这里暂时不需要你安装工具或输入密码。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("已有 nxapi 的用户 · 实验性连接") {
                SettingsPanel(title: "读取现有 nxapi 会话") {
                    TextField("nxapi 可执行文件的绝对路径", text: $executablePath)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 12) {
                        Button(isLoading ? "同步中…" : "读取游玩记录") { Task { await sync() } }
                            .disabled(isLoading || executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLoading { ProgressView().controlSize(.small) }
                    }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Text("此入口只供已经自行安装并登录 nxapi 的用户使用。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("它调用 Nintendo 的非公开接口，认证默认依赖额外服务，可能随时失效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @MainActor
    private func sync() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await NintendoCLI.load(executablePath: executablePath)
            UserDefaults.standard.set(executablePath.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "nintendo.nxapiPath")
            try onSynced(result)
            status = "同步成功 · \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            status = error.localizedDescription
        }
    }
}

private struct PSNSettingsView: View {
    @State private var onlineID = UserDefaults.standard.string(forKey: "psn.onlineID") ?? ""
    @State private var npsso = ""
    @State private var status: String?
    @State private var isLoading = false
    let snapshot: PSNSnapshot?
    let onSynced: (PSNLibrary) throws -> Void

    private var hasSavedSession: Bool { KeychainSecret.read("psn.refreshToken") != nil }

    var body: some View {
        PageShell(eyebrow: "平台连接", title: "PlayStation", subtitle: "使用你的 PlayStation 账号连接游玩记录。") {
            SettingsPanel(title: snapshot == nil ? "连接账号" : "已连接的账号") {
                HStack(spacing: 13) {
                    AccountPlatformMark(platform: .playStation, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(onlineID.isEmpty ? "PlayStation Network" : onlineID)
                            .font(.subheadline.weight(.semibold))
                        Text(hasSavedSession ? "登录凭据已保存在本机钥匙串" : "需要登录 PlayStation 账号")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let snapshot, hasSavedSession {
                    HStack {
                        Text("最近同步")
                        Spacer()
                        Text(DisplayFormat.syncDate(snapshot.syncedAt))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Divider()
                TextField("你的 PSN Online ID", text: $onlineID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)
                HStack(spacing: 10) {
                    Button(isLoading ? "连接中…" : hasSavedSession ? "立即同步" : "使用 PlayStation 账号登录") {
                        Task { await connect(useBrowser: !hasSavedSession) }
                    }
                    .disabled(isLoading || onlineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasSavedSession {
                        Button("重新登录") { Task { await connect(useBrowser: true) } }
                            .disabled(isLoading)
                    }
                    if isLoading { ProgressView().controlSize(.small) }
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("登录窗口由系统打开，Hourcade 不接收你的密码。此连接仍在测试，服务变更可能导致失败。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("登录遇到问题？高级接入方式") {
                SettingsPanel(title: "使用现有 PSN 会话") {
                    SecureField("NPSSO 会话令牌", text: $npsso)
                        .textFieldStyle(.roundedBorder)
                    Button("使用会话令牌同步") { Task { await connect(useBrowser: false, useNPSSO: true) } }
                        .disabled(isLoading || npsso.isEmpty || onlineID.isEmpty)
                    Text("NPSSO 与密码同等敏感；仅用于向 Sony 换取访问令牌。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @MainActor
    private func connect(useBrowser: Bool, useNPSSO: Bool = false) async {
        isLoading = true
        defer { isLoading = false; npsso = "" }
        status = nil
        do {
            let code = useBrowser ? try await PSNWebLogin.shared.authorize() : nil
            let entered = npsso.trimmingCharacters(in: .whitespacesAndNewlines)
            let (result, refresh) = try await PSNAPI.load(
                onlineID: onlineID.trimmingCharacters(in: .whitespacesAndNewlines),
                npsso: useNPSSO ? entered : nil,
                savedRefreshToken: KeychainSecret.read("psn.refreshToken"),
                accessCode: code
            )
            if let refresh { try KeychainSecret.save(refresh, for: "psn.refreshToken") }
            UserDefaults.standard.set(onlineID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "psn.onlineID")
            try onSynced(result)
            status = "同步成功 · \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            status = error.localizedDescription
        }
    }
}

enum KeychainSecret {
    private static let service = "dev.acerola.Hourcade"

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
                throw NSError(domain: "Hourcade.Keychain", code: Int(updateStatus), userInfo: [NSLocalizedDescriptionKey: "无法更新钥匙串中的密钥"])
            }
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Hourcade.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法将密钥保存到钥匙串"])
        }
    }
}
