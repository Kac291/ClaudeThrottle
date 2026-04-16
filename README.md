# ClaudeThrottle

**Claude Code cost optimizer for Sonnet users** — when Sonnet is your main model, the plugin routes simple subagent work to Haiku and saves **79% with zero quality loss** (benchmarked).

> ⚠️ **Opus users: do not install.** Benchmarked with Opus as main, this plugin makes runs **30% more expensive** and slightly worse quality. Opus's $75/MTok output makes the routing-meta tokens (writing prompts to Haiku, summarizing returns) cost more than Haiku saves. See [benchmark/results.md](benchmark/results.md#第三轮测试opus-主模型对比e-vs-f).

---

## The Idea in One Sentence

Whatever model you chose to drive your Claude Code session (Sonnet for balanced cost/quality, Opus for max reasoning), ~70% of what it spends tokens on is mechanical — file searches, single-file edits, test writing, doc generation. ClaudeThrottle delegates those to Haiku subagents, keeps the hard reasoning on your main model, and only reaches for Opus when you explicitly ask.

```
User request
  └→ Main Agent (your chosen model: Sonnet or Opus) classifies the task
       ├─ L1 (search/retrieval)  → Haiku subagent
       ├─ L2 (code gen/edit)     → Haiku subagent (main model retries if needed)
       ├─ L2-debug (debugging)   → Main model handles directly (Haiku's weak spot)
       └─ L3 (complex reasoning) → Main model handles it directly
                                     ↑
                              Optional: /throttle boost → Opus subagent for next L3
```

Routing rules are embedded in CLAUDE.md — zero extra API calls, zero latency overhead. A PreToolUse hook enforces that Opus subagents are never dispatched without explicit user authorization (`/throttle boost`).

---

## Benchmark Results

| Setup | Cost | Quality | Δ vs no plugin |
|-------|------|---------|----------------|
| No plugin (pure Sonnet main) | $3.70 | 50/50 | — |
| **ClaudeThrottle (Sonnet main)** | **~$0.79** | **50/50** | **−79%** ✅ |
| No plugin (pure Opus main) | $20.33 | 50/50 | — |
| ClaudeThrottle (Opus main) | $29.11 | 45.5/50 | **+43%** ❌ |

> 20-task benchmark (Sonnet, 2 rounds) + 10-task benchmark (Opus, dual session). Full report: [benchmark/results.md](benchmark/results.md).

**Why Opus is the wrong fit (and we got it wrong initially):** We expected Opus's higher token price to make Haiku delegation save *more* in absolute dollars. The benchmark proved the opposite: Opus's $75/MTok output makes the routing meta-text (deciding the route, writing the Haiku prompt, summarizing what Haiku returned) cost *more* than the Haiku call saves. The plugin's architecture assumes main-model output cost is comparable to the routing overhead — true for Sonnet, false for Opus. Until this is redesigned (lighter routing chatter, more aggressive delegation), Opus users should run pure.

---

## Routing Logic

### Step 1: Task Classification

The main agent classifies every incoming task into one of four levels before acting:

| Level | What it is | Signal words | Examples |
|-------|-----------|--------------|---------|
| **L1** | Retrieval — no reasoning needed | find, search, list, read, count, show | File search, grep, directory listing, info extraction |
| **L2** | Generation/modification — scoped, no system-level tradeoffs | (none specific) | Write a function, modify a file, generate tests, write docs |
| **L2-debug** | Debugging — causal chain tracing, root-cause analysis | bug, error, broken, why failing, fix, debug | Bug fixes, script not working, log analysis |
| **L3** | Complex reasoning — cross-file, multi-step, architectural | why, design, architecture, refactor, root cause, tradeoffs | Cross-module refactors, architecture design, security audits |

**Classification principle:** When uncertain, prefer L2 over L3. Debugging tasks always go to L2-debug, never plain L2.

---

### Step 2: Routing Decision

Once classified, the routing is deterministic — and independent of which main model you're using:

| Level | Who executes | Why |
|-------|-------------|-----|
| L1 | Haiku subagent | Pure retrieval — fresh context improves coverage |
| L2 | Haiku subagent → main model fallback | Haiku handles 90%+ of cases; main model retries only on failure |
| L2-debug | Main model (self) | Root-cause tracing requires recursive "why" reasoning — Haiku's weak spot |
| L3 | Main model (self) | Multi-file reasoning, architectural tradeoffs |
| L3 + Boost | Opus subagent | One-shot, user-authorized — Boost turns off immediately after |

The table above describes how the plugin *intends* to work regardless of main model. **In practice it only nets savings when main = Sonnet** — see the warning at the top of this README and the Opus benchmark for why.

---

### Step 3: Subagent Execution

For L1/L2 tasks dispatched to Haiku, the main agent:

