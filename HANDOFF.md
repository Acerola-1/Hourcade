# Hourcade 交接记录

更新日期：2026-09-24。此文件持续记录已验证结果、用户决定、调查证据和阻塞；以当前代码与 Git 状态为准，不把编译通过、离屏渲染或登录窗口可打开写成真实账号端到端通过。

## 1. 当前状态与用户决定

- 产品核心是 macOS 桌面聚合小组件，覆盖 Steam、Nintendo Switch、PlayStation；不做社区、商城或分享。
- 用户要求沿用既定主方案，不另造独立 Steam 样式；没有接入的平台保留标志与明确空状态；保留独立演示版本。
- **最新决定：删除带价格的 A 方案，包括真实版和演示版。保留 A2/B/C/D。** 当前没有已验证的三平台统一价格来源，不再显示假金额或“标价未接入”栏。
- **已完成的整轮功能（2026-09-25）**：Nintendo 账号网页登录（OAuth+PKCE）与 Store App `play_histories` 数据接入；PSN 仅保留浏览器登录（NPSSO、Online ID 输入框已删）；总览改为全平台"近期游玩"聚合（平台角标 + 最近游玩时间 + Steam 封面三级兜底）；"常规设置"并入侧边栏（语言/主题/封面缓存管理）；启动自动同步全部已连接平台；侧边栏图标列统一 27pt 对齐、总览图标换 `gamecontroller.circle`。
- **Nintendo 接入已实现并实测通过**：走 My Nintendo / Nintendo Store App 通道（`app-api.znej.nintendo.com`），只需 `id_token`，不依赖第三方 f-token 加密服务，未借用 nxapi 服务身份。调查与验证记录见下文Nintendo 章节。
- 用户要求随实施、验证进展更新本交接文档。不得等到会话结束才补记重要阻塞。

## 2. 仓库、构建与安装

- 仓库：`/Users/acerola/Dev/Swift/Hourcade`；当前分支 `dev`。改动已按进度提交到 dev 分支；用户设计稿 `Design/IconConcepts/` 一并入库。
- 工程 `Hourcade.xcodeproj`，scheme `Hourcade`，Swift 6，最低 macOS 15，验证工具为 Xcode 27.0。
- Bundle ID：`dev.acerola.Hourcade`、`dev.acerola.Hourcade.Widgets`。本机团队 `VTQ6S5M4K3`；App Group 为 `VTQ6S5M4K3.dev.acerola.Hourcade`，通过 entitlements 和 Info.plist 保持一致。
- 本机签名构建：

  ```sh
  xcodebuild -quiet -project Hourcade.xcodeproj -scheme Hourcade -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGN_IDENTITY='Apple Development' build
  ```

- 应用已安装在 `/Applications/Hourcade.app`；最近完成安装验证的是本轮整合构建（价格移除、本地化、高清图、PSN 加固后首次通过）。`CURRENT_PROJECT_VERSION` 仍为 2，未随本轮递增。
- 扩展嵌入 `Contents/PlugIns/HourcadeWidgets.appex`，有沙箱与 App Group 权限；主应用保持原数据路径及钥匙串行为。
- 本机安装不等于发布：未公证、未完成正式发行验证。`Supported platforms ... empty` 在当前工具链是已见非致命构建提示。

## 3. 数据流与代码入口

| 文件 | 职责 |
| --- | --- |
| `Hourcade/App/HourcadeApp.swift` | 主窗口与组件预览窗口；语言/主题经 `AppTheme` 应用（设置场景已并入侧边栏常规设置） |
| `Hourcade/App/AccountDashboard.swift` | 导航、连接页、钥匙串及同步调度 |
| `Hourcade/App/OverviewView.swift` | 真实平台数据总览 |
| `Hourcade/App/ContentView.swift` | 主方案与早期探索稿、真实/演示切换 |
| `Hourcade/App/SteamAPI.swift` | Steam API、用户头像、高清游戏图片下载与缓存、本机 JSON 快照 |
| `Hourcade/App/PSNAPI.swift` / `PSNWebLogin.swift` | PSN 登录、令牌交换、游戏列表；本轮加固 |
| `Hourcade/App/NintendoAPI.swift` / `NintendoWebLogin.swift` | Nintendo Store App API 客户端与浏览器 OAuth 登录（PKCE）；钥匙串存 session token |
| `Hourcade/Shared/GameSnapshot.swift` | 共享数据模型、组件快照和图片路径 |
| `Hourcade/Shared/Localization.swift` | 共享语言偏好与资源查找（`AppLanguage`、`L10n`） |
| `Hourcade/Shared/PlatformSnapshots.swift` | 三平台数据模型、`WidgetSnapshots` 聚合、`WidgetSnapshotStore` 持久化 |
| `Hourcade/Shared/AggregateCards.swift` | 主方案组件渲染（A2/B/C/D） |
| `Hourcade/Shared/App.xcstrings` / `Widgets.xcstrings` | 主应用与组件的双语字符串目录 |
| `Hourcade/Widgets/HourcadeWidgets.swift` | WidgetKit 配置与时间线 |

Steam 个人资料标识存在 UserDefaults；Steam Web API Key 和 PSN 刷新令牌在本机钥匙串，service 为 `dev.acerola.Hourcade`。原始同步快照在用户 `Application Support/Hourcade/`，组件展示数据和缩放后的图片在 App Group；不向组件共享 API Key。**不得提交、打印或粘贴真实快照、账号标识、令牌或钥匙串内容。**

目前已验证的 Steam 行为：启动加载旧快照并刷新；手动同步；失败保留旧数据；成功后写入 App Group 并请求刷新时间线。组件不独立持有 Steam 密钥，关闭主应用后不保证继续从平台同步。

## 4. 已验证结果与已定位问题

- build 2 带签名构建、嵌入扩展和本机安装成功，严格签名校验通过。
- 用户提供的系统桌面截图确认：组件真实显示 Steam 累计/近两周时长、头像、游戏图片和未连接平台栏，原“不可添加/全空白”阻塞已解除。
- 上轮对五种布局的真实、演示、未连接、空库、无近期五类状态做过 25 次离屏渲染；共享快照与宿主数据核对通过，当前账号的头像及三款近期游戏旧版图片缓存齐全。
- 空白问题曾有三个明确原因：`configurationDisplayName` 插值格式导致扩展崩溃；枚举列表标识未实现 Encodable；大图/过多时间线使存档约 11–13 MB 被 WidgetKit 拒绝。对应修复后系统日志显示十个主方案/演示占位存档预缓存完成。
- **用户最新截图仍揭示文字截断、英中文案混用、背景模糊。** 本轮正在修复，不能用上轮的离屏测试代替这些问题的验收。
- 已核实低清背景来自把 Steam 460×215 header 放大。部分新游戏的旧图片路径会 404；`appdetails.header_image` 可取得带哈希的实际地址。本轮正在区分高清 hero/竖封面，hero 不存在时考虑公开商店的全尺寸截图，不把小 header 标记成高清。
- Computer Use 的系统截图多次超时，系统组件库进程也无法可靠访问。可使用宿主可访问性树及离屏图片辅助，但必须明确哪些桌面步骤仍由用户确认，不得声称自动化已完成现场验收。

