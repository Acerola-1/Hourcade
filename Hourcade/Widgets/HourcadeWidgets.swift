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
        completion(AggregateEntry(date: .now, snapshot: data, featuredGame: data.heroCandidates[0]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AggregateEntry>) -> Void) {
        let data = snapshot
        let start = Date.now
        let key = "featured.\(style.rawValue)"
        let previous = L10n.defaults.string(forKey: key)
        let candidates = data.heroCandidates
        let alternatives = candidates.filter { $0.id != previous }
        let game = (alternatives.isEmpty ? candidates : alternatives).randomElement() ?? data.allTimeTopGame
        L10n.defaults.set(game.id, forKey: key)
        let entry = AggregateEntry(date: start, snapshot: data, featuredGame: game)
        completion(Timeline(entries: [entry], policy: .after(start.addingTimeInterval(1800))))
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
            AggregateCard(style: style, snapshot: entry.snapshot, featuredGame: entry.featuredGame)
                .containerBackground(for: .widget) {
                    // Match the platform minis' own gradient so any rounding
                    // seams blend into the card instead of showing as a dark rim.
                    LinearGradient(colors: [WidgetPalette.ink, WidgetPalette.ink],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
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
