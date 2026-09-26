# ADR-0002：Thaw 源码与主应用适配分开维护

日期：2026-09-26。状态：已接受；在 ADR-0001 已确认边界内落实用户要求的代码摆放与架构设计。

ToolIsle 侧实现集中在 `DynamicIsland/ToolIsleFeatures/Thaw/`：`ThawController` 管理启停、定向调用和设置读回，`ThawProtocol` 限定允许的动作及设置并验证回调，`ThawViews` 承载原生设置和刘海快捷菜单，`ThawAppLifecycle` 协调主应用退出与重启。现有 App、设置和刘海视图只保留必要挂点；不引入通用插件框架或两套相互镜像的设置存储。

`integrations/thaw/` 只保存上游版本与压缩包摘要、显式发行补丁、构建脚本及说明。每次从已校验压缩包重建 `.build/thaw/source` 与 `.build/thaw/work` 并应用补丁，完整上游源码和编译缓存不进入主应用的 Swift 源码目录。这样同步 ToolIsle 上游主要检查局部挂点，升级 Thaw 则更新锁定版本与补丁；两套源码不互相合并，也不抽取菜单栏核心。

既有 `publish/publish.sh` 构建主应用，再调用 Thaw 构建脚本把完整辅助应用放入 `Contents/Helpers/Thaw.app`，最后签名外层并生成一个 DMG。内嵌组件使用独立身份和数据目录，父、子应用均采用整包手动升级。固定源码与补丁可追溯，但主应用仍允许从包含未提交改动的工作区构建；发布记录必须明确这一点，不能声称字节级可重现。
