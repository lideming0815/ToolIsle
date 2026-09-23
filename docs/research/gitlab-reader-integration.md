# GitLab Issue 阅读器：调研与实现

日期：2026-09-23。

## 结论与范围

在现有 Gitee 阅读器内增加 GitLab REST v4 适配层，继续复用原来的项目选择、刘海预览、
列表、标签和状态筛选、Markdown、阅读历史及窗口生命周期，不引入第三方 SDK。
一次使用一个平台/站点；切换时取消旧任务并清除内存内容。Gitee 的已有配置和钥匙串标识保持兼容。

入口：设置 → Gitee / GitLab → Issue 来源选择 GitLab。
默认站点为 `https://gitlab.com`，也支持自建 HTTP/HTTPS 站点（端口和反向代理路径前缀）。
例如 `https://git.example.com/gitlab`；不填写 `/api/v4`、Token 或查询参数。
更改地址后点击“应用地址”，确认“当前站点”后再输入该站点的个人访问令牌。
需要 `read_api` 权限，只有 `read_repository` 无法读取本功能所需的 Issue API。
普通 TLS 证书验证保持开启；内网证书需先被系统信任。

项目来源使用“参与项目 / Star 收藏”，对应 GitLab 的 membership/starred，
不将 Gitee Watch 生硬映射为 GitLab 通知订阅。勾选仅影响本机查看范围。
读取 Issue、评论（包括 API 返回的系统记录），支持标签筛选、嵌套子组、跨项目 Issue 链接与 `note_` 评论定位。
GitLab 的 opened 映射为现有 open；不显示 Gitee 专用的“进行中/已拒绝”状态。
不包含 Merge Request、Issue 编辑、讨论线程操作或同时聚合多个平台。

## GitHub 同类实现

通过 GitHub 插件查询并读取以下原始源码；仅借鉴设计，没有复制代码或增加依赖。