## 5. Nintendo 调查结论（2026-09-24）

### 账号与数据范围

需要关联 Switch 网络服务身份的 **Nintendo Account**。NSO/Nintendo Switch App 是服务入口，不是另一个账号；My Nintendo 奖励/会员页面不等于游玩记录接口。nxapi 文档说明基础账号/游玩活动不要求付费 NSO 会员，游戏专属服务另有要求。

PlayLog 返回游戏名称、图片、商店链接、累计游玩分钟、首次游玩 Unix 秒；首次时间的零值是哨兵。**不是逐日会话历史，也不提供逐游戏近 14 天时长。** 家长控制每日活动是另一条接口，需主机官方配对，不能无提示替代账号库。

### 已核实的当前协议

调查基于 nxapi 修订 `47c9d35`（2026-09-09），其中 Coral/Nintendo Switch App 版本为 **3.5.0**。不要拿旧 GitHub release 或包版本 `1.6.1` 判断当前接口兼容性。

1. Nintendo 官方网页授权使用 `response_type=session_token_code`、随机 state 和自定义 PKCE 参数 `session_token_code_challenge` / `session_token_code_challenge_method=S256`。回调参数在 fragment；必须校验 scheme、host、state。
2. 官方 `accounts.nintendo.com/connect/1.0.0/api/session_token` 用会话授权码和 verifier 换 session token；`.../token` 用 session token 换短期 ID/access token；官方 `api.accounts.nintendo.com/2.0.0/users/me` 提供账号 ID/语言。
3. Coral `/v4/Account/Login` 需要 method-1 f 值及请求加密；登录结果包含 Coral user ID、NSA ID、Web API credential。
4. `/v4/User/ShowSelf` 与 `/v4/User/PlayLog/Show` 使用 Coral bearer，且请求/响应均经过加密服务；PlayLog 参数是本人的 NSA ID。当前仅查询游玩记录不需要 SplatNet 的 method-2 token。

### 实际阻塞与隐私边界

- 自 3.0.1（2025 年 6 月）起，Coral 不只是需要 f 签名，还需要专有请求加密与响应解密。当前 nxapi 路线依赖运行 Android/Frida 的服务；没有可直接当作普通本地库嵌入 Swift 的完整替代实现。
- 使用该第三方服务时，**短期 Nintendo ID token、Coral token 及 Coral 请求/响应内容会经过第三方**。Nintendo 密码和本地交换的长期 session token 不必发送给它；这仍需要显式、清晰的登录前告知与用户同意。
- **Hourcade 需联系服务运营者，注册自己的 public client 并取得授权。** 涉及服务 OAuth scopes `ca:gf ca:er ca:dr`、客户端标识与服务兼容头；不得冒用其他客户端。服务文档还要求面向终端用户披露服务，Nintendo 功能免费且无广告等条件。
- 调查时服务配置报告 3.5.0/build 13939/三个 worker；状态页同时警告部分服务异常。这只能证明配置可读，**没有执行真实账号登录或游玩数据验证**。Imink/flapg 旧路线不能视为当前可用替代。
- nxapi 使用 **AGPL-3.0-or-later**。复制、翻译或打包其实现前必须核对许可；改写成 Swift 不自动免除来源代码的许可义务。
- 用户选择本轮暂缓 Nintendo；保留清楚的不可用原因和高级 nxapi 入口，不新增误导性的“连接成功”状态。恢复此任务的前提是明确授权服务、客户端申请结果、隐私告知、许可与真实账号验收。

### 复检补充（2026-09-25）：更正——存在无需 f 参数、无需第三方的官方通道

用户质疑"Switch 也是登录后解析数据，Jump/二饼/小黑盒都做到了，为什么我们不行"。**复核后确认用户的判断是对的，上一条"Nintendo 只能依赖第三方"的结论需要更正。** 之前只盯着 NSO（Coral）一条路，漏掉了 Nintendo Store / My Nintendo App 的接口。

**关键通道：My Nintendo / Nintendo Store App API（`mypage-api.entry.nintendo.co.jp`）**

- 认证链路：Nintendo Account OAuth（`accounts.nintendo.com/connect/1.0.0/authorize`，`response_type=session_token_code` + PKCE）→ session_token → `POST /connect/1.0.0/api/token` 换 **`access_token` / `id_token`**。之后**直接用 `id_token` 作为 `Authorization: Bearer`** 调 `mypage-api`。
- **不需要 f 参数、不需要请求加密、不需要任何第三方服务**。这与 Coral 路线是本质差别——之前"必须外包 f 值生成"的结论只适用于 Coral，不适用于这条。
- 接口：
  - `GET https://mypage-api.entry.nintendo.co.jp/api/v1/users/me/play_histories`（需 `User-Agent: com.nintendo.znej/…`）→ `playHistories[]` / `recentPlayHistories[]` / `lastUpdatedAt`。
  - `GET .../api/v1/users/me/play_histories/game_titles/{titleId}?limit=&offset=` → `playedDays[]`（每项 `playedDate` + `minutesPlayed`，**逐日逐游戏分钟数**）、`totalPlayedMinutes`、`firstPlayedAt`、`lastPlayedAt`、`titleName`、`imageUrl`。
- 数据质量：**比 Coral PlayLog 更好**——Coral 只有累计时长，这条能给出"某游戏在某天玩了多久"，正是总览/组件要展示的粒度。而且这解释了 Jump/小黑盒"登录后能看到真实时长"的来源。
- 该 app 2025-11-05 由 My Nintendo 更名为 Nintendo Store（v3.0.0），游玩记录功能保留在"我的"页；接口路径沿用。参考实现：GitHub `CafeAuLite-CC/NSPlayTime`（用 `mypage-api … /play_histories`）。

**仍需核实/未验证**

- 该通道用的 **My Nintendo App（`com.nintendo.znej`）client_id 已找到**：`5c38e31cd085304b`，redirect 为 `npf5c38e31cd085304b://auth`（对照：NSO App 的 client_id 是 `71b963c1b7b6d119`）。来源：`Swilder-M/nintendo-switch-box` 源码中 `self.client_id = '5c38e31cd085304b'`（同行注释 `# 71b963c1b7b6d119`），及 blog.iiccc.cc 的说明"鉴权流程一样，只是用不同的 client_id 请求 session_token，之后用 api_token 直接请求服务，不需要再换 NSO 的 client_token（即不需要 f）"。
- 端点存在两个已知变体：早期 `https://news-api.entry.nintendo.co.jp/api/v1.1/users/me/play_histories`，较新 `https://mypage-api.entry.nintendo.co.jp/api/v1/users/me/play_histories`。2025-11-05 My Nintendo 更名 Nintendo Store（v3.0.0）后需确认当前有效者。
- 区域：多份资料（含 Jump 官方公告）指出 Jump 支持除港服外的所有区服；港区未开放该数据接口。
- 本轮未做真实账号端到端（本机到 `mypage-api` 的 DNS 被解析到 `198.18.5.1`，疑似代理 fake-IP，curl 返回 000，未能直连验证）。

**对照 Parental Controls（Moon）通道**（上一条已记录）：同样不需要 f/第三方，但要求先用官方家长控制 App 配对主机，语义偏"家长监控"；`daily_summaries` 有逐日逐游戏 `playingTime`。两条都不是 Coral 那种高门槛路线。

