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

    /// List-style hours: whole hours above one hour, one decimal below.
    static func compactHours(_ minutes: Int) -> String {
        guard minutes >= 3 else { return "0" }
        let hours = Double(minutes) / 60
        if hours >= 1 {
            return L10n.format("%lld 小时", Int(hours.rounded()))
        }
        return L10n.format("%.1f 小时", hours)
    }

    /// Stat-card hours with a decimal and locale grouping: 1,300.6 小时.
    static func totalHours(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return hours.formatted(.number.locale(L10n.locale).precision(.fractionLength(1))) + " " + L10n.tr("小时")
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
                    refreshPrices()
                }
            case .playStation:
                PSNSettingsView(snapshot: psnSnapshot) { library in
                    let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "psn")
                    psnSnapshot = newSnapshot
                    try saveWidgetSnapshots()
                    reloadWidgets()
                    refreshPrices()
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
            refreshPrices()
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
        refreshPrices()
    }

    @MainActor
    private func refreshNintendo() async {
        guard let token = KeychainSecret.read("nintendo.sessionToken") else { return }
        do {
            let result = try await NintendoAPI.load(savedSessionToken: token, login: nil)
            let newSnapshot = NintendoSnapshot(
                games: result.games,
                syncedAt: .now,
                accountName: result.accountName ?? nintendoSnapshot?.accountName,
                avatarURL: result.avatarURL ?? nintendoSnapshot?.avatarURL
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
            refreshPrices()
            return true
        } catch {
            steamError = .failure(error)
            return false
        }
    }

    /// Price sweeps run in the background after syncs; pages only ever read
    /// the cached results. The stores themselves throttle to a 24h TTL.
    @MainActor
    private func refreshPrices() {
        let region = PricingRegion.resolve(L10n.defaults.string(forKey: "pricingRegion"), steamCountry: steamSnapshot?.library.player?.countryCode)
        let steamAppIDs = steamSnapshot?.library.games.map(\.id) ?? []
        let nintendoTitleIds = nintendoSnapshot?.games.compactMap(\.titleId) ?? []
        let psnTitles = (psnSnapshot?.library.games.compactMap { game -> (titleId: String, conceptId: String)? in
            guard let conceptId = game.conceptId else { return nil }
            return (game.id, conceptId)
        }) ?? []
        guard !steamAppIDs.isEmpty || !nintendoTitleIds.isEmpty || !psnTitles.isEmpty else { return }
        let storefront = region.psnLocale
        let chihiro = region.chihiroCountry
        Task.detached(priority: .utility) {
            // Sweep 横跨几分钟；申请用户级活动避免后台 AppNap 冻结下载。
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Hourcade price sweep")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            async let steam: Void = SteamPriceStore.shared.sweep(appIDs: steamAppIDs)
            async let nintendo: Void = NintendoPriceStore.shared.sweep(titleIds: nintendoTitleIds)
            async let psn: Void = PSNPriceStore.shared.sweep(titles: psnTitles, storefront: storefront, chihiroCountry: chihiro)
            _ = await (steam, nintendo, psn)
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
    let title: String
    var showsHeading = true
    var eyebrow: String? = nil
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if showsHeading {
                    if let eyebrow {
                        Text(eyebrow.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                    }
                    Text(title).font(.largeTitle.bold())
                    if let subtitle {
                        Text(subtitle).foregroundStyle(.secondary)
                    }
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

/// The account's own avatar with the platform mark as the fallback; the mark
/// stays visible while the avatar loads.
private struct PlatformAvatarView: View {
    let url: URL?
    let platform: GamePlatform
    var size: CGFloat = 52
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            } else {
                AccountPlatformMark(platform: platform, size: size)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await CoverStore.shared.image(primary: url, fallback: nil, appID: nil)
        }
    }
}

private struct StatsRow: View {
    struct Stat {
        let value: String
        let label: String
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stats.indices, id: \.self) { index in
                if index > 0 {
                    Divider().frame(height: 38).padding(.horizontal, 18)
                }
                VStack(spacing: 4) {
                    Text(stats[index].value)
                        .font(.title3.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(stats[index].label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }
}

private enum TrophyPalette {
    static let platinum = Color(red: 0.72, green: 0.78, blue: 0.86)
    static let gold = Color(red: 0.98, green: 0.79, blue: 0.25)
    static let silver = Color(red: 0.71, green: 0.75, blue: 0.82)
    static let bronze = Color(red: 0.80, green: 0.51, blue: 0.28)
}

private struct TrophyCountRow: View {
    let counts: PSNTrophyCounts

    var body: some View {
        HStack(spacing: 22) {
            trophy(L10n.tr("白金"), count: counts.platinum, color: TrophyPalette.platinum)
            trophy(L10n.tr("黄金"), count: counts.gold, color: TrophyPalette.gold)
            trophy(L10n.tr("白银"), count: counts.silver, color: TrophyPalette.silver)
            trophy(L10n.tr("黄铜"), count: counts.bronze, color: TrophyPalette.bronze)
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }

    private func trophy(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.subheadline.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared chrome for the platform game lists: a "My games · N" title, the
/// platform's own column headers, and the lazy rows below.
private struct GameListPanel<Rows: View>: View {
    let count: Int
    let columns: [String]
    let columnWidths: [CGFloat]
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format("我的游戏 · %lld", count))
                .font(.title3.bold())
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(L10n.tr("游戏"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: columnWidths[index], alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                LazyVStack(spacing: 0) {
                    rows
                }
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct SteamGameList: View {
    let games: [SteamGame]
    let steamID: String?
    let key: String

    var body: some View {
        let sorted = games.sorted { lhs, rhs in
            if lhs.fortnightMinutes != rhs.fortnightMinutes { return lhs.fortnightMinutes > rhs.fortnightMinutes }
            switch (lhs.lastPlayedDate, rhs.lastPlayedDate) {
            case let (l?, r?): if l != r { return l > r }
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            return lhs.lifetimeMinutes > rhs.lifetimeMinutes
        }
        GameListPanel(count: games.count, columns: [L10n.tr("两周内"), L10n.tr("上次游玩"), L10n.tr("成就")], columnWidths: [64, 78, 62]) {
            ForEach(sorted) { game in
                SteamGameRow(game: game, steamID: steamID, key: key)
                Divider().padding(.leading, 16)
            }
        }
    }
}

private struct SteamGameRow: View {
    let game: SteamGame
    let steamID: String?
    let key: String
    @State private var achievements: SteamAchievementStore.Entry?

    var body: some View {
        HStack(spacing: 12) {
            GameCover(
                primary: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.id)/header.jpg"),
                fallback: nil,
                storeAppID: game.id,
                size: CGSize(width: 84, height: 39)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(DisplayFormat.compactHours(game.lifetimeMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.compactHours(game.fortnightMinutes))
                .font(.callout.monospacedDigit())
                .frame(width: 64, alignment: .leading)
            Text(DisplayFormat.relative(game.lastPlayedDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Group {
                if let achievements {
                    Text("\(achievements.earned)/\(achievements.total)")
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .frame(width: 62, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .task(id: game.id) {
            guard achievements == nil, !key.isEmpty, let steamID, !steamID.isEmpty else { return }
            achievements = await SteamAchievementStore.shared.summary(appID: game.id, steamID: steamID, key: key)
        }
    }
}

private struct NintendoGameList: View {
    let games: [NintendoGame]

    var body: some View {
        let sorted = games.sorted { lhs, rhs in
            if lhs.fortnightMinutes != rhs.fortnightMinutes { return lhs.fortnightMinutes > rhs.fortnightMinutes }
            switch (lhs.lastPlayedDate, rhs.lastPlayedDate) {
            case let (l?, r?): if l != r { return l > r }
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            return lhs.totalPlayTime > rhs.totalPlayTime
        }
        GameListPanel(count: games.count, columns: [L10n.tr("两周内"), L10n.tr("上次游玩")], columnWidths: [64, 78]) {
            ForEach(sorted) { game in
                NintendoGameRow(game: game)
                Divider().padding(.leading, 16)
            }
        }
    }
}

private struct NintendoGameRow: View {
    let game: NintendoGame

    var body: some View {
        HStack(spacing: 12) {
            GameCover(primary: URL(string: game.imageUri), fallback: nil, storeAppID: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(DisplayFormat.compactHours(game.totalPlayTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.compactHours(game.fortnightMinutes))
                .font(.callout.monospacedDigit())
                .frame(width: 64, alignment: .leading)
            Text(DisplayFormat.relative(game.lastPlayedDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

private struct PSNGameList: View {
    let games: [PSNGame]

    var body: some View {
        let sorted = games.sorted { lhs, rhs in
            switch (lhs.lastPlayedDate, rhs.lastPlayedDate) {
            case let (l?, r?): if l != r { return l > r }
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            return lhs.lifetimeMinutes > rhs.lifetimeMinutes
        }
        GameListPanel(count: games.count, columns: [L10n.tr("奖杯数"), L10n.tr("奖杯进度"), L10n.tr("游戏时长")], columnWidths: [136, 46, 64]) {
            ForEach(sorted) { game in
                PSNGameRow(game: game)
                Divider().padding(.leading, 16)
            }
        }
    }
}

private struct PSNGameRow: View {
    let game: PSNGame
    @State private var trophies: PSNTrophyStore.Entry?

    var body: some View {
        HStack(spacing: 12) {
            GameCover(primary: game.imageURL, fallback: nil, storeAppID: nil)
            Text(game.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Group {
                if let trophies {
                    HStack(spacing: 8) {
                        miniTrophy(TrophyPalette.platinum, count: trophies.platinum, digits: 7)
                        miniTrophy(TrophyPalette.gold, count: trophies.gold, digits: 13)
                        miniTrophy(TrophyPalette.silver, count: trophies.silver, digits: 13)
                        miniTrophy(TrophyPalette.bronze, count: trophies.bronze, digits: 19)
                    }
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 136, alignment: .leading)
            Group {
                if let trophies {
                    Text("\(trophies.progress)%").monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .frame(width: 46, alignment: .leading)
            Text(DisplayFormat.compactHours(game.lifetimeMinutes))
                .font(.callout.monospacedDigit())
                .frame(width: 64, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .task(id: game.id) {
            guard trophies == nil else { return }
            trophies = await PSNTrophyStore.shared.summary(titleId: game.id)
        }
    }

    /// One trophy tier inside the list row. Every tier gets a fixed-width slot
    /// sized for its plausible digit count (platinum 1, gold/silver 2, bronze 3),
    /// so the same tier lines up vertically across all rows.
    private func miniTrophy(_ color: Color, count: Int, digits: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 8))
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: digits, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(color)
    }
}

/// 计价地区：决定价格查询的国家（cc/country/storefront）与显示货币。
/// UI 语言与计价地区是两个独立维度。
enum PricingRegion: String, CaseIterable, Identifiable {
    case auto, cn, hk, jp, us, gb, de, kr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: L10n.tr("跟随 Steam 账号")
        case .cn: L10n.tr("中国大陆")
        case .hk: L10n.tr("香港")
        case .jp: L10n.tr("日本")
        case .us: L10n.tr("美国")
        case .gb: L10n.tr("英国")
        case .de: L10n.tr("欧元区")
        case .kr: L10n.tr("韩国")
        }
    }

    var steamCC: String {
        switch self {
        case .auto: "US"
        case .cn: "CN"
        case .hk: "HK"
        case .jp: "JP"
        case .us: "US"
        case .gb: "GB"
        case .de: "DE"
        case .kr: "KR"
        }
    }

    /// 展示货币固定人民币：港服价与任天堂美区价都按汇率折算。
    var currencyCode: String {
        switch self {
        case .auto: "USD"
        case .cn: "CNY"
        case .hk: "CNY"
        case .jp: "JPY"
        case .us: "USD"
        case .gb: "GBP"
        case .de: "EUR"
        case .kr: "KRW"
        }
    }

    /// PS Store has no mainland-China storefront; CN falls back to the HK one
    /// and the HKD price is converted at display time.
    var psnLocale: String {
        switch self {
        case .auto: "en-us"
        case .cn: "en-hk"
        case .hk: "en-hk"
        case .jp: "ja-jp"
        case .us: "en-us"
        case .gb: "en-gb"
        case .de: "de-de"
        case .kr: "ko-kr"
        }
    }

    var chihiroCountry: String {
        switch self {
        case .auto: "US/en"
        case .cn: "HK/en"
        case .hk: "HK/en"
        case .jp: "JP/ja"
        case .us: "US/en"
        case .gb: "GB/en"
        case .de: "DE/de"
        case .kr: "KR/ko"
        }
    }

    /// 查询区固定港服：实测港区商店覆盖用户库存的 92%（289/312），而国区
    /// 仅 57%——大量游戏不在国区上架。价格统一按汇率折算成人民币展示。
    static func resolve(_ raw: String?, steamCountry: String?) -> PricingRegion {
        .hk
    }
}

/// 价格汇总的读取与格式化；只读缓存，任何调用都不会触发网络请求。
@MainActor
enum PriceValue {
    static func steamText(snapshot: SteamSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        let region = PricingRegion.resolve(L10n.defaults.string(forKey: "pricingRegion"), steamCountry: snapshot.library.player?.countryCode)
        guard let sum = await SteamPriceStore.shared.totalValue(appIDs: snapshot.library.games.map(\.id)),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: region.currencyCode)
    }

    static func nintendoText(snapshot: NintendoSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        let region = PricingRegion.resolve(L10n.defaults.string(forKey: "pricingRegion"), steamCountry: nil)
        guard let sum = await NintendoPriceStore.shared.totalValue(titleIds: snapshot.games.compactMap(\.titleId)),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: region.currencyCode)
    }

    static func psnText(snapshot: PSNSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        let region = PricingRegion.resolve(L10n.defaults.string(forKey: "pricingRegion"), steamCountry: nil)
        let titleIds = snapshot.library.games.map(\.id)
        guard let sum = await PSNPriceStore.shared.totalValue(titleIds: titleIds),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: region.currencyCode)
    }

    /// Overview aggregate: every priced platform contributes in its own query
    /// currency, all converted to the pricing region's currency.
    static func overviewText(steam: SteamSnapshot?, nintendo: NintendoSnapshot?, playStation: PSNSnapshot?) async -> String? {
        let region = PricingRegion.resolve(L10n.defaults.string(forKey: "pricingRegion"), steamCountry: steam?.library.player?.countryCode)
        var total = 0.0
        var any = false
        if let sum = await SteamPriceStore.shared.totalValue(appIDs: steam?.library.games.map(\.id) ?? []),
           let currency = sum.currency {
            any = true
            if currency == region.currencyCode {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: region.currencyCode) {
                total += sum.amount * rate
            }
        }
        if let sum = await NintendoPriceStore.shared.totalValue(titleIds: nintendo?.games.compactMap(\.titleId) ?? []),
           let currency = sum.currency {
            any = true
            if currency == region.currencyCode {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: region.currencyCode) {
                total += sum.amount * rate
            }
        }
        if let sum = await PSNPriceStore.shared.totalValue(titleIds: playStation?.library.games.map(\.id) ?? []),
           let currency = sum.currency {
            any = true
            if currency == region.currencyCode {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: region.currencyCode) {
                total += sum.amount * rate
            }
        }
        guard any else { return nil }
        return await formatted(total, from: region.currencyCode, to: region.currencyCode)
    }

    private static func formatted(_ amount: Double, from currency: String, to display: String) async -> String? {
        let converted: Double
        if currency == display {
            converted = amount
        } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: display) {
            converted = amount * rate
        } else {
            return nil
        }
        return converted.formatted(.currency(code: display).presentation(.narrow))
    }
}

private struct SteamSettingsView: View {
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

private struct NintendoSettingsView: View {
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

private struct PSNSettingsView: View {
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

struct GeneralSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(L10n.languageKey, store: L10n.defaults) private var language: AppLanguage = .system
    @AppStorage(L10n.themeKey, store: L10n.defaults) private var theme: AppTheme = .system
    @AppStorage("pricingRegion", store: L10n.defaults) private var pricingRegionRaw = PricingRegion.auto.rawValue
    @State private var cacheBytes: Int64?
    @State private var cacheFiles = 0
    @State private var isClearing = false

    var body: some View {
        let _ = locale
        PageShell(title: L10n.tr("常规设置"), eyebrow: L10n.tr("偏好设置"), subtitle: L10n.tr("这些选项同时应用于 Hourcade 和桌面小组件。")) {
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
            SettingsPanel(title: L10n.tr("计价地区")) {
                Picker(L10n.tr("计价地区"), selection: $pricingRegionRaw) {
                    ForEach(PricingRegion.allCases) { region in
                        Text(region.title).tag(region.rawValue)
                    }
                }
                .labelsHidden()
                Text(L10n.tr("游戏价值按所选地区的货币折算展示；不影响任何平台账号与购买。"))
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
