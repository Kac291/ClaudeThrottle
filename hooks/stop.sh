#!/usr/bin/env bash
# ClaudeThrottle Stop Hook
# 每轮输出后：记录调试信息、生成成本报告、播报本轮节省摘要

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

# 从 stdin JSON 提取 stop_hook_active
# true = 本次 Stop 是由先前 hook 的 continue:true 触发的（Claude 在输出我们注入的摘要）
# false = 真实用户轮次结束
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*\(true\|false\)' | \
    sed 's/.*:[[:space:]]*\(true\|false\).*/\1/' | head -1)
STOP_HOOK_ACTIVE="${STOP_HOOK_ACTIVE:-false}"

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

# ── 每轮节省摘要播报 ──────────────────────────────────────────
# 在：路由已启用 + 播报已开启 时，每轮必播
if [[ "$CURRENT_MODE" == "on" && "$BROADCAST" == "on" ]]; then

    # ── 防循环：检测 Claude Code 的 stop_hook_active 标志 ──────
    # 当 hook 上次返回 continue:true 触发 Claude 输出摘要时，
    # 这次 Stop 事件的 stdin JSON 会带 stop_hook_active=true。
    # 直接跳过，不依赖外部状态文件（更稳，不会卡）。
    if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
        exit 0
    fi

    # ── 本轮 subagent 调用统计 ─────────────────────────────────
    TURN_START=$(cat "$TURN_MARKER_FILE" 2>/dev/null | tr -d '\r\n ' || echo "1970-01-01T00:00:00")

    TURN_HAIKU=0; TURN_OPUS=0; TURN_HAIKU_TOKENS=0
    if [[ -f "$USAGE_LOG" ]]; then
        TURN_HAIKU=$(awk -F'|' -v s="$TURN_START" -v sid="$SESSION_ID" '
            $1 > s && $2 == sid && $4 == "haiku" && $5 == "ok" {c++}
            END {print c+0}' "$USAGE_LOG")
        TURN_OPUS=$(awk -F'|' -v s="$TURN_START" -v sid="$SESSION_ID" '
            $1 > s && $2 == sid && $4 == "opus" && $5 == "BOOSTED" {c++}
            END {print c+0}' "$USAGE_LOG")
        TURN_HAIKU_TOKENS=$(awk -F'|' -v s="$TURN_START" -v sid="$SESSION_ID" '
            $1 > s && $2 == sid && $4 == "haiku" && $5 == "ok" {t += $6}
            END {printf "%d", t/4}' "$USAGE_LOG")
    fi

    # 更新轮次标记（供下一轮使用）
    echo "$TIMESTAMP" > "$TURN_MARKER_FILE"

    # ── 从 transcript 解析主模型 ──────────────────────────────
    # stdin JSON 给出 transcript_path，读 .jsonl 最后一条 assistant
    # 消息的 model 字段，映射成本估算。
    TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | \
        sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    # 还原 JSON 转义的反斜杠：\\ → \
    TRANSCRIPT_PATH="${TRANSCRIPT_PATH//\\\\/\\}"
    # Windows 路径转 Unix：C:\X\Y → /c/X/Y
    if [[ "$TRANSCRIPT_PATH" =~ ^[A-Za-z]: ]]; then
        DRIVE_LOWER=$(printf '%s' "${TRANSCRIPT_PATH:0:1}" | tr '[:upper:]' '[:lower:]')
        TRANSCRIPT_PATH="/${DRIVE_LOWER}${TRANSCRIPT_PATH:2}"
        TRANSCRIPT_PATH="${TRANSCRIPT_PATH//\\//}"
    fi

    MAIN_RAW=""
    if [[ -f "$TRANSCRIPT_PATH" ]]; then
        MAIN_RAW=$(tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | \
            grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' | \
            tail -1 | \
            sed 's/.*"\([^"]*\)"$/\1/')
    fi

    # 映射成本（单次调用估算 $）
    case "$MAIN_RAW" in
        *opus*)    MAIN_NAME="Opus"   ; MAIN_COST="0.060" ;;
        *sonnet*)  MAIN_NAME="Sonnet" ; MAIN_COST="0.030" ;;
        *haiku*)   MAIN_NAME="Haiku"  ; MAIN_COST="0.008" ;;
        *)         MAIN_NAME="Sonnet" ; MAIN_COST="0.030" ;;   # 默认回退
    esac

    # ── 成本计算 ───────────────────────────────────────────────
    # Haiku subagent ~$0.008, Opus subagent ~$0.060, 主模型按解析值
    SUBAGENT_N=$((TURN_HAIKU + TURN_OPUS))
    TOTAL_CALLS=$((1 + SUBAGENT_N))   # 1 = 主 Agent
    ACTUAL=$(awk -v h="$TURN_HAIKU" -v o="$TURN_OPUS" -v m="$MAIN_COST" \
        'BEGIN{printf "%.4f", h*0.008 + o*0.060 + m}')
    BASELINE=$(awk -v n="$TOTAL_CALLS" -v m="$MAIN_COST" \
        'BEGIN{printf "%.4f", n*m}')
    SAVED=$(awk -v a="$ACTUAL" -v b="$BASELINE" 'BEGIN{printf "%.4f", b-a}')
    SAVED_PCT=$(awk -v a="$ACTUAL" -v b="$BASELINE" \
        'BEGIN{if(b>0 && a<b) printf "%.0f", (1-a/b)*100; else print 0}')

    # ── 构建摘要文本 ───────────────────────────────────────────
    if [[ $SUBAGENT_N -gt 0 ]]; then
        if [[ $TURN_OPUS -gt 0 ]]; then
            CALL_LINE="  调用: Haiku×${TURN_HAIKU} + Opus×${TURN_OPUS} + ${MAIN_NAME}×1（主模型）"
        else
            CALL_LINE="  调用: Haiku×${TURN_HAIKU} + ${MAIN_NAME}×1（主模型）"
        fi
        TOKEN_PART=""
        [[ $TURN_HAIKU_TOKENS -gt 0 ]] && TOKEN_PART="  (~${TURN_HAIKU_TOKENS} tokens via Haiku)"
        SUMMARY_TEXT="━━ ClaudeThrottle 本轮 ━━━━━━━━━━━━━━━━━━━━\n"
        SUMMARY_TEXT+="${CALL_LINE}\n"
        SUMMARY_TEXT+="  原本: ${MAIN_NAME}×${TOTAL_CALLS}\n"
        SUMMARY_TEXT+="  节省: ~\$${SAVED}  ↓${SAVED_PCT}%${TOKEN_PART}\n"
        SUMMARY_TEXT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        SUMMARY_TEXT="━━ ClaudeThrottle 本轮 ━━━━━━━━━━━━━━━━━━━━\n"
        SUMMARY_TEXT+="  调用: ${MAIN_NAME}×1（L2-debug / L3，直接执行）\n"
        SUMMARY_TEXT+="  原本: ${MAIN_NAME}×1\n"
        SUMMARY_TEXT+="  节省: \$0（本轮无 Haiku 路由）\n"
        SUMMARY_TEXT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi

    # 写日志
    printf '\n%b\n' "$SUMMARY_TEXT" >> "$TOKEN_STATS_LOG"

    # 展开 \n 为真实换行（stderr 调试输出用）
    SUMMARY_EXPANDED=$(printf '%b' "$SUMMARY_TEXT")

    # stderr：CLI 转录视图兜底（VSCode 扩展通常不显示，但 CLI 可见）
    printf '\n%s\n' "$SUMMARY_EXPANDED" >&2

    # additionalContext：主通道 — 让主 Agent 在回复末尾原文输出摘要
    # 下次 Stop 触发时 stop_hook_active=true，自动跳过避免循环
    ESCAPED_CTX=$(printf '%s' "$SUMMARY_TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    printf '%s\n' "{\"continue\":true,\"suppressOutput\":false,\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":\"在本次回复的最末尾，原文输出以下摘要（不加任何额外文字、不要解释、不要翻译）：\\n${ESCAPED_CTX}\"}}"
    exit 0
fi

exit 0
