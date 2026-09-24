import SwiftUI

private enum PreviewMode: String, CaseIterable, Identifiable {
    case reference = "主方案"
    case exploration = "早期探索稿"

    var id: Self { self }
}

struct WidgetStudioView: View {
    @State private var selectedStyle: AggregateStyle = .hero
    @State private var previewMode: PreviewMode = .reference
    @State private var featuredGameID = GameSnapshot.demo.heroCandidates[0].id

    private let snapshot = GameSnapshot.demo

    private var featuredGame: FeaturedGame {
        snapshot.heroCandidates.first { $0.id == featuredGameID } ?? snapshot.heroCandidates[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                brand
                modeSelector
                introduction
                styleSelector
                preview
                footnote
            }
            .frame(maxWidth: 830)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .background {
            ZStack {
                WidgetPalette.ink
                Image("HeroAetherfall")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.20)
                    .blur(radius: 42)
                    .accessibilityHidden(true)
                LinearGradient(colors: [WidgetPalette.ink.opacity(0.68), WidgetPalette.ink.opacity(0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipped()
        }
        .frame(minWidth: 950, minHeight: 660)
        .preferredColorScheme(.dark)
        .task(id: previewMode == .reference && (selectedStyle == .hero || selectedStyle == .heroNoValue)) {
            guard previewMode == .reference && (selectedStyle == .hero || selectedStyle == .heroNoValue) else { return }
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

    private var modeSelector: some View {
        HStack {
            Text("设计版本")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Picker("设计版本", selection: $previewMode) {
                ForEach(PreviewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .labelsHidden()
            .onChange(of: previewMode) { _, mode in
                if mode == .exploration && selectedStyle == .heroNoValue {
                    selectedStyle = .hero
                }
            }
            Spacer()
            Text(previewMode == .reference ? "A / A2 已按新需求调整 · B–D 参考总览图" : "保留此前的四张视觉实验")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(WidgetPalette.steam.gradient, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("HOURCADE")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(1.1)
                Text("Widget Studio")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.60))
            }
            Spacer()
            Text("DEMO · SAMPLE DATA")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.70))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.10), in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var introduction: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(previewMode == .reference ? "主方案" : "早期探索稿") · 方案 \(selectedStyle.letter)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.60))
                Text(selectedStyle.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Nintendo、PlayStation 与 Steam，一张卡片看完你的游戏生活。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
            }
            Spacer()
            Text("超大号 · 聚合组件")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private var styleSelector: some View {
        HStack(spacing: 8) {
            ForEach(previewMode == .reference ? AggregateStyle.allCases : [.hero, .atlas, .platforms, .gallery]) { style in
                Button {
                    selectedStyle = style
                } label: {
                    HStack(spacing: 8) {
                        Text(style.letter)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(width: 23, height: 23)
                            .background(Color.white.opacity(selectedStyle == style ? 0.20 : 0.08), in: RoundedRectangle(cornerRadius: 7))
                        Text(style.title)
                            .font(.system(size: 12, weight: selectedStyle == style ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white.opacity(selectedStyle == style ? 1 : 0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(selectedStyle == style ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(selectedStyle == style ? 0.24 : 0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedStyle == style ? .isSelected : [])
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("桌面预览")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("720 × 360 pt")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)

            Group {
                if previewMode == .reference {
                    AggregateCard(style: selectedStyle, snapshot: snapshot, featuredGame: featuredGame)
                } else {
                    ExplorationCard(style: selectedStyle, snapshot: snapshot)
                }
            }
                .frame(width: 720, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.20)))
                .shadow(color: .black.opacity(0.42), radius: 22, y: 14)
                .frame(maxWidth: .infinity)
                .frame(height: 392)
        }
        .padding(20)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.11)))
    }

    private var footnote: some View {
        HStack(spacing: 9) {
            Circle().fill(WidgetPalette.nintendo).frame(width: 6, height: 6)
            Text(selectedStyle == .heroNoValue
                 ? "演示数据：A2 只展示时长和游戏数，不显示金额；背景随机切换近 14 天游戏。"
                 : "演示数据：A 显示累计时长、游戏库及估算标价；背景随机切换近 14 天游戏。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.63))
            Spacer()
            Text("SwiftUI · WidgetKit")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
