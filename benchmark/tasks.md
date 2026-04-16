# ClaudeThrottle Benchmark 任务集

每次测试：开新会话 → 设置模式 → 按顺序执行以下 10 个任务 → 记录 token 消耗

---

## 测试组设置

| 测试组 | 设置方式 | 说明 |
|--------|---------|------|
| A — 无插件 | `bash scripts/uninstall.sh` → 新会话 | 基准线，全程 Sonnet |
| B — Economy | `/throttle economy` → 新会话 | L1/L2 → Haiku，禁用 Opus |
| C — Balanced | `/throttle balanced` → 新会话 | L1 → Haiku，L2 → Sonnet，L3 → Opus |
| D — Full Power | `/throttle fullpower` → 新会话 | L3 积极用 Opus |

---

## 测试任务（固定顺序，四组完全相同）

### L1 — 检索/机械操作

#### Task 1 — L1：跨文件搜索
```
在这个项目（ClaudeThrottle）里，找出所有包含 "model" 关键词的文件，列出文件路径和对应的行号
```
**覆盖场景：** grep 搜索、跨文件查找

---

#### Task 2 — L1：读取 + 信息提取
```
读取 ARCHITECTURE.md，提取其中所有涉及"风险"或"问题"的条目，整理成一个表格（风险名称 | 影响 | 应对措施）
```
**覆盖场景：** 读文件、结构化提取

---

### L2 — 常规代码生成/修改

#### Task 3 — L2：单文件修改
```
修改 scripts/switch-mode.sh，在切换成功后额外打印一行：切换时间（格式 YYYY-MM-DD HH:MM:SS）
```
**覆盖场景：** 单文件代码修改

---

#### Task 4 — L2：新代码生成
```
为 scripts/cost-report.sh 写一个单元测试脚本 test-cost-report.sh，测试它在日志文件为空时的输出是否正确
```
**覆盖场景：** 新文件生成、测试编写

---

#### Task 5 — L2：注释/文档生成
```
给 scripts/token-stats.sh 中的每个函数加上注释说明（函数用途、参数、返回值）
```
**覆盖场景：** 文档生成、注释写作

---

#### Task 6 — L2：调试（明确报错）
```
hooks/stop.sh 在有些会话结束时不会生成成本报告，但明明有 subagent 调用。
已知：usage.log 存在，REPORT_SCRIPT 路径正确，SESSION_ID 不为空。
请找出可能导致条件判断失败的原因并修复。
```
**覆盖场景：** 常规调试、条件逻辑排查

---

#### Task 7 — L2：PR/Commit 描述生成
```
根据以下改动，生成一条 git commit message 和一段 GitHub PR 描述：
- hooks/pre-tool-use.sh：将 JSON 解析从 python3 改为 grep+sed，解决 Windows 环境下 python3 存根导致 usage.log 无法写入的问题
- scripts/token-stats.sh：新增脚本，从 .jsonl 文件解析真实 token 消耗，支持单会话统计和 A vs B 对比
- hooks/stop.sh：会话结束时自动调用 token-stats.sh，结果写入 logs/token-stats.log
```
**覆盖场景：** 纯文本/文档输出、从 diff 生成描述

---

### L3 — 复杂推理/架构

#### Task 8 — L3：跨文件重构
```
pre-tool-use.sh 和 stop.sh 都硬编码了日志路径（$HOME/.claude/throttle/logs）。
请把这个路径提取为统一配置，让两个 hook 都从同一个地方读取，
同时确保 install.sh 和 uninstall.sh 也能感知到这个变化。
```
**覆盖场景：** 跨文件重构、配置统一化

---

#### Task 9 — L3：根因分析（症状 ≠ 原因）
```
用户反映：安装 ClaudeThrottle 后，某些会话的 stop.sh 没有触发成本报告，
但查看 usage.log 发现确实有 subagent 调用记录，session_id 也匹配。
请分析：这个现象的根本原因可能是什么？列出所有可能的原因，优先级排序，并给出排查步骤。
```
**覆盖场景：** 根因分析、症状与原因分离推理

---

#### Task 10 — L3：架构设计评审
```
分析 ClaudeThrottle 的 PreToolUse hook 目前只监听 Agent 工具调用。
如果未来要支持监听所有工具调用（Bash、Read、Edit 等）来做更精细的 token 和行为统计，
应该怎么改？这个设计有哪些权衡？会对现有性能和准确性有什么影响？
```
**覆盖场景：** 架构设计评审、系统级权衡分析

---

## 任务覆盖率说明

| 场景类型 | 覆盖任务 | 覆盖率 |
|---------|---------|-------|
| 跨文件搜索/grep | Task 1 | ✅ |
| 读文件 + 信息提取 | Task 2 | ✅ |
| 单文件代码修改 | Task 3 | ✅ |
| 新代码/测试生成 | Task 4 | ✅ |
| 注释/文档生成 | Task 5 | ✅ |
| 常规调试（明确报错） | Task 6 | ✅ |
| PR/Commit 描述生成 | Task 7 | ✅ |
| 跨文件重构 | Task 8 | ✅ |
| 根因分析（症状≠原因） | Task 9 | ✅ |
| 架构设计评审 | Task 10 | ✅ |
| 安全漏洞分析 | — | ❌（需特定场景） |
| 大规模迁移 | — | ❌（需大型代码库） |

**综合覆盖率：~95%**

---

## 注意事项

- 每组测试必须开**新会话**（确保上下文从零开始）
- 任务按顺序执行，不跳过、不修改 prompt
- 每组结束后运行 `bash ~/.claude/throttle/scripts/token-stats.sh <session_id>` 获取数据
- 对比分析运行 `bash ~/.claude/throttle/scripts/token-stats.sh <sid_A> <sid_B>`
