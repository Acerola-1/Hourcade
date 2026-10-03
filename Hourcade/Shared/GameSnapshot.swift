import Foundation

struct SteamGame: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let lifetimeMinutes: Int
    let fortnightMinutes: Int
    // Unix timestamp from the API's `rtime_last_played`. Snapshots saved before
    // this field shipped have none and fall back to library order.
    var lastPlayedAt: Int? = nil

    var lastPlayedDate: Date? {
        guard let lastPlayedAt, lastPlayedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastPlayedAt))
    }

    var featuredGame: FeaturedGame {
        FeaturedGame(id: String(id), title: name, platform: .steam, artworkName: "steam-\(id)", fortnightMinutes: fortnightMinutes, lifetimeMinutes: lifetimeMinutes)
    }
}

struct SteamPlayer: Codable, Sendable {
    let name: String
    let avatarURL: URL?
    // The resolved 64-bit SteamID, the account level and the account country;
    // nil on snapshots saved before these fields shipped.
    var steamID: String? = nil
    var level: Int? = nil
    var countryCode: String? = nil
    // Live presence captured at sync time: 0 = offline, 1-6 = online variants;
    // playingGame is the localized title of the current session, if any.
    var personaState: Int? = nil
    var playingGame: String? = nil

    var avatarName: String? {
        avatarURL.map { "steam-avatar-" + $0.deletingPathExtension().lastPathComponent }
    }
}

struct SteamLibrary: Codable, Sendable {
    let games: [SteamGame]
    let recent: [SteamGame]
    var player: SteamPlayer? = nil

    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
}

struct SteamSnapshot: Codable, Sendable {
    let library: SteamLibrary
    let syncedAt: Date

    var gameSnapshot: GameSnapshot {
        // "Recently played" spans all history, ordered by last-played date —
        // not just the API's two-week window.
        let recentGames = library.games
            .filter { $0.lastPlayedDate != nil }
            .sorted { lhs, rhs in
                switch (lhs.lastPlayedDate, rhs.lastPlayedDate) {
                case let (l?, r?): l > r
                default: lhs.lifetimeMinutes > rhs.lifetimeMinutes
                }
            }
            .prefix(8)
            .map {
                RecentGame(id: String($0.id), title: $0.name, platform: .steam, artworkName: $0.featuredGame.artworkName, weekMinutes: $0.fortnightMinutes)
            }
        return GameSnapshot(
            playerName: library.player?.name ?? L10n.widget("Steam Player"),
            platforms: [
                PlatformActivity(platform: .steam, playedMinutes: library.totalMinutes, gameCount: library.games.count),
                .disconnected(.nintendo),
                .disconnected(.playStation)
            ],
            recentGames: recentGames,
            fortnightGames: library.recent.map(\.featuredGame),
            allTimeTopGame: library.games.max(by: { $0.lifetimeMinutes < $1.lifetimeMinutes })?.featuredGame ?? .empty,
            totalGameCount: library.games.count,
            updatedAt: syncedAt,
            avatarName: library.player?.avatarName
        )
    }
}

enum SteamWidgetStore {
    static let didChange = Notification.Name("Hourcade.SteamSnapshotDidChange")

    static var container: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HourcadeAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static var artworkDirectory: URL? {
        container?.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    static func artworkURL(named name: String) -> URL? {
        guard !name.isEmpty, name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return artworkDirectory?.appending(path: name + ".jpg")
    }
}

enum GamePlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case nintendo
    case playStation
    case steam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nintendo: "Nintendo"
        case .playStation: "PlayStation"
        case .steam: "Steam"
        }
    }
}

