import SwiftUI

// The first four visual experiments remain available in the app's preview studio.
// The WidgetKit extension uses AggregateCard, which follows the supplied A–D board.
struct ExplorationCard: View {
    let style: AggregateStyle
    let snapshot: GameSnapshot

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch style {
                case .hero, .heroNoValue: explorationHero
                case .atlas: explorationAtlas
                case .platforms: explorationPlatforms
                case .gallery: explorationGallery
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private var explorationHero: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HeroAetherfall")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.90), WidgetPalette.ink.opacity(0.32), WidgetPalette.ink.opacity(0.50)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HOURCADE").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(2)
                            Text("Your gaming life, at a glance.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.76))
                        }
                        Spacer()
                        explorationBadge
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 24) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TOTAL PLAYTIME").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.78))
                            Text(snapshot.totalPlayedMinutes.hoursLabel).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("\(snapshot.totalGameCount) games  ·  3 platforms").font(.system(size: 13)).foregroundStyle(.white.opacity(0.83))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("RECENTLY PLAYED").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.78))
                            Text(snapshot.recentGames[0].title).font(.system(size: 24, weight: .bold))
                            Text("Nintendo · \(snapshot.recentGames[0].weekMinutes.hoursMinutesLabel) this week")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.88))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        ForEach(snapshot.platforms) { activity in
                            HStack(spacing: 8) {
                                explorationPlatformMark(activity.platform, size: 27)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(activity.platform.title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.73))
                                    Text(activity.playedMinutes.hoursLabel).font(.system(size: 14, weight: .bold, design: .rounded))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.37), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(24)
                .foregroundStyle(.white)
            }
        }
    }

    private var explorationAtlas: some View {
        ZStack {
            LinearGradient(colors: [.white, Color(red: 0.84, green: 0.87, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOURCADE").font(.system(size: 17, weight: .bold, design: .rounded)).tracking(1.6)
                        Text("The shape of your playtime").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    explorationBadge(dark: true)
                }
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(WidgetPalette.steam, lineWidth: 13)
                        Circle().trim(from: 0, to: 0.36).stroke(WidgetPalette.nintendo, lineWidth: 13).rotationEffect(.degrees(120))
                        Circle().trim(from: 0, to: 0.16).stroke(WidgetPalette.playStation, lineWidth: 13).rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(snapshot.totalPlayedMinutes.hoursLabel).font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("ALL TIME").font(.system(size: 8)).tracking(0.8).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 128, height: 128)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.platforms) { activity in
                            HStack(spacing: 6) {
                                explorationPlatformMark(activity.platform, size: 21)
                                Text(activity.platform.title).font(.system(size: 11))
                                Spacer()
                                Text(activity.playedMinutes.hoursLabel).font(.system(size: 11, weight: .bold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("THIS WEEK").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                            Spacer()
                            Text(snapshot.weekPlayedMinutes.hoursMinutesLabel).font(.system(size: 19, weight: .bold, design: .rounded))
                        }
                        explorationWeekBars
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                Text("RECENT GAMES").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                HStack(spacing: 8) {
                    ForEach(snapshot.recentGames) { game in
                        HStack(spacing: 7) {
                            Image(game.artworkName).resizable().scaledToFill().frame(width: 37, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                Text(game.weekMinutes.hoursMinutesLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 62)
            }
            .padding(22)
            .foregroundStyle(WidgetPalette.ink)
        }
        .environment(\.colorScheme, .light)
    }

    private var explorationWeekBars: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(snapshot.days) { day in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            WidgetPalette.playStation.frame(height: CGFloat(day.playStationMinutes) / 360 * (geometry.size.height - 18))
                            WidgetPalette.nintendo.frame(height: CGFloat(day.nintendoMinutes) / 360 * (geometry.size.height - 18))
                            WidgetPalette.steam.frame(height: CGFloat(day.steamMinutes) / 360 * (geometry.size.height - 18))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(day.day).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var explorationPlatforms: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.19), WidgetPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HOURCADE").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(1.6)
                        Text("Three worlds. One player.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.64))
                    }
                    Spacer()
                    explorationBadge
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        Text("ALL-TIME PLAYTIME").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.65))
                        Text(snapshot.totalPlayedMinutes.hoursLabel).font(.system(size: 37, weight: .bold, design: .rounded))
                        Text("\(snapshot.totalGameCount) games").font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        Text("Different worlds.\nOne gaming life.").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: 170, alignment: .leading)
                    ForEach(snapshot.platforms) { activity in
                        explorationPortrait(activity)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(23)
            .foregroundStyle(.white)
        }
    }

    private func explorationPortrait(_ activity: PlatformActivity) -> some View {
        let artwork: String = switch activity.platform {
        case .steam: "CoverSignalCity"
        case .nintendo: "CoverHarborlight"
        case .playStation: "CoverEmberGate"
        }
        return GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Image(artwork).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    explorationPlatformMark(activity.platform, size: 27)
                    Spacer()
                    Text(activity.platform.title).font(.system(size: 11, weight: .semibold))
                    Text(activity.playedMinutes.hoursLabel).font(.system(size: 21, weight: .bold, design: .rounded))
                    Capsule().fill(WidgetPalette.color(for: activity.platform)).frame(height: 4)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }

    private var explorationGallery: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HeroAetherfall").resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).opacity(0.23).clipped()
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.90), WidgetPalette.ink.opacity(0.80)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HOURCADE").font(.system(size: 16, weight: .bold, design: .rounded)).tracking(1.5)
                            Text("A week across three worlds").font(.system(size: 10)).foregroundStyle(.white.opacity(0.70))
                        }
                        Spacer()
                        explorationBadge
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(snapshot.weekPlayedMinutes.hoursMinutesLabel).font(.system(size: 39, weight: .bold, design: .rounded))
                        Text("THIS WEEK").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.67))
                        Spacer()
                        Text("\(snapshot.totalGameCount) games · 3 platforms").font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    }
                    HStack(spacing: 9) {
                        ForEach(snapshot.recentGames) { game in
                            GeometryReader { tile in
                                ZStack(alignment: .bottomLeading) {
                                    Image(game.artworkName).resizable().scaledToFill().frame(width: tile.size.width, height: tile.size.height).clipped()
                                    LinearGradient(colors: [.clear, .black.opacity(0.80)], startPoint: .center, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                        Text(game.weekMinutes.hoursMinutesLabel).font(.system(size: 10))
                                    }
                                    .padding(9)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(22)
                .foregroundStyle(.white)
            }
        }
    }

    private var explorationBadge: some View { explorationBadge(dark: false) }

    private func explorationBadge(dark: Bool) -> some View {
        Text("DEMO")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.65) : Color.white.opacity(0.85))
            .background(dark ? Color.black.opacity(0.055) : Color.white.opacity(0.17), in: Capsule())
    }

    private func explorationPlatformMark(_ platform: GamePlatform, size: CGFloat) -> some View {
        Text(platform.monogram)
            .font(.system(size: size * 0.46, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(WidgetPalette.color(for: platform), in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}
