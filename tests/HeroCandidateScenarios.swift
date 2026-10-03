import Foundation

// These checks compile the production snapshot models directly. Localization
// is isolated so fixtures never access a user's App Group or account data.
enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func widget(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: key, locale: locale, arguments: arguments)
    }
}

@main
enum HeroCandidateScenarios {
    static func primary(_ id: String, platform: GamePlatform = .steam, minutes: Int) -> FeaturedGame {
        FeaturedGame(id: id, title: id, platform: platform, artworkName: id,
                     fortnightMinutes: minutes, lifetimeMinutes: minutes * 10)
    }

    static func psn(_ id: String, date: Date?, lifetime: Int = 0) -> FeaturedGame {
        FeaturedGame(id: id, title: id, platform: .playStation, artworkName: id,
                     fortnightMinutes: 0, lifetimeMinutes: lifetime, lastPlayedDate: date)
    }

    static func snapshot(primary: [FeaturedGame] = [], psn: [FeaturedGame] = [],
                         connected: [GamePlatform] = GamePlatform.allCases,
                         walls: [GamePlatform: [FeaturedGame]] = [:]) -> GameSnapshot {
        GameSnapshot(playerName: "fixture",
                     platforms: connected.map { PlatformActivity(platform: $0, playedMinutes: 100, gameCount: 10) },
                     recentGames: [], fortnightGames: primary, allTimeTopGame: .empty,
                     totalGameCount: 30, updatedAt: .now, galleryWalls: walls, psnPlayedGames: psn)
    }

    static func expect(_ snapshot: GameSnapshot, at date: Date, _ ids: [String], _ label: String) {
        let actual = snapshot.recentHeroCandidates(at: date).map(\.id)
        precondition(actual == ids, "\(label): expected \(ids), got \(actual)")
    }

    static func main() {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        let steam = (1...10).map { primary("steam-\($0)", minutes: 200 - $0) }
        let nintendo = (1...10).map { primary("switch-\($0)", platform: .nintendo, minutes: 200 - $0 * 2) }
        let newest = psn("ps-new", date: now.addingTimeInterval(-3_600), lifetime: 1)
        let older = psn("ps-old", date: now.addingTimeInterval(-86_400), lifetime: 100_000)
        let oldest = psn("ps-third", date: now.addingTimeInterval(-2 * 86_400))

        expect(snapshot(), at: now, [], "no recent play")
        expect(snapshot(primary: steam + nintendo, psn: [older, newest]), at: now,
               ["steam-1", "steam-2", "ps-new"], "20 primary games reserve third for latest PSN")
        expect(snapshot(primary: steam), at: now,
               ["steam-1", "steam-2", "steam-3"], "no PSN keeps primary top three")
        expect(snapshot(primary: [steam[0]], psn: [older, newest]), at: now,
               ["steam-1", "ps-new"], "one primary appends one PSN without gaps")
        expect(snapshot(psn: [oldest, older, newest, psn("ps-fourth", date: now.addingTimeInterval(-4 * 86_400))]),
               at: now, ["ps-new", "ps-old", "ps-third"], "PSN only ranks by date and caps at three")
        expect(snapshot(psn: [newest]), at: now, ["ps-new"], "PSN only one title")
        expect(snapshot(psn: [older, newest]), at: now, ["ps-new", "ps-old"], "PSN only two titles")
        expect(snapshot(primary: [primary("zero-steam", minutes: 0),
                                  primary("zero-switch", platform: .nintendo, minutes: 0)],
                        psn: [oldest, newest, older]),
               at: now, ["ps-new", "ps-old", "ps-third"], "connected Steam and Switch with zero recent minutes")
        expect(snapshot(primary: steam, psn: [psn("ancient", date: now.addingTimeInterval(-730 * 86_400))]),
               at: now, ["steam-1", "steam-2", "steam-3"], "two-year-old PSN does not reserve a slot")
        expect(snapshot(psn: [psn("boundary", date: cutoff)]), at: now, ["boundary"], "14-day boundary included")
        expect(snapshot(psn: [psn("expired", date: cutoff.addingTimeInterval(-1))]), at: now, [], "expired date excluded")
        expect(snapshot(psn: [psn("future", date: now.addingTimeInterval(60)), newest]),
               at: now, ["ps-new"], "future date excluded without losing valid game")
        expect(snapshot(psn: [psn("unknown", date: nil)]), at: now, [], "missing date excluded")
        expect(snapshot(psn: [newest, newest, older]), at: now, ["ps-new", "ps-old"], "duplicate PSN titles excluded")
        expect(snapshot(psn: [newest], connected: [.steam]), at: now, [], "disconnected PSN ignored")
        expect(snapshot(primary: [steam[0], steam[0], steam[1], steam[2]]), at: now,
               ["steam-1", "steam-2", "steam-3"], "duplicate primary titles do not consume slots")
        expect(snapshot(primary: steam, connected: [.playStation]), at: now, [], "disconnected primary ignored")
        let tied = psn("ps-a", date: newest.lastPlayedDate, lifetime: 0)
        expect(snapshot(psn: [newest, tied]), at: now, ["ps-a", "ps-new"], "equal dates have stable order")

        let formatter = ISO8601DateFormatter()
        var undatedDuration = PSNGame(id: "unknown-duration", name: "fixture", lifetimeMinutes: 0,
                                     lastPlayed: formatter.string(from: now.addingTimeInterval(-600)))
        undatedDuration.hasPlaytime = false
        let library = PSNLibrary(games: [
            PSNGame(id: "invalid", name: "fixture", lifetimeMinutes: 500, lastPlayed: "invalid"),
            PSNGame(id: "future", name: "fixture", lifetimeMinutes: 500,
                    lastPlayed: formatter.string(from: now.addingTimeInterval(86_400))),
            PSNGame(id: "older", name: "fixture", lifetimeMinutes: 999,
                    lastPlayed: formatter.string(from: now.addingTimeInterval(-86_400))),
            undatedDuration
        ])
        let merged = WidgetSnapshots(steam: nil, nintendo: nil,
                                     playStation: PSNSnapshot(library: library, syncedAt: now)).gameSnapshot
        expect(merged, at: now, ["psn-unknown-duration", "psn-older"], "snapshot conversion preserves date without duration")
        precondition(merged.hasRecentHeroGames)
        precondition(merged.fortnightPlayedMinutes == 0 && merged.fortnightSourceLabel.isEmpty,
                     "PSN lifetime minutes must not enter fortnight totals")

        let zero = snapshot(walls: [.steam: [primary("favorite", minutes: 0)]])
        precondition(!zero.hasRecentHeroGames && !zero.heroCandidates.isEmpty,
                     "empty recent pool must still produce a safe widget entry")
        let historicalLatest = psn("historical-latest", date: now.addingTimeInterval(-30 * 86_400), lifetime: 1)
        let historicalFavorite = psn("historical-favorite", date: now.addingTimeInterval(-730 * 86_400), lifetime: 100_000)
        let historical = snapshot(psn: [historicalFavorite, historicalLatest], connected: [.playStation],
                                  walls: [.playStation: [historicalFavorite, historicalLatest]])
        precondition(!historical.hasRecentHeroGames)
        precondition(historical.heroCandidates.map(\.id) == [historicalLatest.id],
                     "PSN background must also use date rather than lifetime playtime")
        let unknownPSN = snapshot(psn: [psn("undated", date: nil, lifetime: 100_000)], connected: [.playStation])
        precondition(unknownPSN.backgroundHeroCandidates.isEmpty,
                     "missing PSN dates cannot establish a last-played background")
        print("23 hero selection and snapshot scenarios passed")
    }
}