**结论修正**：Hourcade 的 Nintendo 接入**不需要先解决 f 参数、也不需要第三方授权**即可实现"用户登录 → 解析游玩记录"。Jump / 二饼 / 小黑盒 / NSPlayTime / Raycast 的 Switch 时长功能走的都是 My Nintendo（现 Nintendo Store）App 通道，与我们的目标一致。应从这条通道重做接入，取代目前只有 nxapi CLI 的入口。

### Nintendo 接入完工（2026-09-25）

基于上面确认的 `app-api.znej.nintendo.com` 通道，完成 Nintendo 接入实现：

- **新建 `NintendoWebLogin.swift`**：`ASWebAuthenticationSession` + PKCE（S256），client_id `5c38e31cd085304b`，redirect `npf5c38e31cd085304b://auth`。回调 fragment 解析 + state 校验。`prefersEphemeralWebBrowserSession = false`（已登录浏览器可一键选号）。
- **新建 `NintendoAPI.swift`**：完整实现三步——① `session_token_code + verifier` → `session_token`（form POST）；② `session_token` → `id_token / access_token`（JSON POST）；③ `GET app-api.znej.nintendo.com/api/v2.0/users/me/play_histories`（Bearer `id_token`，需 `User-Agent: com.nintendo.znej/3.0.3` 与 `Gentry-Locale` 头）。附 `access_token` 回退。可选调 `api.accounts.nintendo.com/2.0.0/users/me` 取昵称（best-effort）。
- **`NintendoSettingsView` 完全对齐 PSN 页**：连接账号 / 已连接的账号、昵称、最近同步时间、立即同步 / 重新登录、登录后隐藏说明小字、无高级入口。
- **删除 `NintendoCLI.swift`** 及其 pbxproj 引用（`1D` fileRef 改指 NintendoWebLogin.swift、新增 `3B/3C` 给 NintendoAPI.swift）。nxapi 相关字符串全部移除（App.xcstrings 139 → 126 条）。
- **凭据**：`session_token` 存钥匙串 `nintendo.sessionToken`（约 2 年有效）。id_token/access_token 是短期的，每次同步从 session_token 重新派生。
- **数据模型**：`NintendoGame` 新增 `titleId`（可选，快照兼容）；`NintendoSnapshot` 新增 `accountName`（可选）。两者旧文件解码兼容。
- **真实数据验收**：82 款游戏、1300 小时、accountName 已显示真实昵称、Switch/Switch 2 分列、逐日 `recentPlayHistories` 已可获取。

**注意事项**：导入钥匙串令牌时不要用 `security` CLI（ACL 不归应用，反复弹密码授权）；应由应用通过 `KeychainSecret.save()` 自行保存。


用户配合完成了一次真实 Nintendo Account 登录，逐段结果如下：

| 步骤 | 结果 |
| --- | --- |
| 授权链接（client_id `5c38e31cd085304b`，PKCE S256） | 302 → `accounts.nintendo.com/login`，**未报 invalid_client**，client_id 有效 |
| `session_token_code` → `session_token` | **HTTP 200 OK**（`connect/1.0.0/api/session_token`） |
| `session_token` → `id_token` | **HTTP 200 OK**；`aud=5c38e31cd085304b`、`scope` 含 `openid/user/user.email/user.links[].id/user.mii` |
| `mypage-api.entry.nintendo.co.jp/api/v1/users/me/play_histories` | **NXDOMAIN**（DoH Status=3，域名已删除） |
| `news-api.entry.nintendo.co.jp/api/v1.1/users/me/play_histories` | **HTTP 590** 固定维护页 `{"title":"システムメンテナンス","detail":"11月5日 17:00","code":"0900"}`，全站所有路径（含 `/`）均返回此页 |
| 其他候选域名（`api.entry`、`store-api.entry`、`mypage.nintendo.com` 等） | 全部 NXDOMAIN |

**结论**：My Nintendo / Nintendo Store 这条通道的**认证链路已在本机实测打通**（OAuth + PKCE + client_id 全部有效），但**旧的游玩记录数据端点已随 2025-11-05 的 Nintendo Store 改版下线**：`mypage-api` 域名被删除、`news-api` 返回维护页。当前公开资料（NSPlayTime、blog.iiccc.cc、Raycast 插件等）指向的都还是这两个旧端点，因此**尚不能直接实现**——需要从真实 Nintendo Store App（v3.0.0+）抓包确认新的数据端点与 client_id/版本头。

**技术障碍已明确缩小**：不再是"任天堂不给数据"，而是"数据端点随改版迁移，需要一次抓包定位"。这是可解决的工程问题，不是不可逾越的封锁。

**未做**：新端点的抓包定位（需要 iOS/Android 设备或模拟器运行 Nintendo Store App 并抓包）；本机到 Nintendo 域名的访问依赖 Clash 代理（`127.0.0.1:7890`），`198.18.x.x` 为代理 fake-IP。


### 界面重构：总览 + 常规设置（2026-09-25）

用户要求总览页一键同步全部平台、去掉硬编码 3、把设置从独立窗口移入侧边栏。已完成：

**总览页（OverviewView）**

- "同步 Steam"改为**"同步全部"**：一键刷新所有已连接平台（Steam / Nintendo / PSN 各自独立执行、独立容错），新增 `ContentView.syncAll()`。按钮只在 `connectedAny` 时显示。
- 已连接平台计数去掉硬编码 `/3`，改为从 `GamePlatform.allCases.count` 推导。
- 平台卡片从 `GamePlatform.allCases` 驱动（`platformEntries`），新增平台不需要改总览视图。
- Steam 的 `steamConfigured` 与 `refreshError` 保留，但 `refreshSteam` 闭包移除（被 `syncAll` 替代）。

**常规设置（GeneralSettingsView，新建于 AccountDashboard.swift）**

- 侧边栏在"总览"正下方新增"常规设置"入口（`DashboardPage.general`），detail 区域内嵌展示，**不再单独开窗口**。
- 移除了 `HourcadeApp` 里的 `Settings { LanguageSettingsView() }` 场景（macOS 的"设置…"菜单不再可用，这是有意的——入口已移入侧边栏）。
- 内容两项：**语言**（跟随系统 / 简体中文 / English）与**主题**（跟随系统 / 浅色 / 深色）。均使用 segmented picker，写入共享 store（`L10n.defaults`）。
- 主题通过 `AppTheme` 枚举 + `.preferredColorScheme(L10n.colorScheme)` 应用到 WindowGroup 和组件预览窗口；主题只影响应用窗口，桌面小组件跟随系统外观（有说明文字）。

**Nintendo 登录状态丢失的根因与恢复**

用户报告"已登录却显示需要登录"——根因是我在排查钥匙串弹窗时执行了 `security delete-generic-password` 把应用已保存的 `nintendo.sessionToken` 条目删掉了。该条目本应保留。通过从 `~/Library/Application Support/Hourcade/nintendo-session.json` 重新导入（`-T /Applications/Hourcade.app`）恢复。

**教训**：`security add-generic-password` CLI 导入的条目默认 ACL 不信任目标应用，会导致反复弹密码授权。正确做法：由应用通过 `KeychainSecret.save()` 自行保存，或导入时必须带 `-T /Applications/Hourcade.app`。删除/重建 keychain 条目前必须确认应用当前没有活跃凭据依赖它。

