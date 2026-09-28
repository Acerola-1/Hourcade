import Foundation

/// Platform APIs date-stamp play records in slightly different ISO 8601 shapes;
/// this tries the common variants before giving up (the row then sorts last).
enum SnapshotDates {
    nonisolated(unsafe) private static let fractional = makeFractional()
    nonisolated(unsafe) private static let internet = makeInternet()
    private static let plain = makePlain()

    private static func makeFractional() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeInternet() -> ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    private static func makePlain() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? internet.date(from: value) ?? plain.date(from: value)
    }
}

struct PSNGame: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let lifetimeMinutes: Int
    let lastPlayed: String?
    var imageURL: URL? = nil
    var hasPlaytime = true
    // The store concept id, used for one-hop price lookups. nil on snapshots
    // saved before this field shipped (one re-sync fills it).
    var conceptId: String? = nil

    var lastPlayedDate: Date? {
        guard let lastPlayed, !lastPlayed.isEmpty else { return nil }
        return SnapshotDates.parse(lastPlayed)
    }

    var featuredGame: FeaturedGame {
        FeaturedGame(id: "psn-" + id, title: name, platform: .playStation, artworkName: "psn-" + id, fortnightMinutes: 0, lifetimeMinutes: lifetimeMinutes)
    }
}

/// Account-level trophy counts. The per-game breakdown is fetched lazily by
/// the platform page (one request per title) and never persisted here.
struct PSNTrophyCounts: Codable, Sendable {
    var bronze: Int = 0
    var silver: Int = 0
    var gold: Int = 0
    var platinum: Int = 0
}

struct PSNTrophies: Codable, Sendable {
    var level: Int? = nil
    var earned: PSNTrophyCounts = PSNTrophyCounts()
    // Summed across every trophy title the account owns; the completion rate
    // is earned ÷ defined.
    var earnedTotal: Int? = nil
    var definedTotal: Int? = nil
}

struct PSNLibrary: Codable, Sendable {
    let games: [PSNGame]
    var onlineID: String? = nil
    var avatarURL: URL? = nil
    var trophies: PSNTrophies? = nil
    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
}

struct PSNSnapshot: Codable, Sendable {
    let library: PSNLibrary
    let syncedAt: Date
}

struct NintendoGame: Codable, Identifiable, Sendable {
    let name: String
    let imageUri: String
    let totalPlayTime: Int
    let firstPlayedAt: Int
    // Unix timestamp of the play history's `lastPlayedAt`. Snapshots saved before
    // this field shipped have none and fall back to `firstPlayedAt` below.
    var lastPlayedAt: Int? = nil
    // Two-week minutes, summed from the API's daily play records. Snapshots
    // saved before this field shipped have none.
    var fortnightMinutes: Int = 0
    // Nintendo's own title identifier, which the store page and the play history
    // never agree on. Older snapshots saved before the account login shipped have
    // no value and fall back to the fields below.
    var titleId: String? = nil

    var id: String { titleId ?? name }

    var lastPlayedDate: Date? {
        let timestamp = lastPlayedAt ?? firstPlayedAt
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    var featuredGame: FeaturedGame {
        FeaturedGame(
            id: "nintendo-" + id,
            title: name,
            platform: .nintendo,
            artworkName: "nintendo-" + id,
            fortnightMinutes: 0,
            lifetimeMinutes: totalPlayTime
        )
    }
}

struct NintendoSnapshot: Codable, Sendable {
    let games: [NintendoGame]
    let syncedAt: Date
    // The Nintendo Account nickname the history belongs to. Snapshots saved by the
    // nxapi round-trip have none, and the account login fills it best effort.
    var accountName: String? = nil
    var avatarURL: URL? = nil
    var totalMinutes: Int { games.reduce(0) { $0 + $1.totalPlayTime } }
}

struct WidgetSnapshots: Codable, Sendable {
    let steam: SteamSnapshot?
    let nintendo: NintendoSnapshot?
    let playStation: PSNSnapshot?
    // Steam achievement and PSN trophy rollups, computed by the app from its
    // caches and handed to the widget extension through the app group. Empty
    // when the app hasn't refreshed since this feature shipped.
    var progress: PlatformProgress = PlatformProgress()