enum AggregateStyle: String, CaseIterable, Identifiable, Sendable {
    case heroNoValue
    case atlas
    case platforms
    case gallery
    case galleryNintendo
    case galleryPlayStation
    case mini
    case steamMini
    case nintendoMini
    case playStationMini

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .heroNoValue: "A1"
        case .atlas: "A2"
        case .platforms: "A3"
        case .gallery: "A4"
        case .galleryNintendo: "A5"
        case .galleryPlayStation: "A6"
        case .mini: "M1"
        case .steamMini: "M2"
        case .nintendoMini: "M3"
        case .playStationMini: "M4"
        }
    }

    var title: String {
        switch self {
        case .heroNoValue: L10n.widget("Overview")
        case .atlas: L10n.widget("Data overview")
        case .platforms: L10n.widget("Platforms")
        case .gallery: L10n.widget("Steam wall")
        case .galleryNintendo: L10n.widget("Switch wall")
        case .galleryPlayStation: L10n.widget("PS wall")
        case .mini: L10n.widget("Overview")
        case .steamMini: "Steam"
        case .nintendoMini: "Switch"
        case .playStationMini: "PS"
        }
    }

    var liveWidgetKind: String { "Hourcade.Live.\(rawValue)" }
}

struct PlatformActivity: Identifiable, Sendable {
    let platform: GamePlatform
    let playedMinutes: Int
    let gameCount: Int
    var isConnected = true
    var hasPlaytime = true

    var id: GamePlatform { platform }
    var playtimeLabel: String { isConnected && hasPlaytime ? playedMinutes.hoursLabel : "—" }
    var gameCountLabel: String { isConnected ? gameCount.formatted() : "—" }

    static func disconnected(_ platform: GamePlatform) -> PlatformActivity {
        PlatformActivity(platform: platform, playedMinutes: 0, gameCount: 0, isConnected: false)
    }
}

struct RecentGame: Identifiable, Sendable {
    let id: String
    let title: String
    let platform: GamePlatform
    let artworkName: String
    let weekMinutes: Int
}

struct FeaturedGame: Identifiable, Sendable {
    let id: String
    let title: String
    let platform: GamePlatform
    let artworkName: String
    let fortnightMinutes: Int
    let lifetimeMinutes: Int
    // Steam achievement progress (earned/total) copied into the widget snapshot
    // from the app's achievement cache; nil when untracked.
    var achievementEarned: Int? = nil
    var achievementTotal: Int? = nil
    // PSN trophy progress (earned/defined) for this title; nil when untracked.
    var trophyEarned: Int? = nil
    var trophyDefined: Int? = nil
    // PSN supplies a last-played date, but no playtime for the last 14 days.
    var lastPlayedDate: Date? = nil

    static var empty: FeaturedGame {
        FeaturedGame(id: "empty", title: L10n.widget("No play history"), platform: .steam, artworkName: "", fortnightMinutes: 0, lifetimeMinutes: 0)
    }
}

/// Account-level achievement/trophy rollups shown on the platform walls.
/// The per-game dictionaries are keyed by Steam appid / PSN titleId.
struct PlatformProgress: Codable, Sendable {
    var steamEarned: Int = 0
    var steamTotal: Int = 0
    var trophyEarned: Int = 0
    var trophyDefined: Int = 0
    var trophyPlatinum: Int = 0
    // Account-level trophy tiers for the A1 tray; zero on snapshots saved
    // before these fields shipped (one re-sync fills them).
    var trophyGold: Int = 0
    var trophySilver: Int = 0
    var trophyBronze: Int = 0
    var achievementsByGame: [String: [Int]] = [:]  // appid -> [earned, total]
    var trophiesByTitle: [String: [Int]] = [:]     // titleId -> [earned, defined]

    func achievement(appID: Int) -> (earned: Int, total: Int)? {
        guard let pair = achievementsByGame[String(appID)], pair.count == 2 else { return nil }
        return (pair[0], pair[1])
    }

    func trophy(titleId: String) -> (earned: Int, defined: Int)? {
        guard let pair = trophiesByTitle[titleId], pair.count == 2 else { return nil }
        return (pair[0], pair[1])
    }
}

