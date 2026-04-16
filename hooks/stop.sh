#!/usr/bin/env bash
# ClaudeThrottle Stop Hook
# 会话结束时：记录调试信息、生成成本报告、可选播报节省摘要

# shellcheck source=../config/paths.sh
source "${CLAUDE_THROTTLE_DIR:-$HOME/.claude/throttle}/config/paths.sh"
REPORT_SCRIPT="$SCRIPTS_DIR/cost-report.sh"
TOKEN_STATS_SCRIPT="$SCRIPTS_DIR/token-stats.sh"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "off")
BROADCAST=$(cat "$BROADCAST_FILE" 2>/dev/null | tr -d ' \r\n' || echo "on")

# 读取 stdin（Claude Code 传入的会话数据 JSON）
INPUT=$(cat)

# 从 stdin JSON 提取 session_id
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | \
    sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d)}"
SESSION_ID="${SESSION_ID//$'\r'/}"
SESSION_ID="$(echo "$SESSION_ID" | xargs)"

# 将原始 stdin 保存到 debug log（只保留最近 100 行）
echo "=== $TIMESTAMP | session=$SESSION_ID | mode=$CURRENT_MODE | broadcast=$BROADCAST ===" >> "$STOP_DEBUG_LOG"
echo "$INPUT" >> "$STOP_DEBUG_LOG"
echo "" >> "$STOP_DEBUG_LOG"
tail -100 "$STOP_DEBUG_LOG" > "$STOP_DEBUG_LOG.tmp" && mv "$STOP_DEBUG_LOG.tmp" "$STOP_DEBUG_LOG"

# Token 统计（每次会话结束都生成）
if [[ -x "$TOKEN_STATS_SCRIPT" && -n "$SESSION_ID" ]]; then
    bash "$TOKEN_STATS_SCRIPT" "$SESSION_ID" >> "$TOKEN_STATS_LOG" 2>/dev/null || true
fi

# 如果本会话有 subagent 调用，额外生成 subagent 成本报告
if [[ -f "$USAGE_LOG" && -f "$REPORT_SCRIPT" && -n "$SESSION_ID" ]]; then
    GREP_RESULT=$(grep -F "|${SESSION_ID}|agent|" "$USAGE_LOG" 2>>"$STOP_DEBUG_LOG")
    if [[ -n "$GREP_RESULT" ]]; then
        bash "$REPORT_SCRIPT" "$SESSION_ID" >> "$TOKEN_STATS_LOG" 2>/dev/null || true
    else
        {
            echo "  [stop.sh] no subagent records found"
            echo "    session_id='${SESSION_ID}' (length=${#SESSION_ID})"
            echo "    usage_log exists: $(test -f "$USAGE_LOG" && echo yes || echo no)"
            test -f "$USAGE_LOG" && echo "    usage_log sample (last 3 lines):" && tail -3 "$USAGE_LOG" | sed 's/^/      /'
        } >> "$STOP_DEBUG_LOG"
    fi
fi

# ── 节省摘要播报 ──────────────────────────────────────────
# 仅在：路由已启用 + 播报已开启 + 本会话有 Haiku 调用时触发
if [[ -f "$USAGE_LOG" && "$CURRENT_MODE" == "on" && "$BROADCAST" == "on" ]]; then
    HAIKU_COUNT=$(grep -c "|${SESSION_ID}|agent|haiku|" "$USAGE_LOG" 2>/dev/null || echo 0)
    HAIKU_COUNT=${HAIKU_COUNT:-0}
    OPUS_COUNT=$(grep -c "|${SESSION_ID}|agent|opus|BOOSTED|" "$USAGE_LOG" 2>/dev/null || echo 0)
    OPUS_COUNT=${OPUS_COUNT:-0}
    BLOCKED_COUNT=$(grep -c "|${SESSION_ID}|agent|opus|BLOCKED|" "$USAGE_LOG" 2>/dev/null || echo 0)
    BLOCKED_COUNT=${BLOCKED_COUNT:-0}

    if [[ $HAIKU_COUNT -gt 0 ]]; then
        SAVED=$(awk -v n="$HAIKU_COUNT" 'BEGIN{printf "%.2f", n * 0.0154}')

        # 构建摘要文本
        SUMMARY_TEXT="━━━ ClaudeThrottle 会话摘要 ━━━━━━━━━━━━━━━━\n"
        SUMMARY_TEXT+="  Haiku 代理: ${HAIKU_COUNT} 次调用\n"
        [[ $OPUS_COUNT -gt 0 ]]   && SUMMARY_TEXT+="  Opus 代理: ${OPUS_COUNT} 次调用（Boost）\n"
        [[ $BLOCKED_COUNT -gt 0 ]] && SUMMARY_TEXT+="  Opus 拦截: ${BLOCKED_COUNT} 次（未授权）\n"
        SUMMARY_TEXT+="  估算节省: ~\$${SAVED}（vs 全 Sonnet）\n"
        SUMMARY_TEXT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 追加到日志文件
        printf '\n%b\n' "$SUMMARY_TEXT" >> "$TOKEN_STATS_LOG"

        # 通过 JSON continue 指令注入摘要，让 Claude 在对话中输出
        # additionalContext 会作为新的用户消息注入，触发 Claude 最后一次回复
        ESCAPED=$(printf '%s' "$SUMMARY_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
        printf '%s\n' "{\"continue\":true,\"suppressOutput\":false,\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":\"请将以下摘要原文输出给用户，不要添加任何额外内容：\\n${ESCAPED}\"}}"
        exit 0
    fi
fi

exit 0