    /// Per-platform game walls, sorted like the platform pages (recent play
    /// first, then last-played, then lifetime), annotated with per-game
    /// achievement/trophy progress. Feeds the platform cards (A4–A6).
    var gamesByPlatform: [GamePlatform: [FeaturedGame]] {
        var walls: [GamePlatform: [FeaturedGame]] = [:]
        if let steam {
            walls[.steam] = steam.library.games
                .sorted { lhs, rhs in
                    if let r = GameListOrder.fortnight(lhs.fortnightMinutes, rhs.fortnightMinutes) { return r }
                    if let r = GameListOrder.lastPlayed(lhs.lastPlayedDate, rhs.lastPlayedDate) { return r }
                    return lhs.lifetimeMinutes > rhs.lifetimeMinutes
                }
                .map { game in
                    var featured = game.featuredGame
                    if let progress = progress.achievement(appID: game.id) {
                        featured.achievementEarned = progress.earned
                        featured.achievementTotal = progress.total
                    }
                    return featured
                }
        }
        if let nintendo {
            walls[.nintendo] = nintendo.games
                .sorted { lhs, rhs in
                    if let r = GameListOrder.fortnight(lhs.fortnightMinutes, rhs.fortnightMinutes) { return r }
                    if let r = GameListOrder.lastPlayed(lhs.lastPlayedDate, rhs.lastPlayedDate) { return r }
                    return lhs.totalPlayTime > rhs.totalPlayTime
                }
                .map(\.featuredGame)
        }
        if let playStation {
            walls[.playStation] = playStation.library.games
                .filter { $0.hasPlaytime }
                .sorted { lhs, rhs in
                    if let r = GameListOrder.lastPlayed(lhs.lastPlayedDate, rhs.lastPlayedDate) { return r }
                    return lhs.lifetimeMinutes > rhs.lifetimeMinutes
                }
                .map { game in
                    var featured = game.featuredGame
                    if let progress = progress.trophy(titleId: game.id) {
                        featured.trophyEarned = progress.earned
                        featured.trophyDefined = progress.defined
                    }
                    return featured
                }
        }
        return walls
    }

    /// The platform's most recently played game (lifetime top as fallback),
    /// used as the medium widgets' artwork backdrop.
    func recentShowcase(for platform: GamePlatform) -> FeaturedGame? {
        switch platform {
        case .steam:
            steam?.library.games
                .filter { $0.fortnightMinutes > 0 }
                .sorted { $0.fortnightMinutes > $1.fortnightMinutes }.first?.featuredGame
                ?? gamesByPlatform[platform]?.first
        case .nintendo:
            nintendo?.games
                .compactMap { game -> FeaturedGame? in
                    guard game.lastPlayedDate != nil || game.fortnightMinutes > 0 else { return nil }
                    return game.featuredGame
                }
                .max { $0.fortnightMinutes < $1.fortnightMinutes }
                ?? gamesByPlatform[platform]?.first
        case .playStation:
            playStation?.library.games
                .compactMap { game -> FeaturedGame? in
                    guard game.hasPlaytime, game.lastPlayedDate != nil else { return nil }
                    return game.featuredGame
                }
                .max { $0.lifetimeMinutes < $1.lifetimeMinutes }
                ?? gamesByPlatform[platform]?.first
        }
    }