1. **Reads the relevant file section** (for L2-modify tasks) and embeds it directly in the subagent prompt — Haiku gets the current code without needing to read files itself
2. **Adds a "check first" instruction** — if the requested change already exists, return immediately without modifying
3. **Appends a scope constraint** — do only what's asked, no extra files, no out-of-scope changes
4. **Reviews the result** before relaying to the user — checks for syntax errors (runs `bash -n` on shell scripts), obvious logic errors, or incomplete output
5. **Retries on the main model** if Haiku's output fails the quality check

**One-task = one subagent call.** Regardless of how many files a task touches, it goes to Haiku in a single call. Splitting one task into multiple subagent calls would cancel the cost savings (observed in benchmarks: 2 tasks → 12 Haiku calls).

---

### Why This Works: The Fresh Context Effect

Your main agent carries the full conversation history — every prior task, every file read, every user message. By the time it processes a search task deep in a session, its attention is diluted across hundreds of prior turns.

Haiku subagents start with a **clean context window** containing only the specific task. The entire model capacity goes to one job. This is why Haiku outperforms even Sonnet on search and extraction tasks despite being smaller — it's not a weaker generalist, it's a focused specialist.

---

## Install

**Requires:** Claude Code CLI or any Claude Code-compatible client (VSCode extension, JetBrains, web app).

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

Pick your main model via Claude Code's `/model` command (Sonnet or Opus). Then in any conversation:

```
/throttle status          — View routing state and cost savings
/throttle on              — Enable routing (default after install)
/throttle off             — Pause routing (back to pure main model)
/throttle boost           — Next L3 task uses Opus subagent (one-shot)
/throttle broadcast on    — Show per-turn cost summary after every response (default: on)
/throttle broadcast off   — Silence the summary (still logged to file)
```

**Boost is most useful when main = Sonnet** — it gives you one-shot access to Opus reasoning without paying for Opus on every task. If main is already Opus, the main agent itself already covers L3 work; Boost is only relevant if you specifically want a fresh-context Opus subagent.

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
│   └── stop.sh              # Per-turn cost summary
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

1. **Main model is the user's choice, not the plugin's.** Sonnet or Opus — ClaudeThrottle works with either. The routing rules only decide what gets delegated to Haiku; the main model stays whatever you set.

2. **Single strategy, not modes.** Benchmark proved that "Economy" (Haiku-first) is optimal in all scenarios. Multiple routing modes add complexity without value.

3. **Opus subagents are opt-in, not automatic.** Opus costs 5x Sonnet but showed no quality improvement for L3 tasks in benchmarks when dispatched as a subagent. The PreToolUse hook blocks unauthorized Opus subagent calls. (This is separate from using Opus as your main model, which is always your call.)

4. **Haiku-first with fallback.** L2 tasks go to Haiku first. If quality is insufficient, the main model retries. This captures the 79% savings on tasks Haiku handles well.

5. **Debugging stays on the main model.** Benchmarked: Haiku consistently scores 4/5 on debugging (finds surface bugs, misses root causes). L2-debug routes to the main model directly — no wasted Haiku attempt.

6. **One task = one subagent call.** Anti-splitting rules prevent the main agent from decomposing one task into multiple subagent calls (a real issue observed in benchmarks: 2 tasks → 12 Haiku calls).

7. **Subagent output constraints.** Every subagent prompt ends with a scope constraint to prevent "helpful over-delivery" (creating unrequested files, making out-of-scope changes).

8. **Quick quality review.** The main agent scans Haiku's output before relaying — catches failures early without redoing the task.

---

## Per-Turn Cost Summary

After every response, ClaudeThrottle shows a live cost breakdown (Sonnet main):

```
━━ ClaudeThrottle 本轮 ━━━━━━━━━━━━━━━━━━━━
  调用: Haiku×2 + Sonnet×1（主模型）
  原本: Sonnet×3
  节省: ~$0.0440  ↓67%  (~1250 tokens via Haiku)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When no routing occurred (L2-debug or L3 tasks handled directly by the main model):

```
━━ ClaudeThrottle 本轮 ━━━━━━━━━━━━━━━━━━━━
  调用: Sonnet×1（L2-debug / L3，直接执行）
  原本: Sonnet×1
  节省: $0（本轮无 Haiku 路由）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> Per-turn numbers above are *per-call* estimates from the broadcast hook. They do not account for the main agent's own routing-meta tokens (writing prompts to Haiku, summarizing returns), which is why the Opus full-session benchmark shows a net loss despite the per-call display looking favorable.

Toggle with `/throttle broadcast off` to silence.

---

## Token Statistics

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

Balanced and Full Power routed L3 tasks to Opus *subagents automatically* ($75/M output tokens). This single decision costs more than all Haiku savings combined. We removed them. Note this is about Opus-as-automatic-subagent, not Opus-as-user-chosen-main-model — the latter is completely fine and still benefits from Haiku routing for L1/L2.

---

## Why ClaudeThrottle, Not OpusPlan?

Claude Code CLI has a built-in "OpusPlan" feature: Opus plans, Sonnet executes. Here's how ClaudeThrottle compares:

