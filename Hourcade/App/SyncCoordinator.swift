import SwiftUI
import WidgetKit
import ImageIO

/// App-wide sync orchestration, shared by the main window, the menu bar, and
/// the background scheduler. Holds the three platform snapshots in memory so
/// opening a window never restarts a sync in progress.
@Observable
@MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()
    private static let syncRecordsKey = "platformSyncRecords"
    private static let lastAutoAttemptKey = "lastAutomaticSyncAttempt"
    private static let refreshInterval: TimeInterval = 1_800
    private static let retryInterval: TimeInterval = 900

    private init() {
        steamSnapshot = LocalSnapshotStore.load("steam")
        nintendoSnapshot = LocalSnapshotStore.load("nintendo")
        psnSnapshot = LocalSnapshotStore.load("psn")
        if let data = UserDefaults.standard.data(forKey: Self.syncRecordsKey),
           let saved = try? JSONDecoder().decode([String: PlatformSyncRecord].self, from: data) {
            syncRecords = saved
        }
    }

    var steamSnapshot: SteamSnapshot?
    var nintendoSnapshot: NintendoSnapshot?
    var psnSnapshot: PSNSnapshot?
    var isSyncingAll = false
    var steamSyncing = false
    var steamError: AccountMessage?
    private(set) var syncRecords: [String: PlatformSyncRecord] = [:]

    var nintendoSyncError: String? { syncRecords[GamePlatform.nintendo.rawValue]?.lastError }
    var psnSyncError: String? { syncRecords[GamePlatform.playStation.rawValue]?.lastError }
    var steamSyncError: String? { steamError?.text ?? syncRecords[GamePlatform.steam.rawValue]?.lastError }

    @MainActor
    func runLaunchSequence() async {
        migrateNintendoSessionToken()
        do { try await saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
        let previousSteamDate = steamSnapshot?.syncedAt
        let previousNintendoDate = nintendoSnapshot?.syncedAt
        let previousPSNDate = psnSnapshot?.syncedAt
        await refreshIfStale()
        if let steamSnapshot, steamSnapshot.syncedAt == previousSteamDate {
            await SteamAPI.cacheArtwork(for: steamSnapshot)
        }
        // A launch with still-fresh account data must also repair any missing
        // Nintendo or PSN favorite artwork before requesting a new timeline.
        if steamSnapshot?.syncedAt == previousSteamDate,
           nintendoSnapshot?.syncedAt == previousNintendoDate,
           psnSnapshot?.syncedAt == previousPSNDate {
            await refreshWidgetArtwork()
        }
    }

    /// Called on launch, wake and activation. A failed platform can retry after
    /// 15 minutes; successful snapshots are fetched again once 30 minutes old.
    func refreshIfStale() async {
        guard !isSyncingAll else { return }
        let now = Date.now
        if let lastAttempt = UserDefaults.standard.object(forKey: Self.lastAutoAttemptKey) as? Date,
           now.timeIntervalSince(lastAttempt) < Self.retryInterval { return }
        let steamConnected = UserDefaults.standard.string(forKey: "steam.account")?.isEmpty == false
            && KeychainSecret.read("steam.apiKey") != nil
        let nintendoConnected = KeychainSecret.read("nintendo.sessionToken") != nil
        let psnConnected = KeychainSecret.read("psn.refreshToken") != nil
        let stale = (steamConnected && isStale(steamSnapshot?.syncedAt, at: now))
            || (nintendoConnected && isStale(nintendoSnapshot?.syncedAt, at: now))
            || (psnConnected && isStale(psnSnapshot?.syncedAt, at: now))
        guard stale else { return }
        UserDefaults.standard.set(now, forKey: Self.lastAutoAttemptKey)
        await syncAll()
    }

    private func isStale(_ date: Date?, at now: Date) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= Self.refreshInterval
    }

    private func updateSyncRecord(_ platform: GamePlatform, success: Date? = nil, error: Error? = nil) {
        var record = syncRecords[platform.rawValue] ?? PlatformSyncRecord()
        if success == nil && error == nil { record.lastAttempt = .now }
        if let success {
            record.lastSuccess = success
            record.lastError = nil
        } else if let error {
            record.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        syncRecords[platform.rawValue] = record
        if let data = try? JSONEncoder().encode(syncRecords) {
            UserDefaults.standard.set(data, forKey: Self.syncRecordsKey)
        }
    }

    func recordManualSuccess(_ platform: GamePlatform, at date: Date) {
        updateSyncRecord(platform, success: date)
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
    /// CDNs, whose images are direct URLs. Cache wall games, PSN's latest
    /// dated titles, and each platform's lifetime favorite. A1 can show titles
    /// below the wall's top eight, including PSN games with unknown duration.
    private func cachePlatformArtwork() async {
        let merged = WidgetSnapshotStore.load()
        let walls = merged?.gameSnapshot.galleryWalls ?? [:]
        let showcases = merged?.gameSnapshot.showcaseArtwork ?? [:]
        // Nintendo: upgrade to 1024 for better quality when available.
        if let nintendo = nintendoSnapshot {
            var seen = Set<String>()
            let favorite = nintendo.games.max { $0.totalPlayTime < $1.totalPlayTime }?.featuredGame
            let recent = merged?.gameSnapshot.recentHeroCandidates.filter { $0.platform == .nintendo } ?? []
            let showcase = nintendo.games.first { $0.featuredGame.artworkName == showcases[.nintendo] }?.featuredGame
            let visible = Array((walls[.nintendo] ?? []).prefix(8))
                + [favorite, showcase].compactMap { $0 } + recent
            let sources = visible.compactMap { game -> NintendoGame? in
                guard seen.insert(game.id).inserted else { return nil }
                return nintendo.games.first { $0.featuredGame.id == game.id }
            }
            let candidates = sources.compactMap { source -> (URL, String)? in
                guard !source.imageUri.isEmpty,
                      var remote = URL(string: source.imageUri)
                else { return nil }
                if remote.absoluteString.hasSuffix("_512"),
                   let hd = URL(string: remote.absoluteString.replacingOccurrences(of: "_512", with: "_1024")) {
                    remote = hd
                }
                return (remote, source.featuredGame.artworkName)
            }
            for (remote, name) in candidates {
                await downloadAndCache(remote, named: name)
            }
            if let directory = SteamWidgetStore.artworkDirectory {
                await NintendoArtworkStore.shared.cache(
                    titleIDs: sources.compactMap(\.titleId),
                    artworkDirectory: directory
                )
            }
        }
        // PlayStation: the gamelist API gives a direct image URL.
        if let psn = psnSnapshot {
            var seen = Set<String>()
            let favorite = psn.library.games.filter(\.hasPlaytime)
                .max { $0.lifetimeMinutes < $1.lifetimeMinutes }?.featuredGame
            let recent = merged?.gameSnapshot.psnPlayedGames ?? []
            let visible = Array((walls[.playStation] ?? []).prefix(8))
                + [favorite].compactMap { $0 } + recent
            let candidates = visible.compactMap { game -> (URL, String)? in
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

    func refreshWidgetArtwork() async {
        await cachePlatformArtwork()
        reloadWidgets()
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
            let (data, response) = try await session.data(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 8 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32
                  ] as CFDictionary) != nil else { return }
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
              !account.isEmpty, KeychainSecret.read("steam.apiKey") != nil
        else { return }
        _ = await syncSteam(account, "")
    }

    /// Refreshes every platform the user has already connected, in place, without
    /// sending them to each platform page. Platforms without stored credentials are
    /// left alone so the button never turns into an unexpected login prompt.
    func syncAll() async {
        guard !isSyncingAll else { return }
        isSyncingAll = true
        defer { isSyncingAll = false }

        await autoRefreshSteam()
        await refreshNintendo()
        await refreshPlayStation()
        do { try await saveWidgetSnapshots() } catch { steamError = .widgetWriteFailure(error) }
        Task { @MainActor in await refreshWidgetArtwork() }
    }

    private func refreshNintendo() async {
        guard let token = KeychainSecret.read("nintendo.sessionToken") else { return }
        updateSyncRecord(.nintendo)
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
            updateSyncRecord(.nintendo, success: newSnapshot.syncedAt)
        } catch {
            // A failed platform must not discard the others' fresh data.
            updateSyncRecord(.nintendo, error: error)
        }
    }

    private func refreshPlayStation() async {
        guard let refresh = KeychainSecret.read("psn.refreshToken") else { return }
        updateSyncRecord(.playStation)
        do {
            let (library, rotated) = try await PSNAPI.load(
                savedRefreshToken: refresh,
                accessCode: nil
            )
            if let rotated { try KeychainSecret.save(rotated, for: "psn.refreshToken") }
            let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
            try LocalSnapshotStore.save(newSnapshot, as: "psn")
            psnSnapshot = newSnapshot
            updateSyncRecord(.playStation, success: newSnapshot.syncedAt)
        } catch {
            // The previous PlayStation snapshot survives a failed refresh.
            updateSyncRecord(.playStation, error: error)
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
        updateSyncRecord(.steam)
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
            updateSyncRecord(.steam, success: newSnapshot.syncedAt)
            await publishSteamWidget(newSnapshot)
            if library.games.isEmpty {
                steamError = .text("Steam 没有返回游戏。请检查个人资料的“游戏详情”隐私设置；改为公开会让其他人也能查看相关游戏信息")
            }
            return true
        } catch {
            steamError = .failure(error)
            updateSyncRecord(.steam, error: error)
            return false
        }
    }
}

struct PlatformSyncRecord: Codable {
    var lastAttempt: Date?
    var lastSuccess: Date?
    var lastError: String?
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