**凭据收尾（2026-09-25）**

- 用户已手动删除废弃的 `psn.npsso` 钥匙串条目（NPSSO 路径代码删除后该条目已无用途）。现存条目：`nintendo.sessionToken`、`steam.apiKey`、`psn.refreshToken`，均为活跃凭据。
- 明文 `~/Library/Application Support/Hourcade/nintendo-session.json` 已删除——钥匙串条目确认存在且应用可无提示读取（`migrateNintendoSessionToken` 仅在钥匙串为空时读该文件，现恒为 no-op 安全网）。钥匙串现在是唯一凭据存储；若条目再丢失，恢复方式为浏览器重新登录（流程已验证）。
- 平台数写死的最后两处已修复：`AggregateCards.swift` 两处 `connectedPlatformCount, 3` → `GamePlatform.allCases.count`。至此全工程无硬编码平台上限，新增平台只需扩 `GamePlatform` 枚举并在 ContentView 加对应 snapshot 状态。
- 清理仓库根目录接口探测残留 `g1.json` / `g2.json`（仅含错误响应，无敏感数据）。

### 总览"近期游玩"改为全平台聚合（2026-09-25）

用户指出总览里是"Steam 近期游玩"，应为全平台近期游玩，且每行要有平台标识。实现：

- **三个平台的游戏模型都补了 `lastPlayedAt`**：
  - Steam：`GetOwnedGames/v1` 本就返回 `rtime_last_played`（unix），`GameDTO`/`SteamGame` 直接加字段（旧快照解码为 nil，排序回退到 `library.recent` 顺序）。
  - Nintendo：`play_histories` 返回里一直有 `lastPlayedAt`（ISO 8601 带时区），此前解析结构体漏掉了——`PlayHistory`/`NintendoGame` 补上；缺省时回退 `firstPlayedAt`。
  - PSN：`gamelist/v2` 的 `lastPlayedDateTime`（ISO 字符串）早就在模型里，新增 `lastPlayedDate` 计算属性 + `SnapshotDates`（`PlatformSnapshots.swift`）宽容解析（fractional ISO → ISO → 无时区 ISO）。
- `OverviewView` 的近期板块改为 `RecentGame` 聚合：每平台按 last-played 取前 6 候选，合并按时间倒序取前 8 行；行内 = 56×56 封面（AsyncImage 直连平台 CDN）+ 平台角标（`AccountPlatformMark`）+ 游戏名 + "平台 · 近两周/总计 X小时Y分钟" 副标题 + 右侧相对时间（`RelativeDateTimeFormatter`）。无日期的行沉底、按平台顺序排。
- 本地化：新增"近期游玩"、"%1$@ · 近两周 %2$@"、"%1$@ · 总计 %2$@"；删除"Steam 近期游玩"、"过去两周"（133 → 134 条）。
- 总览头部小字"来自 N 个已连接平台"已按用户要求删除（汇总卡片里已有平台数；空状态提示"连接平台后…"保留）
- **旧快照没有新字段**：升级后需要点一次"同步全部"，三个平台的 last-played 才会落库。

### 游戏价值 v2：PSN 接入 + 总览合计（2026-09-25）

调研（探员实测验证）：①gamelist v2 每个 title 自带 `concept.id`（**数字类型**，首次按 String 解析失败——教训：PSN 接口的 id 字段常是数字）；②商店 GraphQL `metGetPricingDataByConceptId` **匿名可用**（`web.np.playstation.com/api/graphql/v1/op`，需要 `Content-Type: application/json` 头否则 CSRF 拦截 + `x-psn-store-locale-override` 头选区域），响应 `data.conceptRetrieve.defaultProduct.price{basePriceValue, discountedValue, currencyCode}`（分为单位）；③persistedQuery sha256Hash 会轮换（旧 hash 实测已 "not whitelisted"），社区均硬编码+手动更新；④legacy chihiro 接口实测仍存活（匿名 JSON，需完整 product id）。

**实现**：
- gamelist 解析 `concept.id`（Flexible String/Int）存进 `PSNGame.conceptId`；临时 gamelist dump 调试钩子已拆除。
- `PSNPriceStore`（actor）：主通道 GraphQL 按 concept id 查价（成功时顺带缓存 defaultProduct.id）；备用通道 chihiro（用此前成功缓存过的 product id，首扫无 product id 时自动跳过）；条目 24h 磁盘缓存（psn-prices.json）。
- 区域映射：`PricingRegion` 新增 `psnLocale`（x-psn-store-locale-override 头）与 `chihiroCountry`；中国大陆无 PS 商店 → 回退港服 HKD + 汇率折算（与 Switch 同思路）。
- 展示：PSN 统计行 5 项（等级/总时长/游戏数量/完成率/游戏价值）；总览大卡片新增"游戏价值"合计（`PriceValue.overviewText`，Steam+Nintendo+PSN 三平台按计价地区货币折算加总）。
- 实测：27/31 款游戏拿到港币价格（GraphQL 连折扣 -50%/-60% 均捕获），HKD 7,371；Steam ¥22,974 + Nintendo ≈¥8,825 + PSN ≈¥6,860 → 总览合计 ≈¥38,600。
- 截图注意：应用窗口在其他 Space 时 `screencapture -l` 返回全黑（optionAll 能找到窗口但无法渲染），AX 切页也会间歇失效——数据验收以缓存文件为准。

### 游戏价值 v1：Steam + Nintendo（2026-09-25）

调研结论：Steam 用官方 appdetails `cc=` 参数直查（CNY/限流 200 次每 5 分钟）；Nintendo 用 eShop 官网同源接口 `api.ec.nintendo.com/v1/price`（country 参数 + **批量 50 个 nsuid**）；PSN 最难（商店 GraphQL 签名轮换、商业 API $100/月）→ **暂缓**，待再调研。业界模式两种：分区原生货币（DekuDeals/SteamDB，无法合计）vs 统一货币折算（GG.deals）——我们的"资产合计"需求选后者。语言与计价地区是独立维度（业界标准），不冲突。

**实现**：
- 常规设置新增"计价地区"（`PricingRegion`：跟随 Steam 账号/中国大陆/香港/日本/美国/英国/欧元区/韩国，`@AppStorage pricingRegion`，auto 用 `loccountrycode` 解析）。
- `SteamPriceStore`（actor）：按 appid 磁盘缓存 24h（steam-prices.json），sweep 每请求间隔 1.6s 全量约 8 分钟，同步后后台跑。
- `NintendoPriceStore`（actor）：titleId→nsuid 映射来自社区 blawar/titledb US.en.json（**只有美区数据完整**，映射表 7 天缓存，全量下载解析约 1 次/周）；价格批量 50 个/请求按美区美元价查询，**响应的 title_id 是 nsuid，需反向映射回 titleId 再入库**（首次实现踩坑：直接用 nsuid 做键导致汇总永远为空）。
- `ExchangeRateStore`（actor）：frankfurter.app（ECB 日频免费）+ open.er-api.com 备源，内存缓存。
- 展示：Steam 统计行 4 项、Nintendo 3 项，新增"游戏价值"=当前售价合计（任天堂美元价按汇率折算），`pricesDidChange` 通知驱动页面刷新。**页面只读缓存、永不触发网络**；清扫只在同步后后台执行 + 24h TTL。
- 实测：Steam 284/312 定价（其余免费/无商店数据），当前合计 ¥22,974（原价 ¥29,296）；Nintendo 33/82 有美区价格（$1,239.43，未覆盖的是美区没有的日亚区游戏+titledb 数据集滞后）。
- 已知限制：①任天堂价格统一美区美元（titledb 仅美区完整），非用户实际购买区；②titledb 覆盖 71%，新游戏可能滞后；③PSN 未接入，总览暂无合计；④折算汇率日频，不构成支付依据。