- [TanukiKit Configuration.swift](https://github.com/nerdishbynature/TanukiKit/blob/a517802914ae48638b675b2c920b86fd93a0d038/TanukiKit/Configuration.swift)：
  将服务地址与认证配置分离，支持自定义服务器。该版本仍使用 API v3，不能直接照搬接口或认证方式。
- [RxGitLabKit HTTPClient.swift](https://github.com/Qase/RxGitLabKit/blob/b16c756ceb104d9c4a1fce825500470a32939253/Sources/HTTPClient.swift)：
  请求传输与响应模型分层，URLSession 可替换，便于以本地响应测试接口。
- [RxGitLabKit Project.swift](https://github.com/Qase/RxGitLabKit/blob/b16c756ceb104d9c4a1fce825500470a32939253/Sources/Models/Project.swift)：
  区分 name、path、path_with_namespace，显示名称不能当作 API 项目路径。

本项目已有 async URLSession 与 Codable，不需要为几个只读接口引入 RequestKit/RxSwift。

## 当前官方接口依据

- [认证](https://docs.gitlab.com/api/rest/authentication/)：PAT 使用 PRIVATE-TOKEN 请求头，不放入 URL。
- [Token 权限](https://docs.gitlab.com/security/tokens/access_token_scopes/)：只读 API 使用 read_api。
- [Projects API](https://docs.gitlab.com/api/projects/)：GET projects，membership=true 或 starred=true。
- [Issues API](https://docs.gitlab.com/api/issues/)：项目完整路径编码成单一 API 路径参数，使用项目内 iid 定位详情；列表显式 state=all、scope=all。
- [Notes API](https://docs.gitlab.com/api/notes/)：projects/:id/issues/:issue_iid/notes；按 created_at 升序分页。

## 改动边界

- `GLAPI.swift`：新增 GitLab DTO 和适配层，将结果映射到既有 GI 模型。
- `GICore.swift`：小型服务协议、站点值对象、兼容旧 Gitee 数据的可选 GitLab 字段和链接路由。
- `GIStore.swift`：复用同一阅读状态；选择、折叠状态按站点及账户区分，Token 按站点存入钥匙串。
- 现有阅读器设置/UI：增加平台与站点选项，按当前平台显示名称与项目来源。
- 外层只改设置入口、菜单文案和刘海标签；不改媒体、锁屏、窗口策略、上游更新器、工程依赖和发布脚本。

所有 API 请求为 GET。认证请求拒绝重定向；跨站链接交给浏览器，不携带 API Token。
远程图片仍默认关闭；GitLab 只允许当前站点的 origin（协议、主机、端口必须一致），不向图片附加 Token。
需额外认证、外部 CDN 或 GitLab 特有语法的内容可在网页查看，渲染器仍是已有的本地 Markdown 组件。

## 验证

新增 `tests/GitLabReaderRegression.swift`，使用 URLProtocol 合成响应验证真实适配代码：
路径编码、子组、iid、状态/标签映射、Notes 分页、错误码、旧 Gitee 数据兼容及站点身份隔离。

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc \
  DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift \
  DynamicIsland/ToolIsleFeatures/Gitee/GLAPI.swift \
  DynamicIsland/ToolIsleFeatures/Gitee/GIListPresentation.swift \
  tests/GitLabReaderRegression.swift -o /tmp/gitlab-reader-tests
/tmp/gitlab-reader-tests
python3 -m unittest discover -s tests -p 'test_gitee*.py'
```

真实 GitLab 账户与私有实例需要本机验收：连接 → 选择参与或收藏项目 → 阅读正文与评论 →
点击同站其他项目 Issue → 返回 → 切换 Gitee → 切回 GitLab 并确认项目恢复。
本次自动测试不使用真实 Token，不代表已验证你的私有服务器、代理和权限配置。

`tests/GitLabStoreRegression.swift` 另外直接测试 GIStore：切换平台后清空旧账户、
正文、评论、历史、项目和筛选，禁用状态不连接，旧站点路由不能进入新会话。
作为独立测试进程运行，使用测试进程的 UserDefaults 和合成演示数据，不访问真实钥匙串。
完成全应用构建后，可使用构建出的 Defaults 模块执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -profile-generate \
  -I publish/gitlab-validation/DerivedData/Build/Products/Release \
  publish/gitlab-validation/DerivedData/Build/Products/Release/Defaults.o \
  DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift \
  DynamicIsland/ToolIsleFeatures/Gitee/GLAPI.swift \
  DynamicIsland/ToolIsleFeatures/Gitee/GIListPresentation.swift \
  DynamicIsland/ToolIsleFeatures/Gitee/GIStore.swift \
  tests/GitLabStoreRegression.swift -o /tmp/gitlab-store-tests
/tmp/gitlab-store-tests
```


本次结果：GitLab API/路由 93 项（含 HTTP）、Store 切换 16 项；Gitee 接口/历史 49 项、
项目路径 40 项、标签与布局 273 项，既有 Python Gitee 检查 18 项通过。
Release 全应用构建通过；真实 GitLab 账号与自建实例尚未验证。

## 内网 HTTP 站点

支持 `http://192.168.0.200`。不要把 `/dzhihao/项目名称` 放进站点地址；
连接后从项目列表选择该项目。首次应用 HTTP 地址或切换到另一个 HTTP 地址时，
界面会明确提示令牌及私有内容以明文传输，确认后才保存并恢复连接。
已确认并保存的站点重启后可恢复，HTTP 和 HTTPS 的凭据与项目配置分别保存。
默认地址仍为 HTTPS，HTTPS 站点不自动降级为 HTTP，API 重定向仍被拒绝。
不修改全局网络安全配置：工程原有的 `NSAllowsArbitraryLoads` 已允许此类请求。
新增 HTTP 测试覆盖 URL/默认端口、同站链接、评论、凭据命名空间及实际请求的协议与请求头。
测试使用合成响应，没有连接你的内网服务器。
