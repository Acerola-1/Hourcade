import SwiftUI
import Security
import WidgetKit

private enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, steam, nintendo, playStation, general, widgetPreview
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: L10n.tr("总览")
        case .steam: "Steam"
        case .nintendo: "Nintendo Switch"
        case .playStation: "PlayStation"
        case .general: L10n.tr("常规设置")
        case .widgetPreview: L10n.tr("桌面组件预览")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gamecontroller.circle"
        case .steam: "gamecontroller.fill"
        case .nintendo: "switch.2"
        case .playStation: "playstation.logo"
        case .general: "gearshape"
        case .widgetPreview: "square.grid.2x2"
        }
    }
}

/// Sidebar rows all share one geometry — a 27×27 mark column followed by the
/// title — so platform logos and plain SF symbols line up on the same edges.
private struct SidebarMark: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 27, height: 27)
    }
}

struct AccountPlatformMark: View {
    let platform: GamePlatform
    var size: CGFloat = 34

    private var asset: String {
        switch platform {
        case .steam: "SteamLogo"
        case .nintendo: "NintendoSwitchLogo"
        case .playStation: "PlayStationLogo"
        }
    }

    private var color: Color {
        WidgetPalette.color(for: platform)
    }

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.57, height: size * 0.57)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

/// The main window: navigation chrome only. All data and sync logic live in
/// `SyncCoordinator`, which outlives this window (closing it keeps the app
/// running in the menu bar).
struct ContentView: View {
    @Environment(\.locale) private var locale
    @State private var selection: DashboardPage? = .overview
    private let coordinator = SyncCoordinator.shared

    var body: some View {
        let _ = locale
        @Bindable var coordinator = coordinator
        NavigationSplitView {
            List(selection: $selection) {
                sidebarRow(.overview)
                sidebarRow(.general)
                sidebarRow(.widgetPreview)
                Section(L10n.tr("平台账号")) {
                    ForEach([DashboardPage.steam, .nintendo, .playStation]) { page in
                        sidebarRow(page)
                    }
                }
            }
            .navigationTitle("Hourcade")
            .navigationSplitViewColumnWidth(min: 210, ideal: 238)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(
                    steam: coordinator.steamSnapshot,
                    nintendo: coordinator.nintendoSnapshot,
                    playStation: coordinator.psnSnapshot,
                    steamConfigured: KeychainSecret.read("steam.apiKey") != nil,
                    isRefreshing: coordinator.steamSyncing,
                    refreshError: coordinator.steamError?.text,
                    selectPlatform: { platform in
                        switch platform {
                        case .steam: selection = .steam
                        case .nintendo: selection = .nintendo
                        case .playStation: selection = .playStation
                        }
                    },
                    syncAll: { Task { await SyncCoordinator.shared.syncAll() } }
                )
            case .steam:
                SteamSettingsView(
                    snapshot: coordinator.steamSnapshot,
                    isRefreshing: coordinator.steamSyncing,
                    syncError: coordinator.steamError?.text,
                    onSync: { await SyncCoordinator.shared.syncSteam($0, $1) }
                )
            case .nintendo:
                NintendoSettingsView(snapshot: coordinator.nintendoSnapshot) { newSnapshot in
                    try LocalSnapshotStore.save(newSnapshot, as: "nintendo")
                    coordinator.nintendoSnapshot = newSnapshot
                    try await SyncCoordinator.shared.saveWidgetSnapshots()
                    NotificationCenter.default.post(name: .pricesDidChange, object: nil)
                }
            case .playStation:
                PSNSettingsView(snapshot: coordinator.psnSnapshot) { library in
                    let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "psn")
                    coordinator.psnSnapshot = newSnapshot
                    try await SyncCoordinator.shared.saveWidgetSnapshots()
                    NotificationCenter.default.post(name: .pricesDidChange, object: nil)
                }
            case .general:
                GeneralSettingsView()
            case .widgetPreview:
                WidgetPreviewPage()
            }
        }
        .frame(minWidth: 820, minHeight: 610)
        .task {
            // Runs once per app process, not once per window: the window can
            // be closed and reopened freely while the app stays resident.
            BackgroundSyncScheduler.runLaunchSequenceOnce()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ page: DashboardPage) -> some View {
        HStack(spacing: 10) {
            if let platform = page.platform {
                AccountPlatformMark(platform: platform, size: 27)
            } else {
                SidebarMark(symbol: page.symbol)
            }
            Text(page.title)
        }
        .tag(page)
    }
}

/// 价格汇总的读取与格式化；只读缓存，任何调用都不会触发网络请求。
/// 查询区固定港服（92% 库存覆盖 vs 国区 57%），展示货币固定人民币。
@MainActor
enum PriceValue {
    private static let displayCurrency = "CNY"

    static func steamText(snapshot: SteamSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        guard let sum = await SteamPriceStore.shared.totalValue(appIDs: snapshot.library.games.map(\.id)),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: displayCurrency)
    }

    static func nintendoText(snapshot: NintendoSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        guard let sum = await NintendoPriceStore.shared.totalValue(titleIds: snapshot.games.compactMap(\.titleId)),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: displayCurrency)
    }

    static func psnText(snapshot: PSNSnapshot?) async -> String? {
        guard let snapshot else { return nil }
        let titleIds = snapshot.library.games.map(\.id)
        guard let sum = await PSNPriceStore.shared.totalValue(titleIds: titleIds),
              let currency = sum.currency else { return nil }
        return await formatted(sum.amount, from: currency, to: displayCurrency)
    }

    /// Overview aggregate: every priced platform contributes in its own query
    /// currency, all converted to the display currency.
    static func overviewText(steam: SteamSnapshot?, nintendo: NintendoSnapshot?, playStation: PSNSnapshot?) async -> String? {
        var total = 0.0
        var any = false
        if let sum = await SteamPriceStore.shared.totalValue(appIDs: steam?.library.games.map(\.id) ?? []),
           let currency = sum.currency {
            any = true
            if currency == displayCurrency {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: displayCurrency) {
                total += sum.amount * rate
            }
        }
        if let sum = await NintendoPriceStore.shared.totalValue(titleIds: nintendo?.games.compactMap(\.titleId) ?? []),
           let currency = sum.currency {
            any = true
            if currency == displayCurrency {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: displayCurrency) {
                total += sum.amount * rate
            }
        }
        if let sum = await PSNPriceStore.shared.totalValue(titleIds: playStation?.library.games.map(\.id) ?? []),
           let currency = sum.currency {
            any = true
            if currency == displayCurrency {
                total += sum.amount
            } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: displayCurrency) {
                total += sum.amount * rate
            }
        }
        guard any else { return nil }
        return await formatted(total, from: displayCurrency, to: displayCurrency)
    }

    private static func formatted(_ amount: Double, from currency: String, to display: String) async -> String? {
        let converted: Double
        if currency == display {
            converted = amount
        } else if let rate = await ExchangeRateStore.shared.rate(from: currency, to: display) {
            converted = amount * rate
        } else {
            return nil
        }
        return converted.formatted(.currency(code: display).presentation(.narrow))
    }
}

private extension DashboardPage {
    var platform: GamePlatform? {
        switch self {
        case .steam: .steam
        case .nintendo: .nintendo
        case .playStation: .playStation
        default: nil
        }
    }
}
