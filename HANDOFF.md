# Hourcade 交接记录

更新日期：2026-09-24。本文供接力开发的 Agent 使用；以当前代码和 Git 状态为准，不要把尚未验证的接口写成已完成能力。

## 1. 仓库与运行

- 仓库：`/Users/acerola/Dev/Swift/Hourcade`
- 当前本地分支：`dev`。功能提交依次为 `d4a1262`（账号主页面与初步连接器）、`065b613`（连接体验、真实数据总览）。`main` / `origin/main` 仍在初始 Demo 提交 `fbff207`；截至本记录，`dev` 没有设置远端跟踪分支，也没有推送。
- 工程：`Hourcade.xcodeproj`，scheme `Hourcade`；Swift 6，最低 macOS 15，当前验证环境 Xcode 27.0。App 和 Widget 扩展的 bundle ID 仍是 `dev.acerola.Hourcade` / `dev.acerola.Hourcade.Widgets` 占位值。
- 构建命令：

  ```sh
  xcodebuild -quiet -project Hourcade.xcodeproj -scheme Hourcade -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
  ```

  此环境的 Xcode/Swift 宏插件在普通沙箱中可能报 `swift-plugin-server produced malformed response`；允许 Xcode 正常启动构建服务后可编译。最近一次构建退出码为 0；`Supported platforms ... empty` 是非致命提示。

## 2. 产品边界与当前体验

产品核心是 macOS 桌面小组件。三平台为 Steam、Nintendo Switch、PlayStation；不做游戏社区、商城、推荐和分享。用户要求设置页面向普通玩家：连接前说明从哪里取得必要信息；连接后只显示账号、连接状态和最近同步时间。游玩数据与近期游戏放在总览，不堆在设置页。不要再把 GitHub 项目、终端命令或空密钥输入框作为普通玩家的默认体验。

当前 App 用 `NavigationSplitView`：总览、三平台账号页、组件预览入口。侧栏与平台卡片使用项目中已有的三家 SVG 品牌标志。组件预览另开窗口，A、A2、B、C、D 及四张早期探索稿均保留。设计详情见 `DESIGN.md`。原始设计截图来自用户对话，未作为独立参考图存入仓库；若接力任务要求按图调整，应先取得对应图片。

## 3. 代码地图与数据流

| 文件 | 职责 |
| --- | --- |
| `Hourcade/App/HourcadeApp.swift` | 主窗口与独立组件预览窗口 |
| `Hourcade/App/AccountDashboard.swift` | 左侧导航、三平台连接页、钥匙串、自动刷新调度 |
| `Hourcade/App/OverviewView.swift` | 真实数据总览；只聚合已连接平台，Steam 近期游戏在此展示 |
| `Hourcade/App/SteamAPI.swift` | Steam Web API 客户端、`SteamSnapshot`、本机 JSON 快照存取 |
| `Hourcade/App/PSNAPI.swift` / `PSNWebLogin.swift` | 实验性 PSN 查询与系统网页登录 |
| `Hourcade/App/NintendoCLI.swift` | 已安装 nxapi 用户的高级实验性读取 |
| `Hourcade/App/ContentView.swift` | `WidgetStudioView`，五种主方案和早期素材预览 |
| `Hourcade/Shared/GameSnapshot.swift` / `AggregateCards.swift` | 当前小组件共享的 **Demo** 模型与渲染 |
| `Hourcade/Widgets/HourcadeWidgets.swift` | 五种 WidgetKit 样式；时间线仍固定使用 `GameSnapshot.demo` |

Steam ID / 个人资料链接存在 UserDefaults；Steam Web API Key 与 PSN 刷新令牌在本机钥匙串，service 为 `dev.acerola.Hourcade`。各平台同步结果以 JSON 写入用户的 `Application Support/Hourcade/`，总览启动时加载；Steam 有凭据时启动后尝试刷新，失败时保留上次快照。**这些文件和钥匙串值都不要提交、打印或粘贴到交接文档。** 当前没有 App Group，也没有把真实快照交给 WidgetKit。

## 4. 已验证与未验证

已验证：

