# 任天堂宽图素材与港服价格：已验证事实与交接说明

- 日期：2026-10-02
- 性质：原文为 **2026-10-02 交接调查，当时未写代码**；2026-10-03 实现与复验情况追加在第六节。
- **2026-10-03 状态更新：价格体系已整体移除**（`NintendoPriceStore` 等三个平台价格仓库、汇率折算、总览/平台页「参考价值」展示全部删除）。本文档保留作溯源；第五节「港服计价重开问题」随功能移除而不再适用。**宽图素材路线（titleId 重定向 → 商品页 JSON-LD → `hero-hd` 缓存）与价格无关，仍在生产使用。**
- 结论速览：`ec.nintendo.com/apps/{titleId}/{country}` 是一个公开、免鉴权的官方 titleId→nsuid 映射；由此可拿到港服 eShop 页面的 **1920×1080 官方横幅**（本库覆盖率 60/82），且港服价格接口对映射出的 nsuid 实测可用。旧结论「不存在公开的 HK/Asia nsuid 数据」被推翻。

---

## 一、背景：A1 大组件背景图为什么裁得难看

A1（`HeroNoValueCard`）的背景 `HeroArtworkBackdrop`（`Hourcade/Shared/AggregateCards.swift`）是：

```swift
GameArtwork(name: role: .hero, maxPixelSize: 1440)
    .scaledToFill()
    .frame(width: size.width, height: size.height)
    .clipped()
```

 Nintendo 管道（`SyncCoordinator.cachePlatformArtwork`）下载的唯一素材是**游玩记录接口返回的正方形图标**（`nintendo-<titleId>.jpg`，512 升 1024）。1:1 图铺进约 1.96:1 的卡片（实测用户桌面截图 1450×739）只露出中间约 51% 的横带，《王国之泪》图标的剑柄/徽章/标题字被拦腰。Steam 没这个问题，因为 `SteamAPI.cacheArtwork` 专门下载了原生宽幅 `library_hero.jpg`（存为 `steam-<appid>-hero-hd`）。

**关键实现事实**：`WidgetImages.load`（AggregateCards.swift 顶部）对 `.hero` 角色的候选名是 `["<name>-hero-hd", "<name>"]`——也就是说，只要把宽幅横幅存成 `nintendo-<titleId>-hero-hd.jpg`，现有 `HeroArtworkBackdrop` 会**自动优先取横幅、自动回退方图标**，视图层零改动即可让映射成功的游戏走全幅裁切。

## 二、已验证事实（全部为 2026-10-02 实测，非转述）

### 2.1 atum 图标 CDN：方形封顶，无宽幅

- 游玩记录接口（港服 `app-api.znej.nintendo.com/api/v2.0/users/me/play_histories`，即 My Nintendo App 接口族，UA `com.nintendo.znej`）每个游戏只有一个图字段 `imageUrl`，指向 `atum-img-lp1.cdn.nintendo.net/i/c/{32位hash}_{size}`。
- 用《王国之泪》真实 hash 实测（hash `6ea2bbe641134135a5f77e419b5178b1`）：`_128 / _256 / _512 / _1024` 与无后缀（=1024）存在，**全部 1:1**；`_64 / _384 / _768 / _2048 / _5120` 均 404。GitHub 全网代码检索（Gemini 复核）：所有真实引用均为 `/i/c/`，无其他命名空间。
- **PSN 同样只有方图**：gamelist 的 `imageUrl` 实测为 1024×1024（剑星、战神验证）。所以「方图兜底构图」的触发条件应是"方形源图"（nintendo + playStation），不是只判 nintendo。

### 2.2 关键发现：官方 titleId→nsuid 重定向

```
curl -sI "https://ec.nintendo.com/apps/0100f2c0115b6000/HK"
→ HTTP/2 307
  location: /HK/zh/titles/70010000063717
```

- `{titleId}` 直接用游玩记录接口里的 16 位十六进制 titleId（大小写均可）。
- **失败形态干净可判定**：未在该区 eShop 上架的 titleId 会 307 到该区 eShop 目录页（HK 为 `https://www.nintendo.com.hk/software/switch/`），不会拿到错误数据。
- `country=US` 时会 307 到域外 `nintendo.com/pos-redirect/{nsuid}`——实现时建议**不要跟随重定向**，直接读 `location` 头并校验其为本域 `/titles/{nsuid}` 形态。

### 2.3 港服 eShop 页 → 1920×1080 官方横幅

请求 `https://ec.nintendo.com/HK/zh/titles/{nsuid}`，页面源码内嵌 schema.org 结构化数据：

