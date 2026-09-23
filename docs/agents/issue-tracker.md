# 任务追踪

需求、规格和任务保存在 lideming0815/ToolIsle 的 GitHub Issues。
使用 gh CLI；仓库从 git remote 推断。

- 发布任务：gh issue create，多行正文使用 --body-file。
- 读取任务：gh issue view <number> --comments，同时检查标签。
- 查询任务：gh issue list，按状态和标签筛选。
- 评论、标签、关闭：使用 gh issue comment、edit、close。
- 发布规格时创建 Issue；获取任务时读取对应 Issue 及评论。

PRs as a request surface: no.

## 大型项目规划

规划地图保存为带 wayfinder:map 标签的 Issue。
决策任务通过 sub-issues 关联；不可用时使用地图中的任务列表，
并在子任务正文注明 Part of #<map>。
任务类型使用 wayfinder:<type> 标签。

阻塞关系优先使用 GitHub 原生 issue dependencies；
不可用时在正文记录 Blocked by: #<number>。
仅领取所有阻塞项已关闭、尚未分配的任务，按地图顺序选择。
领取时分配给当前开发者；完成时记录结论、关闭任务并更新地图。
