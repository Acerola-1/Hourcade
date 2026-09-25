import SwiftUI
import AppKit
import ImageIO

private enum WidgetImages {
    static func load(_ name: String, role: GameArtwork.Role? = nil, maxPixelSize: Int) -> CGImage? {
        guard !name.isEmpty, maxPixelSize > 0 else { return nil }
        if name.hasPrefix("steam-") || name.hasPrefix("psn-") || name.hasPrefix("nintendo-") {
            let candidates = role.map { ["\(name)-\($0.rawValue)-hd", name] } ?? [name]
            for candidate in candidates {
                guard let url = SteamWidgetStore.artworkURL(named: candidate),
                      FileManager.default.fileExists(atPath: url.path),
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continue }
                return image
            }
            return nil
        }
        guard let source = NSImage(named: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Only bounded raster images enter the widget archive; source assets stay untouched.
        let scale = min(1, CGFloat(maxPixelSize) / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

struct GameArtwork: View {
    enum Role: String {
        case hero
        case cover
    }

    let name: String
    var role: Role = .cover
    var maxPixelSize = 400

    var body: some View {
        if let image = WidgetImages.load(name, role: role, maxPixelSize: maxPixelSize) {
            Image(decorative: image, scale: 1).resizable()
        } else {
            LinearGradient(colors: [WidgetPalette.steam.opacity(0.7), WidgetPalette.ink], startPoint: .topTrailing, endPoint: .bottomLeading)
        }
    }
}

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
                case .heroNoValue: HeroNoValueCard(snapshot: snapshot, featuredGame: featuredGame ?? snapshot.heroCandidates[0])
                case .atlas: DataAggregateCard(snapshot: snapshot)
                case .platforms: PlatformAggregateCard(snapshot: snapshot)
                case .gallery: GalleryAggregateCard(snapshot: snapshot)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .environment(\.locale, L10n.locale)
        .accessibilityElement(children: .contain)
    }
}

private struct DemoLabel: View {
    var dark = false

    var body: some View {
        Text(L10n.widget("DEMO"))
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1.1)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.7) : .white.opacity(0.86))
            .background(dark ? Color.black.opacity(0.07) : Color.white.opacity(0.18), in: Capsule())
            .accessibilityLabel(L10n.widget("Demo data"))
    }
}

private struct PlayerIdentity: View {
    let name: String
    var dark = false
    var subtitle = L10n.widget("Play games. Be happy.")
    var avatarName: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let avatarName, let image = WidgetImages.load(avatarName, maxPixelSize: 80) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(dark ? WidgetPalette.steam : .white)
                }
            }
            .frame(width: 34, height: 34)
            .background(dark ? WidgetPalette.steam.opacity(0.12) : Color.white.opacity(0.16), in: Circle())
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.56) : Color.white.opacity(0.67))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
        .accessibilityLabel(L10n.widget("Time range"))
    }

    private func pill(_ period: ActivityPeriod) -> some View {
        Text(L10n.widget(period.title))
            .foregroundStyle(period == selected ? WidgetPalette.ink : (dark ? WidgetPalette.ink.opacity(0.55) : Color.white.opacity(0.77)))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 4)
            .frame(width: period == .month ? 68 : (period == .week ? 66 : 53), height: 20)
            .background(period == selected ? Color.white : Color.clear, in: Capsule())
            .accessibilityAddTraits(period == selected ? .isSelected : [])
    }
}

private struct SyncStatus: View {
    var dark = false
    var updatedAt: Date? = nil
    var isDemo = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.widget(updatedAt == nil ? "Updated" : "Last synced"))
                if let updatedAt {
                    Text(updatedAt, format: .dateTime.month().day().hour().minute().locale(L10n.locale))
                } else {
                    Text(isDemo ? L10n.widget("%1$d minutes ago", 12) : L10n.widget("Open app to connect"))
                }
            }
            .font(.system(size: 8))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundStyle(dark ? WidgetPalette.ink.opacity(0.55) : Color.white.opacity(0.70))
        .accessibilityElement(children: .combine)
    }
}

private struct PlatformMark: View {
    let platform: GamePlatform
    var size: CGFloat = 22

