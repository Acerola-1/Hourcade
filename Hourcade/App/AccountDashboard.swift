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
                    isRefreshing: coordinator.isSyncingAll || coordinator.steamSyncing,
                    refreshError: coordinator.steamSyncError,
                    nintendoSyncError: coordinator.nintendoSyncError,
                    psnSyncError: coordinator.psnSyncError,
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
                    coordinator.recordManualSuccess(.nintendo, at: newSnapshot.syncedAt)
                    try await SyncCoordinator.shared.saveWidgetSnapshots()
                    await SyncCoordinator.shared.refreshWidgetArtwork()
                }
            case .playStation:
                PSNSettingsView(snapshot: coordinator.psnSnapshot) { library in
                    let newSnapshot = PSNSnapshot(library: library, syncedAt: .now)
                    try LocalSnapshotStore.save(newSnapshot, as: "psn")
                    coordinator.psnSnapshot = newSnapshot
                    coordinator.recordManualSuccess(.playStation, at: newSnapshot.syncedAt)
                    try await SyncCoordinator.shared.saveWidgetSnapshots()
                    await SyncCoordinator.shared.refreshWidgetArtwork()
                }
            case .general:
                GeneralSettingsView()
            case .widgetPreview:
                WidgetPreviewPage()
            }
        }
        .frame(minWidth: 820, minHeight: 610)
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
