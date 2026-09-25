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

    var avatarName: String? {
        avatarURL.map { "steam-avatar-" + $0.deletingPathExtension().lastPathComponent }
    }
}

struct SteamLibrary: Codable, Sendable {
    let games: [SteamGame]
    let recent: [SteamGame]
    var player: SteamPlayer? = nil

    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
    var fortnightMinutes: Int { recent.reduce(0) { $0 + $1.fortnightMinutes } }
}

struct SteamSnapshot: Codable, Sendable {
    let library: SteamLibrary
    let syncedAt: Date

    var gameSnapshot: GameSnapshot {
        GameSnapshot(
            playerName: library.player?.name ?? L10n.widget("Steam Player"),
            platforms: [
                PlatformActivity(platform: .steam, playedMinutes: library.totalMinutes, gameCount: library.games.count),
                .disconnected(.nintendo),
                .disconnected(.playStation)
            ],
            days: [],
            recentGames: library.recent.filter { $0.fortnightMinutes > 0 }.sorted { $0.fortnightMinutes > $1.fortnightMinutes }.map {
                RecentGame(id: String($0.id), title: $0.name, platform: .steam, artworkName: $0.featuredGame.artworkName, weekMinutes: $0.fortnightMinutes)
            },
            fortnightGames: library.recent.map(\.featuredGame),
            allTimeTopGame: library.games.max(by: { $0.lifetimeMinutes < $1.lifetimeMinutes })?.featuredGame ?? .empty,
            totalGameCount: library.games.count,
            updatedAt: syncedAt,
            isDemo: false,
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

    private static var file: URL? { container?.appending(path: "steam-widget.json") }

    static var artworkDirectory: URL? {
        container?.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    static func artworkURL(named name: String) -> URL? {
        guard !name.isEmpty, name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return artworkDirectory?.appending(path: name + ".jpg")
    }

    static func load() -> SteamSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SteamSnapshot.self, from: data)
    }

    static func save(_ snapshot: SteamSnapshot) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
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

    var monogram: String {
        switch self {
        case .nintendo: "N"
        case .playStation: "P"
        case .steam: "S"
        }
    }
}

enum DataScope: Hashable, Sendable {
    case all
    case platform(GamePlatform)
}

enum ActivityPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case week
    case month
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .week: L10n.widget("This Week")
        case .month: L10n.widget("This Month")
        case .allTime: L10n.widget("All Time")
        }
    }

    var playtimeTitle: String {
        switch self {
        case .week: L10n.widget("Played This Week")
        case .month: L10n.widget("Played This Month")
        case .allTime: L10n.widget("Total Playtime")
        }
    }

}

enum AggregateStyle: String, CaseIterable, Identifiable, Sendable {
    case heroNoValue
    case atlas
    case platforms
    case gallery

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .heroNoValue: "A2"
        case .atlas: "B"
        case .platforms: "C"
        case .gallery: "D"
        }
    }

    var title: String {
        switch self {
        case .heroNoValue: L10n.widget("Game Life")
        case .atlas: L10n.widget("Data overview")
        case .platforms: L10n.widget("Platforms")
        case .gallery: L10n.widget("Game wall")
        }
    }

    var widgetKind: String { "Hourcade.Aggregate.\(rawValue)" }
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

struct PeriodPlatformActivity: Identifiable, Sendable {
    let platform: GamePlatform
    let playedMinutes: Int

    var id: GamePlatform { platform }
}

struct PeriodSummary: Sendable {
    let period: ActivityPeriod
    let platforms: [PeriodPlatformActivity]

    var playedMinutes: Int { platforms.reduce(0) { $0 + $1.playedMinutes } }

    func playtimeShare(for activity: PeriodPlatformActivity) -> Double {
        Double(activity.playedMinutes) / Double(max(playedMinutes, 1))
    }
}

struct DailyPlay: Identifiable, Sendable {
    let day: String
    let steamMinutes: Int
    let nintendoMinutes: Int
    let playStationMinutes: Int

    var id: String { day }
    var totalMinutes: Int { steamMinutes + nintendoMinutes + playStationMinutes }
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

    static var empty: FeaturedGame {
        FeaturedGame(id: "empty", title: L10n.widget("No play history"), platform: .steam, artworkName: "", fortnightMinutes: 0, lifetimeMinutes: 0)
    }
}

struct GameSnapshot: Sendable {
    let playerName: String
    let platforms: [PlatformActivity]
    let days: [DailyPlay]
    let recentGames: [RecentGame]
    let fortnightGames: [FeaturedGame]
    let allTimeTopGame: FeaturedGame
    let totalGameCount: Int
    let updatedAt: Date
    let isDemo: Bool
    var avatarName: String? = nil
    var platformHighlights: [FeaturedGame] = []

    var connectedPlatformCount: Int { platforms.filter(\.isConnected).count }
    var hasData: Bool { connectedPlatformCount > 0 }
    var hasFortnightData: Bool { isDemo || platforms.contains { $0.platform == .steam && $0.isConnected } }
    var playtimeLabel: String { platforms.contains { $0.isConnected && $0.hasPlaytime } ? totalPlayedMinutes.hoursLabel : "—" }
    var recentMinutes: Int { isDemo ? weekPlayedMinutes : fortnightPlayedMinutes }
    var recentPeriodTitle: String { L10n.widget(isDemo ? "This Week" : "Last 14 Days · Steam") }

