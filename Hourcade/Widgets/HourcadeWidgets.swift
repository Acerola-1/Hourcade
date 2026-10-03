import SwiftUI
import WidgetKit

struct AggregateEntry: TimelineEntry {
    let date: Date
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame
}

struct AggregateProvider: TimelineProvider {
    let style: AggregateStyle

    private var snapshot: GameSnapshot {
        WidgetSnapshotStore.load()?.gameSnapshot ?? .empty
    }

    func placeholder(in context: Context) -> AggregateEntry {
        AggregateEntry(date: .now, snapshot: .empty, featuredGame: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (AggregateEntry) -> Void) {
        let data = snapshot
        let now = Date.now
        let candidates = data.heroCandidates
        let slot = Int(now.timeIntervalSince1970 / Self.entryStep)
        completion(AggregateEntry(date: now, snapshot: data,
                                  featuredGame: candidates[slot % candidates.count]))
    }

    /// How long one timeline covers before WidgetKit asks for the next batch.
    private static let batchInterval: TimeInterval = 30 * 60
    /// Apple's recommended minimum spacing between timeline entries is about
    /// five minutes; the system still decides when they appear on the desktop.
    private static let entryStep: TimeInterval = 5 * 60

    func getTimeline(in context: Context, completion: @escaping (Timeline<AggregateEntry>) -> Void) {
        let data = snapshot
        let start = Date.now
        let candidates = data.heroCandidates

        // Only A1 renders the hero game. A pool of one has nothing to rotate.
        guard style == .heroNoValue, candidates.count > 1 else {
            let entry = AggregateEntry(date: start, snapshot: data, featuredGame: candidates[0])
            completion(Timeline(entries: [entry], policy: .after(start.addingTimeInterval(Self.batchInterval))))
            return
        }

        // Use absolute five-minute slots. An app-triggered reload during a
        // batch keeps the currently scheduled game instead of treating a
        // future entry as if it had already appeared on screen.
        let firstSlot = Int(start.timeIntervalSince1970 / Self.entryStep)
        let nextBoundary = Date(timeIntervalSince1970: Double(firstSlot + 1) * Self.entryStep)
        let entryCount = Int(Self.batchInterval / Self.entryStep)
        let entries = (0..<entryCount).map { index in
            AggregateEntry(date: index == 0 ? start : nextBoundary.addingTimeInterval(Self.entryStep * Double(index - 1)),
                           snapshot: data,
                           featuredGame: candidates[(firstSlot + index) % candidates.count])
        }
        let reloadAt = nextBoundary.addingTimeInterval(Self.entryStep * Double(entryCount - 1))
        completion(Timeline(entries: entries, policy: .after(reloadAt)))
    }
}

struct AggregateWidget: Widget {
    let style: AggregateStyle

    init() { self.init(style: .heroNoValue) }

    init(style: AggregateStyle) {
        self.style = style
    }

    // The mini family composes for the medium size; the desktop cards are extra-large.
    private var supportedFamilies: [WidgetFamily] {
        switch style {
        case .mini, .steamMini, .nintendoMini, .playStationMini: [.systemMedium]
        default: [.systemExtraLarge]
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: style.liveWidgetKind, provider: AggregateProvider(style: style)) { entry in
            AggregateCard(style: style, snapshot: entry.snapshot, featuredGame: entry.featuredGame,
                          rendersHeroBackdropInContent: style != .heroNoValue)
                .containerBackground(for: .widget) {
                    if style == .heroNoValue {
                        GeometryReader { geometry in
                            HeroArtworkBackdrop(featuredGame: entry.featuredGame, size: geometry.size)
                        }
                    } else {
                        LinearGradient(colors: [WidgetPalette.ink, WidgetPalette.ink],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
        }
        .configurationDisplayName(Text(verbatim: "\(style.letter) \(style.title)"))
        .description(Text(verbatim: L10n.widget("Your gaming life, at a glance.")))
        .supportedFamilies(supportedFamilies)
        .contentMarginsDisabled()
    }
}

@main
struct HourcadeWidgets: WidgetBundle {
    var body: some Widget {
        AggregateWidget(style: .heroNoValue)
        AggregateWidget(style: .atlas)
        AggregateWidget(style: .platforms)
        AggregateWidget(style: .gallery)
        AggregateWidget(style: .galleryNintendo)
        AggregateWidget(style: .galleryPlayStation)
        AggregateWidget(style: .mini)
        AggregateWidget(style: .steamMini)
        AggregateWidget(style: .nintendoMini)
        AggregateWidget(style: .playStationMini)
    }
}
