# 本机打包与安装

在仓库根目录运行 `./publish/publish.sh`，生成 Apple Silicon（arm64）自用 DMG。
可先运行 `./publish/publish.sh --check`，检查 Xcode 初始化状态、Metal 编译器与 LFS 资源。

需要完整 Xcode、Python 3 和已下载的 Git LFS 资源（`git lfs pull`）。
脚本自动优先使用 `/Applications/Xcode.app`，也可通过 `DEVELOPER_DIR` 指定其他版本。
首次使用 Xcode，应先打开它完成许可与组件安装；若提示缺少 Metal Toolchain，
运行 `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -downloadComponent MetalToolchain` 下载后重试（自定义 Xcode 路径时相应替换）。
首次解析锁定的 Swift 包依赖需要网络。脚本不自动执行 sudo、不安装应用、不发布到网络。

完整发行包包含 Thaw 2.0.1 菜单栏组件。主应用编译后，脚本调用
`python3 -B integrations/thaw/build.py --output "$APP/Contents/Helpers/Thaw.app"`，
从锁定版本和显式补丁构建完整辅助应用，先验证内层签名，最后签名外层 App。
Thaw 的来源、源码摘要和补丁摘要记录在 `package.json`；上游源码、许可与构建材料保存在辅助应用的
`Contents/Resources/ToolIsleIntegration/` 中。源码摆放与升级方式见
[ADR-0002](adr/0002-thaw-source-and-host-layout.md) 和 [Thaw 构建说明](../integrations/thaw/README.md)。
`.build/thaw/` 是可重建缓存，不能在那里维护定制修改；并发构建同一个 Thaw 缓存会明确失败。

产物保存到 `publish/YYYY-MM-DD/HHMMSS-随机后缀/`：

- `BangsBuddy-版本-构建号-arm64.dmg`
- `SHA256SUMS.txt`、`package.json`、`environment.txt`、`entitlements.plist`、`build.log`

publish 中仅打包脚本纳入 Git，其他内容均被忽略。同日多次打包分别存储；成功后删除该次中间文件，
失败时保留 work 目录供排查。每次从本地工作区进行 Release 构建，包含未提交的源码修改。
版本与构建号从实际产物读取，不写死历史版本号。脚本验证签名和 DMG，并执行 Thaw 的
`--toolisle-launch-check`：实际加载组件的可执行文件，在创建 AppKit、权限界面或菜单栏状态前退出。
不自动启动应用界面或执行会弹窗、截图的 CI 界面测试；安装后的实际功能需手动验收。

## 改名范围

DMG、应用包、系统显示名及 InfoPlist 权限文案中的 ToolIsle 改为 BangsBuddy。
在构建产物中处理并重新临时签名，不修改项目源文件。可执行文件名仍为 ToolIsle；
欢迎页、设置页、菜单等写死的界面文案仍可能显示 ToolIsle 或 Atoll。
这不是全量品牌替换，也不是独立 Bundle ID 的新应用。

主应用保留现有 Bundle ID、偏好设置、钥匙串关联、扩展协议和权限声明。
不要同时运行官方 Atoll、ToolIsle 与 BangsBuddy。融合版关闭父、子应用的独立更新入口，
通过新的完整 DMG 手动替换整个应用。内嵌 Thaw 使用独立身份 `com.toolisle.Thaw`，
不自动导入独立 Thaw 的偏好或配置。更换临时签名或安装位置后，系统可能要求重新授权。
Release 构建禁用调试授权注入，并检查最终签名不包含 `get-task-allow`。
内嵌 Thaw 不编译或链接已停用的 Sparkle 更新器，避免临时签名组件在动态库校验时崩溃；
仍保留 hardened runtime 和动态库校验，不添加关闭校验的权限。

## 安装

退出旧应用并备份后，双击 DMG，把 BangsBuddy.app 拖到 Applications。
若已安装 ToolIsle.app，需将旧应用移出应用程序目录，避免两个名字相同身份的应用并存。
从“应用程序”启动 BangsBuddy，按需授予系统权限。包未经 Apple 公证；
若系统拦截可信的自建包，可从系统设置的“隐私与安全性”中允许打开。

## 首次使用菜单栏融合

菜单栏功能需要 macOS 26 或以上，默认关闭；首次打开主应用不会启动 Thaw 或展示其权限引导。
展开刘海，点击菜单栏图标进入“菜单栏”设置，主动启用后按 Thaw 引导完成系统授权。
点击“授权设置”，允许 ToolIsle 访问后点击“刷新设置”；设置读取成功后才显示可修改的值。
关闭 Thaw 的 Settings URI 后，需在其原生设置中重新开启才能使用统一设置。
拒绝权限不影响 ToolIsle 其余功能。

启用选择会保存，后续随主应用启停。退出或重启会等待 Thaw 正常恢复菜单栏并退出；
若它仍有未关闭对话框，主应用会取消退出并说明原因，不强杀组件。
关闭旧应用后再替换 DMG，安装完成后复验权限、三个快捷操作与常用设置。
已有独立 Thaw 或 Ice 在运行时，需要先自行退出它，融合版不会替你终止这些应用。

构建与签名验证不能代替实机验收：首次授权、设置回调、图标隐藏/恢复、搜索与高级窗口、
多屏以及替换升级后的授权保留都需在实际安装的应用上验证。
