# 本机打包与安装

在仓库根目录运行 `./publish/publish.sh`，生成 Apple Silicon（arm64）自用 DMG。
可先运行 `./publish/publish.sh --check`，检查 Xcode 初始化状态、Metal 编译器与 LFS 资源。

需要完整 Xcode、Python 3 和已下载的 Git LFS 资源（`git lfs pull`）。
脚本自动优先使用 `/Applications/Xcode.app`，也可通过 `DEVELOPER_DIR` 指定其他版本。
首次使用 Xcode，应先打开它完成许可与组件安装；若提示缺少 Metal Toolchain，
运行 `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -downloadComponent MetalToolchain` 下载后重试（自定义 Xcode 路径时相应替换）。
首次解析锁定的 Swift 包依赖需要网络。脚本不自动执行 sudo、不安装应用、不发布到网络。

产物保存到 `publish/YYYY-MM-DD/HHMMSS-随机后缀/`：

- `BangsBuddy-版本-构建号-arm64.dmg`
- `SHA256SUMS.txt`、`package.json`、`environment.txt`、`entitlements.plist`、`build.log`

publish 中仅打包脚本纳入 Git，其他内容均被忽略。同日多次打包分别存储；成功后删除该次中间文件，
失败时保留 work 目录供排查。每次从本地工作区进行 Release 构建，包含未提交的源码修改。
版本与构建号从实际产物读取，不写死历史版本号。脚本验证签名和 DMG，
不自动启动应用或执行会弹窗、截图的 CI 界面测试；安装后的实际功能需手动验收。

## 改名范围

DMG、应用包、系统显示名及 InfoPlist 权限文案中的 ToolIsle 改为 BangsBuddy。
在构建产物中处理并重新临时签名，不修改项目源文件。可执行文件名仍为 ToolIsle；
欢迎页、设置页、菜单等写死的界面文案仍可能显示 ToolIsle 或 Atoll。
这不是全量品牌替换，也不是独立 Bundle ID 的新应用。

保留现有 Bundle ID、偏好设置、钥匙串关联、扩展协议和权限声明。
不要同时运行官方 Atoll、ToolIsle 与 BangsBuddy。上游更新器仍保留，
不要接受会覆盖此定制包的上游更新。更换临时签名或安装位置后，系统可能要求重新授权。

## 安装

退出旧应用并备份后，双击 DMG，把 BangsBuddy.app 拖到 Applications。
若已安装 ToolIsle.app，需将旧应用移出应用程序目录，避免两个名字相同身份的应用并存。
从“应用程序”启动 BangsBuddy，按需授予系统权限。包未经 Apple 公证；
若系统拦截可信的自建包，可从系统设置的“隐私与安全性”中允许打开。
