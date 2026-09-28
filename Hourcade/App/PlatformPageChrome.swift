import SwiftUI

struct PageShell<Content: View>: View {
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

struct SettingsPanel<Content: View>: View {
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
struct PlatformAvatarView: View {
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

struct StatsRow: View {
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

enum TrophyPalette {
    static let platinum = Color(red: 0.72, green: 0.78, blue: 0.86)
    static let gold = Color(red: 0.98, green: 0.79, blue: 0.25)
    static let silver = Color(red: 0.71, green: 0.75, blue: 0.82)
    static let bronze = Color(red: 0.80, green: 0.51, blue: 0.28)
}

struct TrophyCountRow: View {
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
struct GameListPanel<Rows: View>: View {
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

struct SteamGameList: View {
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

struct SteamGameRow: View {
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

struct NintendoGameList: View {
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

struct NintendoGameRow: View {
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

struct PSNGameList: View {
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

struct PSNGameRow: View {
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
