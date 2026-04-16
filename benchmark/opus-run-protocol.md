# Opus 基准测试执行协议

对比两组：Opus + ClaudeThrottle 插件 vs 纯 Opus。10 个任务沿用 [tasks.md](tasks.md)。

---

## 执行前准备

1. 当前会话先结束（保留这个文件作参考）
2. 准备好 10 个任务文本（见下方"任务清单"，直接复制粘贴）

---

## 共用：首条消息（E/F 都用这个）

> **"按顺序执行接下来 10 个任务。规则：
> (1) 每个任务结束后停下，等我下一条消息再继续，不要跳题、不要合并。
> (2) 不要用 TodoWrite、不要读与当前任务无关的文件、不要主动跑 token-stats 或其他基准相关命令（会污染统计）。
> (3) 有改文件的任务直接改，不要额外确认。
> 准备好了回复 `ready`。"**

拿 session_id：Windows 下看 `C:\Users\hewen\.claude\projects\d--ai-project-ClaudeThrottle\` 里**最新的 .jsonl 文件名**（去掉 `.jsonl` 后缀即 session_id）。

---

## Group E — Opus + 插件（Boost OFF）

### 会话开始前
```bash
# 1. 基线干净（只允许 benchmark/ 下未跟踪文件存在）
git status

# 2. 插件状态
bash ~/.claude/throttle/scripts/switch-mode.sh on
bash ~/.claude/throttle/scripts/switch-mode.sh broadcast on
cat ~/.claude/throttle/config/boost.txt   # 应输出 "off"
```

### 会话内
1. 开新会话（Claude Code: `/new` 或重启）
2. 切主模型：`/model opus`
3. 粘贴"共用首条消息"，等 `ready`
4. 依次粘贴 Task 1 → Task 10（每条等回复完再发下一条）
5. 记下 session_id（从 .jsonl 文件名拿），不要让 Claude 跑命令

### 会话结束后
```bash
bash ~/.claude/throttle/scripts/token-stats.sh <session_id_E> > ~/throttle-bench-E.txt
```

---

## 组间重置（E 跑完，F 跑前，必做）

```bash
cd "d:/ai project/ClaudeThrottle"

# 1. 回滚 E 组改的已跟踪文件
git restore .

# 2. 删 E 组生成的未跟踪文件（限定目录，保护 benchmark/ 下的协议文件）
#    -x 包含 gitignored 文件（如 scripts/test-cost-report.sh），否则下组会"已存在"伪通过
git clean -fdx scripts/ hooks/ config/ rules/

# 3. 确认干净
git status --ignored   # scripts/ 下不应再有 ignored 文件残留
```

---

## Group F — 纯 Opus（插件暂停）

### 会话开始前
```bash
bash ~/.claude/throttle/scripts/switch-mode.sh off   # 暂停路由
git status   # 再确认一次基线
```

### 会话内
1. 开新会话
2. 切主模型：`/model opus`
3. 粘贴"共用首条消息"，等 `ready`
4. 依次粘贴同样的 10 个任务
5. 记下 session_id

### 会话结束后
```bash
bash ~/.claude/throttle/scripts/token-stats.sh <session_id_F> > ~/throttle-bench-F.txt
bash ~/.claude/throttle/scripts/switch-mode.sh on    # 恢复插件
```

---

## 回到我这边

回来后告诉我：
- `session_id_E` 和 `session_id_F`
- 或者直接把 `~/throttle-bench-E.txt` 和 `~/throttle-bench-F.txt` 内容贴出来

我会：
1. 对两组的 10 个回答逐项 5 维打分（50 分满）
2. 算 token 消耗和美元成本
3. 算节省比例（对比 Sonnet 那组的 79%）
4. 写入 `benchmark/results.md` 的 Opus 部分

---

## 任务清单（按顺序粘贴）

> 任务正文见 [tasks.md](tasks.md) 第 22–112 行。为方便复制，下面是完整清单：

### Task 1（L1 跨文件搜索）
```
在这个项目（ClaudeThrottle）里，找出所有包含 "model" 关键词的文件，列出文件路径和对应的行号
```

### Task 2（L1 读取+提取）
```
读取 ARCHITECTURE.md，提取其中所有涉及"风险"或"问题"的条目，整理成一个表格（风险名称 | 影响 | 应对措施）
```

### Task 3（L2 单文件修改）
```
修改 scripts/switch-mode.sh，在切换成功后额外打印一行：切换时间（格式 YYYY-MM-DD HH:MM:SS）
```

### Task 4（L2 新代码生成）
```
为 scripts/cost-report.sh 写一个单元测试脚本 test-cost-report.sh，测试它在日志文件为空时的输出是否正确
```

### Task 5（L2 注释生成）
```
给 scripts/token-stats.sh 中的每个函数加上注释说明（函数用途、参数、返回值）
```

### Task 6（L2-debug 调试）
```
hooks/stop.sh 在有些会话结束时不会生成成本报告，但明明有 subagent 调用。
已知：usage.log 存在，REPORT_SCRIPT 路径正确，SESSION_ID 不为空。
请找出可能导致条件判断失败的原因并修复。
```

### Task 7（L2 PR/Commit 描述）
```
根据以下改动，生成一条 git commit message 和一段 GitHub PR 描述：
- hooks/pre-tool-use.sh：将 JSON 解析从 python3 改为 grep+sed，解决 Windows 环境下 python3 存根导致 usage.log 无法写入的问题
- scripts/token-stats.sh：新增脚本，从 .jsonl 文件解析真实 token 消耗，支持单会话统计和 A vs B 对比
- hooks/stop.sh：会话结束时自动调用 token-stats.sh，结果写入 logs/token-stats.log
```

### Task 8（L3 跨文件重构）
```
pre-tool-use.sh 和 stop.sh 都硬编码了日志路径（$HOME/.claude/throttle/logs）。
请把这个路径提取为统一配置，让两个 hook 都从同一个地方读取，
同时确保 install.sh 和 uninstall.sh 也能感知到这个变化。
```

### Task 9（L3 根因分析）
```
用户反映：安装 ClaudeThrottle 后，某些会话的 stop.sh 没有触发成本报告，
但查看 usage.log 发现确实有 subagent 调用记录，session_id 也匹配。
请分析：这个现象的根本原因可能是什么？列出所有可能的原因，优先级排序，并给出排查步骤。
```

### Task 10（L3 架构设计评审）
```
分析 ClaudeThrottle 的 PreToolUse hook 目前只监听 Agent 工具调用。
如果未来要支持监听所有工具调用（Bash、Read、Edit 等）来做更精细的 token 和行为统计，
应该怎么改？这个设计有哪些权衡？会对现有性能和准确性有什么影响？
```

---

## 注意事项

- **两组任务顺序、措辞必须一致**（复制上面的，不要改）
- 两组之间**不要跑其他任务**污染日志
- Task 3/4/5/6/8 涉及修改/新增文件 — 用上方"组间重置"区块，不要只跑 `git restore .`
- 如果插件组某任务 Haiku 失败被主 Opus 重做，不算质量问题（符合设计）
- 如果某组中途崩了，记下哪步崩的，我们决定是否重跑
- Claude 若在会话内主动跑 `token-stats` 或读基准文件，打断它 — 会污染 token 统计