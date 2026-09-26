import SwiftUI
import WidgetKit

/// App-wide sync orchestration, shared by the main window, the menu bar, and
/// the background scheduler. Holds the three platform snapshots in memory so
/// opening a window never restarts a sync in progress.
@Observable
@MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private init() {
        steamSnapshot = LocalSnapshotStore.load("steam")
        nintendoSnapshot = LocalSnapshotStore.load("nintendo")
        psnSnapshot = LocalSnapshotStore.load("psn")
    }

    var steamSnapshot: SteamSnapshot?
    var nintendoSnapshot: NintendoSnapshot?
    var psnSnapshot: PSNSnapshot?
    var steamSyncing = false
    var steamError: AccountMessage?

    @MainActor
    func runLaunchSequence() async {
        migrateNintendoSessionToken()
        do { try await saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
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

    @MainActor
    private func publishSteamWidget(_ snapshot: SteamSnapshot) async {
        do {
            try await saveWidgetSnapshots()
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

    /// Downloads cover art so `GameArtwork` can render real images in widgets
    /// instead of gradients. Steam has its own richer pipeline
    /// (`SteamAPI.cacheArtwork`); this covers the Nintendo and PlayStation
    /// CDNs, whose images are direct URLs. The A5/A6 walls and the M3/M4
    /// backdrops surface each platform's top games, so cache every game that
    /// can appear on them (walls' top eight plus the showcase backdrop).
    private func cachePlatformArtwork() async {
        let merged = WidgetSnapshotStore.load()
        let walls = merged?.gameSnapshot.galleryWalls ?? [:]
        let showcases = merged?.gameSnapshot.showcaseArtwork ?? [:]
        // Nintendo: upgrade to 1024 for better quality when available.
        if let nintendo = nintendoSnapshot {
            var seen = Set<String>()
            let candidates = (walls[.nintendo] ?? []).prefix(8).compactMap { game -> (URL, String)? in
                guard let source = nintendo.games.first(where: { $0.featuredGame.id == game.id }),
                      !source.imageUri.isEmpty,
                      var remote = URL(string: source.imageUri),
                      seen.insert(game.id).inserted
                else { return nil }
                if remote.absoluteString.hasSuffix("_512"),
                   let hd = URL(string: remote.absoluteString.replacingOccurrences(of: "_512", with: "_1024")) {
                    remote = hd
                }
                return (remote, "nintendo-\(source.titleId ?? source.name)")
            }
            for (remote, name) in candidates {
                await downloadAndCache(remote, named: name)
            }
        }
        // PlayStation: the gamelist API gives a direct image URL.
        if let psn = psnSnapshot {
            var seen = Set<String>()
            let candidates = (walls[.playStation] ?? []).prefix(8).compactMap { game -> (URL, String)? in
                guard let source = psn.library.games.first(where: { $0.featuredGame.id == game.id }),
                      let remote = source.imageURL,
                      seen.insert(game.id).inserted
                else { return nil }
                return (remote, "psn-\(source.id)")
            }
            for (remote, name) in candidates {
                await downloadAndCache(remote, named: name)
            }
        }
        // The M2–M4 backdrop may reference a game outside the walls' top eight;
        // resolve its Steam cover through the app's own pipeline if needed.
        if let steamShowcase = showcases[.steam], steamShowcase.hasPrefix("steam-") {
            let appID = steamShowcase
                .dropFirst("steam-".count)
                .split(separator: "-").first
                .flatMap { Int($0) }
            if let appID {
                await SteamAPI.cacheArtwork(for: appID)
            }
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

    func saveWidgetSnapshots() async throws {
        var snapshots = WidgetSnapshots(steam: steamSnapshot, nintendo: nintendoSnapshot, playStation: psnSnapshot)
        // Copy achievement/trophy rollups from the app's caches into the
        // widget snapshot: the extension can't reach Application Support.
        if let steam = steamSnapshot {
            let appIDs = steam.library.games.map(\.id)
            let totals = await SteamAchievementStore.shared.cachedSnapshotProgress(appIDs: appIDs)
            snapshots.progress.steamEarned = totals.earned
            snapshots.progress.steamTotal = totals.total
            snapshots.progress.achievementsByGame = totals.byGame
        }
        if let psn = psnSnapshot {
            let titleIds = psn.library.games.map(\.id)
            let totals = await PSNTrophyStore.shared.cachedSnapshotProgress(titleIds: titleIds)
            snapshots.progress.trophyEarned = totals.earned
            snapshots.progress.trophyDefined = totals.defined
            snapshots.progress.trophiesByTitle = totals.byTitle
            // The A1 tray shows the account-level four tiers, which the sync
            // already rolled up per tier; the per-title cache only has totals.
            // Platinum switches from the per-title cache sum to the account-level
            // rollup, matching gold/silver/bronze (defaults to 0 if rollup is nil).
            let tiers = psn.library.trophies?.earned
            snapshots.progress.trophyPlatinum = tiers?.platinum ?? 0
            snapshots.progress.trophyGold = tiers?.gold ?? 0
            snapshots.progress.trophySilver = tiers?.silver ?? 0
            snapshots.progress.trophyBronze = tiers?.bronze ?? 0
        }
        try WidgetSnapshotStore.save(snapshots)
        reloadWidgets()
    }

    private func reloadWidgets() {
        for style in AggregateStyle.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: style.liveWidgetKind)
        }
        NotificationCenter.default.post(name: SteamWidgetStore.didChange, object: nil)
    }

    private func autoRefreshSteam() async {
        guard let account = UserDefaults.standard.string(forKey: "steam.account"),
              !account.isEmpty, let key = KeychainSecret.read("steam.apiKey")
        else { return }
        _ = await syncSteam(account, key)
    }

    /// Refreshes every platform the user has already connected, in place, without
    /// sending them to each platform page. Platforms without stored credentials are
    /// left alone so the button never turns into an unexpected login prompt.
    func syncAll() async {
        guard !steamSyncing else { return }
        steamSyncing = true
        defer { steamSyncing = false }

        await autoRefreshSteam()
        await refreshNintendo()
        await refreshPlayStation()
        await cachePlatformArtwork()
        do { try await saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
        refreshPrices()
    }

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
            // The previous PlayStation snapshot survives a failed refresh.
        }
    }

    func syncSteam(_ account: String, _ enteredKey: String) async -> Bool {
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
    /// Queries are pinned to the HK storefront (92% library coverage vs 57%
    /// on CN) and every price converts to CNY at display time.
    private func refreshPrices() {
        let steamAppIDs = steamSnapshot?.library.games.map(\.id) ?? []
        let nintendoTitleIds = nintendoSnapshot?.games.compactMap(\.titleId) ?? []
        let psnTitles = (psnSnapshot?.library.games.compactMap { game -> (titleId: String, conceptId: String)? in
            guard let conceptId = game.conceptId else { return nil }
            return (game.id, conceptId)
        }) ?? []
        guard !steamAppIDs.isEmpty || !nintendoTitleIds.isEmpty || !psnTitles.isEmpty else { return }
        let storefront = "en-hk"
        let chihiroCountry = "HK/en"
        Task.detached(priority: .utility) {
            // Sweep 横跨几分钟；申请用户级活动避免后台 AppNap 冻结下载。
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Hourcade price sweep")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            async let steam: Void = SteamPriceStore.shared.sweep(appIDs: steamAppIDs)
            async let nintendo: Void = NintendoPriceStore.shared.sweep(titleIds: nintendoTitleIds)
            async let psn: Void = PSNPriceStore.shared.sweep(titles: psnTitles, storefront: storefront, chihiroCountry: chihiroCountry)
            _ = await (steam, nintendo, psn)
        }
    }
}

// Messages stay symbolic so a language switch also updates existing sync results.
enum AccountMessage {
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
