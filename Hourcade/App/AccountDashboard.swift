import SwiftUI
import Security

private enum DashboardPage: String, CaseIterable, Identifiable {
    case steam, nintendo, playStation, studio
    var id: Self { self }
    var title: String {
        switch self {
        case .steam: "Steam"
        case .nintendo: "Nintendo Switch"
        case .playStation: "PlayStation"
        case .studio: "组件预览"
        }
    }
    var symbol: String {
        switch self {
        case .steam: "gamecontroller.fill"
        case .nintendo: "switch.2"
        case .playStation: "playstation.logo"
        case .studio: "square.grid.2x2"
        }
    }
}

struct ContentView: View {
    @State private var selection: DashboardPage? = .steam
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("平台账号") {
                    ForEach([DashboardPage.steam, .nintendo, .playStation]) { page in
                        Label(page.title, systemImage: page.symbol).tag(page)
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
            switch selection ?? .steam {
            case .steam: SteamSettingsView()
            case .nintendo: NintendoSettingsView()
            case .playStation: PSNSettingsView()
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
    @State private var result: SteamLibrary?
    @State private var message = "尚未同步"
    @State private var isLoading = false

    var body: some View {
        PageShell(eyebrow: "官方 Web API", title: "Steam", subtitle: "连接游戏库，读取累计与近两周游玩时长。") {
            SettingsPanel(title: "账号连接") {
                LabeledContent("SteamID 或个人资料链接") {
                    TextField("17 位 SteamID、/profiles/… 或 /id/…", text: $account)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 390)
                }
                LabeledContent("Web API Key") {
                    SecureField(KeychainSecret.read("steam.apiKey") == nil ? "输入你的 API Key" : "已保存在钥匙串；留空沿用", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 390)
                }
                HStack(spacing: 12) {
                    Button(isLoading ? "同步中…" : "保存并同步") {
                        Task { await sync() }
                    }
                    .disabled(isLoading || account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("密钥只保存在本机钥匙串。游戏库需允许接口读取；私密资料可能返回空列表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let result {
                SettingsPanel(title: "最近一次同步") {
                    HStack(spacing: 34) {
                        metric("游戏数", "\(result.games.count)")
                        metric("累计游玩", hours(result.totalMinutes))
                        metric("近两周", hours(result.fortnightMinutes))
                    }
                    if !result.games.isEmpty {
                        Divider()
                        Text("最近玩的游戏").font(.subheadline.weight(.semibold))
                        ForEach(result.recent.prefix(5)) { game in
                            HStack {
                                Text(game.name)
                                Spacer()
                                Text(hours(game.fortnightMinutes)).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            SettingsPanel(title: "数据口径") {
                Text("Steam 返回已拥有游戏的累计时长和近期游玩的近两周时长。游戏数是接口返回的库条目数；当前标价合计不在此接口内。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hours(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    @MainActor
    private func sync() async {
        isLoading = true
        defer { isLoading = false }
        let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = enteredKey.isEmpty ? KeychainSecret.read("steam.apiKey") : enteredKey
        guard let key, !key.isEmpty else {
            message = "请输入 Steam Web API Key"
            return
        }
        do {
            let library = try await SteamAPI.load(account: account, key: key)
            if !enteredKey.isEmpty { try KeychainSecret.save(enteredKey, for: "steam.apiKey"); apiKey = "" }
            UserDefaults.standard.set(account.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "steam.account")
            result = library
            message = library.games.isEmpty ? "接口没有返回游戏；请检查游戏详情隐私设置" : "同步成功 · \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct NintendoSettingsView: View {
    @State private var executablePath = UserDefaults.standard.string(forKey: "nintendo.nxapiPath") ?? ""
    @State private var games: [NintendoGame]?
    @State private var status = "尚未同步"
    @State private var isLoading = false

    var body: some View {
        PageShell(eyebrow: "nxapi · 实验性连接", title: "Nintendo Switch", subtitle: "使用已登录的 nxapi 读取 Nintendo Switch Online 游玩记录。") {
            SettingsPanel(title: "本机接入") {
                LabeledContent("nxapi 可执行文件") {
                    TextField("例如 /opt/homebrew/bin/nxapi", text: $executablePath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 390)
                }
                HStack(spacing: 12) {
                    Button(isLoading ? "同步中…" : "读取游玩记录") { Task { await sync() } }
                        .disabled(isLoading || executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("先安装 nxapi，并在终端执行 nxapi nso auth，通过 Nintendo 登录页完成授权。Hourcade 调用本机 nxapi nso play-activity --json，不接收 Nintendo 密码。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("查看 nxapi 项目与安装说明", destination: URL(string: "https://github.com/samuelthomas2774/nxapi")!)
            }
            if let games {
                SettingsPanel(title: "最近一次同步") {
                    HStack(spacing: 30) {
                        VStack(alignment: .leading) {
                            Text("\(games.count)").font(.title2.bold().monospacedDigit())
                            Text("游玩记录").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(games.reduce(0) { $0 + $1.totalPlayTime } / 60)h").font(.title2.bold().monospacedDigit())
                            Text("累计时长").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ForEach(games.prefix(5)) { game in
                        HStack {
                            Text(game.name)
                            Spacer()
                            Text("\(game.totalPlayTime / 60)h").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            SettingsPanel(title: "数据口径") {
                Text("NSO PlayLog 提供游戏名称、封面、累计时长和首次游玩时间。它没有近 14 天逐游戏时长；若要准确计算，需另接家长控制每日摘要。nxapi 调用非公开接口，认证默认依赖第三方辅助服务。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func sync() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await NintendoCLI.load(executablePath: executablePath)
            UserDefaults.standard.set(executablePath.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "nintendo.nxapiPath")
            games = result
            status = "同步成功 · \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            status = error.localizedDescription
        }
    }
}

private struct PSNSettingsView: View {
    @State private var onlineID = UserDefaults.standard.string(forKey: "psn.onlineID") ?? ""
    @State private var npsso = ""
    @State private var library: PSNLibrary?
    @State private var status = "尚未同步"
    @State private var isLoading = false

    var body: some View {
        PageShell(eyebrow: "非公开接口 · 实验性连接", title: "PlayStation", subtitle: "读取已玩游戏及累计时长；需要 PSN 登录会话。") {
            SettingsPanel(title: "账号连接") {
                LabeledContent("PSN Online ID") {
                    TextField("你的 PSN ID", text: $onlineID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 390)
                }
                LabeledContent("NPSSO 会话令牌") {
                    SecureField(KeychainSecret.read("psn.refreshToken") == nil ? "从 Sony 登录会话获取" : "已有刷新令牌；留空沿用", text: $npsso)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 390)
                }
                HStack(spacing: 12) {
                    Button(isLoading ? "同步中…" : "连接并同步") { Task { await sync() } }
                        .disabled(isLoading || onlineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("NPSSO 与密码同等敏感。仅在内存中用于向 Sony 换取访问令牌；本机钥匙串只保存刷新令牌。此连接依赖逆向接口，可能失效。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("查看获取 NPSSO 的开源项目说明", destination: URL(string: "https://github.com/achievements-app/psn-api/blob/main/website/docs/authentication/authenticating-manually.md")!)
            }
            if let library {
                SettingsPanel(title: "最近一次同步") {
                    HStack(spacing: 30) {
                        VStack(alignment: .leading) {
                            Text("\(library.games.count)").font(.title2.bold().monospacedDigit())
                            Text("已玩游戏").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(library.totalMinutes / 60)h").font(.title2.bold().monospacedDigit())
                            Text("累计时长").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ForEach(library.games.prefix(5)) { game in
                        HStack {
                            Text(game.name)
                            Spacer()
                            Text("\(game.lifetimeMinutes / 60)h").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            SettingsPanel(title: "数据口径") {
                Text("开源 psn-api 使用已认证会话搜索 Online ID，再读取 played games。该列表代表已玩游戏，不等同于拥有的游戏库。接口只给累计时长；近 14 天需持续记录快照后计算。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func sync() async {
        isLoading = true
        defer { isLoading = false; npsso = "" }
        let entered = npsso.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let (result, refresh) = try await PSNAPI.load(
                onlineID: onlineID.trimmingCharacters(in: .whitespacesAndNewlines),
                npsso: entered.isEmpty ? nil : entered,
                savedRefreshToken: KeychainSecret.read("psn.refreshToken")
            )
            if let refresh { try KeychainSecret.save(refresh, for: "psn.refreshToken") }
            UserDefaults.standard.set(onlineID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "psn.onlineID")
            library = result
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
