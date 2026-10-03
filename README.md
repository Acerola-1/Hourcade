# Hourcade

macOS 桌面小组件，把 Steam、Nintendo Switch 和 PlayStation 的游玩数据汇成一张桌面大卡。宿主 App 负责连接账号、同步数据和管理缓存；所有卡片渲染由宿主与 WidgetKit 扩展共享同一套 Swift 6 / SwiftUI 代码。

## 功能

**桌面组件 10 款**

**数据接入**

- Steam：Web API（GetOwnedGames / GetRecentlyPlayedGames / GetSteamLevel / GetPlayerSummaries），Web API Key 存本机钥匙串
- Nintendo Switch：My Nintendo / Nintendo Store App 通道（OAuth + PKCE 浏览器登录），近 14 天时长来自官方每日记录
- PlayStation：PSN 浏览器登录（OAuth），累计时长 + 账号级奖杯；单游戏奖杯按行懒加载
- 启动即自动刷新所有已连接平台；任何一页都只读缓存，网络清扫在同步后后台执行

**游戏素材**

- Steam 下载 1920 宽幅英雄图与 600×900 竖版封面；Nintendo 优先使用港服 eShop 官方 1920×1080 横幅（titleId 重定向 → 商品页 JSON-LD），缺失时回退游玩记录方图；PSN 使用 gamelist 自带图片
- 历史上的「游戏价值（参考价值）」价格功能已于 2026-10-03 整体移除，调查记录见 `docs/nintendo-eshop-banner-and-pricing.md`

## 系统要求

- macOS 15 或更高版本

## 开发验证

运行 `bash scripts/check-hero-candidates.sh` 检查 A1 的混合平台优先级、PSN 近期日期排序、1–3 款数量、日期边界和空状态。检查直接编译共享快照模型，使用独立样例，不读取本机账号数据。

## 隐私

Hourcade 默认每天最多上报一次匿名心跳（安装 UUID、App 版本、系统版本、芯片型号、语言），用于了解各版本的装机与留存情况，不含账号信息、游玩数据或任何可识别个人身份的内容。可在「常规设置 → 隐私」中随时关闭，关闭后立即停止上报。