```json
{ "@type": "VideoGame", "name": "薩爾達傳說 王國之淚",
  "image": "https://img-eshop.cdn.nintendo.net/i/37349cde8b55828bbdad9d0a62b546c61862c4cb35142a904bd36f222d374e58.jpg" }
```

该图实测 **1920×1080**（11/11 抽样全命中，含全部 3 款 Switch 2 `0400…` 游戏）。建议图片 URL 做 host 白名单（`img-eshop.cdn.nintendo.net`），与代码里 Steam/PSN 的 `isAllowedGameArtworkURL` 同风格；下载后用 ImageIO 验证像素尺寸再落盘，防止把 HTML 错误页存成 .jpg（现有 `downloadAndCache` 不检查 HTTP 状态码，注意）。

### 2.4 覆盖率实测（用户全库 82 款，country=HK）

- **60/82 映射成功**。
- 22 款失败，全部是未上架港服 eShop 的：8 个 Demo、免费网游（Fortnite、Arena of Valor、Eternal Card Game）、NSO 应用（Super NES / NES 应用）、以及 Hades、Blasphemous、Hollow Knight、Dead Cells、Enter the Gungeon、Valiant Hearts、Super Mario Bros. 35、Ori and the Blind Forest、Dragon Quest XI S、Disgaea 4 Demo、Deemo Demo 等。完整清单见附录 A。
- Switch 2 游戏（`0400…` 前缀）映射无障碍。

### 2.5 价格接口对港服 nsuid 实测可用

```
curl -s "https://api.ec.nintendo.com/v1/price?country=HK&lang=zh&ids=70010000063717"
→ sales_status: "onsale", regular_price: HKD 399
```

### 2.6 被推翻的旧结论

- 旧结论（2026-09-25 验证）：「不存在公开的 HK/Asia nsuid 数据源，任天堂价格最多美服覆盖」。当时排查过的 `searching.nintendo-asia.com`、`ec.nintendo.com/HK/search`、tinfoil、NOA json 等确实都不可用，但**漏测了 `/apps/{titleId}/{country}` 这个重定向端点**——它本身就是官方的 titleId→nsuid 映射。
- 影响一（本文档主题）：宽幅横幅可取。
- 影响二（见第五节）：港服计价的技术前提恢复了。

## 三、A1 设计方向（已评估，待最终拍板）

- **主路径**：映射成功的游戏，用 1920×1080 横幅走现有全幅裁切（16:9 对 ~1.96:1 只裁上下合计约 9%，观感对标 Steam 库页头图）。
- **兜底**：未映射的 ~22 款（以及 PSN 方图游戏），落回用户提出的构图：**方图标 contain 完整展示、撑满卡片高度贴左侧**（方图撑满高度时宽度恰为卡片约一半，"完整"与"居左"几何上天然吻合），其余区域用**同一张图的放大模糊铺底 + 主体边缘羽化**做过渡。
- **两个待用户拍板的视觉决策**：
  1. 左半区文字冲突：A1 的「游戏人生」标题（左上）和「总游玩时间 + 大数字」（左下）都压在图标上。倾向方案：压暗渐变改为上下方向为主并整体减淡，两块文字下加薄毛玻璃纱（复用 `HeroGlassBackdrop` 的语言）。
  2. 羽化范围：四边全羽化（TotK 图标底部 "TEARS OF THE KINGDOM" 字样会轻微淡出）vs 仅左右羽化、上下保持完整。
- 注意：5 分钟轮播会在 Steam（全幅宽图）与 Nintendo/PSN（方图构图）之间切换构图，现有 `.transition(.opacity)` 兜底，装好后看实际观感。

## 四、实施指引（给接手的 Agent）

### 4.1 相关代码位置

| 位置 | 作用 |
|---|---|
| `Hourcade/App/SyncCoordinator.swift` `cachePlatformArtwork()` | Nintendo/PSN 封面下载入口，横幅解析应挂在这里 |
| `Hourcade/App/SyncCoordinator.swift` `downloadAndCache(_:named:)` | 通用下载；**不校验 HTTP 状态**，横幅下载需要加强（200 + 尺寸验证） |
| `Hourcade/Shared/AggregateCards.swift` `WidgetImages.load` | `<name>-hero-hd` 优先的候选链，横幅命名正确即自动生效 |
| `Hourcade/Shared/AggregateCards.swift` `HeroArtworkBackdrop` / `HeroGlassBackdrop` | 背景渲染与毛玻璃语言；方图兜底构图改这里 |
| `Hourcade/App/NintendoAPI.swift` | `NintendoGame.titleId`（映射输入）、`NintendoPriceStore`（价格，见第五节） |

