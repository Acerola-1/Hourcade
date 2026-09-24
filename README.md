# Hourcade

面向 macOS 15+ 的游戏游玩数据桌面小组件 Demo，使用 Swift 6、SwiftUI 和 WidgetKit。

## 现在可以体验的内容

- 以最后一张 A–D 总览图为起点实现**超大号**聚合布局：A 英雄封面、A2 无金额版、B 数据概览、C 平台分栏、D 横向游戏墙。A 与 A2 已按后续需求改版。
- A 固定展示全部时间的总时长、各平台时长与占比，以及全局游戏数、当前标价合计和价值占比。A2 沿用同一背景选择逻辑，参考新的 Game Life 截图布局，只显示游玩时长、游戏数和平台占比，不显示任何金额。
- A 与 A2 的大图右侧共用近期游戏信息，展示游戏名、平台和该游戏近 14 天的游玩时长；底栏右侧只显示近 14 天总时长。底栏使用一整块圆角毛玻璃：取当前背景插画的对应区域模糊，再叠半透明中性色；栏内只用细分隔线，不使用外描边。
- A 与 A2 的背景从近 14 天游玩时长最高的五款游戏中随机切换，不连续重复。没有近期游玩的平台不会进入候选；三个平台都没有近期游玩时，使用全部时间游玩最久的一款游戏。宿主预览每 8 秒交叉淡入；WidgetKit 通过每 30 分钟一条的随机时间线轮换，实际刷新时间由系统决定。
- 宿主 App 中还有“早期探索稿”一栏，保留此前制作的四种视觉实验，供后续比较和取材。WidgetKit 扩展注册的是五种主方案布局。
- 画面使用项目内的原创演示插画、虚构游戏名与模拟游玩数据，界面以 `DEMO` 标识。

打开 `Hourcade.xcodeproj`，选择 **Hourcade** scheme，运行 macOS App。在“主方案”和“早期探索稿”之间切换，再点击 A、A2、B、C、D 查看各方案。当前只制作超大号；早期探索稿由 `ExplorationCard` 保存在宿主 App 中。

## 开发

使用支持 Swift 6 的 Xcode 打开工程。最低部署目标是 macOS 15。命令行编译：

```sh
xcodebuild -project Hourcade.xcodeproj -scheme Hourcade -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

目前没有账号连接、平台数据采集、自动同步或游戏数据库。近 14 天数据、游戏插画与当前标价合计均为演示数据；真实平台接口是否能提供游玩时间、完整游戏库与价格仍需分别验证。发布前还需确定正式 App 名称、bundle ID、签名团队与 App Group；当前名称 `Hourcade` 和 bundle ID `dev.acerola.Hourcade` 是占位值。
