#!/usr/bin/env bash
# ClaudeThrottle PreToolUse Hook
# 1. 记录 Agent subagent 调用（模型、prompt 长度）
# 2. 拦截未授权的 Opus 调用（Boost 未激活时拒绝）

# shellcheck source=../config/paths.sh
source "${CLAUDE_THROTTLE_DIR:-$HOME/.claude/throttle}/config/paths.sh"
LOG_FILE="$USAGE_LOG"

mkdir -p "$LOG_DIR"

# 从 stdin 读取 Claude Code 传入的 JSON
INPUT=$(cat)

# 提取字段（纯 bash，不依赖 python/jq）
extract_field() {
    echo "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
        sed "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/" | head -1
}

TOOL_NAME=$(extract_field "tool_name")
TOOL_NAME="${TOOL_NAME:-${CLAUDE_TOOL_NAME:-}}"

# 从 stdin JSON 提取 session_id（修复：不再依赖环境变量）
SESSION_ID=$(extract_field "session_id")
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d)}"
SESSION_ID="${SESSION_ID//$'\r'/}"   # strip CR — Windows env vars may carry \r
SESSION_ID="$(echo "$SESSION_ID" | xargs)"  # trim leading/trailing whitespace

TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

if [[ "$TOOL_NAME" == "Agent" ]]; then
    # 提取 model 字段（在 tool_input 内）
    MODEL=$(extract_field "model")
    MODEL="${MODEL:-sonnet}"

    # 提取 prompt 长度（字符数）
    PROMPT=$(echo "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
    PROMPT_LEN=${#PROMPT}

    # ── Opus 拦截 ──────────────────────────────────────────
    if [[ "$MODEL" == "opus" ]]; then
        BOOST=$(cat "$BOOST_FILE" 2>/dev/null || echo "off")
        BOOST="${BOOST//$'\r'/}"
        BOOST="${BOOST//$'\n'/}"

        if [[ "$BOOST" != "on" ]]; then
            # Boost 未激活，拒绝 Opus 调用
            echo "$TIMESTAMP|$SESSION_ID|agent|opus|BLOCKED|$PROMPT_LEN" >> "$LOG_FILE"
            cat << 'DENY_JSON'
{
  "continue": true,
  "suppressOutput": false,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "ClaudeThrottle: Opus 未授权。请先运行 /throttle boost 激活 Boost，或使用 Sonnet（自己执行）处理此任务。",
    "additionalContext": "Opus subagent 仅在 Boost 模式下可用（一次性）。当前路由策略：L1/L2→Haiku, L3→Sonnet。"
  }
}
DENY_JSON
            exit 0
        fi

        # Boost 激活，允许 Opus 并关闭 Boost（一次性）
        echo "off" > "$BOOST_FILE"
        echo "$TIMESTAMP|$SESSION_ID|agent|opus|BOOSTED|$PROMPT_LEN" >> "$LOG_FILE"
        exit 0
    fi

    # ── 正常记录（Haiku / Sonnet）────────────────────────
    echo "$TIMESTAMP|$SESSION_ID|agent|$MODEL|ok|$PROMPT_LEN" >> "$LOG_FILE"
fi

# 允许工具执行
exit 0
