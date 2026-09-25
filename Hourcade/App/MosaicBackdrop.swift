import SwiftUI
import AppKit
import CoreImage

/// Playtime-weighted mosaic of the top games' covers — the "gaming collage"
/// idea: every connected platform gets tiles, and longer play means more area.
///
/// Currently unwired: the page background built on this was removed by user
/// decision after visual review. Kept compiled for the desktop-widget tile
/// idea; the reusable entry points are `MosaicSource` (tile selection) and
/// `MosaicCanvas` (layout + offscreen rendering). See HANDOFF.md.

/// One weighted tile of the mosaic. Weight is the game's playtime in minutes;
/// relative weights decide how much area each cover claims.
struct MosaicTile: Sendable {
    let id: String
    let artwork: URL?
    // Separate namespace from the widget pipeline so overwriting never
    // changes what the widgets see.
    let cachedName: String?
    let weight: Double
}

enum MosaicSource {
    private static func steamTiles(_ snapshot: SteamSnapshot?, count: Int) -> [MosaicTile] {
        guard let snapshot else { return [] }
        return snapshot.library.games
            .sorted { $0.lifetimeMinutes > $1.lifetimeMinutes }
            .prefix(count)
            .map {
                MosaicTile(
                    id: "steam-\($0.id)",
                    artwork: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\($0.id)/library_600x900.jpg"),
                    cachedName: "mosaic-steam-\($0.id)",
                    weight: Double(max($0.lifetimeMinutes, 30))
                )
            }
    }

    private static func nintendoTiles(_ snapshot: NintendoSnapshot?, count: Int) -> [MosaicTile] {
        guard let snapshot else { return [] }
        return snapshot.games
            .sorted { $0.totalPlayTime > $1.totalPlayTime }
            .prefix(count)
            .map {
                MosaicTile(
                    id: "nintendo-\($0.id)",
                    artwork: URL(string: $0.imageUri),
                    cachedName: "mosaic-nintendo-\($0.id)",
                    weight: Double(max($0.totalPlayTime, 30))
                )
            }
    }

    private static func playStationTiles(_ snapshot: PSNSnapshot?, count: Int) -> [MosaicTile] {
        guard let snapshot else { return [] }
        return snapshot.library.games
            .sorted { $0.lifetimeMinutes > $1.lifetimeMinutes }
            .prefix(count)
            .map {
                MosaicTile(
                    id: "psn-\($0.id)",
                    artwork: $0.imageURL,
                    cachedName: "mosaic-psn-\($0.id)",
                    weight: Double(max($0.lifetimeMinutes, 30))
                )
            }
    }

    /// Top games of every connected platform, `perPlatform` each, so no single
    /// library monopolizes the wall.
    static func allPlatforms(
        steam: SteamSnapshot?,
        nintendo: NintendoSnapshot?,
        playStation: PSNSnapshot?,
        perPlatform: Int = 8
    ) -> [MosaicTile] {
        steamTiles(steam, count: perPlatform)
            + nintendoTiles(nintendo, count: perPlatform)
            + playStationTiles(playStation, count: perPlatform)
    }

    static func steam(_ snapshot: SteamSnapshot?, count: Int = 12) -> [MosaicTile] {
        steamTiles(snapshot, count: count)
    }

    static func nintendo(_ snapshot: NintendoSnapshot?, count: Int = 12) -> [MosaicTile] {
        nintendoTiles(snapshot, count: count)
    }

    static func playStation(_ snapshot: PSNSnapshot?, count: Int = 12) -> [MosaicTile] {
        playStationTiles(snapshot, count: count)
    }
}

/// Loads tile artwork: cached file first, then a one-time download that is
/// kept on disk for the next composition.
enum MosaicArtworkLoader {
    static func load(_ tiles: [MosaicTile]) async -> [CGImage?] {
        await withTaskGroup(of: (Int, CGImage?).self) { group in
            var results = [CGImage?](repeating: nil, count: tiles.count)
            for (index, tile) in tiles.enumerated() {
                group.addTask { (index, await loadTile(tile)) }
            }
            for await (index, image) in group {
                results[index] = image
            }
            return results
        }
    }

    private static func loadTile(_ tile: MosaicTile) async -> CGImage? {
        if let name = tile.cachedName,
           let url = SteamWidgetStore.artworkURL(named: name),
           let data = try? Data(contentsOf: url) {
            return Self.decode(data)
        }
        guard let remote = tile.artwork,
              let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let image = Self.decode(data) else { return nil }
        if let name = tile.cachedName, let url = SteamWidgetStore.artworkURL(named: name) {
            try? data.write(to: url, options: .atomic)
        }
        return image
    }

    private static func decode(_ data: Data) -> CGImage? {
        NSBitmapImageRep(data: data)?.cgImage
    }
}

@MainActor
enum MosaicComposer {
    private static var cache: [String: CGImage] = [:]

    static func image(for tiles: [MosaicTile]) async -> CGImage? {
        guard !tiles.isEmpty else { return nil }
        let key = tiles.map(\.id).joined(separator: ",")
        if let cached = cache[key] { return cached }
        let loaded = await MosaicArtworkLoader.load(tiles)
        let composed = await Task.detached(priority: .utility) {
            MosaicCanvas.compose(tiles: tiles, images: loaded, size: CGSize(width: 1080, height: 810))
        }.value
        guard let composed else { return nil }
        cache[key] = composed
        return composed
    }
}

