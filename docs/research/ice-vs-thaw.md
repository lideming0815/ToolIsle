# Ice 与 Thaw：面向 ToolIsle 低侵入集成的对比

调研日期：2026-09-23。本文是选型建议，未构成已采纳的 ADR。仅做官方文档、发布记录及源码核查，没有安装应用、运行集成或测量性能。

## 推荐

当前优先选 **Thaw 作为独立菜单栏组件，ToolIsle 继续作为产品入口**。主要依据是 Thaw 稳定版已有可用的外部控制协议、近期仍发布更新，且本机 `sw_vers -productVersion` 为 `26.7`，满足其稳定版最低 macOS 26.0 要求。满足最低版本不等于已在本机验证运行正常。

Ice 可作为实现参考，以及需要兼容 macOS 14/15 时重新评估的候选。当前不建议为了集成额外给 Ice 建立和维护一套 Thaw 已经提供的外部控制入口。

用户的选择标准来自[北极星目标](../north-star.md)：小而清晰的定制差异、持续吸收上游、可以重复构建和安装。此前的 [Thaw 融合研究](thaw-integration-research.md)继续适用。

## 基线与版本边界

| 对象 | 核查基线 | 发布或提交日期 |
| --- | --- | --- |
| Ice 最新稳定版 | [0.11.12](https://github.com/jordanbaird/Ice/releases/tag/0.11.12)，`d567f1ecac68936a090d6b47d6f0b882c489c6f4` | 2024-10-29 |
| Ice 最新测试版 | [0.11.13-dev.2](https://github.com/jordanbaird/Ice/releases/tag/0.11.13-dev.2)，`da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e` | 2025-09-16 |
| Ice 默认分支 | [11edd39115f3f43a83ae114b5348df6a0e1741cf](https://github.com/jordanbaird/Ice/commit/11edd39115f3f43a83ae114b5348df6a0e1741cf) | 2025-09-20，更新 issue templates |
| Thaw 最新稳定版 | [2.0.1](https://github.com/thaw-app/Thaw/releases/tag/2.0.1)，`d5eab80b4e1f62328a8b130994220e49524a48d1` | 2026-09-02 |
| Thaw 2.x 最新测试版 | [2.1.0-beta.4](https://github.com/thaw-app/Thaw/releases/tag/2.1.0-beta.4) | 2026-09-21，macOS 26 only |
| Thaw 3.x 最新预览版 | [3.0.0-alpha.6](https://github.com/thaw-app/Thaw/releases/tag/3.0.0-alpha.6) | 2026-09-21，macOS 27 only |
| Thaw 默认分支 | [46a306a9a2fcb0d7f808269230c6a5c4f7a586e4](https://github.com/thaw-app/Thaw/commit/46a306a9a2fcb0d7f808269230c6a5c4f7a586e4) | 2026-09-22 |

以上是查询时的公开记录。Ice 仓库未归档，README 仍称 active development；不能仅据更新间隔断言作者永久停止维护。公开记录足以支持“近期持续获得修复的证据，Thaw 更强”这一选型判断。

## 对比矩阵

| 维度 | Ice | Thaw | 对当前需求的意义 |
| --- | --- | --- | --- |
| 基础能力 | 隐藏区、始终隐藏区、搜索、Ice Bar、拖动排列、外观设置 | 稳定版提供同类基础能力 | 两者都覆盖基础菜单栏整理；不是主要分胜负项 |
| 外部命令入口 | 主线及最新 beta 未发现所需的公开控制 API；有内部快捷键，beta 的内部 XPC 仅查图标来源 | 2.0.1 已有 `thaw://`，可切换隐藏区、搜索、打开设置等 | Thaw 更容易由 ToolIsle 发起操作 |
| 设置读写 | 未发现公开设置协议；内部设置代码不能视为 API | 已有授权后的 `get/set/toggle`，支持 URL 回调；仅支持列出的键 | Thaw 能制作有限的集中控制面板 |
| 两边源码零修改的控制集成 | 缺少现成协议；需研究 UI/快捷键自动化，或者新增上游适配入口 | 独立 Bridge + ToolIsle 扩展 + Thaw URI，有源码层面的可行路径 | Thaw 更符合低侵入目标，但 Bridge 仍待运行验证 |
| 单进程嵌入核心 | 完整 App，没有现成可导入的核心库 | 同样为完整 App，没有可直接导入的菜单栏核心 SDK | 两者直接合并核心都会引入维护工作 |
| 稳定版布局 Profiles | README 列未实现，主线未发现相应模型 | 2.0.1 已实现 Profiles、显示器/Focus 绑定和前后脚本 Hooks | Thaw 已有更丰富的场景切换能力 |
| 分组、间隔项、条件触发 | README 列未实现，主线未发现相应管理器 | 属于 2.1 beta 新增，不能算作 2.0.1 稳定能力 | 仅作为未来扩展空间，不作为首期交付承诺 |
| 最低系统 | 主线构建要求 macOS 14.0 | 2.0.1 构建要求 macOS 26.0 | Ice 对旧系统更友好；本机 26.7 不受此限制 |
| macOS 26 的发布依据 | 0.11.13-dev.2 声明修复大多数 Tahoe 问题，仍列透明菜单栏亮度问题 | 有 2.0.1 稳定版与持续更新的 2.1 beta；同样存在具体问题修复 | 当前优先验证 Thaw 稳定版，不能据此保证零故障 |
| 持续跟踪上游 | 公开更新间隔较长；若自行加接口，将自行维护该差异 | 有近期更新和公开 URI 接口；仍需逐版本验证兼容性 | Thaw 更有利于把工作集中在适配层 |
| 独立升级 | 使用 Sparkle | 使用 Sparkle | 独立 App 可分别升级；重打包或改身份需另设计发布流程 |
| 许可证 | GPL-3.0 | GPL-3.0 | 不是此次技术选型的区分项；分发时按实际方式处理许可要求 |
| CPU、内存、稳定性 | 未实测 | 未实测 | 不依据功能数量、星标数或宣传判断胜负 |

矩阵中“更适合”“维护成本”属于结合用户目标的工程判断；API、版本、构建要求等属于可核查事实。零改源码不等于零新增代码，也不意味着所有 Thaw 界面都能显示在 ToolIsle 内。

## 决定性源码证据

### Ice

对固定主线源码进行全量检索：`CFBundleURL`、`onOpenURL`、`openURLs`、`ice://`、`NSAppleEventManager`、`NSScript`、`AppleScript`、`AppIntents`、`AppIntent`、`NSXPC`、`CommandLine`、`ArgumentParser`，在 `Ice/` 与 Xcode 工程未发现相关外部入口。没有 `Package.swift`；存在的 `Package.resolved` 只是依赖锁定文件。否定结论限定于已检查版本及入口类别。

- [Info.plist](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Info.plist)：只有 Sparkle feed 与公钥。
- [IceApp.swift](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Main/IceApp.swift) 和 [AppDelegate.swift](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Main/AppDelegate.swift)：完整应用生命周期，没有 URL dispatch。
- [HotkeyAction.swift](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Hotkeys/HotkeyAction.swift)：包含内部动作；[HotkeyRegistry.swift](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Hotkeys/HotkeyRegistry.swift)注册全局按键。模拟按键依赖用户配置，不能视为带结果确认的公共协议。
- [AppState.swift](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Main/AppState.swift)：持有菜单栏、权限、设置、更新、缓存等内部管理器。
- [项目配置](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice.xcodeproj/project.pbxproj)：application product、macOS 14.0。
- [README](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/README.md) 与 [LICENSE](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/LICENSE)。README/FREQUENT_ISSUES 部分内容落后于实现，未机械照抄所有 roadmap 项。

最新 beta 与主线存在分叉，因此另下载并检查 `da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e`，不能把主线结构直接当作最新 beta 结构：

- beta [Info.plist](https://github.com/jordanbaird/Ice/blob/da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e/Ice/Resources/Info.plist) 和全树检索仍未发现 URL scheme、AppIntents、AppleScript 或 CLI 控制入口。
- beta 确有内嵌 XPC：[MenuBarItemService](https://github.com/jordanbaird/Ice/blob/da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e/Shared/Services/MenuBarItemService.swift)仅提供 `start` 和 `sourcePID(WindowInfo)`；[listener](https://github.com/jordanbaird/Ice/blob/da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e/MenuBarItemService/Listener.swift#L45)在 macOS 26 要求同签名团队。它不能充当隐藏区、搜索和设置控制协议。
- beta [AppDelegate](https://github.com/jordanbaird/Ice/blob/da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e/Ice/Main/AppDelegate.swift#L55)支持重新打开应用时显示设置。这一单项能力可以直接利用，不需模拟按键；不应将“缺少完整控制 API”夸大为“完全无法外部协作”。
- beta [项目配置](https://github.com/jordanbaird/Ice/blob/da2dd23cdd70d287445cbe3dbb5628a4c3ad8c7e/Ice.xcodeproj/project.pbxproj)仍以 macOS 14.0 为最低要求，产物包含 App 与内部 XPC，没有可直接导入的菜单栏核心 SDK。

### Thaw

- 稳定版 [URI 文档](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/docs/URI_SCHEMES.md)及 [SettingsURIParser.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Utilities/SettingsURIParser.swift)：外部动作和设置协议。授权、回调与无回执限制见前一份融合研究。
- 稳定版 [ProfileManager.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Settings/Models/ProfileManager.swift) 及 [ProfileManager+Live.swift](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw/Settings/Models/ProfileManager%2BLive.swift)：Profiles 与显示器/Focus/script Hooks。
- [2.1.0-beta.1 发布说明](https://github.com/thaw-app/Thaw/releases/tag/2.1.0-beta.1)明确把 groups、spacers、triggers、Zen、Simple Mode 和按 Space 的 Profiles 列为新增。2.0.1 的 README 对功能范围描述更广，不能据其声称这些都已进入稳定版。
- 稳定版 [Xcode 工程](https://github.com/thaw-app/Thaw/blob/d5eab80b4e1f62328a8b130994220e49524a48d1/Thaw.xcodeproj/project.pbxproj)：macOS 26.0。macOS 27 应另行验证 3.x，不能把最低版本要求等同于未来系统兼容保证。

## 建议落地边界

先选择 ToolIsle + 官方 Thaw 2.0.1 的独立进程组合；独立 Bridge 或 ToolIsle 小型原生模块先只实现隐藏区切换、搜索、打开设置。完整布局编辑保留在 Thaw。严格零源码方案仍需验证 ToolIsle 扩展网页到本地 Bridge、Bridge 到 Thaw 的调用和恢复链路。

若后续要求支持 macOS 14/15，再单独评估 Ice 或合适的历史版本，而不是在当前原型中同时维护两套菜单栏引擎。若接入 Thaw，通常跟踪 Thaw 自己的上游即可；参考 Ice 的实现不意味着还要把 Ice 的后续源码单独合并进定制版。

本次只新增调研文档；不修改应用源码、现有定制或发布配置。
