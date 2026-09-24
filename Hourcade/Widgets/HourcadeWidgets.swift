import SwiftUI
import WidgetKit

struct AggregateEntry: TimelineEntry {
    let date: Date
    let snapshot: GameSnapshot
    let featuredGame: FeaturedGame
}

struct DemoProvider: TimelineProvider {
    let style: AggregateStyle

    func placeholder(in context: Context) -> AggregateEntry {
        AggregateEntry(date: .now, snapshot: .demo, featuredGame: GameSnapshot.demo.heroCandidates[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (AggregateEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AggregateEntry>) -> Void) {
        guard style == .hero || style == .heroNoValue else {
            completion(Timeline(entries: [placeholder(in: context)], policy: .never))
            return
        }

        let snapshot = GameSnapshot.demo
        let candidates = snapshot.heroCandidates
        let start = Date.now
        var previousID: String?
        let entries: [AggregateEntry] = (0..<48).map { offset in
            let alternatives = candidates.filter { $0.id != previousID }
            let game = (alternatives.isEmpty ? candidates : alternatives).randomElement() ?? snapshot.allTimeTopGame
            previousID = game.id
            return AggregateEntry(
                date: start.addingTimeInterval(TimeInterval(offset * 30 * 60)),
                snapshot: snapshot,
                featuredGame: game
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct AggregateWidget: Widget {
    let style: AggregateStyle

    init() { style = .hero }
    init(style: AggregateStyle) { self.style = style }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: style.widgetKind, provider: DemoProvider(style: style)) { entry in
            AggregateCard(style: style, snapshot: entry.snapshot, featuredGame: entry.featuredGame)
                .containerBackground(for: .widget) { WidgetPalette.ink }
        }
        .configurationDisplayName("聚合 · \(style.title)")
        .description("Steam、Nintendo、PlayStation 游戏生活的演示组件。")
        .supportedFamilies([.systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@main
struct HourcadeWidgets: WidgetBundle {
    var body: some Widget {
        AggregateWidget(style: .hero)
        AggregateWidget(style: .heroNoValue)
        AggregateWidget(style: .atlas)
        AggregateWidget(style: .platforms)
        AggregateWidget(style: .gallery)
    }
}