/// Pure drawing code, safe to run off the main actor. CGImage in / out keeps
/// everything Sendable across the boundary.
enum MosaicCanvas {
    static func compose(tiles: [MosaicTile], images: [CGImage?], size: CGSize) -> CGImage? {
        let present = tiles.indices.filter { images[$0] != nil }
        guard !present.isEmpty else { return nil }

        // sqrt softens the gap between a 2,000-hour game and a 3-hour one;
        // clamps keep every present tile visible and no single one dominant.
        let raw = present.map { pow(max(tiles[$0].weight, 30), 0.55) }
        let rawTotal = raw.reduce(0, +)
        var shares = raw.map { min(max($0 / rawTotal, 0.02), 0.20) }
        shares = normalize(shares)
        let weights = shares

        let bounds = CGRect(origin: .zero, size: size)
        let rects = mosaicRects(weights: weights, in: bounds)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(deviceWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        for (slot, tileIndex) in present.enumerated() {
            // The layout stacks rows bottom-up in CG coordinates; flip so the
            // biggest tiles (sorted first) read from the top.
            var rect = rects[slot].insetBy(dx: 3, dy: 3)
            rect = NSRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
            drawCover(images[tileIndex]!, in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let rawImage = rep.cgImage else { return nil }
        return blurred(rawImage, radius: 6)
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values }
        return values.map { $0 / total }
    }

    /// Row-based treemap: keep appending tiles to the current row while the
    /// row's worst aspect ratio improves, then commit and move down.
    static func mosaicRects(weights: [Double], in bounds: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, !weights.isEmpty else { return .init(repeating: .zero, count: weights.count) }
        var rects = [CGRect](repeating: .zero, count: weights.count)
        var cursor = bounds
        var remaining = total
        var i = 0

        func worstAspect(rowCount: Int, rowWeight: Double) -> Double {
            let height = cursor.height * rowWeight / remaining
            var worst = 0.0
            var x = cursor.minX
            for offset in 0..<rowCount {
                let index = i + offset
                let width = cursor.width * weights[index] / rowWeight
                worst = max(worst, max(width / height, height / width))
                x += width
            }
            return worst
        }

        while i < weights.count {
            var rowWeight = weights[i]
            var rowCount = 1
            var best = worstAspect(rowCount: rowCount, rowWeight: rowWeight)
            while i + rowCount < weights.count {
                let trialWeight = rowWeight + weights[i + rowCount]
                let trial = worstAspect(rowCount: rowCount + 1, rowWeight: trialWeight)
                if trial < best {
                    rowWeight = trialWeight
                    rowCount += 1
                    best = trial
                } else {
                    break
                }
            }
            let height = cursor.height * rowWeight / remaining
            var x = cursor.minX
            for offset in 0..<rowCount {
                let index = i + offset
                let width = cursor.width * weights[index] / rowWeight
                rects[index] = CGRect(x: x, y: cursor.minY, width: width, height: height)
                x += width
            }
            cursor = CGRect(x: cursor.minX, y: cursor.minY + height, width: cursor.width, height: cursor.height - height)
            remaining -= rowWeight
            i += rowCount
        }
        return rects
    }

    /// Aspect-fill crop of the cover into the tile. Center crop, so mapping
    /// the full image centered on the tile center puts the crop exactly in
    /// place regardless of each coordinate system's y direction.
    private static func drawCover(_ cgImage: CGImage, in rect: NSRect) {
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let sourceAspect = sourceWidth / sourceHeight
        let targetAspect = rect.width / rect.height
        if sourceAspect > targetAspect {
            let scale = rect.height / sourceHeight
            let fullWidth = sourceWidth * scale
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            context.clip(to: rect)
            context.draw(cgImage, in: CGRect(x: rect.midX - fullWidth / 2, y: rect.minY, width: fullWidth, height: rect.height))
            context.restoreGState()
        } else {
            let scale = rect.width / sourceWidth
            let fullHeight = sourceHeight * scale
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            context.clip(to: rect)
            context.draw(cgImage, in: CGRect(x: rect.minX, y: rect.midY - fullHeight / 2, width: rect.width, height: fullHeight))
            context.restoreGState()
        }
    }

    private static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
        let ci = CIImage(cgImage: image).clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return image }
        let context = CIContext(options: [:])
        return context.createCGImage(output, from: CIImage(cgImage: image).extent)
    }
}

/// Blurred mosaic pinned behind a page; falls back to the plain gradient when
/// nothing is connected or no artwork could be loaded.
struct MosaicBackdropView: View {
    let tiles: [MosaicTile]
    @Environment(\.colorScheme) private var scheme
    @State private var image: CGImage?

    private var signature: String {
        tiles.map(\.id).joined(separator: ",")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.10, green: 0.13, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.11)]
                    : [Color(red: 0.86, green: 0.89, blue: 0.93), Color(red: 0.78, green: 0.81, blue: 0.87)],
                startPoint: .top, endPoint: .bottom
            )
            if let image {
                GeometryReader { geo in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .overlay(scrim)
                .transition(.opacity)
            }
        }
        .task(id: signature) {
            let composed = await MosaicComposer.image(for: tiles)
            withAnimation(.easeIn(duration: 0.35)) {
                image = composed
            }
        }
    }

    private var scrim: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black.opacity(0.52), Color.black.opacity(0.74)]
                : [Color.white.opacity(0.52), Color.white.opacity(0.72)],
            startPoint: .top, endPoint: .bottom
        )
    }
}