### 4.2 建议实现形状

1. **解析缓存落盘**：titleId → (nsuid, bannerURL) 存 JSON（建议放应用组容器或 `Application Support/Hourcade/`），每款游戏只解析一次页面；解析失败的 titleId 也缓存失败态（负缓存），避免每次同步重打 82 个请求。
2. **只解析能上墙的游戏**：沿用 `cachePlatformArtwork` 的可见性口径（墙前 8 + 生涯最爱 + 近期），不要全库跑。
3. **横幅落盘命名**：`nintendo-<titleId>-hero-hd.jpg`（小写 titleId，与现有 artworkURL 字符白名单兼容），下载后验证宽>高再写盘；已存在则跳过（沿用现有幂等语义）。
4. **widget 扩展保持零网络**：解析只发生在主 App 同步流程（既定架构）。
5. **缓存纪律**（既定决定）：页面切换只读缓存，抓取在同步后台跑；请求间加小延时即可（一次性 82 HEAD + 60 页面请求，量很小）。
6. 方图兜底构图（第三节）是独立的视图层改动，与横幅下载互不阻塞。

### 4.3 复验命令（一分钟重跑核心事实）

```bash
# 307 映射（成功 / 失败两种形态）
curl -sI "https://ec.nintendo.com/apps/0100f2c0115b6000/HK" | grep -i location
curl -sI "https://ec.nintendo.com/apps/0100646009fbe000/HK" | grep -i location   # Dead Cells → 目录页

# 页面 ld+json 取图
curl -s "https://ec.nintendo.com/HK/zh/titles/70010000063717" | grep -o '"image":"[^"]*"'

# 尺寸验证
curl -s -o /tmp/banner.jpg "https://img-eshop.cdn.nintendo.net/i/37349cde8b55828bbdad9d0a62b546c61862c4cb35142a904bd36f222d374e58.jpg" && sips -g pixelWidth -g pixelHeight /tmp/banner.jpg

# 港服价格
curl -s "https://api.ec.nintendo.com/v1/price?country=HK&lang=zh&ids=70010000063717"
```

用户本机可读的输入数据：`~/Library/Application Support/Hourcade/nintendo.json`（含全部 titleId 与 imageUri）。注意：应用组容器 `~/Library/Group Containers/<TEAM>.dev.acerola.Hourcade/` 对 Agent shell 是 TCC 隔离的，无法直接 ls。

### 4.4 PSN 侧的潜在后续线索（未验证，勿直接采信）

PSN 概念接口（app 已存 `conceptId`）的 `concept.media.images` 里据社区文档存在 `FOUR_BY_THREE_BANNER` 等横幅类型。若要给 PSN 也补宽图，从这条路查起；本文档不对其真实性背书。

## 五、港服计价重开问题（未决，等用户拍板）

- **事实变化**：当年美服计价基准的前提是「HK 查询返回零结果」（用户原话「选 A 呗」）。根因是没有 titleId→nsuid 映射；该前提已于 2026-10-02 失效（见 2.5）。
- **现状**： Nintendo 计价仍为美服（`NintendoAPI.swift` 中 `titledbURL = blawar/titledb US.en.json`，`queryCountry = "US"`，映射 7 天缓存、价格 24 小时缓存）。
- **这是一个已定决定，未被用户重开**。接手 Agent **不得擅自实现港服计价**；如用户明确提出重开，技术上是替换映射来源（307 端点替代/补充 titledb）+ `queryCountry` 改 HK + 走既定的 CNY 换算显示（参考价显示规则与「参考价值」措辞等既有约定不变）。

## 六、2026-10-03 实现与复验

