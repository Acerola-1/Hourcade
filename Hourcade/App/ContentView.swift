import SwiftUI

/// The sidebar page hosting the widget gallery, titled 桌面组件预览.
struct WidgetPreviewPage: View {
    var body: some View {
        PageShell(title: L10n.tr("桌面组件预览"), eyebrow: L10n.tr("设计"), subtitle: L10n.tr("按组件尺寸分组；预览使用真实同步数据。添加或更换组件请在桌面右键菜单中进行。")) {
            WidgetStudioView()
        }
    }
}

/// The widget gallery. Reads the same merged snapshot file as the desktop
/// widgets, so previews show exactly what the system will render. Designs are
/// grouped by WidgetKit family: the desktop-scale extra-large cards first,
/// then the medium minis.
struct WidgetStudioView: View {
    @Environment(\.locale) private var locale
    @State private var selectedStyle: AggregateStyle = .heroNoValue
    @State private var featuredGameID = ""
    @State private var liveSnapshot = WidgetSnapshotStore.load()?.gameSnapshot ?? .empty

    private var snapshot: GameSnapshot { liveSnapshot }

    private var featuredGame: FeaturedGame {
        snapshot.heroCandidates.first { $0.id == featuredGameID } ?? snapshot.heroCandidates[0]
    }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 14) {
            styleSelector
            preview
        }
        .onReceive(NotificationCenter.default.publisher(for: SteamWidgetStore.didChange)) { _ in
            liveSnapshot = WidgetSnapshotStore.load()?.gameSnapshot ?? .empty
        }
        .task(id: selectedStyle == .heroNoValue) {
            guard selectedStyle == .heroNoValue else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                let alternatives = snapshot.heroCandidates.filter { $0.id != featuredGameID }
                guard let next = alternatives.randomElement() else { continue }
                withAnimation(.easeInOut(duration: 1.3)) {
                    featuredGameID = next.id
                }
            }
        }
    }

    // MARK: Style selection, grouped by widget family

    private var styleSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WidgetFamilyGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Rectangle().fill(.quaternary).frame(height: 1)
                        Text(L10n.format("%1$d 个方案", group.styles.count))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 8) {
                        ForEach(group.styles) { style in
                            styleCard(style)
                        }
                    }
                }
            }
        }
    }

    private func styleCard(_ style: AggregateStyle) -> some View {
        Button {
            selectedStyle = style
        } label: {
            HStack(spacing: 8) {
                Text(style.letter)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .frame(width: 23, height: 23)
                    .background(Color.primary.opacity(selectedStyle == style ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 7))
                Text(style.title)
                    .font(.system(size: 12, weight: selectedStyle == style ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary.opacity(selectedStyle == style ? 1 : 0.65))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(selectedStyle == style ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(selectedStyle == style ? 0.22 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedStyle == style ? .isSelected : [])
    }

    // MARK: Live preview canvas

    private var isMedium: Bool {
        switch selectedStyle {
        case .mini, .steamMini, .nintendoMini, .playStationMini: true
        default: false
        }
    }

    private var preview: some View {
        let previewSize = CGSize(width: isMedium ? 329 : 704, height: isMedium ? 155 : 344)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("桌面预览"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(isMedium ? "329 × 155 pt · 中号" : "704 × 344 pt · 超大号")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Group {
                AggregateCard(style: selectedStyle, snapshot: snapshot, featuredGame: featuredGame,
                              rendersHeroBackdropInContent: selectedStyle != .heroNoValue)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .background {
                        if selectedStyle == .heroNoValue {
                            HeroArtworkBackdrop(featuredGame: featuredGame, size: previewSize)
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: isMedium ? 18 : 24))
            .overlay(RoundedRectangle(cornerRadius: isMedium ? 18 : 24).strokeBorder(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
            .frame(maxWidth: .infinity)
            .frame(height: isMedium ? 220 : 376)
        }
    }

}

/// The studio lists widgets grouped by WidgetKit family: the desktop-scale
/// extra-large cards first, then the medium minis (all-platform + per-platform).
private enum WidgetFamilyGroup: CaseIterable, Identifiable {
    case extraLarge
    case medium

    var id: Self { self }

    var title: String {
        switch self {
        case .extraLarge: L10n.tr("超大号")
        case .medium: L10n.tr("中号")
        }
    }

    var styles: [AggregateStyle] {
        switch self {
        case .extraLarge: [.heroNoValue, .atlas, .platforms, .gallery, .galleryNintendo, .galleryPlayStation]
        case .medium: [.mini, .steamMini, .nintendoMini, .playStationMini]
        }
    }
}
