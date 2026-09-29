import SwiftUI
import AppKit
import ImageIO

private enum WidgetImages {
    static func load(_ name: String, role: GameArtwork.Role? = nil, maxPixelSize: Int) -> CGImage? {
        guard !name.isEmpty, maxPixelSize > 0 else { return nil }
        if name.hasPrefix("steam-") || name.hasPrefix("psn-") || name.hasPrefix("nintendo-") {
            // Portrait compositions try the vertical cover first, then the
            // hero backdrop (center-cropped in the view) and only then the
            // 460×215 legacy header, which upscales poorly.
            let candidates: [String]
            switch role {
            case .portrait?: candidates = [name + "-cover-hd", name + "-hero-hd", name]
            case .some(let role): candidates = ["\(name)-\(role.rawValue)-hd", name]
            case .none: candidates = [name]
            }
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
        // The widget archive only receives bounded raster images; source assets stay untouched.
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
        // Vertical composition: cover first, then hero as a sharp fallback.
        case portrait
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
    // Official brand colors: Steam navy (#1B2838), Switch red (#E60012), PS blue (#0070D1).
    static let steam = Color(red: 0.106, green: 0.157, blue: 0.220)
    static let nintendo = Color(red: 0.902, green: 0.0, blue: 0.071)
    static let playStation = Color(red: 0.0, green: 0.439, blue: 0.820)

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
    var rendersHeroBackdropInContent = true

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch style {
                case .heroNoValue: HeroNoValueCard(snapshot: snapshot, featuredGame: featuredGame ?? snapshot.heroCandidates[0], showsBackdrop: rendersHeroBackdropInContent)
                case .atlas: DataAggregateCard(snapshot: snapshot)
                case .platforms: PlatformAggregateCard(snapshot: snapshot)
                case .gallery: GalleryAggregateCard(snapshot: snapshot, platform: .steam)
                case .galleryNintendo: GalleryAggregateCard(snapshot: snapshot, platform: .nintendo)
                case .galleryPlayStation: GalleryAggregateCard(snapshot: snapshot, platform: .playStation)
                case .mini: MiniSummaryCard(snapshot: snapshot)
                case .steamMini: MiniPlatformCard(snapshot: snapshot, platform: .steam)
                case .nintendoMini: MiniPlatformCard(snapshot: snapshot, platform: .nintendo)
                case .playStationMini: MiniPlatformCard(snapshot: snapshot, platform: .playStation)
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

private struct SyncStatus: View {
    var dark = false
    var updatedAt: Date? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.widget(updatedAt == nil ? "Updated" : "Last synced"))
                if let updatedAt {
                    Text(updatedAt, format: .dateTime.month().day().hour().minute().locale(L10n.locale))
                } else {
                    Text(L10n.widget("Open app to connect"))
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

struct HeroArtworkBackdrop: View {
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
            HeroBackdropGrading()
        }
    }
}

/// Two-pass color grading applied over hero game artwork: a horizontal ink grade
/// followed by a top/bottom darkening vignette. Shared across the main backdrop
/// and the subtle shelf glass to keep the visual tone in lockstep.
private struct HeroBackdropGrading: View {
    var body: some View {
        Group {
            LinearGradient(
                colors: [WidgetPalette.ink.opacity(0.81), WidgetPalette.ink.opacity(0.18), WidgetPalette.ink.opacity(0.52)],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(colors: [.black.opacity(0.12), .clear, .black.opacity(0.48)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private let heroNoValueCoordinateSpace = "HeroNoValueCard"

private struct FrostedTrayDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1)
            .padding(.vertical, 13)
    }
}

/// Keep both information surfaces in the same image space and material tone.
private struct HeroGlassBackdrop: View {
    let featuredGame: FeaturedGame
    let canvasSize: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(heroNoValueCoordinateSpace))
            ZStack(alignment: .topLeading) {
                if !featuredGame.artworkName.isEmpty, canvasSize.width > 0, canvasSize.height > 0 {
                    ZStack {
                        GameArtwork(name: featuredGame.artworkName, role: .hero, maxPixelSize: 360)
                            .scaledToFill()
                            .frame(width: canvasSize.width, height: canvasSize.height)
                            .clipped()
                        HeroBackdropGrading()
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .offset(x: -frame.minX, y: -frame.minY)
                    .blur(radius: 10)
                    .accessibilityHidden(true)
                }
                WidgetPalette.ink.opacity(0.24)
                Color.black.opacity(0.12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
            )
        }
    }
}

private struct CompactFeaturedGameSummary: View {
    let featuredGame: FeaturedGame

    private var playedInFortnight: Bool { featuredGame.fortnightMinutes > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.widget(playedInFortnight ? "FROM YOUR LAST 14 DAYS" : "FEATURED GAME"))
                .font(.system(size: 9, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.72))
            Text(featuredGame.id == "empty" ? L10n.widget("No play history") : featuredGame.title)
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 6) {
                PlatformBrandLogo(platform: featuredGame.platform, size: 23)
                Text(featuredGame.id == "empty"
                     ? L10n.widget("Connect a platform or sync play history")
                     : L10n.widget(playedInFortnight ? "%1$@ in 14 days" : "Played %1$@ all time",
                                   playedInFortnight ? featuredGame.fortnightMinutes.hoursMinutesLabel : featuredGame.lifetimeMinutes.hoursLabel))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// A1: the open hero composition, with a compact recent-games shelf beside
/// the featured game. The full platform and fortnight tray stays intact.
private struct HeroCardLayout {
    let verticalInset: CGFloat
    let coverHeight: CGFloat
    let featuredHeight: CGFloat
    let trayHeight: CGFloat
    let sectionGap: CGFloat
    let panelSpacing: CGFloat
    let panelPadding: CGFloat

    init(height: CGFloat) {
        if height < 390 {
            verticalInset = height < 336 ? 10 : 14
            coverHeight = min(62, max(50, height - 282))
            featuredHeight = coverHeight + 110
            trayHeight = 78
            sectionGap = 0
            panelSpacing = 4
            panelPadding = 8
        } else {
            verticalInset = 18
            coverHeight = 70
            featuredHeight = max(186, height - 202)
            trayHeight = 82
            sectionGap = 12
            panelSpacing = 6
            panelPadding = 10
        }
    }
}

private struct HeroNoValueCard: View {
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame
    let showsBackdrop: Bool

    private var otherRecentGames: [RecentGame] {
        Array(snapshot.recentGames
            .filter { $0.id != featuredGame.id || $0.platform != featuredGame.platform }
            .prefix(3))
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = HeroCardLayout(height: geometry.size.height)
            let metricWidth = max(0, geometry.size.width - 18 * 2 - 228 - 26)
            ZStack {
                if showsBackdrop {
                    HeroArtworkBackdrop(featuredGame: featuredGame, size: geometry.size)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.widget("Overview"))
                                .font(.system(size: 32, weight: .medium, design: .rounded))
                            Text(L10n.widget("Play more. Live better."))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        SyncStatus(updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                    }

                    Spacer(minLength: layout.sectionGap)

                    HStack(alignment: .bottom, spacing: 26) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.widget("Total Playtime"))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(snapshot.playtimeLabel)
                                .font(.system(size: 44, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: metricWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: layout.panelSpacing) {
                            CompactFeaturedGameSummary(featuredGame: featuredGame)

                            Text(L10n.widget("Recently Played"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.80))

                            HStack(spacing: 7) {
                                if otherRecentGames.isEmpty {
                                    Text(L10n.widget("No history"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.68))
                                } else {
                                    ForEach(otherRecentGames) { game in
                                        HeroRecentCover(game: game)
                                            .frame(width: 64, height: layout.coverHeight)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: layout.coverHeight, alignment: .leading)
                        }
                        .padding(layout.panelPadding)
                        .frame(width: 228, height: layout.featuredHeight, alignment: .bottom)
                        .background(HeroGlassBackdrop(featuredGame: featuredGame, canvasSize: geometry.size, cornerRadius: 18))
                    }

                    Spacer(minLength: layout.sectionGap)

                    HStack(spacing: 0) {
                        ForEach(snapshot.platforms) { activity in
                            NoValuePlatformStat(activity: activity, totalPlayedMinutes: snapshot.totalPlayedMinutes, snapshot: snapshot)
                                .frame(maxWidth: .infinity)
                            FrostedTrayDivider()
                        }
                        FortnightTotalPanel(playedMinutes: snapshot.fortnightPlayedMinutes, isAvailable: snapshot.hasData)
                            .frame(width: 130)
                    }
                    .frame(height: layout.trayHeight)
                    .background(HeroGlassBackdrop(featuredGame: featuredGame, canvasSize: geometry.size, cornerRadius: 18))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, layout.verticalInset)
            }
            .coordinateSpace(name: heroNoValueCoordinateSpace)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Each platform uses the same identity, value, detail, and share-bar baselines.
private struct NoValuePlatformStat: View {
    let activity: PlatformActivity
    let totalPlayedMinutes: Int
    let snapshot: GameSnapshot

    private var share: Double {
        Double(activity.playedMinutes) / Double(max(totalPlayedMinutes, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PlatformBrandLogo(platform: activity.platform, size: 21)
                Text(activity.platform.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                Spacer(minLength: 2)
                progressBadge
            }
            .frame(height: 21)

            Text(activity.playtimeLabel)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 19, alignment: .leading)
                .padding(.top, 3)

            detailRow
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 12, alignment: .leading)
                .padding(.top, 2)

            Spacer(minLength: 2)

            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(WidgetPalette.color(for: activity.platform))
                            .frame(width: geometry.size.width * share)
                    }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.widget("%1$@, %2$@", activity.platform.title, activity.isConnected ? activity.playtimeLabel : L10n.widget("Not connected")))
    }

    private var gameCountText: Text {
        Text(L10n.widget("%1$@ games", activity.gameCount.formatted(.number.locale(L10n.locale))))
    }

    @ViewBuilder
    private var detailRow: some View {
        if activity.isConnected {
            switch activity.platform {
            case .steam:
                HStack(spacing: 4) {
                    gameCountText
                    if let level = snapshot.steamLevel {
                        FrostedDot()
                        Text(L10n.widget("Lv.%lld", level))
                    }
                }
            case .nintendo:
                gameCountText
            case .playStation:
                HStack(spacing: 4) {
                    gameCountText
                    if let level = snapshot.psnTrophyLevel {
                        FrostedDot()
                        Text(L10n.widget("Lv.%lld", level))
                    }
                }
            }
        } else {
            Text(L10n.widget("Not connected"))
        }
    }

    private var progressBadge: some View {
        Group {
            if activity.isConnected {
                switch activity.platform {
                case .steam:
                    if snapshot.platformProgress.steamTotal > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "rosette")
                            Text(snapshot.platformProgress.steamEarned.formatted(.number.locale(L10n.locale)))
                                .monospacedDigit()
                        }
                    }
                case .playStation:
                    if snapshot.platformProgress.trophyDefined > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill")
                            Text(snapshot.platformProgress.trophyEarned.formatted(.number.locale(L10n.locale)))
                                .monospacedDigit()
                        }
                    }
                case .nintendo:
                    EmptyView()
                }
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.76))
        .lineLimit(1)
    }
}

/// A small separator dot inside tray detail lines.
private struct FrostedDot: View {
    var body: some View {
        Circle().fill(.white.opacity(0.45)).frame(width: 2.5, height: 2.5)
    }
}

private struct FortnightTotalPanel: View {
    let playedMinutes: Int
    var isAvailable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .medium))
                Text(L10n.widget("LAST 14 DAYS"))
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.80))
            .frame(height: 21)

            Text(isAvailable ? playedMinutes.hoursMinutesLabel : "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 19, alignment: .leading)
                .padding(.top, 3)

            Text(verbatim: "Steam · Switch")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.65))
                .frame(height: 12, alignment: .leading)
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAvailable ? L10n.widget("Played %1$@ in 14 days", playedMinutes.hoursMinutesLabel) + ", Steam · Switch" : L10n.widget("%1$@, %2$@", L10n.widget("LAST 14 DAYS"), L10n.widget("No play history")))
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
                    SyncStatus(dark: true, updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                }

                HStack(spacing: 16) {
                    PlaytimeRing(snapshot: snapshot)
                        .frame(width: 140, height: 140)
                    // Fixed metrics column: the ring already carries the total,
                    // so each row shows only platform mark + playtime + share,
                    // sized to never truncate.
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(snapshot.platforms) { activity in
                            HStack(spacing: 8) {
                                PlatformMark(platform: activity.platform, size: 19)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.playtimeLabel)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                    Text(activity.isConnected ? L10n.widget("%1$d%%", Int((Double(activity.playedMinutes) / Double(max(snapshot.totalPlayedMinutes, 1)) * 100).rounded())) : L10n.widget("Not connected"))
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(width: 118)
                    Rectangle().fill(WidgetPalette.ink.opacity(0.12)).frame(width: 1)
                    // Live activity panel: Steam presence plus each connected
                    // platform's most recent session — the only "now" data on
                    // an otherwise all-time card.
                    VStack(alignment: .leading, spacing: 7) {
                        if let playingGame = snapshot.steamPlayingGame {
                            HStack(spacing: 6) {
                                Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 7, height: 7)
                                Text(L10n.widget("Playing %1$@", playingGame))
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else if let state = snapshot.steamPersonaState, state > 0 {
                            HStack(spacing: 6) {
                                Circle().fill(WidgetPalette.steam).frame(width: 7, height: 7)
                                Text(L10n.widget("Online on Steam"))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        Text(L10n.widget("Last played"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        ForEach(Array(snapshot.lastPlayedRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 6) {
                                Circle().fill(WidgetPalette.color(for: row.platform)).frame(width: 7, height: 7)
                                Text(row.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 6)
                                Text(RelativeTime.text(for: row.date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if snapshot.lastPlayedRows.isEmpty {
                            Text(L10n.widget("No play history"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 146)

                HStack {
                    Text(L10n.widget("Recently Played"))
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text(L10n.widget("By last played"))
                        .font(.system(size: 9))
                }

                HStack(spacing: 7) {
                    ForEach(0..<6, id: \.self) { index in
                        if index < previewGames.count {
                            SmallCover(game: previewGames[index])
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
        snapshot.recentGames
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

/// The A1 shelf shows cover art without cramped text overlays.
private struct HeroRecentCover: View {
    let game: RecentGame

    var body: some View {
        GeometryReader { geometry in
            GameArtwork(name: game.artworkName, role: .cover, maxPixelSize: 240)
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    PlatformBrandLogo(platform: game.platform, size: 18)
                        .padding(4)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.platform.title)")
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
                    if game.weekMinutes > 0 {
                        Text(game.weekMinutes.hoursMinutesLabel).font(.system(size: 8))
                    }
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
                    HourcadeMark(size: 35)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.widget("Game Life")).font(.system(size: 15, weight: .semibold))
                        Text(L10n.widget("Same Games. A Bigger You."))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                    SyncStatus(updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 13) {
                        MetricLine(icon: "clock", value: snapshot.playtimeLabel, label: L10n.widget("Total Playtime"))
                        MetricLine(icon: "gamecontroller", value: snapshot.hasData ? snapshot.totalGameCount.formatted(.number.locale(L10n.locale)) : "—", label: L10n.widget("Games"))
                        MetricLine(icon: "calendar", value: snapshot.hasData ? snapshot.fortnightPlayedMinutes.hoursLabelRoundedUp : "—", label: L10n.widget("Last 14 Days"))
                        Spacer(minLength: 0)
                        // Account-wide completion rollup — Steam achievements
                        // and PSN trophies stacked vertically so the numbers
                        // never fight for width; hidden until data exists.
                        if snapshot.platformProgress.steamTotal > 0 || snapshot.platformProgress.trophyDefined > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                if snapshot.platformProgress.steamTotal > 0 {
                                    HStack(spacing: 7) {
                                        Image(systemName: "rosette")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.62))
                                        Text(L10n.widget("%1$d / %2$d", snapshot.platformProgress.steamEarned, snapshot.platformProgress.steamTotal))
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Spacer(minLength: 0)
                                        Text(L10n.widget("Achievements"))
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(1)
                                    }
                                }
                                if snapshot.platformProgress.trophyDefined > 0 {
                                    HStack(spacing: 7) {
                                        Image(systemName: "trophy.fill")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.62))
                                        Text(L10n.widget("%1$d / %2$d", snapshot.platformProgress.trophyEarned, snapshot.platformProgress.trophyDefined))
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Spacer(minLength: 0)
                                        Text(L10n.widget("Trophies"))
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(width: 145)

                    ForEach(snapshot.platforms) { activity in
                        PlatformPortrait(activity: activity, total: snapshot.totalPlayedMinutes, artworkName: snapshot.showcaseArtwork[activity.platform] ?? "")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(18)
            .foregroundStyle(.white)
        }
    }
}

/// The Hourcade app icon, used wherever the widgets brand themselves.
struct HourcadeMark: View {
    var size: CGFloat = 15

    var body: some View {
        Image("HourcadeMark")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
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
                GameArtwork(name: artwork, role: .portrait, maxPixelSize: 600)
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

/// The D/E/F extra-large cards: one platform's game wall. Lifetime top games
/// as covers, the platform's total playtime as the headline, and the most
/// played game's artwork as the backdrop.
private struct GalleryAggregateCard: View {
    let snapshot: GameSnapshot
    let platform: GamePlatform

    private var activity: PlatformActivity {
        snapshot.platforms.first { $0.platform == platform } ?? .disconnected(platform)
    }

    private var wallGames: [FeaturedGame] {
        snapshot.galleryWalls[platform] ?? []
    }

    private var backdropArtwork: String {
        wallGames.first?.artworkName ?? snapshot.platformHighlights.first { $0.platform == platform }?.artworkName ?? ""
    }

    private var headlineMinutes: Int? {
        activity.isConnected && activity.hasPlaytime ? activity.playedMinutes : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GameArtwork(name: backdropArtwork, role: .hero, maxPixelSize: 1440)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.35)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.82), WidgetPalette.color(for: platform).opacity(0.45), WidgetPalette.ink.opacity(0.78)], startPoint: .bottomLeading, endPoint: .topTrailing)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PlatformBrandLogo(platform: platform, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(platform.title).font(.system(size: 15, weight: .semibold))
                            Text(L10n.widget("Game wall")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer(minLength: 0)
                        SyncStatus(updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                    }
                    Spacer(minLength: 12)
                    // Bottom-aligned so the dividers sit flush with the label
                    // baselines instead of floating above them.
                    HStack(alignment: .bottom, spacing: 13) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headlineMinutes.map { $0.hoursLabel } ?? "—")
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(L10n.widget("Total Playtime"))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.isConnected ? activity.gameCountLabel : "—").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text(L10n.widget("Games")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                        }
                        // Platform-flavored third metric: Steam shows the account
                        // achievement rollup, PSN shows the trophy rollup.
                        Rectangle().fill(.white.opacity(0.20)).frame(width: 1, height: 37)
                        if platform == .steam, snapshot.platformProgress.steamTotal > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.widget("%1$d / %2$d", snapshot.platformProgress.steamEarned, snapshot.platformProgress.steamTotal))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(L10n.widget("Achievements")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                            }
                        } else if platform == .playStation, snapshot.platformProgress.trophyDefined > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.widget("%1$d / %2$d", snapshot.platformProgress.trophyEarned, snapshot.platformProgress.trophyDefined))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(L10n.widget("Trophies")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        Spacer(minLength: 0)
                        if let topGame = wallGames.first {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(L10n.widget("LAST PLAYED"))
                                    .font(.system(size: 8, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(.white.opacity(0.62))
                                Text(topGame.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(topGame.lifetimeMinutes.hoursLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: geometry.size.width * 0.34)
                        }
                    }
                    Spacer(minLength: 15)
                    HStack(spacing: 7) {
                        ForEach(0..<5, id: \.self) { index in
                            if index < wallGames.count {
                                GalleryCover(game: wallGames[index])
                                    .frame(maxWidth: .infinity)
                            } else {
                                EmptyGameCover()
                            }
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.10))
                            VStack(spacing: 5) {
                                Text(wallGames.count > 5 ? L10n.widget("+%1$d", wallGames.count - 5) : "—")
                                    .font(.system(size: 18, weight: .semibold))
                                Text(L10n.widget(wallGames.count > 5 ? "More" : "No more games")).font(.system(size: 9))
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
    let game: FeaturedGame

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                GameArtwork(name: game.artworkName, role: .cover, maxPixelSize: 400)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(game.lifetimeMinutes.hoursLabel)
                        // Steam carries per-game achievements, PSN carries
                        // trophies; Switch has neither and just shows playtime.
                        if let earned = game.achievementEarned, let total = game.achievementTotal, total > 0 {
                            Image(systemName: "rosette")
                                .font(.system(size: 7, weight: .semibold))
                            Text("\(earned)/\(total)")
                                .monospacedDigit()
                        } else if let earned = game.trophyEarned, let defined = game.trophyDefined, defined > 0 {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 7, weight: .semibold))
                            Text("\(earned)/\(defined)")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.widget("%1$@, %2$@", game.title, game.lifetimeMinutes.hoursLabel))
    }
}

// MARK: - Mini summary (medium family)

/// A compact multi-platform summary composed for the medium widget family:
/// brand header, two headline metrics, and one colored pill per connected
/// platform. Deliberately leaves out the game-value metric and any user
/// identity — the app has no cross-platform account to attach them to.
private struct MiniSummaryCard: View {
    let snapshot: GameSnapshot

    private var connectedPlatforms: [PlatformActivity] {
        snapshot.platforms.filter { $0.isConnected }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    HourcadeMark(size: 17)
                    Text(L10n.widget("Hourcade"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer(minLength: 8)
                    SyncStatus(updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer(minLength: 6)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.hasData ? snapshot.playtimeLabel : "—")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(L10n.widget("Total Playtime"))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.hasData ? snapshot.totalGameCount.formatted(.number.locale(L10n.locale)) : "—")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(L10n.widget("Games"))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .frame(width: width * 0.22, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    ForEach(connectedPlatforms) { activity in
                        MiniPlatformPill(activity: activity)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 30)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}

/// One platform's compact medium widget (M2–M4): the platform logo and sync
/// status on top, total playtime as the headline, then the platform's top
/// games as text rows. The most recently played game's cover sits quietly in
/// the backdrop — lifetime top game when nothing recent exists. The layout
/// fills whatever canvas the system provides; only padding and font sizes
/// are fixed.
private struct MiniPlatformCard: View {
    let snapshot: GameSnapshot
    let platform: GamePlatform

    private var activity: PlatformActivity {
        snapshot.platforms.first { $0.platform == platform } ?? .disconnected(platform)
    }

    private var wallGames: [FeaturedGame] {
        snapshot.galleryWalls[platform] ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GameArtwork(name: snapshot.showcaseArtwork[platform] ?? "", role: .hero, maxPixelSize: 720)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.28)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.86), WidgetPalette.color(for: platform).opacity(0.55), WidgetPalette.ink.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        PlatformBrandLogo(platform: platform, size: 20)
                        Text(platform.title)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 8)
                        SyncStatus(updatedAt: snapshot.hasData ? snapshot.updatedAt : nil)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.isConnected && activity.hasPlaytime ? activity.playedMinutes.hoursLabel : "—")
                                .font(.system(size: 27, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(L10n.widget("Total Playtime"))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(activity.isConnected ? activity.gameCountLabel : "—")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text(L10n.widget("Games"))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(wallGames.prefix(3).enumerated()), id: \.offset) { index, game in
                            HStack(spacing: 7) {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 10)
                                // Long titles end in an ellipsis at full size:
                                // mixed font sizes across the three platform
                                // widgets read as a rendering bug.
                                Text(game.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                                Text(game.lifetimeMinutes.hoursLabel)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        if wallGames.isEmpty {
                            Text(L10n.widget("No games"))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}

private struct MiniPlatformPill: View {
    let activity: PlatformActivity

    var body: some View {
        HStack(spacing: 6) {
            PlatformBrandLogo(platform: activity.platform, size: 20)
            Text(activity.playtimeLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WidgetPalette.color(for: activity.platform).opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.widget("%1$@, %2$@", activity.platform.title, activity.playtimeLabel))
    }
}