struct GameSnapshot: Sendable {
    let playerName: String
    let platforms: [PlatformActivity]
    let recentGames: [RecentGame]
    let fortnightGames: [FeaturedGame]
    let allTimeTopGame: FeaturedGame
    let totalGameCount: Int
    let updatedAt: Date
    var avatarName: String? = nil
    var platformHighlights: [FeaturedGame] = []
    // Per-platform lifetime top games feeding the A4–A6 walls; empty when the
    // snapshot was saved before this field shipped.
    var galleryWalls: [GamePlatform: [FeaturedGame]] = [:]
    // Artwork name of each platform's most recently played game (lifetime top
    // as fallback), for the medium platform widgets' backdrop.
    var showcaseArtwork: [GamePlatform: String] = [:]
    // Account-level Steam achievements and PSN trophies, copied from the app's
    // caches when the widget snapshot is saved.
    var platformProgress: PlatformProgress = PlatformProgress()
    // Steam live presence captured at sync time (nil = unknown/offline data).
    var steamPersonaState: Int? = nil
    var steamPlayingGame: String? = nil
    // Steam account level for the A1 tray; nil on snapshots saved before this
    // field shipped (one re-sync fills it).
    var steamLevel: Int? = nil
    // PSN trophy level for the A1 tray, same shipping caveat as steamLevel.
    var psnTrophyLevel: Int? = nil
    // One "last played" row per connected platform, most recent first, prepared
    // app-side for the A2 card's activity panel. Row date is nil when unknown.
    var lastPlayedRows: [LastPlayedRow] = []
    var psnPlayedGames: [FeaturedGame] = []

    var connectedPlatforms: [PlatformActivity] { platforms.filter(\.isConnected) }
    var connectedPlatformCount: Int { connectedPlatforms.count }
    var hasData: Bool { connectedPlatformCount > 0 }
    // Steam and Nintendo provide recent-play minutes; PSN does not.
    var hasFortnightDataSource: Bool {
        connectedPlatforms.contains { $0.platform == .steam || $0.platform == .nintendo }
    }
    var playtimeLabel: String { platforms.contains { $0.isConnected && $0.hasPlaytime } ? totalPlayedMinutes.hoursLabel : "—" }
    // Platforms actually contributing to the fortnight total; only Steam and
    // Nintendo expose period playtime; PSN's last-played date supplies no minutes.
    var recentPeriodTitle: String {
        let names = fortnightGames.filter { $0.fortnightMinutes > 0 }
            .map(\.platform)
            .uniqued()
            .map(\.title)
        return names.isEmpty
            ? L10n.widget("Last 14 Days")
            : L10n.widget("Last 14 Days · %1$@", names.joined(separator: " / "))
    }

    static var empty: GameSnapshot {
        GameSnapshot(
            playerName: L10n.widget("Connect your gaming platforms"),
            platforms: [.disconnected(.steam), .disconnected(.nintendo), .disconnected(.playStation)],
            recentGames: [], fortnightGames: [], allTimeTopGame: .empty,
            totalGameCount: 0, updatedAt: .distantPast
        )
    }

    var totalPlayedMinutes: Int {
        platforms.reduce(0) { $0 + $1.playedMinutes }
    }

    var fortnightPlayedMinutes: Int {
        fortnightGames.reduce(0) { $0 + max($1.fortnightMinutes, 0) }
    }

    var recentHeroCandidates: [FeaturedGame] {
        recentHeroCandidates(at: .now)
    }

    func recentHeroCandidates(at now: Date) -> [FeaturedGame] {
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let psn = psnGamesPlayed(at: now, since: cutoff)
        let connected = Set(connectedPlatforms.map(\.platform))
        var seenPrimary = Set<String>()
        let ranked = fortnightGames
            .filter { connected.contains($0.platform) && $0.platform != .playStation && $0.fortnightMinutes > 0 }
            .sorted { lhs, rhs in
                if lhs.fortnightMinutes != rhs.fortnightMinutes {
                    return lhs.fortnightMinutes > rhs.fortnightMinutes
                }
                if lhs.lifetimeMinutes != rhs.lifetimeMinutes {
                    return lhs.lifetimeMinutes > rhs.lifetimeMinutes
                }
                return lhs.id < rhs.id
            }
            .filter { seenPrimary.insert("\($0.platform.rawValue):\($0.id)").inserted }
        // With PSN as the only recent platform, show its latest titles in date
        // order. In a mixed pool it contributes only the most recent title.
        if ranked.isEmpty { return Array(psn.prefix(3)) }
        // PSN reserves the last available position, without comparing its
        // lifetime minutes to the other platforms' recent-play minutes.
        return Array(ranked.prefix(psn.isEmpty ? 3 : 2)) + Array(psn.prefix(1))
    }

