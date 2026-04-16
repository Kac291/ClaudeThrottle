#!/usr/bin/env bash
# ClaudeThrottle 成本报告生成器
# 用法：cost-report.sh [--json] [session_id]  — 不传则统计全部

# shellcheck source=../config/paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/paths.sh" 2>/dev/null \
    || source "$HOME/.claude/throttle/config/paths.sh"
LOG_FILE="$USAGE_LOG"
CONFIG_FILE="$MODE_FILE"

if [[ ! -f "$LOG_FILE" ]]; then
  if [[ "${1:-}" == "--json" ]]; then
    echo "{\"error\":\"No usage log available\"}"
  else
    echo "无使用日志。"
  fi
  exit 0
fi

# Parse arguments
JSON_OUTPUT=false
SESSION_FILTER=""

for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    JSON_OUTPUT=true
  else
    SESSION_FILTER="$arg"
  fi
done

CURRENT_MODE=$(cat "$CONFIG_FILE" 2>/dev/null || echo "unknown")

# 过滤目标记录
if [[ -n "$SESSION_FILTER" ]]; then
  RECORDS=$(grep "$SESSION_FILTER" "$LOG_FILE" 2>/dev/null || echo "")
  SCOPE="session"
else
  RECORDS=$(cat "$LOG_FILE")
  SCOPE="all"
fi

if [[ -z "$RECORDS" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "{\"error\":\"No subagent calls found\"}"
  else
    echo "本次会话无 subagent 调用记录。"
  fi
  exit 0
fi

# 统计各模型调用次数
HAIKU_COUNT=$(echo "$RECORDS" | grep -c "|agent|haiku|" 2>/dev/null || echo 0)
SONNET_COUNT=$(echo "$RECORDS" | grep -c "|agent|sonnet|" 2>/dev/null || echo 0)
OPUS_COUNT=$(echo "$RECORDS" | grep -c "|agent|opus|" 2>/dev/null || echo 0)
TOOL_COUNT=$(echo "$RECORDS" | grep -c "|tool|sonnet|" 2>/dev/null || echo 0)

# 估算成本（粗略：假设每次 subagent 调用平均 2K tokens in + 1K out）
# Haiku: $0.80/1M in + $4.00/1M out → 2K in = $0.0016, 1K out = $0.004 → ~$0.006/call
# Sonnet: $3.00/1M in + $15.00/1M out → ~$0.021/call
# Opus: $15.00/1M in + $75.00/1M out → ~$0.105/call
HAIKU_COST=$(echo "scale=4; $HAIKU_COUNT * 0.006" | bc 2>/dev/null || echo "N/A")
SONNET_AGENT_COST=$(echo "scale=4; $SONNET_COUNT * 0.021" | bc 2>/dev/null || echo "N/A")
OPUS_COST=$(echo "scale=4; $OPUS_COUNT * 0.105" | bc 2>/dev/null || echo "N/A")
TOTAL_COST=$(echo "scale=4; $HAIKU_COUNT * 0.006 + $SONNET_COUNT * 0.021 + $OPUS_COUNT * 0.105" | bc 2>/dev/null || echo "N/A")

# 纯 Sonnet 假设基准（所有 subagent 调用都用 Sonnet）
TOTAL_SUBAGENT=$((HAIKU_COUNT + SONNET_COUNT + OPUS_COUNT))
BASELINE_COST=$(echo "scale=4; $TOTAL_SUBAGENT * 0.021" | bc 2>/dev/null || echo "N/A")

if [[ "$BASELINE_COST" != "N/A" && "$TOTAL_COST" != "N/A" ]]; then
  SAVED=$(echo "scale=2; (1 - $TOTAL_COST / $BASELINE_COST) * 100" | bc 2>/dev/null || echo "N/A")
else
  SAVED="N/A"
fi

# Output in JSON or text format
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Convert saved_pct to number or null
  if [[ "$SAVED" == "N/A" ]]; then
    SAVED_PCT="null"
  else
    SAVED_PCT="$SAVED"
  fi

  # Convert costs to numbers or null
  if [[ "$TOTAL_COST" == "N/A" ]]; then
    TOTAL_COST_NUM="null"
  else
    TOTAL_COST_NUM="$TOTAL_COST"
  fi

  if [[ "$BASELINE_COST" == "N/A" ]]; then
    BASELINE_COST_NUM="null"
  else
    BASELINE_COST_NUM="$BASELINE_COST"
  fi

  # Output JSON
  cat <<EOF
{
  "scope": "$SCOPE",
  "mode": "$CURRENT_MODE",
  "haiku_count": $HAIKU_COUNT,
  "sonnet_count": $SONNET_COUNT,
  "opus_count": $OPUS_COUNT,
  "tool_count": $TOOL_COUNT,
  "total_cost": $TOTAL_COST_NUM,
  "baseline_cost": $BASELINE_COST_NUM,
  "saved_pct": $SAVED_PCT
}
EOF
else
  echo ""
  echo "━━━ ClaudeThrottle 成本报告（${SCOPE}）━━━"
  echo "当前模式: $CURRENT_MODE"
  echo ""
  echo "Subagent 调用："
  echo "  Haiku  调用: ${HAIKU_COUNT} 次   (~\$${HAIKU_COST})"
  echo "  Sonnet 调用: ${SONNET_COUNT} 次   (~\$${SONNET_AGENT_COST})"
  echo "  Opus   调用: ${OPUS_COUNT} 次   (~\$${OPUS_COST})"
  echo "  主Agent工具: ${TOOL_COUNT} 次"
  echo ""
  echo "估算成本: ~\$${TOTAL_COST}"
  echo "全 Sonnet 基准: ~\$${BASELINE_COST}"
  if [[ "$SAVED" != "N/A" ]]; then
    echo "节省: ~${SAVED}%"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️  成本为粗略估算（按均值计），仅供参考"
  echo ""
fi
