import SwiftUI

enum WidgetPalette {
    static let ink = Color(red: 0.09, green: 0.14, blue: 0.22)
    static let steam = Color(red: 0.27, green: 0.57, blue: 0.96)
    static let nintendo = Color(red: 0.99, green: 0.30, blue: 0.34)
    static let playStation = Color(red: 0.48, green: 0.42, blue: 0.93)

    static func color(for platform: GamePlatform) -> Color {
        switch platform {
        case .steam: steam
        case .nintendo: nintendo
        case .playStation: playStation
        }
    }
}

struct AggregateCard: View {
    let style: AggregateStyle
    let snapshot: GameSnapshot
    var featuredGame: FeaturedGame? = nil

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch style {
                case .hero: HeroAggregateCard(snapshot: snapshot, featuredGame: featuredGame ?? snapshot.heroCandidates[0])
                case .heroNoValue: HeroNoValueCard(snapshot: snapshot, featuredGame: featuredGame ?? snapshot.heroCandidates[0])
                case .atlas: DataAggregateCard(snapshot: snapshot)
                case .platforms: PlatformAggregateCard(snapshot: snapshot)
                case .gallery: GalleryAggregateCard(snapshot: snapshot)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DemoLabel: View {
    var dark = false

    var body: some View {
        Text("DEMO")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1.1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.7) : .white.opacity(0.86))
            .background(dark ? Color.black.opacity(0.07) : Color.white.opacity(0.18), in: Capsule())
            .accessibilityLabel("演示数据")
    }
}

private struct PlayerIdentity: View {
    let name: String
    var dark = false
    var subtitle = "Play games. Be happy."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(dark ? WidgetPalette.steam : .white)
                .frame(width: 34, height: 34)
                .background(dark ? WidgetPalette.steam.opacity(0.12) : Color.white.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.56) : Color.white.opacity(0.67))
            }
        }
    }
}

private struct ScopePills: View {
    var dark = false
    var selected: ActivityPeriod = .week
    var onSelect: ((ActivityPeriod) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ActivityPeriod.allCases) { period in
                Group {
                    if let onSelect {
                        Button { onSelect(period) } label: { pill(period) }
                            .buttonStyle(.plain)
                    } else {
                        pill(period)
                    }
                }
            }
        }
        .font(.system(size: 8, weight: .medium))
        .padding(3)
        .background(dark ? Color.black.opacity(0.055) : Color.white.opacity(0.11), in: Capsule())
        .accessibilityLabel("时间范围")
    }

    private func pill(_ period: ActivityPeriod) -> some View {
        Text(period.title)
            .foregroundStyle(period == selected ? WidgetPalette.ink : (dark ? WidgetPalette.ink.opacity(0.55) : Color.white.opacity(0.77)))
            .frame(width: period == .month ? 68 : (period == .week ? 66 : 53), height: 20)
            .background(period == selected ? Color.white : Color.clear, in: Capsule())
            .accessibilityAddTraits(period == selected ? .isSelected : [])
    }
}

private struct SyncStatus: View {
    var dark = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text("Updated")
                Text("12 minutes ago")
            }
            .font(.system(size: 8))
        }
        .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.55) : Color.white.opacity(0.70))
        .accessibilityLabel("示意更新状态，12 分钟前")
    }
}

private struct PlatformMark: View {
    let platform: GamePlatform
    var size: CGFloat = 22