- 已实现 `NintendoArtworkStore`，仅由宿主同步流程调用，选择平台墙前八、A1 近期候选、生涯最爱与平台 showcase，按 titleId 去重，不遍历全库。大小写统一为小写缓存名。
- 重定向不自动跟随，仅接受官方域名、对应地区/语言、14 位 nsuid 商品路径；从 JSON-LD 的 `VideoGame.image` 取图，支持数组、`@graph` 和 `ImageObject`。图片 host 限定 `img-eshop.cdn.nintendo.net`。
- 下载须 HTTP 200、≤8 MiB、可解码，宽≥1280、高≥400、宽>高且两维≤8192 才原子落盘；不会把 HTML 或方图误存为 `hero-hd`。Nintendo/PSN 通用图标下载也增加 HTTP 和图像解码校验。
- 解析结果保存在 `Application Support/Hourcade/nintendo-artwork.json`。确定未上架缓存 7 天；网络、页面结构或图片失败退避 1 小时；成功 URL 缓存 30 天。已存在且有效的宽图不发请求；图片缺失时复用 URL，缓存损坏时重新下载。失败不影响账号同步。
- 用户本次选定方图兜底：完整方图靠左、同图模糊延展、保持文字布局。`HeroArtworkScene` 按实际宽高比（<1.3）触发，PSN 方图同样适用；仅右缘 4% 过渡，上下保持完整。毛玻璃栏共享同一坐标与构图。宽幅图片继续全幅裁切。
- 追加线索：同一 titleId 的 Hades、Dead Cells 在日服能映射 nsuid，但 `/JP/ja/titles/{nsuid}` 随后 307 到 `store-jp.nintendo.com`，当前没有完成可用横幅验证。**生产实现只使用已复验的港服路径**，日服仅是后续调查线索。计价实现未改动。
- 实际联网跑生产下载器：王国之泪（`0100f2c0115b6000`）、超级马里奥 奥德赛（`0100000000010000`）、旷野之息（`01007ef00011e000`）均取得并验证 1920×1080 宽图。没有重新核验全库 60/82 的覆盖率；该数字仍属 10-02 调查结果。
- 验证入口：`bash scripts/check-nintendo-artwork.sh`（33 项解析/缓存场景）；加 `--live` 验证上述三款实际下载。既有 `check-hero-candidates.sh` 的 23 项场景通过。宿主与 Widget 的 Debug 构建通过。
- [官方宽图构图预览](nintendo-artwork-preview/official-wide-backdrop.png) / [方图兜底构图预览](nintendo-artwork-preview/square-fallback-backdrop.png)：来自生产 `HeroArtworkBackdrop` 的离屏 SwiftUI 渲染，使用官方素材、仅展示背景构图，**不是用户桌面 Widget 截图**。完整组件另外检查了 0/1/3 近期候选的离屏布局；桌面实际显示及轮播仍待安装后验收。
- [Hades 完整 A1 方图兜底截图](nintendo-artwork-preview/hades-a1-square-fallback-screenshot.png)：2026-10-03 再次请求港服映射，确认重定向到目录页；游玩记录对应官方图片为 1024×1024。截图来自实际运行的独立原生预览窗口，直接复用生产 `AggregateCard(.heroNoValue)` 和资源/翻译表，测试缓存只有方图、没有任何 `hero-hd`。窗口使用隔离缓存与明确标注的演示统计，没有修改用户账号快照或安装中的 App。用于验收完整构图，含文字、近期封面框、底部平台栏；不是 WidgetKit 桌面时间线运行截图。

## 附录 A：22 款未映射港服 eShop 的游戏（307 → nintendo.com.hk/software/switch/）

```
0100535012974000 Hades
0100698009c6e000 Blasphemous
010036f0182c4000 Sea of Stars Demo
01009d60076f6000 Enter the Gungeon
0100bef013050000 MONSTER HUNTER RISE DEMO Version2
0100206010406000 BRAVELY DEFAULT Ⅱ Final Demo
010099700b01a000 Valiant Hearts: The Great War
0100277011f1a000 Super Mario Bros. 35
0100b6801137e000 BRAVELY DEFAULT Ⅱ Demo ver.
010096000b3ea000 OCTOPATH TRAVELER Prologue Demo
01008d300c50c000 Super Nintendo Entertainment System (NSO)
0100d870045b6000 Nintendo Entertainment System (NSO)
0100633007d48000 Hollow Knight
01002120116c4000 Splatoon 2: Special Demo 2020
010025400aece000 Fortnite for Nintendo Switch
01008d8006a6a000 Arena of Valor
0100f0b00a214000 Eternal Card Game
010068c00f324000 Disgaea 4 Complete+ Demo
010005800f46e000 Ori and the Blind Forest: Definitive Edition
010026800ea0a000 DRAGON QUEST XI S: Echoes of an Elusive Age
0100dd100ae8c000 Deemo Demo
0100646009fbe000 Dead Cells
```

## 附录 B：参考链接

- nxapi 社区文档（重定向端点的公开出处）：https://github.com/samuelthomas2774/nxapi/blob/main/src/discord/titles/README.md
- 港服 eShop 页面示例：https://ec.nintendo.com/HK/zh/titles/70010000063717
- My Nintendo 接口族社区记录（play_histories 响应结构）：https://github.com/CafeAuLait-CC/NSPlayTime
- atum CDN 社区记录：https://github.com/PretendoNetwork/nintendo-wiki-gh-pages/blob/master/docs/servers.md