- Swift 6 工程构建成功，三平台页面、SVG 标志、预览窗口均在 macOS 中打开检查。
- 在用户已有的 Steam 连接上，官方 `GetOwnedGames` / `GetRecentlyPlayedGames` 返回真实游戏记录、累计时长和近两周时长；数据在总览显示。退出并重开 App 后，本机快照仍显示，启动自动刷新运行。曾遇到一次网络超时，手动重试成功。
- Steam 连接后的页面隐藏 Key 输入框，只显示账号、钥匙串状态与最近同步时间；首次连接流程包含页内两步说明和 Steam 官方密钥入口。

尚未验证：

- PSN 系统网页登录是否能在真实账号上完成 Sony 回调、换取令牌并读取目标 Online ID 的游戏；目前仅通过编译和页面检查。此链路基于非公开接口和开源项目使用的移动端 OAuth 参数，可能失效。高级 NPSSO 入口也未用真实账号验证。
- Nintendo 的 nxapi CLI 路径尚未在此机器用真实账号验证，普通用户的应用内 Nintendo 登录仍未实现。界面将 CLI 放在高级实验折叠区，普通流程明确告知尚在开发。
- WidgetKit 仍只显示 DEMO 数据；没有真实账号的后台定时同步、快照差分、App Group 共享或正式发布签名。

## 5. 平台数据的真实边界

- **Steam**：官方 Web API 可取已返回的游戏库条目、累计时长和近期接口提供的两周时长。资料隐私可能使游戏列表为空。当前要求用户提供个人 Web API Key 只是测试版方案；Steam OpenID 只能识别身份，不能单独授权读取私密游戏库。正式版需重新设计密钥/服务端与授权体验，不能只隐藏密钥表单。
- **Nintendo**：[nxapi](https://github.com/samuelthomas2774/nxapi) 的 NSO PlayLog 可读游戏名、封面、累计时长、首次游玩时间，**不提供近 14 天逐游戏时长**。家长控制每日摘要是另一个可研究的数据源，要求用户另行绑定主机。nxapi 采用 AGPL-3.0，NSO 认证默认依赖第三方辅助服务；在集成、分发与告知前核对许可、凭据流和可靠性。
- **PlayStation**：[psn-api](https://github.com/achievements-app/psn-api) 显示已认证会话可查询 Online ID 的公开可见已玩游戏、封面、累计时长。**只有 PSN ID 不够**；接口也不提供首次连接前的近 14 天游玩时长。当前“已玩游戏”不等于“拥有的游戏库”；后续只能靠定期累计快照差分估计期间增量。
- 三平台的“当前标价合计”都需要单独的商店价格来源、地区、货币和版本映射。当前 A 方案金额完全是 Demo；不要把它写成真实同步结果。总览称“游戏记录条目”，避免把三种不同口径的数据误称去重游戏库。

## 6. 下一步建议与验收

1. **先处理真实数据到小组件的链路**：定义跨 App / Widget 扩展共享存储和同步状态；配置 App Group 后，将已验证字段组成非 Demo 的快照。缺失的平台、近 14 天和价格要显示缺失状态，不能补假数。保留现有 A/A2/B/C/D 设计素材。
2. **完成普通玩家的账号连接**：Steam 去掉最终用户申请开发者 Key 的长期依赖；PSN 用真实账号测试网页登录的回调和过期刷新；Nintendo 研究可以在 App 内完成且许可、凭据流清晰的实现。未经验证不要把“连接成功”状态提前放出。
3. **定义时间与口径**：Steam 两周时长来自接口；Nintendo 需每日摘要或明确不支持；PSN 需快照差分并明确首次连接无历史。价格单独设计数据源和用户可关闭的隐私显示。
4. **正式发布前**：核对现有 SVG 的来源及平台商标使用要求；确认签名、bundle ID、App Group、凭据保护、隐私说明和错误恢复。

可用的下一轮验收：有账号时总览显示真实数据；无账号时有清晰连接路径；网络失败后保留上次数据及更新时间；Widget 不把 Demo/缺失值包装成真实；三个设置页只保留连接相关信息。
