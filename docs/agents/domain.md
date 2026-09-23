# 领域文档

采用 single-context：根目录 CONTEXT.md 和 docs/adr/。

探索代码前，读取 CONTEXT.md 及与当前任务相关的 ADR。
若存在 CONTEXT-MAP.md，按其中的索引读取相关领域文档。
文档不存在时直接继续，由 domain-modeling 在形成术语或决策时按需创建。

任务、方案和测试使用 CONTEXT.md 中的领域术语。
缺少必要术语时交由 domain-modeling 澄清。
方案与已有 ADR 冲突时，明确指出冲突及重新讨论的理由。