### 封面缓存重构：CoverStore（2026-09-25）

用户观察到两个现象，根因不同：
1. **同一封面每次进页面都重新加载**——旧 GameCover 把图存在视图 `@State`，页面切换即销毁，无应用级缓存。
2. **DragonSword : Awakening 永远灰块**——两因叠加：负缓存（`missingHeaders` Set）进程级永不过期（早期非懒加载时代 312 并发把 appdetails 打到限流，一次失败终身拉黑）；且 Steam appdetails 有**响应重键怪癖**：商店条目迁移到内部 appid 后（如 4570720 → 包装键 4742660，内层 steam_appid 仍是 4570720），按请求 appid 取键取不到数据。

修复：新 `CoverStore`（actor，OverviewView.swift，与 GameCover 同文件）统一所有应用内图片瓦片：内存 → 磁盘（`Application Support/Hourcade/covers/<sha256 前 8 位>.jpg`）→ 网络；Steam 兜底的 appdetails 解析结果持久化到 `steam-headers.json`（键匹配改为**按内层 success+data 匹配**，不信任包装键），失败负缓存 1 小时过期。`GameCover` 与 `PlatformAvatarView` 全部走 CoverStore。`ArtworkCache`（常规设置缓存管理）的统计与清除已并入 covers 目录。行为：重进页面秒显、DragonSword 类游戏成功解析、缓存清除一并生效。

### 平台页大改版（2026-09-25，grill-me 拷问式设计后实施）

经三轮拷问确认共识后实施。删页头冗余：先删 eyebrow"平台连接"+副标题，后进一步**移除平台页内容区的大标题**（导航栏已有同名标题，重复；PageShell 加 `showsHeading` 参数，三个平台页关闭，常规设置保留原头部）。新增内容全部参考小黑盒 Switch 页截图：

**头部行**：平台头像（新）+ 昵称 + 最近同步时间；右侧"立即同步"按钮 + "⋯"菜单（重新登录/更换账号或密钥）。
- 头像来源：Steam=GetPlayerSummaries avatarfull（已有）；Nintendo=账号 profile 的 `iconUri`（Mii 图，与昵称同一请求，实测可用）；PSN=profile2 `avatarUrls`，**按 onlineId 二次请求才有**（对 "me" 不返回），默认头像走 http、已升级 https 过 ATS。拿不到回退平台 logo 色块。

**统计行**（StatsRow）：Steam=等级/总时长/游戏数；Nintendo=总时长/游戏数；PSN=等级/总时长/游戏数/完成率。
- Steam 等级：`IPlayerService/GetSteamLevel/v1`，参数是 **steamid 单数**（写成 steamids 会静默失败）。
- PSN 等级：`trophy/v1/users/me/trophySummary`（me 可用），同时给四色奖杯计数。
- PSN 完成率（用户定义 B 口径）：`trophy/v1/users/{accountId}/trophyTitles` 全列表求和 earned÷defined（**该端点不认 me，必须用数字 accountId**，accountId 从 trophySummary 响应取；列表响应的键是 `trophyTitles` 而非 `titles`）。实测 192/1229=15.6%。
- PSN 四色奖杯行：TrophyCountRow，SF Symbols `trophy.fill` 染白金/金/银/铜四色。

**游戏列表**（GameListPanel + 各平台行，LazyVStack，按各平台排序）：
- 列表统一标题"我的游戏 · N"+ 各自列头。
- Nintendo：封面 | 名字/总时长堆叠 | 两周内 | 上次游玩。两周内从 `play_histories` 的 `recentPlayHistories[].dailyPlayHistories` 按日求和（14 天窗口，prefix(10) 字符串比较日期），列 `NintendoGame.fortnightMinutes`。排序：两周内 desc → 上次游玩 desc → 总时长 desc。
- Steam：横幅封面（header.jpg，Q12 用户选原生横幅；仍走 appdetails 哈希兜底）| 名字/总时长 | 两周内 | 上次游玩 | 成就（"2/53"）。成就懒加载：`ISteamUserStats/GetPlayerAchievements` 每游戏一请求，`SteamAchievementStore` actor + 磁盘缓存 24h（achievements.json）；steamID 从 GetPlayerSummaries 存进 `SteamPlayer.steamID`。
- PSN：方形封面（原生 1024×1024）| 名字 | **奖杯数（四色迷你图标+数量：白金/金/银/铜，TrophyPalette 与账号行同色）** | 奖杯进度% | 游戏时长。排序：上次游玩 desc → 总时长 desc。逐游戏奖杯：`trophy/v1/users/me/titles/trophyTitles?npTitleIds={titleId}`（gamelist 的 titleId 与奖杯 npCommunicationId 无直接键，PSNAWP 同款按 titleId 查询方案），`PSNTrophyStore` actor + 24h 磁盘缓存（psn-trophies.json），Entry 含四色计数（缓存格式变更会整体失效重取一次），查无奖杯缓存 0。四色小图标横向排布，列宽 136pt。**对齐规则（用户要求）：三个列表的列头与数值全部左对齐**（GameListPanel 列头 frame 改 leading，各行列值同步改）；四色奖杯用固定槽位防串行——按各层级合理位数预留宽度（白金 1 位 7pt、金/银 2 位 13pt、铜 3 位 19pt，超出 minimumScaleFactor 缩放），保证每行同类型奖杯垂直对齐。
- 紧凑时长格式：≥1h 取整"41 小时"，<1h 一位小数"0.6 小时"，<3 分钟"0"；统计行 totalHours 一位小数千分组。

调参记录：PSN 头像/完成率调试用了临时 debug-psn.log 诊断（已拆除），教训：us-prof 旧端点对 me 和对 onlineId 的返回字段集不同；trophy 端点族对 me/数字 id 的接受度不一致，盲猜不如记状态码。

### 拼图背景（2026-09-25，灵感：社区"游戏拼图"）——**已按用户决定从界面撤下，代码保留**

用户提出总览背景不要被单一平台垄断，采用小黑盒式"游戏拼图"思路：所有平台 Top 游戏封面按时长加权拼成方块画布，模糊压暗后铺底。实现于 `Hourcade/App/MosaicBackdrop.swift`（在 app target 编译，**未接线**）：

