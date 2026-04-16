# ClaudeThrottle

**Claude Code cost optimizer** — automatically routes tasks to the cheapest model that can handle them. Benchmarked: **79% cost savings, zero quality loss.**

Claude Code uses Sonnet for everything. But 70% of tasks — searches, code edits, test generation, docs — can be done by Haiku at 1/4 the cost with identical results. ClaudeThrottle makes this happen automatically.

---

## Benchmark Results

| Setup | Cost | Quality | Savings |
|-------|------|---------|---------|
| No plugin (all Sonnet) | $3.70 | 50/50 | — |
| **ClaudeThrottle v2.1** | **~$0.79** | **50/50** | **79%** |

> 20-task benchmark (2 rounds) across search, extraction, code generation, new file creation, debugging, refactoring, security analysis, and architecture review. On search/extraction tasks, Haiku subagents consistently matched or outperformed direct Sonnet execution. Full report: [benchmark/results.md](benchmark/results.md)

---

## How It Works

```
User request
  └→ Main Agent (Sonnet) classifies task complexity
       ├─ L1 (search/retrieval)  → Haiku subagent
       ├─ L2 (code gen/edit)     → Haiku subagent (retry with Sonnet if needed)
       ├─ L2-debug (debugging)   → Sonnet handles directly (Haiku's weak spot)
       └─ L3 (complex reasoning) → Sonnet handles it directly
                                     ↑
                              Optional: /throttle boost → Opus for next L3 task
```

Routing rules are embedded in CLAUDE.md — zero extra API calls, zero latency overhead. An Opus gatekeeper hook enforces that Opus is never called without explicit user authorization.

---

## Routing Logic

### Step 1: Task Classification

The main Sonnet agent classifies every incoming task into one of four levels before acting:

| Level | What it is | Signal words | Examples |
|-------|-----------|--------------|---------|
| **L1** | Retrieval — no reasoning needed | find, search, list, read, count, show | File search, grep, directory listing, info extraction |
| **L2** | Generation/modification — scoped, no system-level tradeoffs | (none specific) | Write a function, modify a file, generate tests, write docs |
| **L2-debug** | Debugging — causal chain tracing, root-cause analysis | bug, error, broken, why failing, fix, debug | Bug fixes, script not working, log analysis |
| **L3** | Complex reasoning — cross-file, multi-step, architectural | why, design, architecture, refactor, root cause, tradeoffs | Cross-module refactors, architecture design, security audits |

**Classification principle:** When uncertain, prefer L2 over L3. Debugging tasks always go to L2-debug, never plain L2.

---

### Step 2: Routing Decision

Once classified, the routing is deterministic:

| Level | Who executes | Why |
|-------|-------------|-----|
| L1 | Haiku subagent | Pure retrieval — fresh context improves coverage |
| L2 | Haiku subagent → Sonnet fallback | Haiku handles 90%+ of cases; Sonnet retries only on failure |
| L2-debug | Sonnet (main agent) | Root-cause tracing requires recursive "why" reasoning — Haiku's weak spot |
| L3 | Sonnet (main agent) | Multi-file reasoning, architectural tradeoffs |
| L3 + Boost | Opus subagent | One-shot, user-authorized — Boost turns off immediately after |

---

### Step 3: Subagent Execution

For L1/L2 tasks dispatched to Haiku, the main agent:

1. **Reads the relevant file section** (for L2-modify tasks) and embeds it directly in the subagent prompt — Haiku gets the current code without needing to read files itself
2. **Adds a "check first" instruction** — if the requested change already exists, return immediately without modifying
3. **Appends a scope constraint** — do only what's asked, no extra files, no out-of-scope changes
4. **Reviews the result** before relaying to the user — checks for syntax errors (runs `bash -n` on shell scripts), obvious logic errors, or incomplete output
5. **Retries on Sonnet** if Haiku's output fails the quality check

**One-task = one subagent call.** Regardless of how many files a task touches, it goes to Haiku in a single call. Splitting one task into multiple subagent calls would cancel the cost savings (observed in benchmarks: 2 tasks → 12 Haiku calls).

---

### Why This Works: The Fresh Context Effect

The main Sonnet agent carries the full conversation history — every prior task, every file read, every user message. By the time it processes a search task deep in a session, its attention is diluted across hundreds of prior turns.

Haiku subagents start with a **clean context window** containing only the specific task. The entire model capacity goes to one job. This is why Haiku outperforms Sonnet on search and extraction tasks despite being a smaller model — it's not a weaker generalist, it's a focused specialist.

---

