# Hourcade

面向 macOS 15+ 的游戏游玩数据桌面小组件 Demo，使用 Swift 6、SwiftUI 和 WidgetKit。

## 现在可以体验的内容

- 宿主 App 默认打开“总览”：已连接平台的累计时长、游戏记录数、各平台状态，以及 Steam 近两周游玩都显示在这里。左侧选择 Steam、Nintendo Switch、PlayStation 进行连接；“组件预览”会在独立窗口打开原有设计稿，A、A2、B、C、D 和早期素材均保留。
- Steam：首次连接页内有获取个人资料链接和 Web API Key 的两步说明。连接后只显示账号、密钥已保存状态与最近同步时间；不会留下空密码框。使用官方 GetOwnedGames / GetRecentlyPlayedGames 同步，Key 保存在本机钥匙串，数据保存在本机 Application Support，重开 App 会自动刷新。
- Nintendo Switch：普通账号连接仍在适配中。已有 nxapi 的用户可展开实验性入口，调用本机已登录的 nxapi CLI 读取 NSO PlayLog。nxapi 使用非公开接口，登录默认依赖第三方认证辅助服务；此项目没有嵌入或改写 nxapi 的 AGPL 代码。
- PlayStation：账号页提供系统网页登录入口，使用 [psn-api](https://github.com/achievements-app/psn-api) 研究出的非公开 OAuth 请求流程；如失败，仍有高级 NPSSO 会话入口。两种方式都需要 Online ID，刷新令牌存本机钥匙串。网页登录尚未用真实 PSN 账号验证，可能因 Sony 更新而失败。**仅有 PSN ID 不足以调用接口。**

- 以最后一张 A–D 总览图为起点实现**超大号**聚合布局：A 英雄封面、A2 无金额版、B 数据概览、C 平台分栏、D 横向游戏墙。A 与 A2 已按后续需求改版。
- A 固定展示全部时间的总时长、各平台时长与占比，以及全局游戏数、当前标价合计和价值占比。A2 沿用同一背景选择逻辑，参考新的 Game Life 截图布局，只显示游玩时长、游戏数和平台占比，不显示任何金额。
- A 与 A2 的大图右侧共用近期游戏信息，展示游戏名、平台和该游戏近 14 天的游玩时长；底栏右侧只显示近 14 天总时长。底栏使用一整块圆角毛玻璃：取当前背景插画的对应区域模糊，再叠半透明中性色；栏内只用细分隔线，不使用外描边。
- A 与 A2 的背景从近 14 天游玩时长最高的五款游戏中随机切换，不连续重复。没有近期游玩的平台不会进入候选；三个平台都没有近期游玩时，使用全部时间游玩最久的一款游戏。宿主预览每 8 秒交叉淡入；WidgetKit 通过每 30 分钟一条的随机时间线轮换，实际刷新时间由系统决定。
- 宿主 App 中还有“早期探索稿”一栏，保留此前制作的四种视觉实验，供后续比较和取材。WidgetKit 扩展注册的是五种主方案布局。
- 画面使用项目内的原创演示插画、虚构游戏名与模拟游玩数据，界面以 `DEMO` 标识。

打开 `Hourcade.xcodeproj`，选择 **Hourcade** scheme，运行 macOS App。在侧栏选择平台进行配置，或点击“组件预览”打开设计窗口。当前只制作超大号；早期探索稿由 `ExplorationCard` 保存在宿主 App 中。

## 开发

使用支持 Swift 6 的 Xcode 打开工程。最低部署目标是 macOS 15。命令行编译：

```sh
xcodebuild -project Hourcade.xcodeproj -scheme Hourcade -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

Steam 已用真实账号完成一次成功同步并核对了总览呈现；启动自动刷新曾遇到一次网络超时，手动重试成功，失败时保留上次数据。Nintendo 与 PSN 尚未用真实账号做端到端验证，也没有定期后台同步或将真实结果写入 WidgetKit。小组件中的近 14 天数据、游戏插画与当前标价合计仍为演示数据。Nintendo NSO PlayLog 不提供逐游戏近 14 天时长；需要另外接入家长控制每日摘要。PSN 接口仅提供累计时长，近 14 天数据需要从持续保存的快照计算。三平台的当前标价合计都需要独立价格来源、地区与版本匹配。发布前还需确定正式 App 名称、bundle ID、签名团队与 App Group；当前名称 `Hourcade` 和 bundle ID `dev.acerola.Hourcade` 是占位值。