- `MosaicSource`：总览 = 三平台各 Top8（24 块）；平台页 = 该平台 Top12。权重 = `pow(分钟, 0.55)`，份额钳制在 2%–20% 再归一，防止单块垄断/消失。
- `MosaicCanvas`：行式 treemap（贪心并行使最差长宽比最优）→ `NSBitmapImageRep` 离屏绘制（y 轴翻转让大块在顶部）→ `CIGaussianBlur` 半径 6、方块间 3px 缝（用户反馈 19 模糊到无法辨认；6 时封面可辨识、格子感清晰，浅色 scrim 兜住文字对比度）。纯函数跑在 `Task.detached`，CGImage 进出（Sendable 安全）。
- `MosaicBackdropView`：`.background` 铺底 + 随 colorScheme 切换的 scrim（深色黑 0.52→0.74，浅色白 0.52→0.72 渐变）；内存缓存按"游戏 id 集合"签名，同步后集合变化自动重拼；失败/未连接回退纯渐变。
- 封面下载走独立 `mosaic-` 缓存命名空间（`mosaic-steam-<id>` 等），不污染小组件管线；Steam 用 library_600x900、Nintendo 用 payload imageUrl、PSN 用 gamelist imageURL，首次下载后落盘复用。
- 接线：`PageShell` 加可选 `backdrop:` 参数（三平台连接页传各自拼图，常规设置无背景）；总览在 `.navigationTitle` 前挂 `.background(MosaicBackdropView(...))`。
- 验收：两轮窗口截图（模糊 19 → 用户反馈"什么都看不清" → 模糊 6 方块可辨，但整体效果仍不满意）。
- **最终决定（用户）**：撤下页面背景；思路保留，未来桌面小组件可能用到。`MosaicSource`（选图）与 `MosaicCanvas`（行式 treemap + 离屏渲染 + CI 模糊）是可复用入口，做组件拼图时需把文件迁到 Shared/组件 target。

### 侧边栏图标与对齐（2026-09-25）

- 总览图标 `square.grid.2x2.fill` → `gamecontroller.circle`（用户指定手柄状图标）。
- 对齐修复：平台行原是 27pt 彩色 logo 的自定义 `HStack`，总览/常规设置/组件预览行是 `Label`（SF 符号默认 ~16pt，缩进由系统样式决定），两种结构的图标列宽度与起点不一致。修复：全部行统一走 `ContentView.sidebarRow(_:)`——图标列固定 27×27（`SidebarMark` 把 SF 符号 17pt 居中放进同尺寸框），文字起点与行高全列一致。
- 验收：窗口截图核对（`screencapture -l <windowID>`，未抢前台）。

### 近期游玩两项修复（2026-09-25）

