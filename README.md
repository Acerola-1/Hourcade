# Hourcade

macOS 桌面小组件，把 Steam、Nintendo Switch 和 PlayStation 的游玩数据汇成一张桌面大卡。宿主 App 负责连接账号、同步数据和管理缓存；所有卡片渲染由宿主与 WidgetKit 扩展共享同一套 Swift 6 / SwiftUI 代码。

## 功能

**桌面组件 10 款**

**数据接入**

- Steam：Web API（GetOwnedGames / GetRecentlyPlayedGames / GetSteamLevel / GetPlayerSummaries），Web API Key 存本机钥匙串
- Nintendo Switch：My Nintendo / Nintendo Store App 通道（OAuth + PKCE 浏览器登录），近 14 天时长来自官方每日记录
- PlayStation：PSN 浏览器登录（OAuth），累计时长 + 账号级奖杯；单游戏奖杯按行懒加载
- 启动即自动刷新所有已连接平台；任何一页都只读缓存，网络清扫在同步后后台执行

**游戏价值（参考价值）**

- Steam 走商店 appdetails（国区优先、港服补缺，2.5s/次限速）；PSN 走匿名商店 GraphQL（chihiro 旧接口兜底）；Nintendo 走美区 eShop 价格（nsuid 映射来自社区 titledb，7 天缓存）
- 查询区固定港服（库存覆盖 92%），展示货币固定人民币，按当日汇率（er-api，frankfurter 备用）折算；所有价格磁盘缓存 24 小时

## 系统要求

- macOS 15 或更高版本

## 隐私

Hourcade 默认每天最多上报一次匿名心跳（安装 UUID、App 版本、系统版本、芯片型号、语言），用于了解各版本的装机与留存情况，不含账号信息、游玩数据或任何可识别个人身份的内容。可在「常规设置 → 隐私」中随时关闭，关闭后立即停止上报。
