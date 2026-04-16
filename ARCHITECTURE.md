# ClaudeThrottle Architecture

## Core Constraint

Claude Code's main agent model is fixed per session. ClaudeThrottle cannot change it. What it CAN control:

| Mechanism | Capability | How We Use It |
|-----------|-----------|---------------|
| `Agent` tool `model` param | Choose subagent model (haiku/sonnet/opus) | **Core lever** — route tasks to cheaper models |
| CLAUDE.md rules | Control Claude's behavior | Drive routing decisions ("brain") |
| PreToolUse hook | Intercept tool calls, allow/deny/modify | **Opus gatekeeper** + usage logging |
| Stop hook | Run on session end | Cost summary + token stats |
| Slash command | User-facing skill | `/throttle` control interface |

**Key insight:** The main agent is the dispatcher, subagents are workers. ClaudeThrottle makes the dispatcher smarter about assignment.

---

## System Layers

```
┌─────────────────────────────────────────────┐
│                 User Layer                   │
│   /throttle on | off | boost | status       │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│           Rule Layer (CLAUDE.md)             │
│                                              │
│  base.md: Task classification (L1/L2/L3)    │
│  + Single routing strategy                   │
│  + Anti-splitting discipline                 │
│  + Boost mechanism for Opus                  │
│                                              │
│  current.md: Active / Paused state           │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│          Routing Engine (Main Agent)         │
│                                              │
│  Sonnet receives user request, then:         │
│  1. Classify task → L1 / L2 / L3            │
│  2. Route:                                   │
│     L1 → Haiku subagent                     │
│     L2 → Haiku subagent (Sonnet fallback)   │
│     L3 → Self (Sonnet)                      │
│          └─ If Boost active → Opus subagent │
└──────┬───────────────────────────────────────┘
       │
┌──────▼──────────────────────────────────────┐
│          Enforcement Layer (Hooks)           │
│                                              │
│  pre-tool-use.sh:                            │
│  ├─ Extract session_id from stdin JSON       │
│  ├─ If Agent call with model=opus:           │
│  │   ├─ boost.txt == "on" → Allow, clear    │
│  │   └─ boost.txt != "on" → DENY            │
│  └─ Log: timestamp|session|model|status      │
│                                              │
│  stop.sh:                                    │
│  ├─ Extract session_id from stdin JSON       │
│  ├─ Run token-stats.sh                       │
│  └─ Output savings summary to log            │
└──────────────────────────────────────────────┘
```

---

## File Structure

```
ClaudeThrottle/
├── rules/
│   ├── base.md              # Classification + routing + discipline
│   ├── current.md           # State: active or paused
│   ├── paused.md            # Paused state template
│   └── deprecated/          # Old v1 mode files (reference only)
├── hooks/
│   ├── pre-tool-use.sh      # Opus gatekeeper + logging
│   └── stop.sh              # Session end: stats + summary
├── config/
│   ├── models.json          # Model pricing & capabilities
│   ├── routing-table.json   # Task→model mapping (single strategy)
│   ├── paths.sh             # Centralized path constants
│   ├── mode.txt             # "on" or "off"
│   └── boost.txt            # "on" or "off" (one-shot Opus)
├── scripts/
│   ├── install.sh           # One-command install
│   ├── uninstall.sh         # Clean uninstall
│   ├── switch-mode.sh       # on/off/boost/status handler
│   ├── token-stats.sh       # Parse .jsonl for real token usage
│   ├── cost-report.sh       # Subagent cost breakdown
│   ├── merge-settings.ps1   # PowerShell settings.json merger
│   └── merge-settings.py    # Python settings.json merger
├── skills/
│   └── throttle.md          # /throttle slash command definition
└── CLAUDE.md                # Project entry point, loads rules
```

---

## Key Design Decisions

### 1. Single Strategy, Not Modes

**v1** had three modes (Economy/Balanced/Full Power). Benchmark showed:
- Economy: 79% savings, 48/50 quality
- Balanced: 3x MORE expensive, same quality
- Full Power: 2x MORE expensive, WORSE quality

**v2** uses Economy's strategy as the only strategy. Simpler, proven optimal.

### 2. Opus is Gated, Not Automatic

Opus at $75/M output is 5x Sonnet. Benchmark showed no quality improvement for L3 tasks. The PreToolUse hook **blocks** Opus calls unless the user explicitly activates Boost. This prevents the "Opus trap" where automatic routing to Opus costs more than no plugin at all.

### 3. Haiku-First with Fallback

L2 tasks go to Haiku first. If the result is clearly wrong/incomplete, Sonnet retries. This is the key to 79% savings — most L2 tasks succeed on Haiku.

**Failure criteria** (from base.md):
- Result obviously incomplete or missing key content
- Code has syntax errors or clear logic bugs
- Haiku explicitly says it's unsure
- NOT failure: style differences, sparse comments, formatting preferences

### 4. Anti-Splitting Discipline

Benchmark found 2 L1 tasks exploding into 12 Haiku calls (Claude over-decomposed them). base.md now enforces: **one user request = at most one subagent call per task**. This is critical for cost control.

### 5. Session ID from stdin, Not Environment

Claude Code does NOT set `CLAUDE_SESSION_ID` as an environment variable for hooks. It provides `session_id` in the stdin JSON. Both hooks now extract it from stdin, fixing the usage.log data quality issue from v1.

---

## Data Flow

```
User request → Sonnet reads base.md rules
  → Classifies task (L1/L2/L3)
  → Calls Agent tool with model:"haiku" (or "opus" if boosted)
    → PreToolUse hook fires:
       ├─ Reads stdin JSON {session_id, tool_name, tool_input:{model,prompt}}
       ├─ If model=opus and boost=off → DENY (returns deny JSON)
       ├─ If model=opus and boost=on → ALLOW, clear boost
       └─ Logs to usage.log
    → Subagent executes
    → Result returns to Sonnet
       ├─ Quality OK → Done
       └─ Quality bad → Sonnet retries itself

Session ends → Stop hook fires:
  ├─ Reads stdin JSON {session_id, transcript_path, ...}
  ├─ Runs token-stats.sh with real session_id
  └─ Writes savings summary to token-stats.log
```

---

## Pricing Reference

| Model | Input/M | Output/M | Cache Read | Cache Write |
|-------|---------|----------|------------|-------------|
| Haiku 4.5 | $0.80 | $4.00 | 10% of input | 125% of input |
| Sonnet 4.6 | $3.00 | $15.00 | 10% of input | 125% of input |
| Opus 4.6 | $15.00 | $75.00 | 10% of input | 125% of input |

Per-call savings estimate (avg 2K in + 1K out):
- Haiku call: $0.0056
- Sonnet call: $0.021
- **Savings per Haiku delegation: $0.0154**