    var body: some View {
        Text(platform.monogram)
            .font(.system(size: size * 0.49, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(WidgetPalette.color(for: platform), in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityLabel(platform.title)
    }
}

private struct PlatformBrandLogo: View {
    let platform: GamePlatform
    var size: CGFloat = 38

    private var imageName: String {
        switch platform {
        case .steam: "SteamLogo"
        case .nintendo: "NintendoSwitchLogo"
        case .playStation: "PlayStationLogo"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.65, height: size * 0.65)
            .frame(width: size, height: size)
            .background(WidgetPalette.color(for: platform), in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityLabel(platform.title)
    }
}

private struct HeroAggregateCard: View {
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HeroArtworkBackdrop(featuredGame: featuredGame, size: geometry.size)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 13) {
                        PlayerIdentity(name: snapshot.playerName)
                        Spacer(minLength: 0)
                        SyncStatus()
                        DemoLabel()
                    }

                    Spacer(minLength: 12)

                    HStack(alignment: .bottom, spacing: 26) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Playtime · All Time")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.80))
                            Text(snapshot.totalPlayedMinutes.hoursLabel)
                                .font(.system(size: 42, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("\(snapshot.totalGameCount) games  ·  \(snapshot.totalCatalogValueYuan.yuanLabel) est. list price")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        FeaturedGameSummary(snapshot: snapshot, featuredGame: featuredGame)
                    }

                    Spacer(minLength: 12)
                    HStack(spacing: 0) {
                        ForEach(snapshot.platforms) { activity in
                            GlassPlatformCompact(
                                activity: activity,
                                totalPlayedMinutes: snapshot.totalPlayedMinutes,
                                totalCatalogValueYuan: snapshot.totalCatalogValueYuan
                            )
                            .frame(maxWidth: .infinity)
                            FrostedTrayDivider()
                        }
                        FortnightTotalPanel(playedMinutes: snapshot.fortnightPlayedMinutes)
                            .frame(width: 130)
                    }
                    .frame(height: 96)
                    .background(FrostedHeroTray(featuredGame: featuredGame, canvasSize: geometry.size, height: 96, cornerRadius: 19))
                }
                .foregroundStyle(.white)
                .padding(18)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct HeroArtworkBackdrop: View {
    let featuredGame: FeaturedGame
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach([featuredGame]) { game in
                Image(game.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            LinearGradient(
                colors: [WidgetPalette.ink.opacity(0.81), WidgetPalette.ink.opacity(0.18), WidgetPalette.ink.opacity(0.52)],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(colors: [.black.opacity(0.12), .clear, .black.opacity(0.48)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct FrostedHeroTray: View {
    let featuredGame: FeaturedGame
    let canvasSize: CGSize
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach([featuredGame]) { game in
                    Image(game.artworkName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .offset(x: -18, y: -(canvasSize.height - 18 - height))
                        .blur(radius: 18)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                Color(red: 0.34, green: 0.40, blue: 0.46)
                    .opacity(0.62)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                Color.white.opacity(0.07)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct FrostedTrayDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1)
            .padding(.vertical, 13)
    }
}

private struct GlassPlatformCompact: View {
    let activity: PlatformActivity
    let totalPlayedMinutes: Int
    let totalCatalogValueYuan: Int

    private var playtimeShare: Double {
        Double(activity.playedMinutes) / Double(max(totalPlayedMinutes, 1))
    }

    private var valueShare: Double {
        Double(activity.catalogValueYuan) / Double(max(totalCatalogValueYuan, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                PlatformBrandLogo(platform: activity.platform, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.platform.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(activity.playedMinutes.hoursLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(activity.gameCount.formatted())
                    Text("games")
                }
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .frame(width: 34, alignment: .trailing)
                    .foregroundStyle(.white.opacity(0.84))
            }
            shareRow(title: "TIME", share: playtimeShare, tint: WidgetPalette.color(for: activity.platform))
            HStack(spacing: 2) {
                Text(activity.catalogValueYuan.yuanLabel).fontWeight(.semibold)
                Spacer(minLength: 0)
                Text("LIST PRICE")
                    .font(.system(size: 6, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .font(.system(size: 8))
            shareRow(title: "VALUE", share: valueShare, tint: .white.opacity(0.82))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.platform.title)，全部时间游玩\(activity.playedMinutes.hoursLabel)，时长占比\(Int((playtimeShare * 100).rounded()))%，游戏库\(activity.gameCount)款，当前估算标价\(activity.catalogValueYuan.yuanLabel)，价值占比\(Int((valueShare * 100).rounded()))%")
    }

    private func shareRow(title: String, share: Double, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 6, weight: .semibold))
                .tracking(0.3)
                .frame(width: 23, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: geometry.size.width * share)
                    }
            }
            .frame(height: 3)
            Text("\(Int((share * 100).rounded()))%")
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 23, alignment: .trailing)
        }
        .foregroundStyle(.white.opacity(0.70))
    }
}

private struct FeaturedGameSummary: View {
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame

    private var hasRecentPlay: Bool { snapshot.fortnightPlayedMinutes > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(hasRecentPlay ? "FROM YOUR LAST 14 DAYS" : "MOST PLAYED · ALL TIME")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.76))
            Text(featuredGame.title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            HStack(spacing: 8) {
                PlatformBrandLogo(platform: featuredGame.platform, size: 31)
                VStack(alignment: .leading, spacing: 2) {
                    Text(featuredGame.platform.title)
                        .font(.system(size: 11, weight: .medium))
                    Text(hasRecentPlay ? "Played \(featuredGame.fortnightMinutes.hoursMinutesLabel) in 14 days" : "Played \(featuredGame.lifetimeMinutes.hoursLabel) all time")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .frame(width: 225, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HeroNoValueCard: View {
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HeroArtworkBackdrop(featuredGame: featuredGame, size: geometry.size)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Game Life")
                                .font(.system(size: 32, weight: .medium, design: .rounded))
                            Text("Play more. Live better.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        Spacer(minLength: 0)
                        SyncStatus()
                        DemoLabel()
                    }

                    Spacer(minLength: 20)

                    HStack(alignment: .bottom, spacing: 26) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Total Playtime · All Time")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.78))
                            Text(snapshot.totalPlayedMinutes.hoursLabel)
                                .font(.system(size: 44, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Text("\(snapshot.totalGameCount) games  ·  \(snapshot.platforms.count) platforms")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        FeaturedGameSummary(snapshot: snapshot, featuredGame: featuredGame)
                    }

                    Spacer(minLength: 19)

                    HStack(spacing: 0) {
                        ForEach(snapshot.platforms) { activity in
                            NoValuePlatformStat(activity: activity, totalPlayedMinutes: snapshot.totalPlayedMinutes)
                                .frame(maxWidth: .infinity)
                            FrostedTrayDivider()
                        }
                        FortnightTotalPanel(playedMinutes: snapshot.fortnightPlayedMinutes)
                            .frame(width: 130)
                    }
                    .frame(height: 82)
                    .background(FrostedHeroTray(featuredGame: featuredGame, canvasSize: geometry.size, height: 82, cornerRadius: 20))
                }
                .foregroundStyle(.white)
                .padding(18)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct NoValuePlatformStat: View {
    let activity: PlatformActivity
    let totalPlayedMinutes: Int

    private var share: Double {
        Double(activity.playedMinutes) / Double(max(totalPlayedMinutes, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                PlatformBrandLogo(platform: activity.platform, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.playedMinutes.hoursLabel)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(Int((share * 100).rounded()))% of playtime")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.77))
                        .lineLimit(1)
                }
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(WidgetPalette.color(for: activity.platform))
                            .frame(width: geometry.size.width * share)
                    }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.platform.title)，全部时间游玩\(activity.playedMinutes.hoursLabel)，占总时长\(Int((share * 100).rounded()))%")
    }
}

private struct FortnightTotalPanel: View {
    let playedMinutes: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text("LAST 14 DAYS")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Text(playedMinutes.hoursMinutesLabel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("近 14 天游玩\(playedMinutes.hoursMinutesLabel)")
    }
}

private struct DataAggregateCard: View {
    let snapshot: GameSnapshot

    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, Color(red: 0.90, green: 0.92, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Game Life")
                            .font(.system(size: 19, weight: .semibold))
                        Text("Your gaming life, at a glance.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ScopePills(dark: true)
                    SyncStatus(dark: true)
                    DemoLabel(dark: true)
                }

                HStack(spacing: 16) {
                    PlaytimeRing(snapshot: snapshot)
                        .frame(width: 140, height: 140)
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(snapshot.platforms) { activity in
                            HStack(spacing: 7) {
                                PlatformMark(platform: activity.platform, size: 19)
                                Text(activity.playedMinutes.hoursLabel)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Spacer(minLength: 0)
                                Text("\(Int((Double(activity.playedMinutes) / Double(snapshot.totalPlayedMinutes) * 100).rounded()))%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 104)
                    Rectangle().fill(WidgetPalette.ink.opacity(0.12)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("This Week")
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(snapshot.weekPlayedMinutes.hoursMinutesLabel)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        WeekBars(days: snapshot.days)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 146)

                HStack {
                    Text("Recently Played")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("See All ›")
                        .font(.system(size: 9))
                }

                HStack(spacing: 7) {
                    ForEach(Array(previewGames.prefix(6).enumerated()), id: \.element.id) { index, game in
                        SmallCover(game: game, recolor: index >= 4)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(19)
            .foregroundStyle(WidgetPalette.ink)
        }
        .environment(\.colorScheme, .light)
    }

    private var previewGames: [RecentGame] {
        snapshot.recentGames + [
            RecentGame(id: "starwake", title: "Starwake", platform: .steam, artworkName: "CoverSignalCity", weekMinutes: 126),
            RecentGame(id: "verdant-run", title: "Verdant Run", platform: .nintendo, artworkName: "CoverHarborlight", weekMinutes: 96)
        ]
    }
}

private struct PlaytimeRing: View {
    let snapshot: GameSnapshot

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.ink.opacity(0.08), lineWidth: 17)
            ForEach(snapshot.platforms, id: \.platform) { activity in
                Circle()
                    .trim(from: start(for: activity.platform), to: end(for: activity.platform))
                    .stroke(WidgetPalette.color(for: activity.platform), lineWidth: 17)
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(snapshot.totalPlayedMinutes.hoursLabel)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Total")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("总游玩时间 \(snapshot.totalPlayedMinutes.hoursLabel)")
    }

    private func start(for platform: GamePlatform) -> CGFloat {
        let index = snapshot.platforms.firstIndex { $0.platform == platform } ?? 0
        let before = snapshot.platforms.prefix(index).reduce(0) { $0 + $1.playedMinutes }
        return CGFloat(before) / CGFloat(max(snapshot.totalPlayedMinutes, 1))
    }

    private func end(for platform: GamePlatform) -> CGFloat {
        let activity = snapshot.platforms.first { $0.platform == platform }
        return start(for: platform) + CGFloat(activity?.playedMinutes ?? 0) / CGFloat(max(snapshot.totalPlayedMinutes, 1))
    }
}

private struct WeekBars: View {
    let days: [DailyPlay]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            WidgetPalette.nintendo.frame(height: CGFloat(day.nintendoMinutes) / 360 * (geometry.size.height - 16))
                            WidgetPalette.steam.frame(height: CGFloat(day.steamMinutes) / 360 * (geometry.size.height - 16))
                            WidgetPalette.playStation.frame(height: CGFloat(day.playStationMinutes) / 360 * (geometry.size.height - 16))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(day.day)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.day), \(day.totalMinutes.hoursMinutesLabel)")
                }
            }
        }
    }
}

private struct SmallCover: View {
    let game: RecentGame
    var recolor = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image(game.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .hueRotation(.degrees(recolor ? 95 : 0))
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, .black.opacity(0.80)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Text(game.weekMinutes.hoursMinutesLabel).font(.system(size: 8))
                }
                .foregroundStyle(.white)
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlatformAggregateCard: View {
    let snapshot: GameSnapshot

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.18, green: 0.21, blue: 0.22), WidgetPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 17))
                        .frame(width: 35, height: 35)
                        .background(.white.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Game Life").font(.system(size: 15, weight: .semibold))
                        Text("Same Games. A Bigger You.")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                    SyncStatus()
                    DemoLabel()
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 13) {
                        MetricLine(icon: "clock", value: snapshot.totalPlayedMinutes.hoursLabel, label: "Total Playtime")
                        MetricLine(icon: "gamecontroller", value: "\(snapshot.totalGameCount)", label: "Games")
                        MetricLine(icon: "square.3.layers.3d", value: "3", label: "Platforms")
                        Spacer(minLength: 0)
                        Text("“ Good games\nmake a brighter day.")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(width: 145)

                    ForEach(snapshot.platforms) { activity in
                        PlatformPortrait(activity: activity, total: snapshot.totalPlayedMinutes)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(18)
            .foregroundStyle(.white)
        }
    }
}

private struct MetricLine: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(label).font(.system(size: 8)).foregroundStyle(.white.opacity(0.68))
            }
        }
    }
}

private struct PlatformPortrait: View {
    let activity: PlatformActivity
    let total: Int

    private var artwork: String {
        switch activity.platform {
        case .steam: "CoverSignalCity"
        case .nintendo: "CoverHarborlight"
        case .playStation: "CoverEmberGate"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image(artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, .black.opacity(0.10), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    PlatformMark(platform: activity.platform, size: 27)
                    Spacer()
                    Text(activity.platform.title).font(.system(size: 10, weight: .semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(activity.playedMinutes.hoursLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(Int((Double(activity.playedMinutes) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 8))
                    }
                    GeometryReader { bar in
                        Capsule().fill(.white.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(WidgetPalette.color(for: activity.platform))
                                    .frame(width: bar.size.width * CGFloat(activity.playedMinutes) / CGFloat(max(total, 1)))
                            }
                    }
                    .frame(height: 4)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activity.platform.title), \(activity.playedMinutes.hoursLabel)")
    }
}

private struct GalleryAggregateCard: View {
    let snapshot: GameSnapshot

    private var previewGames: [RecentGame] {
        snapshot.recentGames + [
            RecentGame(id: "starwake", title: "Starwake", platform: .steam, artworkName: "CoverSignalCity", weekMinutes: 126)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HeroAetherfall")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.35)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.82), Color(red: 0.17, green: 0.30, blue: 0.51).opacity(0.75)], startPoint: .bottomLeading, endPoint: .topTrailing)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PlayerIdentity(name: snapshot.playerName, subtitle: "Play More. Live Better.")
                        Spacer(minLength: 0)
                        ScopePills()
                        SyncStatus()
                        DemoLabel()
                    }
                    Spacer(minLength: 12)
                    HStack(alignment: .firstTextBaseline, spacing: 13) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.weekPlayedMinutes.hoursMinutesLabel)
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                            Text("This Week")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(snapshot.totalGameCount)").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("Games").font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                        }
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("3").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("Platforms").font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer(minLength: 0)
                        Text("A different world today,\na brighter you tomorrow.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    Spacer(minLength: 15)
                    HStack(spacing: 7) {
                        ForEach(Array(previewGames.enumerated()), id: \.element.id) { index, game in
                            GalleryCover(game: game, recolor: index == 4)
                                .frame(maxWidth: .infinity)
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.10))
                            VStack(spacing: 5) {
                                Text("+7").font(.system(size: 18, weight: .semibold))
                                Text("More").font(.system(size: 9))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: geometry.size.height * 0.50)
                }
                .padding(18)
                .foregroundStyle(.white)
            }
        }
    }
}

private struct GalleryCover: View {
    let game: RecentGame
    var recolor = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image(game.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .hueRotation(.degrees(recolor ? 95 : 0))
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    Text(game.weekMinutes.hoursMinutesLabel).font(.system(size: 8))
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), 本周 \(game.weekMinutes.hoursMinutesLabel)")
    }
}