| | OpusPlan | ClaudeThrottle |
|---|---------|---------------|
| **Planning model** | Opus ($15/$75 per M tokens), always | Your main model (Sonnet or Opus) — no extra planning call |
| **Execution model** | Sonnet | Haiku (4x cheaper than Sonnet, 19x cheaper than Opus) or main model |
| **Cost direction** | Higher than baseline (adds Opus) | **Lower than baseline with Sonnet main** (−79%); **higher with Opus main** (+43%, do not use) |
| **Quality** | No public benchmarks | **50/50** (matches or beats pure Sonnet) |
| **VSCode support** | Not available | Works everywhere |
| **CLI support** | CLI only | Works everywhere |
| **Configuration** | Feature flag, all-or-nothing | `/throttle on/off/boost` per-session |
| **Main model choice** | Fixed (Opus plans, Sonnet executes) | Free — user picks Sonnet or Opus |
| **Opus subagent access** | Always on for planning | Opt-in, one-shot (`/throttle boost`) |

### The Core Difference

**OpusPlan adds cost at the top** — it uses Opus for planning on every task, whether the task needs it or not. A grep search doesn't need Opus to plan it.

**ClaudeThrottle removes cost at the bottom** — it routes simple and standard tasks to Haiku, keeps your main model for complex work, and only invokes Opus as a subagent on explicit user request. The savings compound: 70% of tasks cost 1/4 as much, regardless of what you picked for the other 30%.

### Why Quality is Higher, Not Just Equal

Across two benchmark rounds (20 tasks total, all new implementations in round 2), ClaudeThrottle scored **50/50** vs pure Sonnet's **50/50** — with Haiku actually outperforming Sonnet on several search and extraction tasks. There are structural reasons for both effects.

#### Why Haiku beats the main model on search and extraction tasks

In the benchmark (Sonnet as main), Haiku outperformed Sonnet on tasks it should theoretically be "worse" at:

- **File search (N1):** Haiku found files in the backup directory that Sonnet missed — Sonnet stopped at the obvious locations.
- **Information extraction (Task 2, N3):** Haiku extracted 6 risks from a document vs Sonnet's 5. Haiku matched all `echo` occurrences including sub-shell contexts; Sonnet only matched line-starting `echo`.
- **Documentation generation (N7):** Haiku produced a 1,500-word document with flow diagrams, comparison tables, and workflow examples. Sonnet produced a precise 200-word summary. Both met the requirements, but Haiku's output was more thorough.

**Why this happens:**

1. **Fresh context, no accumulated task history.** The main agent carries the full conversation history — every prior task, every file read, every user message. By the time it processes a search task, its attention is diluted across hundreds of previous turns. The Haiku subagent starts with a clean context window containing only the specific task. Its full attention goes to one job.

2. **Specialization effect.** When the main model does a search as part of a multi-step session, it stops when it finds "enough." A Haiku subagent dispatched specifically to search has no other goal — it searches exhaustively until the task is done. This is the same reason specialists outperform generalists on narrow tasks even when the generalist is more capable overall.

3. **Haiku's architecture favors retrieval.** Haiku 4.5 is optimized for speed, retrieval, and long-context processing. These are exactly the properties that matter for L1 tasks. Using a model matched to the task type beats using a more powerful model that's optimized for different strengths.

4. **No anchoring bias.** The main model may pre-form a partial answer before executing a search (based on context it already knows), causing it to stop early when results confirm the expectation. Haiku has no prior context to anchor on, so it processes the task cold.

#### Structural quality improvements beyond raw model capability

1. **Forced task decomposition.** The routing classification forces the main agent to explicitly think about task complexity before acting — even when it ultimately handles the task itself. This deliberate framing improves output quality regardless of which model executes.

2. **Debugging stays on the main model, always.** L2-debug routes to the main agent directly. Pure Sonnet or pure Opus has no such guardrail — it runs the same inference path whether the task is a grep or a root-cause analysis. ClaudeThrottle ensures the heavy-reasoning model is used for the task that matters most.

3. **Output constraints prevent scope creep.** Every subagent prompt ends with a strict constraint: only do what's asked, don't create unrequested files, don't make out-of-scope changes. This prevents "helpful over-delivery" — a real failure mode observed in benchmarks where Haiku created diagnostic scripts nobody asked for.

4. **Quality gate catches failures before they reach the user.** The main agent scans Haiku's output before relaying it. For `.sh` files, it runs `bash -n` to verify syntax. This lightweight QA layer catches errors that pure Sonnet or pure Opus has no equivalent for — there's no second agent reviewing its own work.

### Platform Independence

OpusPlan requires Claude Code CLI with specific feature flags. It is **not available in VSCode** or other IDE integrations.

ClaudeThrottle works through CLAUDE.md rules and standard Claude Code hooks — both available in CLI, VSCode, JetBrains, and the web app. Install once to `~/.claude/`, use everywhere.

---

## License

MIT
