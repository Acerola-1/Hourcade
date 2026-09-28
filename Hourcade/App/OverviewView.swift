import SwiftUI
import CryptoKit

struct OverviewView: View {
    @Environment(\.locale) private var locale
    @State private var priceText: String?
    let steam: SteamSnapshot?
    let nintendo: NintendoSnapshot?
    let playStation: PSNSnapshot?
    let steamConfigured: Bool
    let isRefreshing: Bool
    let refreshError: String?
    let nintendoSyncError: String?
    let psnSyncError: String?
    let selectPlatform: (GamePlatform) -> Void
    let syncAll: () -> Void

    private var connectedCount: Int {
        [steam != nil, nintendo != nil, playStation != nil].filter { $0 }.count
    }
    private var totalMinutes: Int {
        (steam?.library.totalMinutes ?? 0) + (nintendo?.totalMinutes ?? 0) + (playStation?.library.totalMinutes ?? 0)
    }
    private var gameEntries: Int {
        (steam?.library.games.count ?? 0) + (nintendo?.games.count ?? 0) + (playStation?.library.games.count ?? 0)
    }
    private var connectedAny: Bool { connectedCount > 0 }

    /// Each known platform paired with whatever this account has for it, so the
    /// cards and the counters all come from one source.
    private var platformEntries: [(platform: GamePlatform, count: Int, minutes: Int, date: Date?)] {
        func entry(_ platform: GamePlatform, count: Int?, minutes: Int?, date: Date?) -> (GamePlatform, Int, Int, Date?) {
            (platform, count ?? 0, minutes ?? 0, date)
        }
        return [
            entry(.steam, count: steam?.library.games.count, minutes: steam?.library.totalMinutes, date: steam?.syncedAt),
            entry(.nintendo, count: nintendo?.games.count, minutes: nintendo?.totalMinutes, date: nintendo?.syncedAt),
            entry(.playStation, count: playStation?.library.games.count, minutes: playStation?.library.totalMinutes, date: playStation?.syncedAt),
        ]
    }