    static var empty: GameSnapshot {
        GameSnapshot(
            playerName: L10n.widget("Connect your gaming platforms"),
            platforms: [.disconnected(.steam), .disconnected(.nintendo), .disconnected(.playStation)],
            days: [], recentGames: [], fortnightGames: [], allTimeTopGame: .empty,
            totalGameCount: 0, updatedAt: .distantPast, isDemo: false
        )
    }

    var totalPlayedMinutes: Int {
        platforms.reduce(0) { $0 + $1.playedMinutes }
    }

    var fortnightPlayedMinutes: Int {
        fortnightGames.reduce(0) { $0 + max($1.fortnightMinutes, 0) }
    }

    var heroCandidates: [FeaturedGame] {
        let active = fortnightGames
            .filter { $0.fortnightMinutes > 0 }
            .sorted { $0.fortnightMinutes > $1.fortnightMinutes }
        return active.isEmpty ? [allTimeTopGame] : Array(active.prefix(5))
    }

    var weekPlayedMinutes: Int {
        days.reduce(0) { $0 + $1.totalMinutes }
    }

    func weeklyMinutes(for platform: GamePlatform) -> Int {
        days.reduce(0) { total, day in
            switch platform {
            case .nintendo: total + day.nintendoMinutes
            case .playStation: total + day.playStationMinutes
            case .steam: total + day.steamMinutes
            }
        }
    }

    func summary(for period: ActivityPeriod) -> PeriodSummary {
        let items: [PeriodPlatformActivity] = platforms.map { activity in
            let minutes: Int
            switch period {
            case .allTime:
                minutes = activity.playedMinutes
            case .week:
                minutes = weeklyMinutes(for: activity.platform)
            case .month:
                switch activity.platform {
                case .steam: minutes = 55 * 60 + 40
                case .nintendo: minutes = 38 * 60 + 20
                case .playStation: minutes = 22 * 60 + 30
                }
            }
            return PeriodPlatformActivity(platform: activity.platform, playedMinutes: minutes)
        }
        return PeriodSummary(period: period, platforms: items)
    }

    static let demo = GameSnapshot(
        playerName: "Player One",
        platforms: [
            PlatformActivity(platform: .steam, playedMinutes: 4_164 * 60, gameCount: 279),
            PlatformActivity(platform: .nintendo, playedMinutes: 1_292 * 60, gameCount: 82),
            PlatformActivity(platform: .playStation, playedMinutes: 1_065 * 60, gameCount: 52)
        ],
        days: [
            DailyPlay(day: "Mon", steamMinutes: 65, nintendoMinutes: 55, playStationMinutes: 30),
            DailyPlay(day: "Tue", steamMinutes: 100, nintendoMinutes: 80, playStationMinutes: 30),
            DailyPlay(day: "Wed", steamMinutes: 95, nintendoMinutes: 92, playStationMinutes: 50),
            DailyPlay(day: "Thu", steamMinutes: 170, nintendoMinutes: 120, playStationMinutes: 70),
            DailyPlay(day: "Fri", steamMinutes: 120, nintendoMinutes: 80, playStationMinutes: 55),
            DailyPlay(day: "Sat", steamMinutes: 120, nintendoMinutes: 90, playStationMinutes: 60),
            DailyPlay(day: "Sun", steamMinutes: 66, nintendoMinutes: 51, playStationMinutes: 63)
        ],
        recentGames: [
            RecentGame(id: "aetherfall", title: "Aetherfall", platform: .nintendo, artworkName: "HeroAetherfall", weekMinutes: 432),
            RecentGame(id: "signal-city", title: "Signal City", platform: .steam, artworkName: "CoverSignalCity", weekMinutes: 268),
            RecentGame(id: "harborlight", title: "Harborlight", platform: .nintendo, artworkName: "CoverHarborlight", weekMinutes: 232),
            RecentGame(id: "ember-gate", title: "Ember Gate", platform: .playStation, artworkName: "CoverEmberGate", weekMinutes: 199)
        ],
        fortnightGames: [
            FeaturedGame(id: "aetherfall", title: "Aetherfall", platform: .nintendo, artworkName: "HeroAetherfall", fortnightMinutes: 665, lifetimeMinutes: 102 * 60),
            FeaturedGame(id: "signal-city", title: "Signal City", platform: .steam, artworkName: "CoverSignalCity", fortnightMinutes: 580, lifetimeMinutes: 218 * 60),
            FeaturedGame(id: "harborlight", title: "Harborlight", platform: .nintendo, artworkName: "CoverHarborlight", fortnightMinutes: 440, lifetimeMinutes: 87 * 60),
            FeaturedGame(id: "ember-gate", title: "Ember Gate", platform: .playStation, artworkName: "CoverEmberGate", fortnightMinutes: 355, lifetimeMinutes: 74 * 60)
        ],
        allTimeTopGame: FeaturedGame(id: "signal-city", title: "Signal City", platform: .steam, artworkName: "CoverSignalCity", fortnightMinutes: 0, lifetimeMinutes: 218 * 60),
        totalGameCount: 413,
        updatedAt: .now,
        isDemo: true
    )
}

extension Int {
    var hoursLabel: String { L10n.widget("%@h", (self / 60).formatted(.number.locale(L10n.locale))) }
    var hoursMinutesLabel: String { L10n.widget("%dh %dm", self / 60, self % 60) }
}
