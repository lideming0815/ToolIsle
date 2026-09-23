# ToolIsle gitee.6 — 紧凑选择与 dev 集成

应用 2.3.3（1644），arm64。基于 gitee.5 提交 9b93364，继续使用原 DynamicIsland.xcodeproj / DynamicIsland scheme，产物 ToolIsle.app，不恢复独立 Swift Package 工具箱。

状态及标签平铺筛选去掉勾选图标及其 13pt 占位；选中/未选中宽度一致，用底色、边框和无障碍信息区分。更多状态使用“（当前）”文字；标签多选面板取消方框，使用选中背景/边框。保持三个优先状态单行、标签两行、搜索/OR 多选、按项目折叠与阅读位置。列表和刘海无复制图标，顶部复制仍在字号后。

Gitee API、Markdown、链接路由、窗口生命周期、刘海尺寸、媒体、锁屏、Shelf 和计时器不在此次改动范围。账户和项目配置不重置，GPL 与第三方声明保留。

ToolIsle 使用 toolisle-integration.yml 在集成分支与 dev 构建原 Target，并运行两轮原生窗口回归及标签 UI 检查。详细通过结果、源码 SHA 和截图见同提交的 toolisle-integrated-preview Actions 产物。旧上游 CI/发布/镜像/nightly/命令自动化已原样归档到 docs/upstream-workflows，不随 dev 合并重新启用，避免意外发布或修改其他分支。代码通过普通 PR merge 合入，不 force-push。

测试包声明最低 macOS 14.6，临时签名、未经 Apple 公证。先退出旧 ToolIsle 和官方 Atoll，备份旧应用再替换，不需要清空账户。仍保留原 Bundle ID、偏好域、扩展协议及上游更新器；不要同时运行官方版，不要接受上游更新覆盖测试包。

自动测试使用合成数据、不含私有令牌；仅测试进程通过 -SUEnableAutomaticChecks NO 隔离首次更新询问，不修改产品更新设置。真实私有 Gitee、第三方 AltTab、实体多屏/合盖及全部原 Atoll 能力仍需本机验收。