## Install

**Requires:** Claude Code CLI

```bash
git clone https://github.com/Kac291/ClaudeThrottle.git
cd ClaudeThrottle
bash scripts/install.sh
```

This will (all reversible):
- Copy routing rules to `~/.claude/throttle/`
- Append rule references to `~/.claude/CLAUDE.md`
- Merge hooks into `~/.claude/settings.json`
- Install the `/throttle` slash command

---

## Usage

In any Claude Code conversation:

```
/throttle status   — View routing state and cost savings
/throttle on       — Enable routing (default after install)
/throttle off      — Pause routing (back to pure Sonnet)
/throttle boost    — Next L3 task uses Opus (one-shot)
```

That's it. No modes to learn, no configuration needed.

---

## Uninstall

```bash
bash scripts/uninstall.sh          # Uninstall (keep logs)
bash scripts/uninstall.sh --purge  # Full uninstall (including logs)
```

---

## Architecture

```
ClaudeThrottle/
├── rules/
│   ├── base.md              # Task classification + routing strategy
│   ├── current.md           # Active/paused state
│   └── paused.md            # Paused state template
├── hooks/
│   ├── pre-tool-use.sh      # Opus gatekeeper + usage logging
│   └── stop.sh              # Session cost summary
├── config/
│   ├── models.json          # Model pricing data
│   ├── routing-table.json   # Task→model mapping
│   ├── paths.sh             # Path constants
│   ├── mode.txt             # on/off state
│   └── boost.txt            # Boost state (on/off)
├── scripts/
│   ├── install.sh / uninstall.sh
│   ├── switch-mode.sh       # on/off/boost/status handler
│   ├── token-stats.sh       # Real token usage from .jsonl
│   └── cost-report.sh       # Subagent cost breakdown
└── skills/
    └── throttle.md           # /throttle slash command
```

### Key Design Decisions

1. **Single strategy, not modes.** Benchmark proved that "Economy" (Haiku-first) is optimal in all scenarios. Multiple modes add complexity without value.

2. **Opus is opt-in, not automatic.** Opus costs 5x Sonnet but showed no quality improvement in benchmarks. The PreToolUse hook blocks unauthorized Opus calls.

3. **Haiku-first with fallback.** L2 tasks go to Haiku first. If quality is insufficient, Sonnet retries. This captures the 79% savings on tasks Haiku handles well.

4. **Debugging stays on Sonnet.** Benchmarked: Haiku consistently scores 4/5 on debugging (finds surface bugs, misses root causes). L2-debug routes to Sonnet directly — no wasted Haiku attempt.

5. **One task = one subagent call.** Anti-splitting rules prevent Claude from decomposing one task into multiple subagent calls (a real issue observed in benchmarks: 2 tasks → 12 Haiku calls).

6. **Subagent output constraints.** Every subagent prompt ends with a scope constraint to prevent "helpful over-delivery" (creating unrequested files, making out-of-scope changes).

7. **Quick quality review.** Main agent scans Haiku's output before relaying — catches failures early without redoing the task.

---

## Token Statistics

### Automatic (on session end)

The Stop hook generates a cost summary:
```
━━━ ClaudeThrottle 会话摘要 ━━━━━━━━━━━━━━━━
  Haiku 代理: 5 次调用
  估算节省: ~$0.08（vs 全 Sonnet）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Manual

```bash
# Single session stats
bash ~/.claude/throttle/scripts/token-stats.sh <session_id>

# List recent sessions
bash ~/.claude/throttle/scripts/token-stats.sh --list

