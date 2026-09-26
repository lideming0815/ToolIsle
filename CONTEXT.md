# ToolIsle 定制版

本仓库承载基于 [ToolIsle](https://github.com/lideming0815/ToolIsle) 的定制版本；ToolIsle 源自 Atoll 开源项目。项目目标见 [北极星目标](docs/north-star.md)。

## 术语

**上游版**：本仓库采用的 [ToolIsle 上游仓库](https://github.com/lideming0815/ToolIsle)及其发布版本。

**定制版**：本仓库在上游基础上加入个人实际需求后形成的应用版本；其首要使用者是本人，同事是可能的后续使用者。

**定制差异**：定制版相对于所采用上游基线，为满足实际需求而保留的改动集合。

**同步上游**：把上游的后续代码变化引入本仓库，同时保留并验证定制差异。

**应用升级**：用新的应用版本更新 Mac 上已安装的定制版，与仓库层面的同步上游分开讨论。

**融合版**：在一个安装的外层应用包中交付 ToolIsle 功能与菜单栏管理能力的定制版；一个应用包可以包含辅助进程。首版产品边界见 [ADR-0001](docs/adr/0001-menubar-integration-product-boundaries.md)。