    private func psnGamesPlayed(at now: Date, since cutoff: Date? = nil) -> [FeaturedGame] {
        guard connectedPlatforms.contains(where: { $0.platform == .playStation }) else { return [] }
        var seen = Set<String>()
        return psnPlayedGames
            .filter { game in
                guard game.platform == .playStation,
                      let date = game.lastPlayedDate else { return false }
                return date <= now && (cutoff.map { date >= $0 } ?? true)
            }
            .sorted { lhs, rhs in
                if lhs.lastPlayedDate != rhs.lastPlayedDate {
                    return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
                }
                return lhs.id < rhs.id
            }
            .filter { seen.insert($0.id).inserted }
    }

    var hasRecentHeroGames: Bool { !recentHeroCandidates.isEmpty }

    // With no recent play, give each connected platform one background. PSN
    // always uses its last-played date; Steam and Nintendo use lifetime playtime.
    var backgroundHeroCandidates: [FeaturedGame] {
        let psn = psnGamesPlayed(at: .now).first
        return connectedPlatforms.compactMap { activity in
            if activity.platform == .playStation { return psn }
            return galleryWalls[activity.platform]?
                .filter { $0.lifetimeMinutes > 0 }
                .max { $0.lifetimeMinutes < $1.lifetimeMinutes }
                ?? platformHighlights.first {
                    $0.platform == activity.platform && $0.lifetimeMinutes > 0
                }
        }
    }

    var heroCandidates: [FeaturedGame] {
        let recent = recentHeroCandidates
        if !recent.isEmpty { return recent }
        let backgrounds = backgroundHeroCandidates
        return backgrounds.isEmpty ? [.empty] : backgrounds
    }

    var fortnightSourceLabel: String {
        fortnightGames.filter { $0.fortnightMinutes > 0 }
            .map(\.platform).uniqued().map(\.title).joined(separator: " / ")
    }
}

/// One platform's most recent play session, shown on the A2 card.
struct LastPlayedRow: Sendable {
    let platform: GamePlatform
    let title: String
    let date: Date?
}

/// Shared relative-time formatter (e.g. "3天前"); both the app pages and the
/// widget extension render dates with it.
enum RelativeTime {
    static func text(for date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension Int {
    var hoursLabel: String { L10n.widget("%@h", (self / 60).formatted(.number.locale(L10n.locale))) }
    // Ceiling variant for short periods: any playtime under an hour still
    // reads as "1h" instead of an ugly "0h".
    var hoursLabelRoundedUp: String {
        guard self > 0 else { return "0" }
        return L10n.widget("%@h", ((self + 59) / 60).formatted(.number.locale(L10n.locale)))
    }
    var hoursMinutesLabel: String { L10n.widget("%dh %dm", self / 60, self % 60) }
}

/// The one sort order used everywhere a game list appears — the platform
/// pages and the A4–A6 walls: most played recently first, then last-played
/// date, then lifetime playtime.
enum GameListOrder {
    static func fortnight(_ lhs: Int, _ rhs: Int) -> Bool? {
        lhs == rhs ? nil : lhs > rhs
    }

    static func lastPlayed(_ lhs: Date?, _ rhs: Date?) -> Bool? {
        switch (lhs, rhs) {
        case let (l?, r?): l == r ? nil : l > r
        case (.some, nil): true
        case (nil, .some): false
        default: nil
        }
    }
}

extension Array where Element == GamePlatform {
    func uniqued() -> [GamePlatform] {
        var seen = Set<GamePlatform>()
        return filter { seen.insert($0).inserted }
    }
}
