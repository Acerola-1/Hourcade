import Foundation

enum GamePlatform: String, CaseIterable, Identifiable, Sendable {
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

enum ActivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "This Week"
        case .month: "This Month"
        case .allTime: "All Time"
        }
    }

    var playtimeTitle: String {
        switch self {
        case .week: "Played This Week"
        case .month: "Played This Month"
        case .allTime: "Total Playtime"
        }
    }

}

enum AggregateStyle: String, CaseIterable, Identifiable, Sendable {
    case hero
    case heroNoValue
    case atlas
    case platforms
    case gallery

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .hero: "A"
        case .heroNoValue: "A2"
        case .atlas: "B"
        case .platforms: "C"
        case .gallery: "D"
        }
    }

    var title: String {
        switch self {
        case .hero: "英雄封面"
        case .heroNoValue: "无金额版"
        case .atlas: "数据概览"
        case .platforms: "平台分栏"
        case .gallery: "游戏墙"
        }
    }

    var widgetKind: String { "Hourcade.Aggregate.\(rawValue)" }
}

struct PlatformActivity: Identifiable, Sendable {
    let platform: GamePlatform
    let playedMinutes: Int
    let gameCount: Int
    let catalogValueYuan: Int

    var id: GamePlatform { platform }
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

    var totalPlayedMinutes: Int {
        platforms.reduce(0) { $0 + $1.playedMinutes }
    }

    var totalCatalogValueYuan: Int {
        platforms.reduce(0) { $0 + $1.catalogValueYuan }
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
        playerName: "Acerola",
        platforms: [
            PlatformActivity(platform: .steam, playedMinutes: 4_164 * 60, gameCount: 279, catalogValueYuan: 18_460),
            PlatformActivity(platform: .nintendo, playedMinutes: 1_292 * 60, gameCount: 82, catalogValueYuan: 15_200),
            PlatformActivity(platform: .playStation, playedMinutes: 1_065 * 60, gameCount: 52, catalogValueYuan: 9_340)
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
    var hoursLabel: String { "\((self / 60).formatted())h" }
    var hoursMinutesLabel: String { "\(self / 60)h \(self % 60)m" }
    var yuanLabel: String { "¥\(self.formatted())" }
}