**斯普拉顿显示"一个月前"**：不是显示逻辑错，是旧快照缺 `lastPlayedAt` 时回退到了 `firstPlayedAt`（首次游玩时间）。znej v2.0 返回确认含 `lastPlayedAt`（对照独立项目 [nscard](https://github.com/ChengChung/nscard) 的同一端点解析器）。**根因是 Nintendo/PSN 不随启动自动刷新**，数据停在用户上次手动同步。修复：`syncAll` 拆出 `refreshNintendo()` / `refreshPlayStation()`，启动 `.task` 在 Steam 刷新后依次调用三平台刷新 + `cachePlatformArtwork()`（已有文件存在跳过逻辑，无重复下载成本）。实测启动后 82 款 Nintendo 游戏 `lastPlayedAt` 全部落库。

**Steam 封面加载不出来（如 Kingdom Rush 6: Genesis TD、DragonSword : Awakening）**：这类 2023 素材迁移后上架的游戏在固定路径 `/steam/apps/{id}/` 下**所有素材 404**（capsule/header/library 全部），真身是带哈希段的 `store_item_assets/steam/apps/{id}/{hash}/header.jpg`，无法拼接，只能通过 `appdetails?appids={id}&filters=basic` 的 `header_image` 拿到（游戏本体仍在商店，appdetails 正常）。修复：`OverviewView.GameCover` 三级兜底链——`library_600x900` → `header.jpg` → `appdetails` 解析 `header_image`（每游戏仅一次查询，进程内缓存命中/未命中两个表）；Nintendo/PSN 封面仍直连 CDN（未报告问题）。加载改用 `URLSession.shared`（吃 URLCache），替换原 `AsyncImage`。

**Steam 封面模糊（如 MONSTER HUNTER RISE）**：首版兜底链第一级是 `capsule_184x69`（69px 高），Retina 下 56pt 方块（112px）放大裁切必然糊。2023 前上架的游戏都有 Valve 2019 年给全目录生成的竖版库素材 `library_600x900.jpg`（600×900，实测 MHR 与老游戏均 200），已把它设为第一级，`header.jpg`（460×215）为第二级，`capsule_184x69` 从链中移除（可用性被 header 完全覆盖）。

### 缓存管理（常规设置，2026-09-25）

- `SteamWidgetStore` 新增 `artworkDirectory` 访问器（App Group `<team>.dev.acerola.Hourcade/Artwork/`，全部为 `.jpg`；该容器受 TCC 保护，终端无法直读，只能由应用读写）。
- `AccountDashboard.swift` 新增 `ArtworkCache`：`usage()`（后台 Task.detached 遍历目录求字节/文件数）与 `clear()`（删除全部 `.jpg`，后台执行）。
- `GeneralSettingsView` 加第三个面板"缓存"：行内显示"封面图片"占用（`ByteCountFormatter` + "N 张图片"）与"清除"按钮；为 0 时按钮禁用，清除中显示 ProgressView；清除后 `reloadAllTimelines()` 让小组件立即回退渐变占位。封面在下次同步或启动时自动重新下载（`cachePlatformArtwork`/`cacheArtwork` 均有已存在跳过逻辑）。
- 本地化 +6 条（缓存/封面图片/清除/计算中…/占用格式/N 张图片），134 → 140 条。

### 调查证据

- [nxapi 要求与会员说明](https://github.com/samuelthomas2774/nxapi/blob/main/README.md#do-i-need-a-nintendo-switch-online-membership)
- [Nintendo Account OAuth 与交换](https://github.com/samuelthomas2774/nxapi/blob/47c9d35/src/api/na.ts)
- [网页授权回调处理](https://github.com/samuelthomas2774/nxapi/blob/47c9d35/src/app/main/na-auth.ts)
- [Coral 3.5.0 登录与加密调用](https://github.com/samuelthomas2774/nxapi/blob/47c9d35/src/api/coral.ts)
- [PlayLog 数据定义](https://github.com/samuelthomas2774/nxapi/blob/47c9d35/src/api/coral-types.ts)
- [CLI 活动映射](https://github.com/samuelthomas2774/nxapi/blob/47c9d35/src/cli/nso/play-activity.ts)
- [第三方服务终端用户披露](https://github.com/samuelthomas2774/nxapi-znca-api/blob/docs/docs/end-user-help.md)
- [服务客户端认证](https://github.com/samuelthomas2774/nxapi-znca-api/blob/docs/docs/api-auth.md)
- [服务使用条款](https://github.com/samuelthomas2774/nxapi-znca-api/blob/docs/docs/public-api-terms.md)
- [服务当前配置](https://nxapi-znca-api.fancy.org.uk/api/znca/config)与[状态页](https://nxapi-status.fancy.org.uk)
- [独立维护的 s3si.ts](https://github.com/spacemeowx2/s3si.ts#authentication)：同样依赖当前加密链路，重点是 SplatNet，不是无依赖的通用游戏库方案。

## 6. PSN 调查与本轮验收边界

已直接核对 [psn-api 的按用户游戏列表实现](https://github.com/achievements-app/psn-api/blob/main/src/user/getUserPlayedGames.ts)及其[返回模型](https://github.com/achievements-app/psn-api/blob/main/src/models/user-played-games-response.model.ts)：查询 `gamelist/v2/users/{accountId}/titles` 需要 bearer token，本人可用 `me`；支持分页，返回图片、最后游玩时间和 ISO 8601 累计 duration。

按 Online ID 搜索也需要已认证会话；用户观察到别的软件只输入 ID，**不证明它匿名访问 Sony，也不能推断小黑盒的具体实现**。本项目采用用户自行登录后查询的路线，不使用共享陌生账号、窃取令牌或绕过隐私权限。私有/受限列表必须报清楚错误，不能显示“零游戏”伪装成功。

PSN 游戏列表是已玩记录，不是拥有的库；不提供首次连接前近 14 天历史。本轮代码仍在完善，Sony 网页回调、令牌刷新、真实账号游戏获取与写入组件，均需分别验收。系统网页能打开不算这些步骤全部通过。

## 7. 本轮（2026-09-24 第二轮）实施进度

上一轮 Agent 余额耗尽，本轮接续整合并修复构建错误。

### 已完成

1. **价格 A 方案彻底移除。** `AggregateStyle.hero` 枚举值、`HeroAggregateCard`、`GlassPlatformCompact`、`catalogValueYuan`/`hasCatalogValue` 字段全部删除。组件注册从 10 个减至 8 个（A2/B/C/D 各一个真实版 + 一个演示版）。
2. **中英文本地化框架。** 新增 `Localization.swift`（`AppLanguage` 枚举、`L10n.tr/format/widget` 查找函数）；新增 `App.xcstrings`（sourceLanguage `zh-Hans`，~113 条双语）和 `Widgets.xcstrings`（~75 条双语）。主应用 `HourcadeApp.swift` 加入 `.environment(\.locale, L10n.locale)` 和 `Settings { LanguageSettingsView() }`。所有组件与主应用的用户可见字符串已切换到 `L10n` 调用。
3. **高清游戏图片。** `SteamAPI.swift` 新增 `ArtworkKind`（hero/cover/avatar/header）、`ArtworkJob`、`storeDetails()` 接口；`cacheGameArtwork()` 按优先级尝试 `library_hero.jpg` → `library_600x900_2x.jpg` → `appdetails` 截图 → `header_image`。`AggregateCards.swift` 的 `GameArtwork` 按 Role 区分 hero（1920px）和 cover（900px），`WidgetImages.load()` 用 `CGImageSource` 降采样。
4. **PSN 登录加固。** `PSNAPI.swift` 重写：加入 `state` 参数校验、`authorizationCode(from:expectedState:)` 回调验证、`saveRefreshToken` 在 profile 请求前写入钥匙串、ISO 8601 duration 解析器（支持天/时/分/秒）、分类错误（`expiredSession`/`privateLibrary`/`rateLimited` 等）、`StopRedirect` 代理阻止跨域 cookie。`PSNWebLogin.swift` 重写：`activeAttemptID` 防并发、`prefersEphemeralWebBrowserSession = true`、取消处理。
5. **共享数据模型整合。** 新增 `PlatformSnapshots.swift`，将 `PSNGame`/`PSNLibrary`/`PSNSnapshot`/`NintendoGame`/`NintendoSnapshot` 从各自的 API 文件移出；新增 `WidgetSnapshots` 和 `WidgetSnapshotStore` 用于 App Group 持久化。
6. **构建修复。** `L10n.defaults` 加 `nonisolated(unsafe)` 解决 Swift 6 `UserDefaults` 非 Sendable 错误；`AccountDashboard.swift` 移除不存在的 `PSNAPI.cacheArtwork` 调用；PSN `onSynced` 回调加 `await`。
7. **安装。** Debug 签名构建成功，已复制到 `/Applications/Hourcade.app`（build 2 之后，未更新 `CURRENT_PROJECT_VERSION`）。

### 崩溃修复（2026-09-25 凌晨）

用户报告 PSN 登录"网页摆着没反应，点叉关闭后主窗口也一起消失"。已定位为**同一处崩溃**，非两个问题：

- 崩溃报告 `~/Library/Logs/DiagnosticReports/Hourcade-2026-09-24-235728.ips`：`EXC_BREAKPOINT / SIGTRAP`，故障队列 `com.apple.NSXPCConnection.m-user.com.apple.SafariLaunchAgent`，栈为 `ASWebAuthenticationSession _endSessionWithCallbackURL:error:` → 完成回调闭包 → `swift_task_checkIsolatedSwift` → `_dispatch_assert_queue_fail`。
- 根因：`PSNWebLogin` 是 `@MainActor` 类，传入 `ASWebAuthenticationSession` 的完成闭包未标注 `@Sendable`，被 Swift 6 推断为 **MainActor 隔离**；系统在 Safari 的 XPC 后台队列上调用它，隔离断言失败并杀掉整个进程。因此登录成功/取消两条回调路径都会崩，表现为"网页无反应"与"关窗口应用消失"。
- 修复：`PSNWebLogin.swift` 的完成闭包加 `@Sendable`（变为 nonisolated），闭包体内原有的 `Task { @MainActor }` 负责跳回主线程。SWIFT 6 编译器证据：不加 `@Sendable` 时闭包内直接访问 MainActor 属性可编译（即被隔离）；加 `@Sendable` 后编译器报 `main actor-isolated property can not be mutated from a Sendable closure`。
- 端到端验证：同 `ASWebAuthenticationSession` 形态的预置工程，修复前退出码 **133（SIGTRAP）** 且无输出；修复后成功回调 `com.scee.psxandroid.scecompcall://redirect?...` 退出码 0。真实应用内：点"使用 PlayStation 账号登录"→ Safari 打开 Sony 授权页 → **关闭该窗口，应用存活**（无新崩溃报告），界面显示"已取消 PlayStation 登录"。
- 附带结论：`callbackURLScheme` 初始化参数已足以接收回调，**无需在 Info.plist 注册 URL scheme**（已用本地 302 重定向实测）。

### PSN Online ID 输入框删除（2026-09-25）

用户指出：网页登录本身已确认身份，且留空时 `PSNAPI` 一直用 `accountId = "me"` 查本人，输入框只是"查别人的库"且界面上不存在该场景，因此删除。

- 删除 `PSNSettingsView` 的 `PSN Online ID（留空查询本人）` 输入框、`@State onlineID` 与 `psn.onlineID` 的读写。
- `PSNAPI.load()` 去掉 `onlineID` 参数及 `universalSearch` 按 ID 解析分支，恒用 `me`；删除随之无用的 `PSNError.invalidOnlineID` / `.accountNotFound`、`SearchResult` 系列结构和 404 映射。
- **自动获取本人 Online ID**：新增 `PSNAPI.selfOnlineID()`，用已登录令牌请求
  `GET https://us-prof.np.community.playstation.net/userProfile/v1/users/me/profile2?fields=onlineId`，
  解析 `{profile:{onlineId}}`，仅作显示名（`PSNLibrary.onlineID` → 组件 `playerName`）。失败一律返回 nil、绝不影响同步。
  端点探测记录：该 legacy 端点返回 200；`m.np.../internal/users/me/profiles` 返回 400、`web.np.../basicProfile/v1/profiles/me` 返回 403，均不可用。
- 删除 `App.xcstrings` 三条已无引用的字符串，本地化条目从 139 → 134。
- 验证：登录后 Online ID 自动显示在"已连接的账号"，31 款、212 小时数据正常；磁盘快照 `~/Library/Application Support/Hourcade/psn.json` 的 `library.onlineID` 已是真名。

### PSN 界面精简：移除高级会话方式（2026-09-25）

用户要求界面简洁易懂：登录后不再显示"登录窗口由系统打开…"那段说明，并删除整个"登录遇到问题？高级接入方式"（NPSSO 会话令牌）入口。

- `PSNSettingsView`：那句说明改为仅在 `!hasSavedSession`（未登录）时显示；删除 `DisclosureGroup` 高级接入方式整块、`@State npsso`、`SecureField` 与"使用会话令牌同步"按钮。
- `connect(useBrowser:)` 去掉 `useNPSSO` 参数与 npsso 读取。
- `PSNAPI.load()` 去掉 `npsso` 参数与 NPSSO 换取 access code 的分支；删除只被该分支使用的私有函数 `accessCode(_:session:)`。浏览器登录仍使用 `authorizationURL` / `authorizationCode` / `callbackURLScheme`。
- `.missingSession` 文案由"请先登录 PlayStation 或提供 NPSSO 会话令牌"改为"请先登录 PlayStation 账号"。
- 删除 `App.xcstrings` 中随之无引用的 6 条字符串（Sony 会话页面、NPSSO 提示、高级接入方式等），本地化条目 134 → 127。
- 验证：已登录状态下 PlayStation 页仅剩"已连接的账号 / 账号昵称 / 最近同步 / 立即同步 / 重新登录"，无小字、无高级入口；构建通过。

### 已知风险与待验证

- **PSN `saveRefreshToken` 未接线。** `PSNAPI.load()` 的 `saveRefreshToken` 回调参数在 `AccountDashboard` 侧未传递，当前靠调用方在 `PSNAPI.load()` 返回后自行写钥匙串（`AccountDashboard.swift:592`）。如果 `PSNAPI.load()` 内部在 profile 请求前就调用 `saveRefreshToken`，该闭包是 `nil`，不会崩溃但也不会提前保存。需要确认 `PSNAPI.load()` 的实际签名和调用约定。
- **xcstrings sourceLanguage。** `App.xcstrings` 的 `sourceLanguage` 是 `zh-Hans`，但 `L10n.tr()` 用 `Bundle.main.path(forResource: language.rawValue, ofType: "lproj")` 查找 `.lproj` 目录。Xcode 会从 `.xcstrings` 自动生成 `.lproj`，但需要验证 `zh-Hans.lproj` 和 `en.lproj` 都在 Copy Resources 阶段。
- **Nintendo 编译。** `NintendoGame`/`NintendoSnapshot` 已移到 `PlatformSnapshots.swift`，`NintendoCLI.swift` 只保留 CLI 调用。`NintendoSettingsView.onSynced` 签名是 `([NintendoGame]) throws -> Void`，与移动前的类型一致，但需确认 `NintendoCLI.load()` 返回类型匹配。
- **PSN 游戏图片未缓存到本地。** `PSNAPI` 把 Sony CDN 的 `imageURL` 直接赋给 `PSNGame.imageURL`，但 WidgetKit 扩展无法直接加载网络图片。`GameArtwork` 当前只处理 `steam-` 前缀的本地缓存图片和 bundle 资源。PSN 游戏在组件中会显示占位渐变，直到实现图片下载和缓存。
- **WidgetKit 存档体积。** 高清 hero 图（1920px）和封面（900px）经 `CGImageSource` 降采样后写入 App Group，但 8 个组件（4 真实 + 4 演示）的总存档体积未实测。如果超过 ~11MB 会重现空白画廊问题。
- **语言切换实时性。** `L10n.locale` 是计算属性，每次读取都查 `UserDefaults`。主应用的 `@Environment(\.locale)` 在 `LanguageSettingsView` 改值后是否自动刷新未验证。组件侧在 timeline reload 时读取，30 分钟内不会响应语言切换。

### 需要用户执行的验收步骤

1. **启动应用，检查语言设置。** 打开 Hourcade → 菜单栏 → Settings → 确认有"语言"选项；切换 系统/简体中文/English，确认主应用和组件预览文案跟随变化。
2. **检查组件画廊。** 右键桌面 → 编辑小组件 → 搜索 Hourcade → 确认有 8 个条目（A2/B/C/D 各两个，带"演示"标签的是占位数据）。拖动真实版到桌面，确认显示 Steam 数据、Nintendo/PlayStation 显示平台图标和"尚未连接"。
3. **检查高清图片。** 真实版组件的 Steam 游戏背景是否清晰（不是模糊的 460×215 header）。如果某款游戏仍然模糊，可能是该游戏没有 `library_hero.jpg`，回退到了截图或 header。
4. **测试 PSN 登录。** 在 PlayStation 连接页输入 PSN Online ID → 点击"使用 PlayStation 账号登录" → 系统浏览器打开 Sony 登录页 → 登录并授权 → 回调到 Hourcade → 显示"已连接的账号"和最近同步时间。如果失败，检查错误信息是否清晰（不是"请求失败"这种泛称）。
5. **检查文字截断。** 组件中的游戏名、平台名、时间标签是否完整显示，没有被 `...` 截断。如果有截断，记录具体组件和位置。

## 8. 后续交接检查清单

- [x] 本轮整合构建通过，安装的新 build 与当前源码一致。
- [x] 价格 A 真实版/演示版均移除，A2/B/C/D 保留。
- [x] PSN 登录回调崩溃（MainActor 隔离 SIGTRAP）已修复并端到端验证；取消登录不再导致应用退出。
- [x] PSN 登录后自动识别本人账号，移除多余的 Online ID 输入框；账号名从索尼接口获取。
- [ ] 语言跟随系统、中文、英文在主应用和组件一致，日期/动态文案不混用，无关键文字截断。**（需用户验收）**
- [ ] 高清 hero/封面实测命中；缺图有合理回退；高清条件下 WidgetKit 存档仍可接受。**（需用户验收）**
- [ ] PSN 登录取消、回调错误、刷新失效、隐私限制、分页和成功同步都正确；凭据不进入共享快照。**（需用户验收）**
- [x] Nintendo 界面说明与用户暂缓决定一致，不把第三方授权未完成包装成可测试接入。
- [ ] 更新本文件的已安装版本、实际测试证据和仍需用户执行的步骤。**（验收后更新）**
- [ ] PSN 游戏图片下载到本地缓存，组件可显示真实封面而不是占位渐变。
- [ ] 确认 `PSNAPI.load()` 的 `saveRefreshToken` 回调是否需要在 `AccountDashboard` 侧传递。

正式发布前另需确认签名/公证、平台品牌素材许可、OAuth/非公开接口条款、隐私披露与恢复路径；当前开发证书本机可运行不代表正式分发已完成。