    var body: some View {
        let _ = locale
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if connectedCount == 0 {
                    ContentUnavailableView {
                        Label(
                            steamConfigured
                                ? (isRefreshing ? L10n.tr("正在同步 Steam") : L10n.tr("Steam 尚未完成同步"))
                                : L10n.tr("你的游戏生活，从连接平台开始"),
                            systemImage: steamConfigured ? "arrow.clockwise" : "gamecontroller"
                        )
                    } description: {
                        Text(refreshError ?? nintendoSyncError ?? psnSyncError ?? (steamConfigured
                            ? L10n.tr("数据就绪后会自动显示在这里。也可以进入 Steam 页面重试。")
                            : L10n.tr("选择左侧平台，完成第一次连接后，这里会显示真实游玩数据。")))
                    }
                } else {
                    summary
                    platforms
                    if !recentGames.isEmpty {
                        recentSection
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
        .navigationTitle(L10n.tr("总览"))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.tr("HOURCADE · 你的游戏生活"))
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(L10n.tr("你的游戏时间"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                if connectedCount == 0 {
                    // This hint belongs to the empty state; the summary card
                    // carries the counts once platforms connect.
                    Text(L10n.tr("连接平台后，游玩记录会汇集在这里。"))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if connectedAny {
                Button {
                    syncAll()
                } label: {
                    Label(isRefreshing ? L10n.tr("同步中") : L10n.tr("同步全部"), systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(totalMinutes / 60)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(L10n.tr("小时"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.tr("已连接平台的累计游玩时长"))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                smallMetric("\(gameEntries)", L10n.tr("游戏记录条目"))
                Divider().frame(height: 42).padding(.horizontal, 28)
                smallMetric("\(connectedCount)", L10n.tr("已连接平台"))
                Divider().frame(height: 42).padding(.horizontal, 28)
                smallMetric(priceText ?? "—", L10n.tr("参考价值"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.24, blue: 0.34), Color(red: 0.08, green: 0.13, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-18))
                .padding(.trailing, 20)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .task { priceText = await PriceValue.overviewText(steam: steam, nintendo: nintendo, playStation: playStation) }
        .onReceive(NotificationCenter.default.publisher(for: .pricesDidChange)) { _ in
            Task { priceText = await PriceValue.overviewText(steam: steam, nintendo: nintendo, playStation: playStation) }
        }
    }

    private func smallMetric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.67))
        }
    }

    private var platforms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("平台")).font(.title3.bold())
            HStack(spacing: 12) {
                ForEach(platformEntries, id: \.platform) { item in
                    platformCard(
                        item.platform,
                        count: item.count,
                        minutes: item.minutes,
                        date: item.date
                    )
                }
            }
            if let refreshError {
                Label(L10n.format("Steam 刷新失败：%@。上方保留上次同步结果。", refreshError), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let nintendoSyncError {
                Label(L10n.format("%@ 同步失败：%@。已保留上次数据。", GamePlatform.nintendo.title, nintendoSyncError), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let psnSyncError {
                Label(L10n.format("%@ 同步失败：%@。已保留上次数据。", GamePlatform.playStation.title, psnSyncError), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func platformCard(_ platform: GamePlatform, count: Int, minutes: Int, date: Date?) -> some View {
        Button {
            selectPlatform(platform)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    AccountPlatformMark(platform: platform, size: 36)
                    Text(platform.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                if date != nil {
                    Text(L10n.format("%lld小时", minutes / 60))
                        .font(.title2.bold().monospacedDigit())
                    Text(L10n.format("%lld 款记录 · 同步于 %@", count, DisplayFormat.syncDate(date!)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(L10n.tr("尚未连接"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("点击设置账号"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(18)
            .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: 近期游玩（全平台合并）

    private struct RecentRow: Identifiable {
        let id: String
        let name: String
        let platform: GamePlatform
        let lastPlayed: Date?
        let minutes: Int
        let minutesIsRecentWindow: Bool
        let artwork: URL?
        let fallbackArtwork: URL?
        // Steam appid for the store lookup when both fixed CDN paths 404.
        let storeAppID: Int?
    }

    /// Every connected platform contributes its best-known last-played date and
    /// the rows merge newest first, so a new platform needs no change here.
    private var recentGames: [RecentRow] {
        var candidates: [RecentRow] = []

        if let steam {
            // Owned games carry `rtime_last_played`; snapshots saved before that
            // field shipped fall back to the already recency-ordered recent list.
            let dated = steam.library.games.filter { $0.lastPlayedDate != nil }
            let ranked = dated.isEmpty
                ? steam.library.recent
                : dated.sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            candidates += ranked.prefix(6).map { game in
                RecentRow(
                    id: "steam-\(game.id)",
                    name: game.name,
                    platform: .steam,
                    lastPlayed: game.lastPlayedDate,
                    minutes: game.fortnightMinutes,
                    minutesIsRecentWindow: true,
                    artwork: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.id)/library_600x900.jpg"),
                    // The portrait library capsule is sharp at tile size; the
                    // wide header covers games without library assets.
                    fallbackArtwork: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.id)/header.jpg"),
                    storeAppID: game.id
                )
            }
        }

        if let nintendo {
            let ranked = nintendo.games.sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            candidates += ranked.prefix(6).map { game in
                RecentRow(
                    id: "nintendo-\(game.id)",
                    name: game.name,
                    platform: .nintendo,
                    lastPlayed: game.lastPlayedDate,
                    minutes: game.totalPlayTime,
                    minutesIsRecentWindow: false,
                    artwork: URL(string: game.imageUri),
                    fallbackArtwork: nil,
                    storeAppID: nil
                )
            }
        }

        if let playStation {
            let ranked = playStation.library.games.sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            candidates += ranked.prefix(6).map { game in
                RecentRow(
                    id: "psn-\(game.id)",
                    name: game.name,
                    platform: .playStation,
                    lastPlayed: game.lastPlayedDate,
                    minutes: game.lifetimeMinutes,
                    minutesIsRecentWindow: false,
                    artwork: game.imageURL,
                    fallbackArtwork: nil,
                    storeAppID: nil
                )
            }
        }

        return candidates.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.lastPlayed, rhs.element.lastPlayed) {
                case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l > r
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.offset < rhs.offset
                }
            }
            .prefix(8)
            .map(\.element)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("近期游玩")).font(.title3.bold())
            ForEach(recentGames) { game in
                HStack(spacing: 14) {
                    GameCover(primary: game.artwork, fallback: game.fallbackArtwork, storeAppID: game.storeAppID)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            AccountPlatformMark(platform: game.platform, size: 15)
                            Text(game.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        Text(caption(for: game))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(RelativeTime.text(for: game.lastPlayed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(22)
        .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 18))
    }

    private func caption(for game: RecentRow) -> String {
        let hours = L10n.format("%lld小时 %lld分钟", game.minutes / 60, game.minutes % 60)
        return game.minutesIsRecentWindow
            ? L10n.format("%1$@ · 近两周 %2$@", game.platform.title, hours)
            : L10n.format("%1$@ · 总计 %2$@", game.platform.title, hours)
    }
}

/// Shared cover pipeline for every in-app artwork tile: memory → disk →
/// network. Steam covers whose fixed CDN paths 404 (everything published after
/// the 2023 asset migration) get their hashed store asset resolved through one
/// `appdetails` lookup; positive resolutions persist to disk, failures are
/// retried after an hour.
actor CoverStore {
    static let shared = CoverStore()

    private var memory: [String: CGImage] = [:]
    private var resolved: [Int: ResolvedHeader]?
    private var missingSince: [Int: Date] = [:]

    private struct ResolvedHeader: Codable {
        let url: URL
        let fetchedAt: Date
    }

    static var coversDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "Hourcade/covers", directoryHint: .isDirectory)
    }

    private static var resolvedFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "Hourcade/steam-headers.json")
    }

    func image(primary: URL?, fallback: URL?, appID: Int?) async -> CGImage? {
        let key = appID.map { "steam-\($0)" } ?? primary?.absoluteString ?? ""
        guard !key.isEmpty else { return nil }
        if let hit = memory[key] { return hit }
        if let data = diskData(key), let image = decode(data) {
            memory[key] = image
            return image
        }

        var data = await download(primary)
        if data == nil { data = await download(fallback) }
        if data == nil, let appID, let resolvedURL = await storeHeaderURL(for: appID) {
            data = await download(resolvedURL)
        }
        guard let data, let image = decode(data) else { return nil }
        memory[key] = image
        persist(data, key: key)
        return image
    }

    /// Wipes the in-app cover cache (disk and memory).
    func clear() {
        memory.removeAll()
        resolved = nil
        missingSince.removeAll()
        if let dir = Self.coversDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        if let file = Self.resolvedFile {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func download(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    private func decode(_ data: Data) -> CGImage? {
        NSBitmapImageRep(data: data)?.cgImage
    }

    private func diskData(_ key: String) -> Data? {
        guard let file = Self.coversDirectory?.appending(path: "\(Self.diskName(key)).jpg") else { return nil }
        return try? Data(contentsOf: file)
    }

    private func persist(_ data: Data, key: String) {
        guard let dir = Self.coversDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(Self.diskName(key)).jpg"), options: .atomic)
    }

    private static func diskName(_ key: String) -> String {
        String(SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined())
    }

    private func storeHeaderURL(for appID: Int) async -> URL? {
        if resolved == nil {
            if let file = Self.resolvedFile, let data = try? Data(contentsOf: file) {
                resolved = (try? JSONDecoder().decode([Int: ResolvedHeader].self, from: data)) ?? [:]
            } else {
                resolved = [:]
            }
        }
        if let hit = resolved?[appID] { return hit.url }
        if let since = missingSince[appID], Date().timeIntervalSince(since) < 3_600 { return nil }

        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&filters=basic")!
        var request = URLRequest(url: components.url!)
        var remote: URL?
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Steam sometimes re-keys the response under a migrated internal
            // appid; match on the inner payload instead of the wrapper key.
            let entry = payload.values
                .compactMap { $0 as? [String: Any] }
                .first(where: { ($0["success"] as? Bool) == true })?["data"] as? [String: Any]
            if let header = entry?["header_image"] as? String {
                remote = URL(string: header)
            }
        }
        guard let remote else {
            if missingSince[appID] == nil { missingSince[appID] = .now }
            return nil
        }
        missingSince[appID] = nil
        resolved?[appID] = ResolvedHeader(url: remote, fetchedAt: .now)
        if let file = Self.resolvedFile, let resolved, let data = try? JSONEncoder().encode(resolved) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return remote
    }
}

/// Thin tile view over the shared cover pipeline; falls back to a plain
/// rounded rectangle while loading or when every source fails.
struct GameCover: View {
    let primary: URL?
    let fallback: URL?
    let storeAppID: Int?
    var size: CGSize = CGSize(width: 56, height: 56)
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: "\(primary?.absoluteString ?? "")|\(fallback?.absoluteString ?? "")|\(storeAppID ?? 0)") {
            image = await CoverStore.shared.image(primary: primary, fallback: fallback, appID: storeAppID)
        }
    }
}