    var body: some View {
        PlatformBrandLogo(platform: platform, size: size)
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

private struct HeroArtworkBackdrop: View {
    let featuredGame: FeaturedGame
    let size: CGSize

    var body: some View {
        ZStack {
            if featuredGame.artworkName.isEmpty {
                LinearGradient(colors: [WidgetPalette.steam, WidgetPalette.ink], startPoint: .topTrailing, endPoint: .bottomLeading)
            } else {
                ForEach([featuredGame]) { game in
                    GameArtwork(name: game.artworkName, role: .hero, maxPixelSize: 1440)
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
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
                if !featuredGame.artworkName.isEmpty {
                    ForEach([featuredGame]) { game in
                        GameArtwork(name: game.artworkName, role: .hero, maxPixelSize: 240)
                            .scaledToFill()
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .offset(x: -18, y: -(canvasSize.height - 18 - height))
                            .blur(radius: 18)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
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

private struct FeaturedGameSummary: View {
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame

    private var hasRecentPlay: Bool { snapshot.fortnightPlayedMinutes > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.widget(hasRecentPlay ? "FROM YOUR LAST 14 DAYS" : "MOST PLAYED · ALL TIME"))
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(featuredGame.id == "empty" ? L10n.widget("No play history") : featuredGame.title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                PlatformBrandLogo(platform: featuredGame.platform, size: 31)
                VStack(alignment: .leading, spacing: 2) {
                    Text(featuredGame.platform.title)
                        .font(.system(size: 11, weight: .medium))
                    Text(featuredGame.id == "empty" ? L10n.widget("Connect a platform or sync play history") : (hasRecentPlay ? L10n.widget("Played %1$@ in 14 days", featuredGame.fortnightMinutes.hoursMinutesLabel) : L10n.widget("Played %1$@ all time", featuredGame.lifetimeMinutes.hoursLabel)))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
            // Keep A2's two-column layout, but give its metric a real width in WidgetKit.
            let metricWidth = max(0, geometry.size.width - 18 * 2 - 225 - 26)
            ZStack {
                HeroArtworkBackdrop(featuredGame: featuredGame, size: geometry.size)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.widget("Game Life"))
                                .font(.system(size: 32, weight: .medium, design: .rounded))
                            Text(L10n.widget("Play more. Live better."))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        SyncStatus(updatedAt: snapshot.isDemo || !snapshot.hasData ? nil : snapshot.updatedAt, isDemo: snapshot.isDemo)
                        if snapshot.isDemo { DemoLabel() }
                    }

                    Spacer(minLength: 20)

                    HStack(alignment: .bottom, spacing: 26) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.widget("Total Playtime · All Time"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(snapshot.playtimeLabel)
                                .font(.system(size: 44, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(L10n.widget("%1$@ games  ·  %2$d / %3$d platforms", snapshot.hasData ? snapshot.totalGameCount.formatted(.number.locale(L10n.locale)) : "—", snapshot.connectedPlatformCount, GamePlatform.allCases.count))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(width: metricWidth, alignment: .leading)
                        FeaturedGameSummary(snapshot: snapshot, featuredGame: featuredGame)
                    }

                    Spacer(minLength: 19)

                    HStack(spacing: 0) {
                        ForEach(snapshot.platforms) { activity in
                            NoValuePlatformStat(activity: activity, totalPlayedMinutes: snapshot.totalPlayedMinutes)
                                .frame(maxWidth: .infinity)
                            FrostedTrayDivider()
                        }
                        FortnightTotalPanel(playedMinutes: snapshot.fortnightPlayedMinutes, isAvailable: snapshot.hasData)
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
                    Text(activity.playtimeLabel)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(activity.isConnected ? L10n.widget("%1$d%% of playtime", Int((share * 100).rounded())) : L10n.widget("Not connected"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.77))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .accessibilityLabel(L10n.widget("%1$@, %2$@", activity.platform.title, activity.isConnected ? activity.playtimeLabel : L10n.widget("Not connected")))
    }
}

private struct FortnightTotalPanel: View {
    let playedMinutes: Int
    var isAvailable = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.widget("LAST 14 DAYS"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Text(isAvailable ? playedMinutes.hoursMinutesLabel : "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAvailable ? L10n.widget("Played %1$@ in 14 days", playedMinutes.hoursMinutesLabel) : L10n.widget("%1$@, %2$@", L10n.widget("LAST 14 DAYS"), L10n.widget("No play history")))
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
                        Text(L10n.widget("Game Life"))
                            .font(.system(size: 19, weight: .semibold))
                        Text(L10n.widget("Your gaming life, at a glance."))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if snapshot.isDemo {
                        ScopePills(dark: true)
                    } else {
                        Text(L10n.widget("All Time"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(7)
                            .background(.black.opacity(0.05), in: Capsule())
                    }
                    SyncStatus(dark: true, updatedAt: snapshot.isDemo || !snapshot.hasData ? nil : snapshot.updatedAt, isDemo: snapshot.isDemo)
                    if snapshot.isDemo { DemoLabel(dark: true) }
                }

                HStack(spacing: 16) {
                    PlaytimeRing(snapshot: snapshot)
                        .frame(width: 140, height: 140)
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(snapshot.platforms) { activity in
                            HStack(spacing: 7) {
                                PlatformMark(platform: activity.platform, size: 19)
                                Text(activity.playtimeLabel)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                Text(activity.isConnected ? L10n.widget("%1$d%%", Int((Double(activity.playedMinutes) / Double(max(snapshot.totalPlayedMinutes, 1)) * 100).rounded())) : L10n.widget("Not connected"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 104)
                    Rectangle().fill(WidgetPalette.ink.opacity(0.12)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.widget(snapshot.recentPeriodTitle))
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(snapshot.hasData ? snapshot.recentMinutes.hoursMinutesLabel : "—")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        if snapshot.isDemo {
                            WeekBars(days: snapshot.days)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 28))
                                Text(L10n.widget("No daily history yet"))
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 146)

                HStack {
                    Text(L10n.widget("Recently Played"))
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text(L10n.widget(snapshot.isDemo ? "See All ›" : "Steam · Last 14 Days"))
                        .font(.system(size: 9))
                }

                HStack(spacing: 7) {
                    ForEach(0..<6, id: \.self) { index in
                        if index < previewGames.count {
                            SmallCover(game: previewGames[index], recolor: snapshot.isDemo && index >= 4)
                        } else {
                            EmptyGameCover()
                        }
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
        snapshot.recentGames + (snapshot.isDemo ? [
            RecentGame(id: "starwake", title: "Starwake", platform: .steam, artworkName: "CoverSignalCity", weekMinutes: 126),
            RecentGame(id: "verdant-run", title: "Verdant Run", platform: .nintendo, artworkName: "CoverHarborlight", weekMinutes: 96)
        ] : [])
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
                Text(snapshot.playtimeLabel)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(L10n.widget("Total"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.widget("Total playtime %1$@", snapshot.playtimeLabel))
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
                        Text(L10n.widget(day.day))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.widget("%1$@, %2$@", L10n.widget(day.day), day.totalMinutes.hoursMinutesLabel))
                }
            }
        }
    }
}

private struct EmptyGameCover: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gamecontroller")
            Text(L10n.widget("No history")).font(.system(size: 9))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SmallCover: View {
    let game: RecentGame
    var recolor = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                GameArtwork(name: game.artworkName, role: .cover, maxPixelSize: 400)
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
                        Text(L10n.widget("Game Life")).font(.system(size: 15, weight: .semibold))
                        Text(L10n.widget("Same Games. A Bigger You."))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                    SyncStatus(updatedAt: snapshot.isDemo || !snapshot.hasData ? nil : snapshot.updatedAt, isDemo: snapshot.isDemo)
                    if snapshot.isDemo { DemoLabel() }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 13) {
                        MetricLine(icon: "clock", value: snapshot.playtimeLabel, label: L10n.widget("Total Playtime"))
                        MetricLine(icon: "gamecontroller", value: snapshot.hasData ? snapshot.totalGameCount.formatted(.number.locale(L10n.locale)) : "—", label: L10n.widget("Games"))
                        MetricLine(icon: "square.3.layers.3d", value: L10n.widget("%1$d / %2$d", snapshot.connectedPlatformCount, GamePlatform.allCases.count), label: L10n.widget("Platforms"))
                        Spacer(minLength: 0)
                        Text(L10n.widget("“ Good games\nmake a brighter day."))
                            .font(.system(size: 9))
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(width: 145)

                    ForEach(snapshot.platforms) { activity in
                        PlatformPortrait(activity: activity, total: snapshot.totalPlayedMinutes, artworkName: snapshot.isDemo ? nil : (activity.platform == .steam ? snapshot.allTimeTopGame.artworkName : ""))
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
    var artworkName: String? = nil

    private var artwork: String {
        if let artworkName { return artworkName }
        switch activity.platform {
        case .steam: return "CoverSignalCity"
        case .nintendo: return "CoverHarborlight"
        case .playStation: return "CoverEmberGate"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                GameArtwork(name: artwork, role: .cover, maxPixelSize: 600)
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
                        Text(activity.playtimeLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(activity.isConnected ? L10n.widget("%1$d%%", Int((Double(activity.playedMinutes) / Double(max(total, 1)) * 100).rounded())) : L10n.widget("Not connected"))
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
        .accessibilityLabel(L10n.widget("%1$@, %2$@", activity.platform.title, activity.isConnected ? activity.playtimeLabel : L10n.widget("Not connected")))
    }
}

private struct GalleryAggregateCard: View {
    let snapshot: GameSnapshot

    private var previewGames: [RecentGame] {
        snapshot.recentGames + (snapshot.isDemo ? [
            RecentGame(id: "starwake", title: "Starwake", platform: .steam, artworkName: "CoverSignalCity", weekMinutes: 126)
        ] : [])
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GameArtwork(name: snapshot.isDemo ? "HeroAetherfall" : snapshot.heroCandidates[0].artworkName, role: .hero, maxPixelSize: 1440)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.35)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.82), Color(red: 0.17, green: 0.30, blue: 0.51).opacity(0.75)], startPoint: .bottomLeading, endPoint: .topTrailing)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PlayerIdentity(name: snapshot.playerName, subtitle: L10n.widget("Play More. Live Better."), avatarName: snapshot.avatarName)
                        Spacer(minLength: 0)
                        if snapshot.isDemo { ScopePills() }
                        SyncStatus(updatedAt: snapshot.isDemo || !snapshot.hasData ? nil : snapshot.updatedAt, isDemo: snapshot.isDemo)
                        if snapshot.isDemo { DemoLabel() }
                    }
                    Spacer(minLength: 12)
                    HStack(alignment: .firstTextBaseline, spacing: 13) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.hasData ? snapshot.recentMinutes.hoursMinutesLabel : "—")
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                            Text(L10n.widget(snapshot.recentPeriodTitle))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.hasData ? snapshot.totalGameCount.formatted(.number.locale(L10n.locale)) : "—").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text(L10n.widget("Games")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                        }
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.widget("%1$d / %2$d", snapshot.connectedPlatformCount, GamePlatform.allCases.count)).font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text(L10n.widget("Platforms")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer(minLength: 0)
                        Text(L10n.widget("A different world today,\na brighter you tomorrow."))
                            .font(.system(size: 10))
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    Spacer(minLength: 15)
                    HStack(spacing: 7) {
                        ForEach(0..<5, id: \.self) { index in
                            if index < previewGames.count {
                                GalleryCover(game: previewGames[index], recolor: snapshot.isDemo && index == 4)
                                    .frame(maxWidth: .infinity)
                            } else {
                                EmptyGameCover()
                            }
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.10))
                            VStack(spacing: 5) {
                                Text(snapshot.isDemo ? L10n.widget("+%1$d", 7) : (previewGames.count > 5 ? L10n.widget("+%1$d", previewGames.count - 5) : "—"))
                                    .font(.system(size: 18, weight: .semibold))
                                Text(L10n.widget(snapshot.isDemo || previewGames.count > 5 ? "More" : "No more games")).font(.system(size: 9))
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
                GameArtwork(name: game.artworkName, role: .cover, maxPixelSize: 400)
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
        .accessibilityLabel(L10n.widget("%1$@, %2$@", game.title, game.weekMinutes.hoursMinutesLabel))
    }
}
