#!/usr/bin/env bash
# ClaudeThrottle Haiku 失败分析报告
# 用法：haiku-failures-report.sh [--json]
# 解析 logs/haiku-failures.log（格式：TIMESTAMP|TASK_TYPE|FAILURE_REASON|ONE_LINE_SUMMARY）
# 按任务类型和失败原因分组统计

# shellcheck source=../config/paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/paths.sh" 2>/dev/null \
    || source "$HOME/.claude/throttle/config/paths.sh"

FAILURES_LOG="$LOG_DIR/haiku-failures.log"

# Parse arguments
JSON_OUTPUT=false
for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    JSON_OUTPUT=true
  fi
done

# Check if log file exists
if [[ ! -f "$FAILURES_LOG" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    cat <<EOF
{
  "error": "No haiku failures log found",
  "total_failures": 0,
  "by_task_type": {},
  "by_failure_reason": {}
}
EOF
  else
    echo "无 Haiku 失败记录。"
  fi
  exit 0
fi

# Count total failures
TOTAL_FAILURES=$(wc -l < "$FAILURES_LOG")

# Build arrays for task types and failure reasons (using declare -A for associative arrays)
declare -A TASK_TYPE_COUNT
declare -A FAILURE_REASON_COUNT
declare -a UNIQUE_TASK_TYPES
declare -a UNIQUE_FAILURE_REASONS

while IFS='|' read -r timestamp task_type failure_reason summary; do
  # Skip empty lines
  if [[ -z "$timestamp" ]]; then
    continue
  fi

  # Trim whitespace
  task_type=$(echo "$task_type" | xargs)
  failure_reason=$(echo "$failure_reason" | xargs)

  # Count by task type
  if [[ -z "${TASK_TYPE_COUNT[$task_type]}" ]]; then
    TASK_TYPE_COUNT[$task_type]=1
    UNIQUE_TASK_TYPES+=("$task_type")
  else
    ((TASK_TYPE_COUNT[$task_type]++))
  fi

  # Count by failure reason
  if [[ -z "${FAILURE_REASON_COUNT[$failure_reason]}" ]]; then
    FAILURE_REASON_COUNT[$failure_reason]=1
    UNIQUE_FAILURE_REASONS+=("$failure_reason")
  else
    ((FAILURE_REASON_COUNT[$failure_reason]++))
  fi
done < "$FAILURES_LOG"

# Output in JSON or text format
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Build JSON for task types
  TASK_TYPE_JSON="{"
  first=true
  for task_type in "${UNIQUE_TASK_TYPES[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      TASK_TYPE_JSON="$TASK_TYPE_JSON,"
    fi
    TASK_TYPE_JSON="$TASK_TYPE_JSON\"$(echo "$task_type" | sed 's/"/\\"/g')\": ${TASK_TYPE_COUNT[$task_type]}"
  done
  TASK_TYPE_JSON="$TASK_TYPE_JSON}"

  # Build JSON for failure reasons
  FAILURE_REASON_JSON="{"
  first=true
  for failure_reason in "${UNIQUE_FAILURE_REASONS[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      FAILURE_REASON_JSON="$FAILURE_REASON_JSON,"
    fi
    FAILURE_REASON_JSON="$FAILURE_REASON_JSON\"$(echo "$failure_reason" | sed 's/"/\\"/g')\": ${FAILURE_REASON_COUNT[$failure_reason]}"
  done
  FAILURE_REASON_JSON="$FAILURE_REASON_JSON}"

  # Output JSON
  cat <<EOF
{
  "total_failures": $TOTAL_FAILURES,
  "by_task_type": $TASK_TYPE_JSON,
  "by_failure_reason": $FAILURE_REASON_JSON
}
EOF
else
  # Text output
  echo ""
  echo "━━━ ClaudeThrottle Haiku 失败分析 ━━━"
  echo "总失败次数: $TOTAL_FAILURES"
  echo ""

  if [[ ${#UNIQUE_TASK_TYPES[@]} -gt 0 ]]; then
    echo "按任务类型分组:"
    for task_type in "${UNIQUE_TASK_TYPES[@]}"; do
      echo "  ${task_type}: ${TASK_TYPE_COUNT[$task_type]} 次"
    done
    echo ""
  fi

  if [[ ${#UNIQUE_FAILURE_REASONS[@]} -gt 0 ]]; then
    echo "按失败原因分组:"
    for failure_reason in "${UNIQUE_FAILURE_REASONS[@]}"; do
      echo "  ${failure_reason}: ${FAILURE_REASON_COUNT[$failure_reason]} 次"
    done
    echo ""
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi
