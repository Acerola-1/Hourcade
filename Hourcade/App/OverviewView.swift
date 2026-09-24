import SwiftUI

struct OverviewView: View {
    let steam: SteamSnapshot?
    let nintendo: NintendoSnapshot?
    let playStation: PSNSnapshot?
    let steamConfigured: Bool
    let isRefreshing: Bool
    let refreshError: String?
    let selectPlatform: (GamePlatform) -> Void
    let refreshSteam: () -> Void

    private var connectedCount: Int {
        [steam != nil, nintendo != nil, playStation != nil].filter { $0 }.count
    }
    private var totalMinutes: Int {
        (steam?.library.totalMinutes ?? 0) + (nintendo?.totalMinutes ?? 0) + (playStation?.library.totalMinutes ?? 0)
    }
    private var gameEntries: Int {
        (steam?.library.games.count ?? 0) + (nintendo?.games.count ?? 0) + (playStation?.library.games.count ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if connectedCount == 0 {
                    ContentUnavailableView {
                        Label(
                            steamConfigured ? (isRefreshing ? "正在同步 Steam" : "Steam 尚未完成同步") : "你的游戏生活，从连接平台开始",
                            systemImage: steamConfigured ? "arrow.clockwise" : "gamecontroller"
                        )
                    } description: {
                        Text(refreshError ?? (steamConfigured ? "数据就绪后会自动显示在这里。也可以进入 Steam 页面重试。" : "选择左侧平台，完成第一次连接后，这里会显示真实游玩数据。"))
                    }
                } else {
                    summary
                    platforms
                    if let recent = steam?.library.recent, !recent.isEmpty {
                        recentGames(recent)
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
        .navigationTitle("总览")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("HOURCADE · YOUR GAME LIFE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("你的游戏时间")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(connectedCount == 0 ? "连接平台后，游玩记录会汇集在这里。" : "来自 \(connectedCount) 个已连接平台")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if steam != nil {
                Button {
                    refreshSteam()
                } label: {
                    Label(isRefreshing ? "同步中" : "同步 Steam", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(totalMinutes / 60)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("小时")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("已连接平台的累计游玩时长")
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                smallMetric("\(gameEntries)", "游戏记录条目")
                Divider().frame(height: 42).padding(.horizontal, 28)
                smallMetric("\(connectedCount) / 3", "已连接平台")
                if let steam {
                    Divider().frame(height: 42).padding(.horizontal, 28)
                    smallMetric("\(steam.library.fortnightMinutes / 60)h \(steam.library.fortnightMinutes % 60)m", "Steam 近两周")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.24, blue: 0.34), Color(red: 0.08, green: 0.13, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-18))
                .padding(.trailing, 20)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
    }

    private func smallMetric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.67))
        }
    }

    private var platforms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("平台").font(.title3.bold())
            HStack(spacing: 12) {
                platformCard(.steam, count: steam?.library.games.count, minutes: steam?.library.totalMinutes, date: steam?.syncedAt)
                platformCard(.nintendo, count: nintendo?.games.count, minutes: nintendo?.totalMinutes, date: nintendo?.syncedAt)
                platformCard(.playStation, count: playStation?.library.games.count, minutes: playStation?.library.totalMinutes, date: playStation?.syncedAt)
            }
            if let refreshError {
                Label("Steam 刷新失败：\(refreshError)。上方保留上次同步结果。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func platformCard(_ platform: GamePlatform, count: Int?, minutes: Int?, date: Date?) -> some View {
        Button {
            selectPlatform(platform)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    AccountPlatformMark(platform: platform, size: 36)
                    Text(platform.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                if let count, let minutes, let date {
                    Text("\(minutes / 60)h")
                        .font(.title2.bold().monospacedDigit())
                    Text("\(count) 款记录 · 同步于 \(DisplayFormat.syncDate(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("尚未连接")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("点击设置账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(18)
            .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func recentGames(_ games: [SteamGame]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steam 近期游玩").font(.title3.bold())
                Spacer()
                Text("过去两周").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(games.prefix(4)) { game in
                HStack(spacing: 14) {
                    AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.id)/capsule_184x69.jpg")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 92, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                    Text(game.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(game.fortnightMinutes / 60)h \(game.fortnightMinutes % 60)m")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(22)
        .background(.quaternary.opacity(0.40), in: RoundedRectangle(cornerRadius: 18))
    }
}