# Compare two sessions (A baseline vs B with plugin)
bash ~/.claude/throttle/scripts/token-stats.sh <sid_a> <sid_b>
```

---

## Why Not Multiple Modes?

We built and benchmarked three modes (Economy/Balanced/Full Power). Results:

| Mode | Cost | Quality | Verdict |
|------|------|---------|---------|
| Economy (v2.0) | $0.79 | 48/50 | Winner, evolved into v2.1 |
| Balanced | $11.41 | 48/50 | 3x MORE expensive than no plugin |
| Full Power | $7.78 | 47/50 | 2x more expensive, worse quality |

Balanced and Full Power route L3 tasks to Opus ($75/M output tokens). This single decision costs more than all Haiku savings combined. We removed them.

---

## Why ClaudeThrottle, Not OpusPlan?

Claude Code CLI has a built-in "OpusPlan" feature: Opus plans, Sonnet executes. Here's how ClaudeThrottle compares:

| | OpusPlan | ClaudeThrottle |
|---|---------|---------------|
| **Planning model** | Opus ($15/$75 per M tokens) | Sonnet (free — it's the main agent) |
| **Execution model** | Sonnet | Haiku (4x cheaper) or Sonnet |
| **Cost direction** | Higher than baseline (adds Opus) | **79% lower** than baseline |
| **Quality** | No public benchmarks | **50/50** (matches or beats pure Sonnet) |
| **VSCode support** | Not available | Works everywhere |
| **CLI support** | CLI only | Works everywhere |
| **Configuration** | Feature flag, all-or-nothing | `/throttle on/off/boost` per-session |
| **Opus access** | Always on for planning | Opt-in, one-shot (`/throttle boost`) |

### The Core Difference

**OpusPlan adds cost at the top** — it uses Opus for planning on every task, whether the task needs it or not. A grep search doesn't need Opus to plan it.

**ClaudeThrottle removes cost at the bottom** — it routes simple and standard tasks to Haiku, keeps the main Sonnet agent for complex work, and only invokes Opus on explicit user request. The savings compound: 70% of tasks cost 1/4 as much.

### Why Quality is Higher, Not Just Equal

Across two benchmark rounds (20 tasks total, all new implementations in round 2), ClaudeThrottle scored **50/50** vs pure Sonnet's **50/50** — with Haiku actually outperforming Sonnet on several search and extraction tasks. There are structural reasons for both effects.

#### Why Haiku beats Sonnet on search and extraction tasks

In the benchmark, Haiku outperformed Sonnet on tasks it should theoretically be "worse" at:

- **File search (N1):** Haiku found files in the backup directory that Sonnet missed — Sonnet stopped at the obvious locations.
- **Information extraction (Task 2, N3):** Haiku extracted 6 risks from a document vs Sonnet's 5. Haiku matched all `echo` occurrences including sub-shell contexts; Sonnet only matched line-starting `echo`.
- **Documentation generation (N7):** Haiku produced a 1,500-word document with flow diagrams, comparison tables, and workflow examples. Sonnet produced a precise 200-word summary. Both met the requirements, but Haiku's output was more thorough.

**Why this happens:**

1. **Fresh context, no accumulated task history.** The main Sonnet agent carries the full conversation history — every prior task, every file read, every user message. By the time it processes a search task, its attention is diluted across hundreds of previous turns. The Haiku subagent starts with a clean context window containing only the specific task. Its full attention goes to one job.

2. **Specialization effect.** When Sonnet does a search as part of a multi-step session, it stops when it finds "enough." A Haiku subagent dispatched specifically to search has no other goal — it searches exhaustively until the task is done. This is the same reason specialists outperform generalists on narrow tasks even when the generalist is more capable overall.

3. **Haiku's architecture favors retrieval.** Haiku 4.5 is optimized for speed, retrieval, and long-context processing. These are exactly the properties that matter for L1 tasks. Using a model matched to the task type beats using a more powerful model that's optimized for different strengths.

4. **No anchoring bias.** Sonnet may pre-form a partial answer before executing a search (based on context it already knows), causing it to stop early when results confirm the expectation. Haiku has no prior context to anchor on, so it processes the task cold.

#### Structural quality improvements beyond raw model capability

1. **Forced task decomposition.** The routing classification forces Sonnet to explicitly think about task complexity before acting — even when Sonnet ultimately handles it. This deliberate framing improves output quality regardless of which model executes.

2. **Debugging stays on Sonnet, always.** L2-debug routes to Sonnet directly. Pure Sonnet has no such guardrail — it runs the same inference path whether the task is a grep or a root-cause analysis. ClaudeThrottle ensures the right model is used for the task that matters most.

3. **Output constraints prevent scope creep.** Every subagent prompt ends with a strict constraint: only do what's asked, don't create unrequested files, don't make out-of-scope changes. This prevents "helpful over-delivery" — a real failure mode observed in benchmarks where Haiku created diagnostic scripts nobody asked for.

4. **Quality gate catches failures before they reach the user.** The main agent scans Haiku's output before relaying it. For `.sh` files, it runs `bash -n` to verify syntax. This lightweight QA layer catches errors that pure Sonnet has no equivalent for — there's no second agent reviewing its own work.

### Platform Independence

OpusPlan requires Claude Code CLI with specific feature flags. It is **not available in VSCode** or other IDE integrations.

ClaudeThrottle works through CLAUDE.md rules and standard Claude Code hooks — both available in CLI, VSCode, JetBrains, and the web app. Install once to `~/.claude/`, use everywhere.

---

## License

MIT
