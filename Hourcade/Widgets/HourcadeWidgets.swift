import SwiftUI
import WidgetKit

struct AggregateEntry: TimelineEntry {
    let date: Date
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame
}

struct AggregateProvider: TimelineProvider {
    let style: AggregateStyle
    let isDemo: Bool

    private var snapshot: GameSnapshot {
        isDemo ? .demo : WidgetSnapshotStore.load()?.gameSnapshot ?? .empty
    }

    func placeholder(in context: Context) -> AggregateEntry {
        let data: GameSnapshot = isDemo ? .demo : .empty
        return AggregateEntry(date: .now, snapshot: data, featuredGame: data.heroCandidates[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (AggregateEntry) -> Void) {
        let data = snapshot
        completion(AggregateEntry(date: .now, snapshot: data, featuredGame: data.heroCandidates[0]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AggregateEntry>) -> Void) {
        let data = snapshot
        let start = Date.now
        let key = "featured.\(isDemo).\(style.rawValue)"
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
    let isDemo: Bool

    init() { self.init(style: .heroNoValue) }

    init(style: AggregateStyle, isDemo: Bool = false) {
        self.style = style
        self.isDemo = isDemo
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: isDemo ? style.widgetKind : style.liveWidgetKind, provider: AggregateProvider(style: style, isDemo: isDemo)) { entry in
            AggregateCard(style: style, snapshot: entry.snapshot, featuredGame: entry.featuredGame)
                .containerBackground(for: .widget) { WidgetPalette.ink }
        }
        .configurationDisplayName(Text(verbatim: "\(isDemo ? L10n.widget("DEMO") : L10n.tr("主方案")) · \(style.letter) \(style.title)"))
        .description(Text(verbatim: isDemo ? L10n.widget("Demo data") : L10n.widget("Your gaming life, at a glance.")))
        .supportedFamilies([.systemExtraLarge])
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
        AggregateWidget(style: .heroNoValue, isDemo: true)
        AggregateWidget(style: .atlas, isDemo: true)
        AggregateWidget(style: .platforms, isDemo: true)
        AggregateWidget(style: .gallery, isDemo: true)
    }
}
