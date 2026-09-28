# Hourcade

macOS 桌面小组件，把 Steam、Nintendo Switch 和 PlayStation 的游玩数据汇成一张桌面大卡。宿主 App 负责连接账号、同步数据和管理缓存；所有卡片渲染由宿主与 WidgetKit 扩展共享同一套 Swift 6 / SwiftUI 代码。

## 功能

**桌面组件（10 款，命名 A1–A6 / M1–M4）**

- 超大号（systemExtraLarge）：A1 游戏人生（英雄封面）、A2 数据概览（环形占比 + 动态活动面板）、A3 平台（竖排数据 + 三张平台封面）、A4/A5/A6 游戏墙（Steam / Switch / PS 各自的 Top 封面墙 + 成就/奖杯数）
- 中号（systemMedium）：M1 迷你汇总（全平台）、M2/M3/M4 单平台迷你（文字排行 + 封面背景）
- 组件与「桌面组件预览」页读取同一份合并快照（App Group 内 `accounts-widget.json`），预览即所得
- 英雄封面、近期游戏轮换由随机时间线驱动，宿主预览每 8 秒交叉淡入

**数据接入**

- Steam：Web API（GetOwnedGames / GetRecentlyPlayedGames / GetSteamLevel / GetPlayerSummaries），Web API Key 存本机钥匙串
- Nintendo Switch：My Nintendo / Nintendo Store App 通道（OAuth + PKCE 浏览器登录），近 14 天时长来自官方每日记录
- PlayStation：PSN 浏览器登录（OAuth），累计时长 + 账号级奖杯；单游戏奖杯按行懒加载
- 启动即自动刷新所有已连接平台；任何一页都只读缓存，网络清扫在同步后后台执行

**游戏价值（参考价值）**

- Steam 走商店 appdetails（国区优先、港服补缺，2.5s/次限速）；PSN 走匿名商店 GraphQL（chihiro 旧接口兜底）；Nintendo 走美区 eShop 价格（nsuid 映射来自社区 titledb，7 天缓存）
- 查询区固定港服（库存覆盖 92%），展示货币固定人民币，按当日汇率（er-api，frankfurter 备用）折算；所有价格磁盘缓存 24 小时

## 系统要求

- macOS 15+，Xcode 27（Swift 6 工具链）
- 签名需要配置开发团队；App Group 为 `$(TeamID).dev.acerola.Hourcade`

## 构建

打开 `Hourcade.xcodeproj`，选择 **Hourcade** scheme 运行。命令行：

```sh
xcodebuild -project Hourcade.xcodeproj -scheme Hourcade \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

首次使用：在侧边栏选择平台完成连接（Steam 需要个人资料链接 + Web API Key，Nintendo / PSN 走系统浏览器登录），数据就绪后回到桌面添加组件。

## 工程结构

```
Hourcade/
  App/            宿主界面与平台 API
    AccountDashboard.swift        侧边栏壳、导航、全平台同步编排、PriceValue
    PlatformPageChrome.swift      页面骨架、统计行、三平台游戏列表
    PlatformSettingsPages.swift   Steam / Nintendo / PSN 账号页
    GeneralSettingsView.swift     常规设置（语言、主题、缓存）与封面缓存管理
    OverviewView.swift            总览页与通用封面管线（CoverStore）
    SteamAPI.swift / PSNAPI.swift / NintendoAPI.swift
    SteamWebLogin / PSNWebLogin / NintendoWebLogin.swift
  Shared/         宿主与组件扩展共享（同时编入两个 target）
    GameSnapshot.swift            组件数据模型、卡片样式枚举、Steam 快照存储
    PlatformSnapshots.swift       Switch/PSN 快照、合并快照 WidgetSnapshotStore
    AggregateCards.swift          A1–A6 / M1–M4 全部卡片视图
    KeychainSecret.swift / DisplayFormat.swift / Localization.swift
  Widgets/        WidgetKit 扩展入口（HourcadeWidgets.swift）
历史资产/          早期概念图与初版文档（已被现状取代，仅作参考）
Design/IconConcepts/  App 图标概念稿与决策记录
HANDOFF.md         交接记录：已验证结论、用户决定、调查证据
```

## 状态说明

Steam、Nintendo、PSN 三平台均已用真实账号完成端到端同步并核对了总览与组件呈现。价格来源均为公开或半公开接口，可能随服务端变更失效——失效时对应游戏显示「—」，不影响其余数据。详细的服务端怪癖、决策依据与调查证据见 `HANDOFF.md`。
