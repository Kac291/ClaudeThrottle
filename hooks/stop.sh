#!/usr/bin/env bash
# ClaudeThrottle Stop Hook
# 会话结束时：提取 session_id、记录调试信息、生成成本报告、输出节省摘要

# shellcheck source=../config/paths.sh
source "${CLAUDE_THROTTLE_DIR:-$HOME/.claude/throttle}/config/paths.sh"
REPORT_SCRIPT="$SCRIPTS_DIR/cost-report.sh"
TOKEN_STATS_SCRIPT="$SCRIPTS_DIR/token-stats.sh"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "off")

# 读取 stdin（Claude Code 传入的会话数据 JSON）
INPUT=$(cat)

# 从 stdin JSON 提取 session_id（修复：不再依赖环境变量）
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | \
    sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d)}"
SESSION_ID="${SESSION_ID//$'\r'/}"
SESSION_ID="$(echo "$SESSION_ID" | xargs)"  # trim leading/trailing whitespace

# 将原始 stdin 保存到 debug log（只保留最近 100 行）
echo "=== $TIMESTAMP | session=$SESSION_ID | mode=$CURRENT_MODE ===" >> "$STOP_DEBUG_LOG"
echo "$INPUT" >> "$STOP_DEBUG_LOG"
echo "" >> "$STOP_DEBUG_LOG"
tail -100 "$STOP_DEBUG_LOG" > "$STOP_DEBUG_LOG.tmp" && mv "$STOP_DEBUG_LOG.tmp" "$STOP_DEBUG_LOG"

# Token 统计（每次会话结束都生成）
if [[ -x "$TOKEN_STATS_SCRIPT" && -n "$SESSION_ID" ]]; then
    bash "$TOKEN_STATS_SCRIPT" "$SESSION_ID" >> "$TOKEN_STATS_LOG" 2>/dev/null || true
fi

# 如果本会话有 subagent 调用，额外生成 subagent 成本报告
if [[ -f "$USAGE_LOG" && -f "$REPORT_SCRIPT" && -n "$SESSION_ID" ]]; then
    # 使用 grep 匹配标准格式：TIMESTAMP|SESSION_ID|agent|...
    # -F 使用固定字符串匹配（不解释正则），避免 sed/awk 的复杂性
    GREP_RESULT=$(grep -F "|${SESSION_ID}|agent|" "$USAGE_LOG" 2>>"$STOP_DEBUG_LOG")
    if [[ -n "$GREP_RESULT" ]]; then
        bash "$REPORT_SCRIPT" "$SESSION_ID"
    else
        # 诊断信息：记录搜索失败的上下文
        {
            echo "  [stop.sh] no subagent records found"
            echo "    session_id='${SESSION_ID}' (length=${#SESSION_ID})"
            echo "    grep pattern: |${SESSION_ID}|agent|"
            echo "    usage_log exists: $(test -f "$USAGE_LOG" && echo yes || echo no)"
            test -f "$USAGE_LOG" && echo "    usage_log sample (last 3 lines):" && tail -3 "$USAGE_LOG" | sed 's/^/      /'
        } >> "$STOP_DEBUG_LOG"
    fi
fi

# ── 节省摘要 ──────────────────────────────────────────────
# 统计本会话 Haiku subagent 调用次数
if [[ -f "$USAGE_LOG" && "$CURRENT_MODE" == "on" ]]; then
    HAIKU_COUNT=$(grep -c "|${SESSION_ID}|agent|haiku|" "$USAGE_LOG" 2>/dev/null || echo 0)
    HAIKU_COUNT=${HAIKU_COUNT:-0}
    OPUS_COUNT=$(grep -c "|${SESSION_ID}|agent|opus|" "$USAGE_LOG" 2>/dev/null || echo 0)
    OPUS_COUNT=${OPUS_COUNT:-0}
    BLOCKED_COUNT=$(grep -c "|${SESSION_ID}|agent|opus|BLOCKED|" "$USAGE_LOG" 2>/dev/null || echo 0)
    BLOCKED_COUNT=${BLOCKED_COUNT:-0}

    if [[ $HAIKU_COUNT -gt 0 ]]; then
        # 粗略估算：每次 Haiku 调用平均 2K in + 1K out
        # Haiku 成本: 2000*0.0000008 + 1000*0.000004 = $0.0056
        # Sonnet 成本: 2000*0.000003 + 1000*0.000015 = $0.021
        # 每次节省: $0.021 - $0.0056 = $0.0154
        SAVED=$(awk -v n="$HAIKU_COUNT" 'BEGIN{printf "%.2f", n * 0.0154}')
        SUMMARY=$(cat <<SUMMARY_EOF

━━━ ClaudeThrottle 会话摘要 ━━━━━━━━━━━━━━━━
  Haiku 代理: ${HAIKU_COUNT} 次调用
$(  [[ $OPUS_COUNT -gt 0 ]] && echo "  Opus 代理: ${OPUS_COUNT} 次调用（Boost）")
$(  [[ $BLOCKED_COUNT -gt 0 ]] && echo "  Opus 拦截: ${BLOCKED_COUNT} 次（未授权）")
  估算节省: ~\$${SAVED}（vs 全 Sonnet）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY_EOF
)
        # 输出到 stdout（显示在 Claude Code 会话中）
        echo "$SUMMARY"
        # 同时追加到日志文件
        echo "$SUMMARY" >> "$TOKEN_STATS_LOG"
    fi
fi

exit 0
