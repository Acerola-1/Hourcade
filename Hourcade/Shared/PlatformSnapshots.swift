import Foundation

/// Platform APIs date-stamp play records in slightly different ISO 8601 shapes;
/// this tries the common variants before giving up (the row then sorts last).
enum SnapshotDates {
    nonisolated(unsafe) private static let fractional = makeFractional()
    nonisolated(unsafe) private static let internet = makeInternet()
    nonisolated(unsafe) private static let plain = makePlain()

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

    var lastPlayedDate: Date? {
        guard let lastPlayed, !lastPlayed.isEmpty else { return nil }
        return SnapshotDates.parse(lastPlayed)
    }

    var featuredGame: FeaturedGame {
        FeaturedGame(id: "psn-" + id, title: name, platform: .playStation, artworkName: "psn-" + id, fortnightMinutes: 0, lifetimeMinutes: lifetimeMinutes)
    }
}

struct PSNLibrary: Codable, Sendable {
    let games: [PSNGame]
    var onlineID: String? = nil
    var totalMinutes: Int { games.reduce(0) { $0 + $1.lifetimeMinutes } }
}

struct PSNSnapshot: Codable, Sendable {
    let library: PSNLibrary
    let syncedAt: Date
}

struct NintendoGame: Codable, Identifiable, Sendable {
    let name: String
    let imageUri: String
    let shopUri: String
    let totalPlayTime: Int
    let firstPlayedAt: Int
    // Unix timestamp of the play history's `lastPlayedAt`. Snapshots saved before
    // this field shipped have none and fall back to `firstPlayedAt` below.
    var lastPlayedAt: Int? = nil
    // Nintendo's own title identifier, which the store page and the play history
    // never agree on. Older snapshots saved before the account login shipped have
    // no value and fall back to the fields below.
    var titleId: String? = nil

    var id: String { titleId ?? (shopUri.isEmpty ? name : shopUri) }

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
    var totalMinutes: Int { games.reduce(0) { $0 + $1.totalPlayTime } }
}

struct WidgetSnapshots: Codable, Sendable {
    let steam: SteamSnapshot?
    let nintendo: NintendoSnapshot?
    let playStation: PSNSnapshot?

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
        return GameSnapshot(
            playerName: steamData?.playerName ?? playStation?.library.onlineID ?? L10n.widget("Connect your gaming platforms"),
            platforms: platforms,
            days: [],
            recentGames: steamData?.recentGames ?? [],
            fortnightGames: steamData?.fortnightGames ?? [],
            allTimeTopGame: favorites.max { $0.lifetimeMinutes < $1.lifetimeMinutes } ?? .empty,
            totalGameCount: platforms.reduce(0) { $0 + $1.gameCount },
            updatedAt: [steam?.syncedAt, nintendo?.syncedAt, playStation?.syncedAt].compactMap { $0 }.max() ?? .distantPast,
            isDemo: false,
            avatarName: steamData?.avatarName,
            platformHighlights: favorites
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
