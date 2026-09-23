# ToolIsle 与 Thaw 的低侵入式融合可行性

调研日期：2026-09-23。本文是建议与源码调研记录，不是已采纳的 ADR，也不代表集成已实现或通过运行验证。

## 结论

建议以 **ToolIsle 作为产品入口，Thaw 作为独立的菜单栏管理应用**。技术上保留两个应用的进程、权限、设置及更新机制，用小型适配层协作。Thaw 的稳定版已经提供 `thaw://` 自动化接口，因此不需要把它的菜单栏核心源码移植进 ToolIsle。

“不改两边主体源码”在有限的交互范围内有可行路径：单独开发一个 Bridge 应用，经 ToolIsle 现有扩展接口提供控制面板，再由 Bridge 调用 Thaw。它仍然需要新增集成代码，并且 UI、授权、回调和窗口共存需要 PoC 验证。若要求一个进程、完全原生且共用设置的应用，当前证据不支持零源码修改。

这个选择符合本仓库的[北极星目标](../north-star.md)：用尽可能小、清晰、可维护的定制差异持续吸收上游。该目标明确允许必要的局部修改，不要求为了“零修改”建立插件框架。

## 调研基线

| 对象 | 本次核查基线 | 用途 |
| --- | --- | --- |
| 本地 ToolIsle | `5c10551462dfc51eeddfeb4ff7f557b00663dc8c` | 主任务完成本地架构核查 |
| Thaw 最新稳定版 | [2.0.1](https://github.com/thaw-app/Thaw/releases/tag/2.0.1)，2026-09-02 发布，commit `d5eab80b4e1f62328a8b130994220e49524a48d1` | 下文稳定版能力的主要依据 |
| Thaw 最新 beta | [2.1.0-beta.4](https://github.com/thaw-app/Thaw/releases/tag/2.1.0-beta.4)，2026-09-21 发布，commit `ffdb1a1aa2742f52dde60c4fd5afbbb3641cb74f` | 仅确认版本存在，未完整审计该版 |
| Thaw development | [46a306a9a2fcb0d7f808269230c6a5c4f7a586e4](https://github.com/thaw-app/Thaw/commit/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4)，2026-09-22 | 当前架构及后续演化的补充依据 |

查询时另有 3.0.0-alpha.6 预发布。融合 PoC 不需要以 alpha/development 为前提，也不应把当前 README 的全部新功能当成稳定版契约。

## 已确认：Thaw 可直接提供什么

稳定版 2.0.1 的[接口文档](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/docs/URI_SCHEMES.md)和[实际 URI 解析器](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Utilities/SettingsURIParser.swift#L15)均包含下列能力。

| 需要的能力 | 现有入口 | 限制 |
| --- | --- | --- |
| 显示/隐藏隐藏区 | `thaw://toggle-hidden` | 是切换，不是可确认状态的幂等 show/hide |
| 显示/隐藏始终隐藏区 | `thaw://toggle-always-hidden` | 同上 |
| 打开菜单栏搜索 | `thaw://search` | 打开的是 Thaw 自己的搜索界面 |
| 切换 Thaw Bar | `thaw://toggle-thawbar` | 作用于活动显示器；不能据此嵌入其视图 |
| 切换应用菜单 | `thaw://toggle-application-menus` | 仍由 Thaw 操作菜单栏 |
| 打开设置 | `thaw://open-settings` | 打开的是 Thaw 自己的设置窗口 |
| 控制支持的设置 | `thaw://set?key=...&value=...`、`thaw://toggle?key=...` | 仅支持白名单键，不是任意 UserDefaults 写入口 |
| 读取支持的设置、显示器、版本 | `thaw://get?key=...&callback=...&requestId=...` | 完整结果走 URL 回调；需要自己的回调接收端 |
| 请求自动化授权 | `thaw://authorize` | 用户需先启用 Settings URI 功能 |

设置 API 覆盖 autoRehide、hover/click/scroll 触发方式、延时、Thaw Bar 使用与位置等。只把实际需要的少数设置放到 ToolIsle/Bridge 的控制面板即可；完整布局编辑仍可跳转到 Thaw。

授权边界由稳定版 [AppDelegate](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Main/AppDelegate.swift#L330)和 [SettingsURIHandler](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Utilities/SettingsURIHandler.swift#L231)确认：

- 六个基本动作直接派发，不经过 Settings URI 设置开关和设置白名单检查。
- `authorize/get/set/toggle` 先检查 Settings URI 开关；默认关闭。设置读写识别发起应用 bundle ID，并进行白名单及已记录签名身份核验。
- `get?key=version` 免白名单，但仍在设置总开关之后，不能用它绕过未启用状态。
- 完整 JSON 通过 `yourapp://...?...&data=<JSON>` 回调；普通 `broadcast=true` 只给 acknowledgement。尽管文档称版本可 broadcast，稳定版实现的通用 broadcast 路径仍只发送 ack；版本检测应使用回调或读取已安装应用的元数据，不依赖广播取得版本值。
- `set/toggle` 没有成功回调；接入端应在需要时再 `get` 确认值。不能把 `NSWorkspace.open` 返回成功当成设置已经生效。
- shell 的 `open` 可能不能正确提供调用者身份。手动 `bundleId` 覆盖仅适用于 DEBUG 版。设置读写宜由具有固定 bundle ID 的原生 Bridge 直接调用 `NSWorkspace.shared.open`，不能把命令行脚本当作正式授权方案。

## 已确认：它不是可直接导入的菜单栏 SDK

Thaw 是完整 macOS 应用。入口 [IceApp.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Main/IceApp.swift)通过 `@main ThawMain` 和 `IceApp.main()` 启动 SwiftUI/AppKit 生命周期，并创建自己的 AppDelegate/AppState。主项目产物是 application、内部 XPC service 和 tests；未提供可供 ToolIsle `import` 的菜单栏 library/framework 产品。

容易误读的 `ThawCtl` 也不是现成的通用命令行接口：[Package.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/ThawCtl/Package.swift)只定义 executable，而其 [ThawCtlApp.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/ThawCtl/Sources/ThawCtl/ThawCtlApp.swift)实际为 SwiftUI 控制测试窗口，调用 `NSWorkspace.open` 并接收 `thawctl://` 回调。它能作为适配方式的参考，不能理解为已抽出的 Thaw Core。

稳定版的 [MenuBarItemService 协议](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Shared/Services/MenuBarItemService.swift)只有启动、配置日志和 sourcePIDs 查询；[官方签名构建的 listener](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/MenuBarItemService/Listener.swift)要求同签名团队。这不是给第三方接入的完整菜单栏控制 API，不应复用为融合通道。

development [架构文档](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/docs/ARCHITECTURE.md)已加入第二个 MenuBarCaptureService，以隔离图标捕获；稳定 2.0.1 的项目文件只有 MenuBarItemService。这个差异也说明内部 helper 是上游可变实现，公开 URI 更适合长期适配。

已检查的公开路由没有提供“返回完整菜单栏项目列表/图标流”“按项目移动、点击”“把 Thaw Bar 视图嵌入其他应用”“远程完整布局编辑”等接口。AppleScript 示例只是打开 `thaw://`，不是独立的脚本字典。未发现可复用核心插件体系。上述否定限定于已检查的源码及文档，不宣称系统上绝无其他自动化办法。

## ToolIsle 的现有接入点

本地事实由主任务核查：

- `DynamicIsland/DynamicIslandApp.swift:28` 是主应用入口，约 725–726 行启动 `ExtensionXPCServiceHost` 和 `ExtensionRPCServer`。
- `DynamicIsland/services/Extensions/ExtensionRPCServer.swift:90` 提供 localhost WebSocket，默认端口 9020。
- `DynamicIsland/services/Extensions/ExtensionRPCService.swift:90` 处理 `atoll.presentNotchExperience`。
- `DynamicIsland/components/Extensions/ExtensionLiveActivityViews.swift:183` 已有扩展 tab 和可交互 `webContent`。
- `DynamicIsland/components/Settings/ExtensionsSettings.swift:109` 附近提供扩展开关。已锁定的 AtollExtensionKit SDK revision 为 `e2d30afedbbcc259bec7eeb1bea0757e52f4ca01`。
- 现有 WebView 在 `DynamicIsland/components/Extensions/ExtensionLockScreenWidgetView.swift:357` 附近检查 URL scheme；直接 `<a href="thaw://...">` 会被拒绝。SDK 也未提供原生 action/button descriptor。

因此，“Bridge 向 ToolIsle 扩展面板提供网页，网页按钮请求 Bridge 本地端点，Bridge 再原生打开 thaw://”是源码层面可行的候选。锁定 SDK 支持 `TabConfiguration.webContent`、`allowWebInteraction` 与 descriptor 的 `allowLocalhostRequests`，也需开启对应全局开关。优先让内嵌 HTML 导航到 Bridge 的 localhost 页面，以同源按钮端点避免 `baseURL:nil` 时的跨域 fetch 问题。它增加第三个进程，扩展权限、WebView 请求路径、Bridge 身份、回调及生命周期仍需最小原型验证。

## 方案取舍

| 方案 | 主体源码改动 | 上游维护成本 | 体验与适用范围 |
| --- | --- | --- | --- |
| 两应用独立安装，使用现成快捷键/URI | 可以为零 | 最低 | 能协作，尚不是 ToolIsle 内的一体化面板 |
| 独立 Bridge + ToolIsle 现有扩展 + Thaw URI | 目标是两边均零修改 | 维护小型 Bridge 和两边接口兼容性 | 优先验证的严格零修改方案；控制 UI 主要是网页 |
| ToolIsle 新增隔离的 ThawIntegration 模块 | ToolIsle 少量入口与设置 UI 修改，Thaw 零修改 | 通常可控 | 更直接的原生体验；未必比第三进程复杂 |
| 把 Thaw 核心合进 ToolIsle 进程 | 两侧生命周期、管理器、权限、资源、更新均需适配 | 高 | 当前没有可直接复用的核心库，不适合先做 |
| 一个安装包内放两个独立应用 | 可以不合并源码，但需发布工程 | 中等，取决于更新设计 | 一次安装不等于一个进程或共用权限；需另做验证 |

“以谁为主”可以拆开理解：产品上 ToolIsle 主导入口、刘海交互及工具体验；菜单栏项目的隐藏、移动、捕获和外观由 Thaw 独占负责；源码上两项目各自保留上游关系。让两边同时管理同一组菜单栏项目会增加状态争抢，适配层不应复制 Thaw 的管理逻辑。

## 权限、升级、发布与许可证

稳定版 [Xcode 项目](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw.xcodeproj/project.pbxproj)的 deployment target 为 macOS 26.0。其 [Permission.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Permissions/Permission.swift#L145)标记 Accessibility 必需、Screen Recording 可选；缺少后者会影响捕获预览等能力。独立运行时每个应用各自保有系统权限，不应承诺共享 ToolIsle 已获授权。

Thaw 使用 Sparkle。[稳定版 Info.plist](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Resources/Info.plist)包含官方 feed 与 EdDSA 公钥；[发布说明](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/docs/RELEASES.md)区分人用 DMG 与 Sparkle ZIP/delta。使用独立官方 Thaw 时可继续走其官方升级；若重签、改 bundle ID、嵌套打包或制作 Thaw 定制版，就需要重新设计更新归属，不能默认沿用官方 updater 一切正常。

本地 ToolIsle 也存在需单独核对的发布问题：`DynamicIsland/services/AtollUpdaterDelegate.swift:25` 在运行时读取 `Defaults[.updateChannel].feedURL`，而 `DynamicIsland/models/UpdateChannel.swift:55` 附近的 feed base 仍为 `https://raw.githubusercontent.com/Ebullioscopic/Atoll/main/Updates`。只改 Info.plist 的 feed 不足以保证定制版保留自身；应遵守 CONTEXT 的区分：**同步上游**是仓库代码演进，**应用升级**是替换已安装应用。后者不能意外覆盖定制身份。

Thaw 根目录 [LICENSE](https://github.com/thaw-app/Thaw/blob/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4/LICENSE)为 GPL v3，Swift 文件也有相应许可证标注。分发任何合并或重打包版本前，应按最终采用方式核对许可证、版权说明与对应源码交付；本次没有作出“独立进程即自动免除任何许可证义务”的结论。

## 建议的最小验证顺序

1. 固定 Thaw 2.0.1 作为首个兼容基线，分别运行原版应用，确认刘海界面与 Thaw 的隐藏区、弹出条、多显示器和全屏行为能共存。
2. 做一个最小 Bridge：具有固定 bundle ID、自己的回调 URI；只接通“切换隐藏区、搜索、打开设置”三个动作。利用 ToolIsle 现有扩展面板放三个按钮。
3. 验证启动/退出/扩展被禁用/Thaw 未安装的降级提示，以及 Settings URI 开关、首次授权和回调链路；按需再加入少量设置读写。
4. 验证一次 Thaw 小版本升级、一次 ToolIsle 上游同步；记录固定版本、兼容测试与 Bridge revision。只有出现确切 API 缺口时才考虑上游接口提案或局部补丁。
5. 若网页控制面板或第三进程代价不合适，再选择 ToolIsle 的小型原生集成模块。一个 DMG、登录启动联动、统一升级入口可作为后续交付需求单独处理。

本次仅进行静态源码与官方文档调研，未安装 Thaw、未修改应用源码、未运行集成原型。不能据此声称界面共存、设置回调或更新闭环已通过。