    /// The A1 card's "Recently played" row: every platform's games merged and
    /// ordered by last-played date across all history (not just the two-week
    /// window), capped at eight covers.
    var recentlyPlayedAcrossPlatforms: [RecentGame] {
        var entries: [(date: Date?, game: RecentGame)] = []
        if let steam {
            for game in steam.library.games {
                guard let date = game.lastPlayedDate else { continue }
                entries.append((date, RecentGame(id: String(game.id), title: game.name, platform: .steam, artworkName: game.featuredGame.artworkName, weekMinutes: game.fortnightMinutes)))
            }
        }
        if let nintendo {
            for game in nintendo.games {
                guard let date = game.lastPlayedDate else { continue }
                entries.append((date, RecentGame(id: game.featuredGame.id, title: game.name, platform: .nintendo, artworkName: game.featuredGame.artworkName, weekMinutes: game.fortnightMinutes)))
            }
        }
        if let playStation {
            for game in playStation.library.games where game.hasPlaytime {
                guard let date = game.lastPlayedDate else { continue }
                entries.append((date, RecentGame(id: game.featuredGame.id, title: game.name, platform: .playStation, artworkName: game.featuredGame.artworkName, weekMinutes: 0)))
            }
        }
        return entries
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (l?, r?): l > r
                case (.some, nil): true
                case (nil, .some): false
                default: lhs.game.weekMinutes > rhs.game.weekMinutes
                }
            }
            .prefix(8)
            .map(\.game)
    }

    var gameSnapshot: GameSnapshot {
        let steamData = steam?.gameSnapshot
        let nintendoFavorite = nintendo?.games.max { $0.totalPlayTime < $1.totalPlayTime }?.featuredGame
        let psnFavorite = playStation?.library.games.filter(\.hasPlaytime).max { $0.lifetimeMinutes < $1.lifetimeMinutes }?.featuredGame
        let favorites = [steamData?.allTimeTopGame, nintendoFavorite, psnFavorite].compactMap { $0 }.filter { $0.id != "empty" }
        let platforms: [PlatformActivity] = [
            steamData?.platforms.first ?? .disconnected(.steam),
            nintendo.map { PlatformActivity(platform: .nintendo, playedMinutes: $0.totalMinutes, gameCount: $0.games.count) } ?? .disconnected(.nintendo),
            playStation.map { PlatformActivity(platform: .playStation, playedMinutes: $0.library.totalMinutes, gameCount: $0.library.games.count, hasPlaytime: $0.library.games.isEmpty || $0.library.games.contains(where: \.hasPlaytime)) } ?? .disconnected(.playStation)
        ]
        // The A2 activity panel: each connected platform's most recent session.
        var lastPlayed: [LastPlayedRow] = []
        if let steam, let latest = steam.library.games.compactMap(\.lastPlayedDate).max() {
            let game = steam.library.games
                .filter { $0.lastPlayedDate == latest }
                .max { $0.lifetimeMinutes < $1.lifetimeMinutes }
            if let game {
                lastPlayed.append(LastPlayedRow(platform: .steam, title: game.name, date: latest))
            }
        }
        if let nintendo, let latest = nintendo.games.compactMap(\.lastPlayedDate).max() {
            let game = nintendo.games
                .filter { $0.lastPlayedDate == latest }
                .max { $0.totalPlayTime < $1.totalPlayTime }
            if let game {
                lastPlayed.append(LastPlayedRow(platform: .nintendo, title: game.name, date: latest))
            }
        }
        if let playStation, let latest = playStation.library.games.compactMap(\.lastPlayedDate).max() {
            let game = playStation.library.games
                .filter { $0.hasPlaytime && $0.lastPlayedDate == latest }
                .max { $0.lifetimeMinutes < $1.lifetimeMinutes }
            if let game {
                lastPlayed.append(LastPlayedRow(platform: .playStation, title: game.name, date: latest))
            }
        }
        lastPlayed.sort { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): l > r
            case (.some, nil): true
            case (nil, .some): false
            default: false
            }
        }
        return GameSnapshot(
            playerName: steamData?.playerName ?? playStation?.library.onlineID ?? L10n.widget("Connect your gaming platforms"),
            platforms: platforms,
            recentGames: recentlyPlayedAcrossPlatforms,
            fortnightGames: steamData?.fortnightGames ?? [],
            allTimeTopGame: favorites.max { $0.lifetimeMinutes < $1.lifetimeMinutes } ?? .empty,
            totalGameCount: platforms.reduce(0) { $0 + $1.gameCount },
            updatedAt: [steam?.syncedAt, nintendo?.syncedAt, playStation?.syncedAt].compactMap { $0 }.max() ?? .distantPast,
            avatarName: steamData?.avatarName,
            platformHighlights: favorites,
            galleryWalls: gamesByPlatform,
            showcaseArtwork: [
                .steam: recentShowcase(for: .steam)?.artworkName ?? "",
                .nintendo: recentShowcase(for: .nintendo)?.artworkName ?? "",
                .playStation: recentShowcase(for: .playStation)?.artworkName ?? ""
            ],
            platformProgress: progress,
            steamPersonaState: steam?.library.player?.personaState,
            steamPlayingGame: steam?.library.player?.playingGame,
            steamLevel: steam?.library.player?.level,
            psnTrophyLevel: playStation?.library.trophies?.level,
            lastPlayedRows: lastPlayed
        )
    }
}

enum WidgetSnapshotStore {
    private static var file: URL? { SteamWidgetStore.container?.appending(path: "accounts-widget.json") }

    static func load() -> WidgetSnapshots? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshots.self, from: data)
    }

    static func save(_ snapshots: WidgetSnapshots) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshots).write(to: file, options: .atomic)
    }
}
